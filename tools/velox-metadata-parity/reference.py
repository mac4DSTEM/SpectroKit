#!/usr/bin/env python3
"""Truth for tools/velox-metadata-parity: what the pinned Velox files say, read without the Swift reader.

    reference.py <rsciio-root> <unzipped-dir> <out.json> [extra.emd ...]

For every .emd of RosettaSciIO 049e7d70's public test data and every `Data/Image/<id>` entry that holds a rank-3 `Data`
and a `Metadata` (the entries `VeloxEMDReader.images()` lists), it reads COLUMN 0 of `Metadata` with h5py (cut at the
first NUL, parsed with json) and writes the expected value of each field SpectroKit 0.2.0 added to `VeloxMetadata`:

  nominalMagnification   Optics.NominalMagnification: Python float() of the stored string or number; absent or
                         unparseable: null
  stemMagnification      CustomProperties.StemMagnification.value, the same (null too when CustomProperties or
                         StemMagnification is not an object)
  cameraLengthMeters     Optics.CameraLength, the same
  operatingMode          Optics.OperatingMode: the stored string; absent or not a string: null
  projectorMode          Optics.ProjectorMode, the same
  exposureTimeSeconds    ExposureTime of the Detectors entry RosettaSciIO's `_get_detector_metadata_dict(om,
                         BinaryResult.Detector)` returns (null when BinaryResult.Detector is absent or empty, or
                         nothing matches)
  detectors[].exposureTimeSeconds   every `Detector-<n>` entry's own ExposureTime, the same float() rule

and, for the report only (never compared): RosettaSciIO's DetectorIndex-based ExposureTime (what its `_parse_frame_time`
path reads: `Detectors["Detector-<BinaryResult.DetectorIndex>"]["ExposureTime"]`), the first-by-index exposure the
reader computes (see "deviation" in compare.py), and the stored text and `type` of
`CustomProperties.StemMagnification`.

`_get_detector_metadata_dict` is NOT imported: `rsciio.emd._emd_velox` needs packaging, python-dateutil and pint, which
the reference venv (h5py and numpy only) does not have. It is taken from the pinned file itself: the file's sha256 is
asserted, and the function's source is cut out with `ast` and compiled alone, so what runs is the pinned code, not a
retyped copy.

Nothing here reads a fixture's truth file: the planted file and every extra file are read like the public ones.

Before anything is read: registry.txt is the pinned file, every zip and loose .emd matches its registry entry (the
registry names the four zips, not their members), and every unzipped member is byte-identical to the member of the
verified archive. The file also checks the six doc-comment claims of VeloxEMDReader.swift against the public files and
the pinned source (see `claims` in the output; planted and extra files are left out of that check). A disagreement
exits 1 here, loudly: that is a reference check failing, never a pass.
"""
import ast
import hashlib
import importlib.metadata
import json
import os
import re
import struct
import sys
import zipfile

import h5py

RSCIIO_COMMIT = "049e7d70"
REGISTRY_SHA256 = "31417482938f80160be2c03525ba58dd810c7f16b1790f597470ece8dd0b1bcb"
VELOX_PY_SHA256 = "1a3e12f2d550c5378c5e3ee0e02c963f0ef547af9dd4bde9bd1c2ee2df56a8e3"
PYTHON_MINOR = "3.14"
WANT = {"h5py": "3.16.0", "numpy": "2.5.4"}

ZIPS = ["fei_emd_files.zip", "velox_EELS_EDS.zip", "velox_emd_v11_elementSelection.zip", "velox_emd_version11.zip"]
LOOSE_VELOX = ["FFTComplexEven.emd", "FFTComplexOdd.emd", "fei_example_complex_fft.emd", "fei_example_dpc_titles.emd",
               "fei_example_tem_stack.emd"]
# Berkeley-EMD files: no Velox `Version`, so both readers must refuse them (images() throws notVeloxFile).
LOOSE_OTHER = ["Si100_1x1x3-zStart5.43.emd", "Si100_1x1x3-zStart6.7875.emd", "Si100_2D_3D_DPC_potential_2slices.emd",
               "Si100_2x1x1_3D.emd", "Si100_3D.emd", "Si100_4D.emd", "example_axis_len_1.emd",
               "example_bytes_string_metadata.emd", "example_image.emd", "example_metadata.emd",
               "example_object_dtype_data.emd", "example_signal.emd", "example_spectrum.emd"]
PLANTED = "velox-metadata-planted.emd"
DETECTOR_KEY = re.compile(r"^Detector-([0-9]+)$")


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def encode(x):
    """A float as the comparison key: its IEEE-754 bit pattern (16 hex digits) and %.17g text; None stays None."""
    if x is None:
        return None
    return {"bits": "%016x" % struct.unpack(">Q", struct.pack(">d", x))[0], "text": "%.17g" % x}


def num(v):
    """Python float() of a stored string or number; None when absent or unparseable. A JSON bool is a number here, as
    to both readers: `float(True)` is 1.0 (RosettaSciIO) and the reader takes the `NSNumber` 1/0."""
    if v is None:
        return None
    if isinstance(v, (int, float)):       # bool is an int
        try:
            return float(v)
        except OverflowError:
            return None
    if isinstance(v, str):
        try:
            return float(v)
        except ValueError:
            return None
    return None


def text(v):
    return v if isinstance(v, str) else None


# ----------------------------------------------------------------------------------------------------- the pins
def check_pins(root):
    python = "%d.%d" % sys.version_info[:2]
    if python != PYTHON_MINOR:
        fail(f"Python {python} is not the pinned {PYTHON_MINOR}")
    for package, version in WANT.items():
        have = importlib.metadata.version(package)
        if have != version:
            fail(f"{package} {have} is not the pinned {version}")
    registry_path = os.path.join(root, "rsciio", "tests", "registry.txt")
    if sha256_file(registry_path) != REGISTRY_SHA256:
        fail("rsciio/tests/registry.txt is not the pinned file (References/rosettasciio is not the lock)")
    registry = {}
    for line in open(registry_path, encoding="utf-8"):
        m = re.match(r"^'([^']+)'\s+([0-9a-f]{64})\s*$", line)
        if m:
            registry[m.group(1)] = m.group(2)
    return registry


def load_rsciio_function(root):
    """`_get_detector_metadata_dict` from the pinned _emd_velox.py, compiled alone (see the module docstring)."""
    path = os.path.join(root, "rsciio", "emd", "_emd_velox.py")
    if sha256_file(path) != VELOX_PY_SHA256:
        fail("rsciio/emd/_emd_velox.py is not the pinned file")
    source = open(path, encoding="utf-8").read()
    found = [n for n in ast.parse(source).body
             if isinstance(n, ast.FunctionDef) and n.name == "_get_detector_metadata_dict"]
    if len(found) != 1:
        fail("_get_detector_metadata_dict is not a single top-level function of the pinned _emd_velox.py")
    namespace = {}
    exec(compile(ast.Module(body=[found[0]], type_ignores=[]), path, "exec"), namespace)
    return namespace["_get_detector_metadata_dict"], ast.get_source_segment(source, found[0])


def verify_files(root, registry, unzipped):
    """Hash every zip and loose file against the registry; compare every unzipped member with the verified archive."""
    data = os.path.join(root, "rsciio", "tests", "data", "emd")
    files = []   # (label, path, sha256, source, expect_velox)
    for name in ZIPS:
        zip_path = os.path.join(data, name)
        want = registry.get("emd/" + name)
        if want is None:
            fail(f"emd/{name} is not in registry.txt")
        have = sha256_file(zip_path)
        if have != want:
            fail(f"{name}: sha256 {have} is not the registry's {want}")
        stem = name[:-4]
        with zipfile.ZipFile(zip_path) as archive:
            members = [i for i in archive.infolist() if not i.is_dir()]
            for info in members:
                if os.path.basename(info.filename) != info.filename or info.filename.startswith("."):
                    fail(f"{name}: member {info.filename!r} is not a plain file name")
                extracted = os.path.join(unzipped, stem, info.filename)
                if not os.path.isfile(extracted):
                    fail(f"{name}: member {info.filename!r} was not unzipped to {extracted}")
                member_bytes = archive.read(info)           # zipfile checks the CRC-32 while reading
                if sha256_bytes(member_bytes) != sha256_file(extracted):
                    fail(f"{name}: unzipped {info.filename!r} differs from the archive's member")
                if info.filename.endswith(".emd"):
                    files.append((f"{stem}.zip/{info.filename}", extracted, sha256_bytes(member_bytes),
                                  f"member of {name} (registry sha256 {want[:12]})", None))
            on_disk = sorted(os.listdir(os.path.join(unzipped, stem)))
            if on_disk != sorted(i.filename for i in members):
                fail(f"{name}: the unzipped directory holds {on_disk}, the archive "
                     f"{sorted(i.filename for i in members)}")
    for names, velox in ((LOOSE_VELOX, True), (LOOSE_OTHER, False)):
        for name in names:
            path = os.path.join(data, name)
            want = registry.get("emd/" + name)
            if want is None:
                fail(f"emd/{name} is not in registry.txt")
            have = sha256_file(path)
            if have != want:
                fail(f"{name}: sha256 {have} is not the registry's {want}")
            files.append((f"loose/{name}", path, have, f"loose file (registry sha256 {want[:12]})", velox))
    return files


# ------------------------------------------------------------------------------------------------------- reading
def read_version(f):
    """The root `Version` JSON's `format`, or None when there is no readable Velox-style Version."""
    if "Version" not in f:
        return None
    try:
        raw = f["Version"][0] if f["Version"].shape else f["Version"][()]
        raw = raw.decode("utf-8") if isinstance(raw, bytes) else str(raw)
        return json.loads(raw)["format"]
    except Exception:
        return None


def column_json(dataset, column):
    return json.loads(bytes(dataset[:, column]).split(b"\0")[0].decode("utf-8"))


def detectors_of(om):
    """`Detector-<n>` entries as (index, dict) in the file's order; what the reader lists."""
    out = []
    section = om.get("Detectors")
    if isinstance(section, dict):
        for key, value in section.items():
            m = DETECTOR_KEY.match(key)
            if m and isinstance(value, dict):
                out.append((int(m.group(1)), value))
    return out


def detector_type(om):
    """The DetectorType of BinaryResult.Detector: by name, else the one type every name containing it shares, else by
    index."""
    binary = om.get("BinaryResult") if isinstance(om.get("BinaryResult"), dict) else {}
    name = text(binary.get("Detector"))
    entries = detectors_of(om)
    if name:
        exact = [d.get("DetectorType") for _, d in entries if d.get("DetectorName") == name]
        if exact:
            return exact[0]
        types = {d.get("DetectorType") for _, d in entries if name in str(d.get("DetectorName", ""))}
        if len(types) == 1:
            return types.pop()
    index = binary.get("DetectorIndex")
    if isinstance(index, int) and not isinstance(index, bool):
        for i, d in entries:
            if i == index:
                return d.get("DetectorType")
    return None


def read_entry(group, rsciio_detector):
    om = column_json(group["Metadata"], 0)
    if not isinstance(om, dict):
        fail(f"{group.name}: column 0 of Metadata is not a JSON object")
    optics = om.get("Optics") if isinstance(om.get("Optics"), dict) else {}
    binary = om.get("BinaryResult") if isinstance(om.get("BinaryResult"), dict) else {}
    name = text(binary.get("Detector"))

    exposure, raised = None, False
    if name:
        try:
            chosen = rsciio_detector(om, name)
        except (KeyError, TypeError):
            # rsciio itself raises (no Detectors, or an entry without DetectorName): the same walk with .get.
            raised = True
            chosen = next((d for _, d in detectors_of(om) if d.get("DetectorName") == name), None)
        exposure = num(chosen.get("ExposureTime")) if isinstance(chosen, dict) else None
    # The reader cannot see the order a JSON object was stored in (Foundation's dictionaries have none), so it takes
    # `Detector-<n>` in index order. rsciio takes the stored order. They are the same whenever the keys are stored in
    # index order, which every public file does (claim 6); this is the only place the two can part, and compare.py
    # tolerates the part only on the planted fixture (see "deviation" there).
    stored = [i for i, _ in detectors_of(om)]
    in_index_order = None
    if name:
        in_index_order = next((num(d.get("ExposureTime")) for _, d in sorted(detectors_of(om), key=lambda e: e[0])
                               if d.get("DetectorName") == name), None)

    index = binary.get("DetectorIndex")
    by_index, index_name = None, None
    section = om.get("Detectors") if isinstance(om.get("Detectors"), dict) else {}
    target = section.get(f"Detector-{index}") if index is not None else None
    if isinstance(target, dict):
        by_index, index_name = num(target.get("ExposureTime")), text(target.get("DetectorName"))

    custom = om.get("CustomProperties") if isinstance(om.get("CustomProperties"), dict) else {}
    stem = custom.get("StemMagnification")
    stem_stored = stem.get("value") if isinstance(stem, dict) else None
    return {
        "binaryResultDetector": name,
        "nominalMagnification": encode(num(optics.get("NominalMagnification"))),
        "stemMagnification": encode(num(stem_stored)),
        "cameraLengthMeters": encode(num(optics.get("CameraLength"))),
        "operatingMode": text(optics.get("OperatingMode")),
        "projectorMode": text(optics.get("ProjectorMode")),
        "exposureTimeSeconds": encode(exposure),
        "exposureInIndexOrder": {"storedOutOfIndexOrder": stored != sorted(stored), "value": encode(in_index_order)},
        "detectors": [{"index": i, "name": text(d.get("DetectorName")) or "", "type": text(d.get("DetectorType")) or "",
                       "exposureTimeSeconds": encode(num(d.get("ExposureTime")))} for i, d in detectors_of(om)],
        "report": {
            "binaryResultDetectorIndex": index,
            "exposureByDetectorIndex": encode(by_index),
            "detectorIndexPointsAt": index_name,
            "storedStemMagnification": stem_stored,
            "storedStemMagnificationType": (stem.get("type") if isinstance(stem, dict) else None),
            "detectorType": detector_type(om),
            "rsciioRaised": raised,
            "rawNominalMagnification": optics.get("NominalMagnification"),
            "rawCameraLength": optics.get("CameraLength"),
        },
    }


def read_file(path, rsciio_detector):
    with h5py.File(path, "r") as f:
        fmt = read_version(f)
        out = {"format": fmt, "velox": fmt == "Velox", "entries": {}, "columns": {},
               "eels": {"detectors": [], "datasets": {}}}
        if fmt != "Velox":
            return out
        eels = f.get("Data/EelsSpectrumImage")
        if isinstance(eels, h5py.Group):
            for name in sorted(eels.keys()):
                if isinstance(eels[name], h5py.Group) and "Metadata" in eels[name]:
                    meta = eels[name]["Metadata"]
                    columns = [column_json(meta, c) for c in range(meta.shape[1])]
                    out["eels"]["datasets"][name] = [carries_stem(c) for c in columns]
                    binary = columns[0].get("BinaryResult") if isinstance(columns[0].get("BinaryResult"), dict) else {}
                    if text(binary.get("Detector")) and binary["Detector"] not in out["eels"]["detectors"]:
                        out["eels"]["detectors"].append(binary["Detector"])
        images = f.get("Data/Image")
        if not isinstance(images, h5py.Group):
            return out
        for name in sorted(images.keys()):
            group = images[name]
            if not isinstance(group, h5py.Group) or "Data" not in group or "Metadata" not in group:
                continue
            data = group["Data"]
            if not isinstance(data, h5py.Dataset) or data.ndim != 3:
                continue
            out["entries"][name] = read_entry(group, rsciio_detector)
            meta = group["Metadata"]
            out["columns"][name] = [column_json(meta, c) for c in range(meta.shape[1])]
    return out


# ------------------------------------------------------------------------------------------------------- claims
CAMERA = "ImagingDetector"
# The doc comment's own figures for the camera images' StemMagnification, as stored (strings): "0" on three, "115000"
# on one.
DOC_CAMERA_STEM = ["0", "0", "0", "115000"]


def carries_stem(column):
    """True when this Metadata column has CustomProperties.StemMagnification at all (any value)."""
    custom = column.get("CustomProperties")
    return isinstance(custom, dict) and "StemMagnification" in custom


def stored_stem(column):
    """The stored `value` of CustomProperties.StemMagnification (text as written) and its `type`, or (None, None)."""
    custom = column.get("CustomProperties")
    stem = custom.get("StemMagnification") if isinstance(custom, dict) else None
    return (stem.get("value"), stem.get("type")) if isinstance(stem, dict) else (None, None)


def has_nominal(column):
    optics = column.get("Optics")
    return isinstance(optics, dict) and optics.get("NominalMagnification") is not None


def new_claim(text, definition):
    return {"text": text, "definition": definition, "checked": 0, "counterexamples": [], "detail": []}


def source_claim(root):
    """Claim 5, about the pinned source and not the data: what `_emd_velox.py`'s `_get_mapping` maps (via `ast`)."""
    c = new_claim("RosettaSciIO 049e7d70 maps CustomProperties.StemMagnification.value as the magnification (float) "
                  "and Optics.CameraLength x1e3 in every mode, and maps neither Optics.NominalMagnification nor the "
                  "modes",
                  "`_get_mapping`'s `mapping` dict literal (top level of the function) and a text search of "
                  "rsciio/emd/*.py")
    path = os.path.join(root, "rsciio", "emd", "_emd_velox.py")
    function = None
    for node in ast.walk(ast.parse(open(path, encoding="utf-8").read())):
        if isinstance(node, ast.FunctionDef) and node.name == "_get_mapping":
            function = node
    entries = {}
    for statement in (function.body if function else []):
        if (isinstance(statement, ast.Assign) and isinstance(statement.value, ast.Dict)
                and any(isinstance(t, ast.Name) and t.id == "mapping" for t in statement.targets)):
            entries = {k.value: v for k, v in zip(statement.value.keys, statement.value.values)
                       if isinstance(k, ast.Constant)}
    if not entries:
        c["counterexamples"].append("_get_mapping has no top-level `mapping = {...}`")
        return c

    def pair(key):
        value = entries.get(key)
        if not (isinstance(value, ast.Tuple) and len(value.elts) == 2 and isinstance(value.elts[0], ast.Constant)):
            return None, None
        return value.elts[0].value, value.elts[1]

    def shown(node):
        return ast.unparse(node) if node else None

    c["checked"] += 1
    target, convert = pair("CustomProperties.StemMagnification.value")
    if target != "Acquisition_instrument.TEM.magnification" or not (
            isinstance(convert, ast.Name) and convert.id == "float"):
        c["counterexamples"].append(f"CustomProperties.StemMagnification.value maps to {target!r} with "
                                    f"{shown(convert)!r}, not magnification with float")
    c["checked"] += 1
    target, convert = pair("Optics.CameraLength")
    if target != "Acquisition_instrument.TEM.camera_length" or not (
            isinstance(convert, ast.Lambda) and ast.unparse(convert.body) == "float(x) * 1000.0"):
        c["counterexamples"].append(f"Optics.CameraLength maps to {target!r} with {shown(convert)!r}, not "
                                    f"camera_length with float(x) * 1e3")
    c["checked"] += 1
    magnification = [n.value for n in ast.walk(function) if isinstance(n, ast.Constant) and isinstance(n.value, str)
                     and n.value.endswith(".magnification")]
    if magnification != ["Acquisition_instrument.TEM.magnification"]:
        c["counterexamples"].append(f"the targets ending in .magnification are {magnification}, expected exactly one")
    c["checked"] += 1
    removed = [ast.unparse(n) for n in ast.walk(function) if isinstance(n, ast.Delete) or (
        isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr in ("pop", "popitem", "clear"))]
    if removed:
        c["counterexamples"].append(f"_get_mapping removes entries it has mapped: {removed}")
    for needle in ("NominalMagnification", "OperatingMode", "ProjectorMode"):
        c["checked"] += 1
        hits = []
        for directory, _, names in os.walk(os.path.join(root, "rsciio", "emd")):
            for name in sorted(names):
                if name.endswith(".py") and needle in open(os.path.join(directory, name), encoding="utf-8").read():
                    hits.append(os.path.join(directory, name))
        if hits:
            c["counterexamples"].append(f"{needle} appears in {hits}")
    c["detail"].append("StemMagnification.value -> TEM.magnification with float; CameraLength -> TEM.camera_length "
                       "with float(x) * 1e3, both unconditionally; NominalMagnification, OperatingMode, "
                       "ProjectorMode: no occurrence in rsciio/emd/*.py")
    return c


def nominal_claim(entries):
    """Claim 1: NominalMagnification is absent from every STEM image (every Metadata column), present on cameras."""
    c = new_claim("Optics.NominalMagnification is absent from every STEM image of the public files",
                  "STEM image: an entry whose BinaryResult.Detector is not an ImagingDetector; every Metadata column "
                  "is read")
    by_type, stem_columns, cameras, cameras_with = {}, 0, 0, 0
    for tag, entry, columns in entries:
        dtype = entry["report"]["detectorType"]
        if dtype == CAMERA:
            cameras += 1
            cameras_with += 1 if all(has_nominal(column) for column in columns) else 0
            continue
        c["checked"] += 1
        by_type[dtype] = by_type.get(dtype, 0) + 1
        stem_columns += len(columns)
        for index, column in enumerate(columns):
            if has_nominal(column):
                c["counterexamples"].append(f"{tag} col {index}: NominalMagnification "
                                            f"{column['Optics']['NominalMagnification']!r} on a STEM image "
                                            f"(detector type {dtype})")
    types = ", ".join(f"{n} {k}" for k, n in sorted(by_type.items(), key=lambda kv: str(kv[0])))
    c["detail"].append(f"{sum(by_type.values())} STEM images ({types}), {stem_columns} Metadata columns: none has it; "
                       f"it is present on {cameras_with} of the {cameras} camera images")
    return c


def exposure_claim(entries):
    """Claim 2: ExposureTime is set only on ImagingDetector entries (every Detectors entry of every column)."""
    c = new_claim("per-detector ExposureTime is set only on camera (ImagingDetector) entries",
                  "every Detectors entry of every Metadata column of every entry")
    carriers = imaging_without = 0
    for tag, _, columns in entries:
        for index, column in enumerate(columns):
            section = column.get("Detectors") if isinstance(column.get("Detectors"), dict) else {}
            for key, d in section.items():
                if not isinstance(d, dict):
                    continue
                c["checked"] += 1
                if d.get("ExposureTime") is not None:
                    carriers += 1
                    if d.get("DetectorType") != CAMERA:
                        c["counterexamples"].append(f"{tag} col {index}: {key} {d.get('DetectorName')!r} "
                                                    f"({d.get('DetectorType')}) has ExposureTime {d['ExposureTime']!r}")
                elif d.get("DetectorType") == CAMERA:
                    imaging_without += 1
    c["detail"].append(f"{carriers} Detectors entries carry an ExposureTime, all ImagingDetector; "
                       f"{imaging_without} ImagingDetector entries carry none")
    return c


def modes_claim(entries):
    """Claim 3: OperatingMode and ProjectorMode are the codes "1" / "2" wherever present (every Metadata column)."""
    c = new_claim('Optics.OperatingMode and Optics.ProjectorMode are codes "1" / "2"',
                  "both keys in every Metadata column of every entry; absent is not a counterexample")
    values, absent = {}, 0
    for tag, _, columns in entries:
        for index, column in enumerate(columns):
            optics = column.get("Optics") if isinstance(column.get("Optics"), dict) else {}
            for key in ("OperatingMode", "ProjectorMode"):
                value = optics.get(key)
                c["checked"] += 1
                if value is None:
                    absent += 1
                    continue
                values[repr(value)] = values.get(repr(value), 0) + 1
                if value not in ("1", "2"):
                    c["counterexamples"].append(f"{tag} col {index}: {key} = {value!r}")
    c["detail"].append(f"values {dict(sorted(values.items()))}; {absent} of {c['checked']} columns lack the key")
    return c


def stem_claim(files):
    """Claim 4: StemMagnification is not a STEM marker (camera images carry it, EELS spectrometer entries do not)."""
    c = new_claim('CustomProperties.StemMagnification is not a STEM marker: the camera images carry it too ("0" on '
                  'three of the four, "115000" on the fourth) and the EELS spectrometer\'s entries carry none',
                  "camera image: BinaryResult.Detector is an ImagingDetector; EELS spectrometer entry: "
                  "BinaryResult.Detector is the detector of the file's Data/EelsSpectrumImage datasets, and those "
                  "datasets themselves; 'carries': CustomProperties.StemMagnification present in any Metadata column")
    camera_stored, camera_types, camera_columns = [], [], 0
    eels_entries = eels_datasets = other_carry = other_total = 0
    other_without = []
    for label, info in files.items():
        if not info["velox"]:
            continue
        eels_names = set(info["eels"]["detectors"])
        for eid, entry in info["entries"].items():
            tag, columns = f"{label} | {eid[:6]}", info["columns"][eid]
            carry = [carries_stem(column) for column in columns]
            if entry["report"]["detectorType"] == CAMERA:
                c["checked"] += 1
                camera_columns += len(columns)
                if not all(carry):
                    missing = [i for i, x in enumerate(carry) if not x]
                    c["counterexamples"].append(f"{tag}: a camera image without CustomProperties.StemMagnification "
                                                f"in column(s) {missing}")
                    continue
                stored = {stored_stem(column) for column in columns}
                if len(stored) != 1:
                    c["counterexamples"].append(f"{tag}: the columns store different StemMagnification "
                                                f"{sorted(map(str, stored))}")
                    continue
                value, kind = stored.pop()
                camera_stored.append(value)
                camera_types.append(kind)
                if not all(has_nominal(column) for column in columns):
                    c["counterexamples"].append(f"{tag}: a camera image without Optics.NominalMagnification, which "
                                                f"the comment names as its magnification")
            elif entry["binaryResultDetector"] in eels_names:
                c["checked"] += 1
                eels_entries += 1
                if any(carry):
                    c["counterexamples"].append(f"{tag}: an EELS spectrometer entry ({entry['binaryResultDetector']}) "
                                                f"carries CustomProperties.StemMagnification")
            else:
                other_total += 1
                if any(carry):
                    other_carry += 1
                else:
                    other_without.append(tag)
        for did, dataset_columns in info["eels"]["datasets"].items():
            c["checked"] += 1
            eels_datasets += 1
            if any(dataset_columns):
                c["counterexamples"].append(f"{label} | {did[:6]}: an EelsSpectrumImage dataset carries "
                                            f"CustomProperties.StemMagnification")
    cameras = len(camera_stored)
    if sorted(camera_stored, key=str) != DOC_CAMERA_STEM:
        c["counterexamples"].append(f"the camera images store StemMagnification {sorted(camera_stored, key=str)}, the "
                                    f"comment says {DOC_CAMERA_STEM}")
    if eels_entries == 0 or eels_datasets == 0:
        c["counterexamples"].append(f"found {eels_entries} EELS spectrometer image entries and {eels_datasets} "
                                    f"EelsSpectrumImage datasets: nothing to show 'carry none' on")
    if other_without:
        c["counterexamples"].append(f"entries that are neither camera nor EELS and carry no StemMagnification (the "
                                    f"comment's contrast with a 'STEM marker' needs them to carry it): {other_without}")
    c["detail"].append(f"{cameras} camera images ({camera_columns} columns) store {sorted(camera_stored, key=str)} "
                       f"(type {sorted(map(str, camera_types))}); {eels_entries} EELS spectrometer image entries and "
                       f"{eels_datasets} EelsSpectrumImage datasets carry none; the other {other_total} entries "
                       f"all carry it ({other_carry} of {other_total})")
    return c


def order_claim(entries):
    """Claim 6: in every `Detectors` section, the `Detector-<n>` keys are stored in ascending index order and no two
    entries share a DetectorName (every Metadata column of every entry). With both, the first entry as stored and the
    first by index are one entry, so RosettaSciIO's choice and the reader's cannot part."""
    c = new_claim("the Detectors keys of every image entry are stored in ascending Detector-<n> index order, and no "
                  "two entries of one image share a DetectorName",
                  "every `Detectors` section of every Metadata column of every entry; an entry without a string "
                  "DetectorName has no name to share")
    images = set()
    sections = columns_seen = widest = 0
    for tag, _, columns in entries:
        images.add(tag)
        for index, column in enumerate(columns):
            found = detectors_of(column)
            if not found:
                continue
            c["checked"] += 1
            sections += 1
            widest = max(widest, len(found))
            stored = [i for i, _ in found]
            if stored != sorted(stored):
                c["counterexamples"].append(f"{tag} col {index}: the Detector-<n> keys are stored in the order "
                                            f"{stored}, not ascending")
            if len(set(stored)) != len(stored):
                c["counterexamples"].append(f"{tag} col {index}: two keys carry one index {sorted(stored)}")
            names = {}
            for i, d in found:
                if isinstance(d.get("DetectorName"), str):
                    names.setdefault(d["DetectorName"], []).append(i)
            for name, indices in sorted(names.items()):
                if len(indices) > 1:
                    c["counterexamples"].append(f"{tag} col {index}: DetectorName {name!r} is on the entries with "
                                                f"indices {indices}")
        columns_seen += len(columns)
    c["detail"].append(f"{len(images)} image entries ({columns_seen} Metadata columns), {sections} Detectors sections "
                       f"of up to {widest} entries each: keys ascending and names distinct in all {sections}")
    return c


def claims(files, root):
    """The doc-comment claims of VeloxEMDReader.swift, against every public Velox file read and the pinned source.

    A camera image is a `Data/Image` entry whose `BinaryResult.Detector` has DetectorType ImagingDetector (BM-Ceta
    here); a STEM image is any other entry (ScanningDetector or AnalyticalDetector); an EELS spectrometer entry is an
    entry whose `BinaryResult.Detector` is the detector of the file's `Data/EelsSpectrumImage` datasets (rsciio's EELS
    spectrum images: "Zebra" in the one public file that has them). The type is `detector_type()`'s."""
    entries = [(f"{label} | {eid[:6]}", entry, info["columns"][eid])
               for label, info in files.items() if info["velox"] for eid, entry in info["entries"].items()]
    return {"claim1": nominal_claim(entries), "claim2": exposure_claim(entries), "claim3": modes_claim(entries),
            "claim4": stem_claim(files), "claim5": source_claim(root), "claim6": order_claim(entries)}


# ------------------------------------------------------------------------------------------------------- main
def main():
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    root, unzipped, out_path, extras = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    registry = check_pins(root)
    rsciio_detector, source = load_rsciio_function(root)
    files = verify_files(root, registry, unzipped)
    for extra in extras:
        if not os.path.isfile(extra):
            fail(f"extra file {extra} does not exist")
        label = ("planted/" if os.path.basename(extra) == PLANTED else "extra/") + os.path.basename(extra)
        files.append((label, os.path.abspath(extra), sha256_file(extra), "given on the command line", None))

    result_files, read = {}, {}
    for label, path, digest, source_note, expect_velox in files:
        info = read_file(path, rsciio_detector)
        if expect_velox is not None and info["velox"] != expect_velox:
            fail(f"{label}: Velox is {info['velox']} here, expected {expect_velox}")
        read[label] = info
        result_files[label] = {"path": os.path.abspath(path), "sha256": digest, "source": source_note, **{
            k: info[k] for k in ("format", "velox", "entries")}}

    entries = sum(len(i["entries"]) for i in read.values())
    result = {
        "pins": {"rsciio": RSCIIO_COMMIT, "registry_sha256": REGISTRY_SHA256, "_emd_velox.py_sha256": VELOX_PY_SHA256,
                 "python": sys.version.split()[0], **{p: importlib.metadata.version(p) for p in WANT},
                 "_get_detector_metadata_dict": "cut from the pinned _emd_velox.py with ast (rsciio is not "
                                                "importable here)",
                 "_get_detector_metadata_dict_source": source},
        "files": result_files,
        # The claims are about the public files: planted and extra files are built to break them (a planted fixture
        # may put an ExposureTime on a scanning detector or a mode "TEM" on purpose).
        "claims": claims({k: v for k, v in read.items() if not k.startswith(("planted/", "extra/"))}, root),
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=1, sort_keys=True)
    velox = sum(1 for i in read.values() if i["velox"])
    print(f"reference: {len(read)} files ({velox} Velox, {len(read) - velox} not Velox), {entries} image entries; "
          f"pins ok (registry, _emd_velox.py, h5py {WANT['h5py']}, numpy {WANT['numpy']}, "
          f"Python {result['pins']['python']})")


if __name__ == "__main__":
    main()
