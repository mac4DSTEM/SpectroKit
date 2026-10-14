#!/usr/bin/env python3
"""Writes the planted Velox EMD that SpectroKitTests/VeloxMetadataFieldsTests.swift reads, and its truth file.

    make_fixture.py [--out DIR]     DIR defaults to Tests/SpectroKitTests/Fixtures; writes
                                    velox-metadata-planted.emd and velox-metadata-planted.truth.json there and prints
                                    sha256, size, and for every stored string the Python float it parses to (repr).

What it plants (SpectroKit 0.2.0): the six `VeloxMetadata` fields `nominalMagnification`, `stemMagnification`,
`cameraLengthMeters`, `operatingMode`, `projectorMode`, `exposureTimeSeconds` (macTEM's ask 2 is the five,
`stemMagnification` the owner's sixth of 2026-10-14; plus each `VeloxDetectorInfo`'s `exposureTimeSeconds`), twelve
images, one rule each. `stemMagnification` is `CustomProperties.StemMagnification.value`, what RosettaSciIO 049e7d70
maps as the magnification. Layout copied from Tests/SpectroCoreTests/Fixtures/velox-tiny.emd: root `Version` (a
variable-length string, `{"version": "11", "format": "Velox"}`), `Data/Image/<id>/Data` (a uint16 stack,
(y, x, frame) = (2, 2, 2)), `Data/Image/<id>/Metadata` (uint8, (ROWS, frames); every column one NUL-padded JSON, as
Velox writes it, one column per frame).

Column 0 is what `images()` reads (rsciio's `[:, 0]`). Column 1 is a DECOY: every field has a different value there
(or a value where column 0 has none), so a reader that takes the wrong column cannot pass any case.

The truth is written BY HAND below (TRUTH), as the values the reader must return: it is not computed from the stored
text, and the Swift test repeats it as literals. `check_truth()` only guards the generator against a typo (a
hand-written number that is not what its stored string parses to).

Only the standard library, h5py and numpy are used. Run it with the reference venv's interpreter, isolated:
`References/python-venv/bin/python -I tools/velox-metadata-parity/make_fixture.py` (h5py 3.16.0, numpy 2.5.4,
HDF5 2.0.0). Datasets are written with `track_times=False`, and two runs five seconds apart wrote byte-identical files:
the .emd is 53960 bytes, sha256 d977884f9147365c496217d859cb0b49beea6d75ae3c5e135e6ff06e7100df4e. The committed .emd
is the one the tests read; another h5py/HDF5 may lay the bytes out differently."""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
EMD = "velox-metadata-planted.emd"
TRUTH_JSON = "velox-metadata-planted.truth.json"

# ------------------------------------------------------------------------------------------------ columns
# Velox stores every number as a STRING. Column 0 of each image is what must be read; column 1 is the decoy.


def det(name=None, kind="ImagingDetector", exposure=None):
    """One `Detectors.Detector-<n>` entry. `name=None` leaves DetectorName out (an unnamed entry);
    `exposure=None` leaves ExposureTime out. Keys keep insertion order, which is the file order."""
    d = {}
    if name is not None:
        d["DetectorName"] = name
    d["DetectorType"] = kind
    if exposure is not None:
        d["ExposureTime"] = exposure
    return d


def meta(optics=None, binary=None, detectors=None, custom=None):
    """A metadata column as a dict; a section that is None is absent from the JSON. `detectors` is a list of
    (key, entry) pairs so the key order (the file order) is explicit."""
    m = {}
    if optics is not None:
        m["Optics"] = optics
    if binary is not None:
        m["BinaryResult"] = binary
    if detectors is not None:
        m["Detectors"] = dict(detectors)
    if custom is not None:
        m["CustomProperties"] = custom
    return m


def stem(value):
    """`CustomProperties` holding only `StemMagnification`, written as Velox writes an entry:
    {"type": "double", "value": ...}."""
    return {"StemMagnification": {"type": "double", "value": value}}


def dets(*entries):
    """Detector-0, Detector-1, ... in the order given."""
    return [(f"Detector-{i}", e) for i, e in enumerate(entries)]


CASES = [
    # a: all six as Velox stores them: a camera image carrying BOTH Optics.NominalMagnification and
    # CustomProperties.StemMagnification ("115000", as RosettaSciIO's public '1854 Camera Ceta.emd' does), read
    # independently. Detector-0's name CONTAINS the binary detector's ("BM-Ceta-2" has "BM-Ceta"): the energy axis's
    # `contains` rule would take it (ExposureTime 9); the exposure must take the first EQUAL name (0.5), not the later
    # duplicate (7).
    ("case-a-ceta-strings",
     meta(optics={"AccelerationVoltage": "200000", "NominalMagnification": "8609.4279999999999",
                  "CameraLength": "0.125", "OperatingMode": "1", "ProjectorMode": "2"},
          binary={"Detector": "BM-Ceta", "DetectorIndex": "1"},
          detectors=dets(det("BM-Ceta-2", exposure="9"), det("BM-Ceta", exposure="0.5"), det("BM-Ceta", exposure="7")),
          custom=stem("115000")),
     meta(optics={"AccelerationVoltage": "300000", "NominalMagnification": "1111.25", "CameraLength": "9.75",
                  "OperatingMode": "3", "ProjectorMode": "4"},
          binary={"Detector": "BM-Ceta", "DetectorIndex": "1"},
          detectors=dets(det("BM-Ceta-2", exposure="13"), det("BM-Ceta", exposure="3.25"),
                         det("BM-Ceta", exposure="5")),
          custom=stem("222000"))),

    # b: STEM-like. No Optics.NominalMagnification; CustomProperties.StemMagnification ("225000") is the magnification
    # and is NOT copied into nominalMagnification. The binary detector's entry (HAADF) has no ExposureTime, while
    # another detector has one.
    ("case-b-stem-like",
     meta(optics={"AccelerationVoltage": "200000", "CameraLength": "0.15", "OperatingMode": "1", "ProjectorMode": "1"},
          binary={"Detector": "HAADF", "DetectorIndex": "0"},
          detectors=dets(det("HAADF", kind="ScanningDetector"), det("BM-Ceta", exposure="0.5")),
          custom=stem("225000")),
     meta(optics={"AccelerationVoltage": "300000", "NominalMagnification": "777", "CameraLength": "0.3",
                  "OperatingMode": "2", "ProjectorMode": "3"},
          binary={"Detector": "HAADF", "DetectorIndex": "0"},
          detectors=dets(det("HAADF", kind="ScanningDetector", exposure="1.5"), det("BM-Ceta", exposure="0.5")),
          custom=stem("450000"))),

    # c1: numbers stored as JSON numbers (not strings) are read, the stem magnification's value too; the two modes
    # stored as JSON numbers are nil (strings only).
    ("case-c1-json-numbers",
     meta(optics={"NominalMagnification": 49000.5, "CameraLength": 0.0625, "OperatingMode": 1, "ProjectorMode": 2},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure=0.25)),
          custom=stem(62500.5)),
     meta(optics={"NominalMagnification": "5", "CameraLength": "6", "OperatingMode": "7", "ProjectorMode": "8"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="9")),
          custom=stem("41"))),

    # c2: not a number -> nil: "" and "abc" and "n/a" (and a JSON null mode); the stem magnification "abc" too. A mode
    # that is a string is kept as stored ("TEM", what a Velox TIFF's XML holds).
    ("case-c2-unparsable",
     meta(optics={"NominalMagnification": "", "CameraLength": "abc", "OperatingMode": "TEM", "ProjectorMode": None},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="n/a")),
          custom=stem("abc")),
     meta(optics={"NominalMagnification": "10", "CameraLength": "11", "OperatingMode": "12", "ProjectorMode": "13"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="14")),
          custom=stem("42"))),

    # d1: BinaryResult has no Detector while a detector carries an ExposureTime -> nil. Only ProjectorMode is in Optics,
    # and there is no CustomProperties: the stem magnification is nil, not a copy of anything.
    ("case-d1-no-binary-detector",
     meta(optics={"ProjectorMode": "2"},
          binary={"DetectorIndex": "0"},
          detectors=dets(det("BM-Ceta", exposure="0.5"))),
     meta(optics={"NominalMagnification": "15", "CameraLength": "16", "OperatingMode": "17", "ProjectorMode": "18"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="19")),
          custom=stem("43"))),

    # d2: BinaryResult.Detector is "" and an UNNAMED entry (no DetectorName) carries an ExposureTime -> nil: "" must not
    # match an entry whose name is "". No Optics section at all: every optics field nil.
    ("case-d2-empty-binary-detector",
     meta(binary={"Detector": ""},
          detectors=dets(det(None, exposure="0.75"), det("BM-Ceta", exposure="0.5"))),
     meta(optics={"NominalMagnification": "20", "CameraLength": "21", "OperatingMode": "22", "ProjectorMode": "23"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="24")),
          custom=stem("44"))),

    # e: the FIRST entry of that name has no ExposureTime and a later same-named one has -> nil (the first entry
    # decides, as rsciio's loop returns it). Scientific notation is read: "1e5", "1.5e-1", and "1.3e+006" for the stem
    # magnification, the three-digit exponent RosettaSciIO's public fei_SI_EDS-HAADF-4detectors_2frames.emd stores.
    ("case-e-first-entry-no-exposure",
     meta(optics={"NominalMagnification": "1e5", "CameraLength": "1.5e-1", "OperatingMode": "1", "ProjectorMode": "1"},
          binary={"Detector": "BM-Ceta", "DetectorIndex": "0"},
          detectors=dets(det("BM-Ceta"), det("BM-Ceta", exposure="2")),
          custom=stem("1.3e+006")),
     meta(optics={"NominalMagnification": "25", "CameraLength": "26", "OperatingMode": "27", "ProjectorMode": "28"},
          binary={"Detector": "BM-Ceta", "DetectorIndex": "0"},
          detectors=dets(det("BM-Ceta", exposure="29"), det("BM-Ceta", exposure="30")),
          custom=stem("45"))),

    # f: the Detectors keys are written OUT of index order (4, 2, 5, 1, 3, 0). "File order" is the Detector-<n> index
    # order parse() sorts by, so the first BM-Ceta is Detector-1 (0.5), not the first written (Detector-4, 4). No
    # CustomProperties: the stem magnification is nil.
    ("case-f-key-order",
     meta(optics={"NominalMagnification": "20000", "CameraLength": "0.5", "OperatingMode": "2", "ProjectorMode": "1"},
          binary={"Detector": "BM-Ceta", "DetectorIndex": "1"},
          detectors=[("Detector-4", det("BM-Ceta", exposure="4")), ("Detector-2", det("BM-Ceta", exposure="7")),
                     ("Detector-5", det("BM-Ceta", exposure="5")), ("Detector-1", det("BM-Ceta", exposure="0.5")),
                     ("Detector-3", det("BM-Ceta", exposure="3")),
                     ("Detector-0", det("HAADF", kind="ScanningDetector"))]),
     meta(optics={"NominalMagnification": "31", "CameraLength": "32", "OperatingMode": "33", "ProjectorMode": "34"},
          binary={"Detector": "BM-Ceta", "DetectorIndex": "1"},
          detectors=[("Detector-1", det("BM-Ceta", exposure="35")),
                     ("Detector-0", det("HAADF", kind="ScanningDetector"))],
          custom=stem("46"))),

    # g: zero is a value, not an absence: "0" parses to 0.0 in every numeric field (modes "0" are the string "0"). The
    # stem magnification is stored as three of the four public camera images store it, {"type": "bool", "value": "0"}:
    # the "type" is not consulted, the value is read as RosettaSciIO's `float` reads it.
    ("case-g-zeros",
     meta(optics={"NominalMagnification": "0", "CameraLength": "0", "OperatingMode": "0", "ProjectorMode": "0"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="0")),
          custom={"StemMagnification": {"type": "bool", "value": "0"}}),
     meta(optics={"NominalMagnification": "36", "CameraLength": "37", "OperatingMode": "38", "ProjectorMode": "39"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="40")),
          custom=stem("47"))),

    # h: CustomProperties.StemMagnification is there but has no "value" key -> nil, and Optics.NominalMagnification
    # (60000) is not a fallback for it.
    ("case-h-stem-without-value",
     meta(optics={"NominalMagnification": "60000", "CameraLength": "0.3", "OperatingMode": "1", "ProjectorMode": "1"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="0.1")),
          custom={"StemMagnification": {"type": "double"}}),
     meta(optics={"NominalMagnification": "61", "CameraLength": "62", "OperatingMode": "63", "ProjectorMode": "64"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="52")),
          custom=stem("48"))),

    # i: CustomProperties.StemMagnification is a bare string, not the {"type", "value"} object -> nil.
    ("case-i-stem-bare-string",
     meta(optics={"NominalMagnification": "70000", "CameraLength": "0.4", "OperatingMode": "2", "ProjectorMode": "1"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="0.2")),
          custom={"StemMagnification": "250000"}),
     meta(optics={"NominalMagnification": "65", "CameraLength": "66", "OperatingMode": "67", "ProjectorMode": "68"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="53")),
          custom=stem("49"))),

    # j: CustomProperties itself is a string (RosettaSciIO checks `isinstance(om["CustomProperties"], str)`): the stem
    # magnification and the scan transformation are nil and nothing else is disturbed.
    ("case-j-custom-properties-string",
     meta(optics={"NominalMagnification": "80000", "CameraLength": "0.2", "OperatingMode": "2", "ProjectorMode": "2"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="1.25")),
          custom=""),
     meta(optics={"NominalMagnification": "69", "CameraLength": "70", "OperatingMode": "71", "ProjectorMode": "72"},
          binary={"Detector": "BM-Ceta"},
          detectors=dets(det("BM-Ceta", exposure="54")),
          custom=stem("50"))),
]

# -------------------------------------------------------------------------------------------------- truth
# BY HAND: what `VeloxEMDReader(path:).images()` must return for column 0 of each image. null = nil. Floats as typed
# here (the same decimal text as the Swift literals). `detectorExposures` is each `Detectors` entry's own
# exposureTimeSeconds by Detector-<n> index, i.e. `metadata.detectors` in index order.
TRUTH = {
    "case-a-ceta-strings": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 8609.4279999999999,
        "stemMagnification": 115000.0, "cameraLengthMeters": 0.125,
        "operatingMode": "1", "projectorMode": "2", "exposureTimeSeconds": 0.5,
        "detectorExposures": [9.0, 0.5, 7.0]},
    "case-b-stem-like": {
        "binaryResultDetector": "HAADF", "nominalMagnification": None,
        "stemMagnification": 225000.0, "cameraLengthMeters": 0.15,
        "operatingMode": "1", "projectorMode": "1", "exposureTimeSeconds": None,
        "detectorExposures": [None, 0.5]},
    "case-c1-json-numbers": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 49000.5,
        "stemMagnification": 62500.5, "cameraLengthMeters": 0.0625,
        "operatingMode": None, "projectorMode": None, "exposureTimeSeconds": 0.25,
        "detectorExposures": [0.25]},
    "case-c2-unparsable": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": None,
        "stemMagnification": None, "cameraLengthMeters": None,
        "operatingMode": "TEM", "projectorMode": None, "exposureTimeSeconds": None,
        "detectorExposures": [None]},
    "case-d1-no-binary-detector": {
        "binaryResultDetector": None, "nominalMagnification": None,
        "stemMagnification": None, "cameraLengthMeters": None,
        "operatingMode": None, "projectorMode": "2", "exposureTimeSeconds": None,
        "detectorExposures": [0.5]},
    "case-d2-empty-binary-detector": {
        "binaryResultDetector": "", "nominalMagnification": None,
        "stemMagnification": None, "cameraLengthMeters": None,
        "operatingMode": None, "projectorMode": None, "exposureTimeSeconds": None,
        "detectorExposures": [0.75, 0.5]},
    "case-e-first-entry-no-exposure": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 100000.0,
        "stemMagnification": 1300000.0, "cameraLengthMeters": 0.15,
        "operatingMode": "1", "projectorMode": "1", "exposureTimeSeconds": None,
        "detectorExposures": [None, 2.0]},
    "case-f-key-order": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 20000.0,
        "stemMagnification": None, "cameraLengthMeters": 0.5,
        "operatingMode": "2", "projectorMode": "1", "exposureTimeSeconds": 0.5,
        "detectorExposures": [None, 0.5, 7.0, 3.0, 4.0, 5.0]},
    "case-g-zeros": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 0.0,
        "stemMagnification": 0.0, "cameraLengthMeters": 0.0,
        "operatingMode": "0", "projectorMode": "0", "exposureTimeSeconds": 0.0,
        "detectorExposures": [0.0]},
    "case-h-stem-without-value": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 60000.0, "stemMagnification": None,
        "cameraLengthMeters": 0.3, "operatingMode": "1", "projectorMode": "1", "exposureTimeSeconds": 0.1,
        "detectorExposures": [0.1]},
    "case-i-stem-bare-string": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 70000.0, "stemMagnification": None,
        "cameraLengthMeters": 0.4, "operatingMode": "2", "projectorMode": "1", "exposureTimeSeconds": 0.2,
        "detectorExposures": [0.2]},
    "case-j-custom-properties-string": {
        "binaryResultDetector": "BM-Ceta", "nominalMagnification": 80000.0, "stemMagnification": None,
        "cameraLengthMeters": 0.2, "operatingMode": "2", "projectorMode": "2", "exposureTimeSeconds": 1.25,
        "detectorExposures": [1.25]},
}

# Distinct pixel values per image, so the stacks differ (their values are never asserted; the fields are the test).
STACK_VALUES = {case_id: np.arange(1, 9, dtype=np.uint16).reshape(2, 2, 2) * (i + 1)
                for i, (case_id, _, _) in enumerate(CASES)}


def encode(column):
    return json.dumps(column, separators=(",", ":")).encode("utf-8")


def rows_needed():
    longest = max(len(encode(c)) for _, c0, c1 in CASES for c in (c0, c1))
    rows = 256
    while rows <= longest:        # at least one NUL after the longest column, as Velox pads
        rows *= 2
    return rows, longest


def number(v):
    """What a stored value parses to: a JSON number as is, a string as Python's float() reads it, else None. The
    reader's rule is `Double(String)` or `NSNumber.doubleValue`; no planted string differs between the two (no spaces,
    no underscores)."""
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if not isinstance(v, str):
        return None
    try:
        return float(v) if v.strip() == v and v != "" else None
    except ValueError:
        return None


def stem_value(column):
    """`CustomProperties.StemMagnification.value`. CustomProperties can be a string, the entry a bare string, and
    `value` absent."""
    custom = column.get("CustomProperties")
    entry = custom.get("StemMagnification") if isinstance(custom, dict) else None
    return number(entry.get("value")) if isinstance(entry, dict) else None


def check_truth():
    """Typo guard: a hand-written number must be what the stored string (or JSON number) parses to. Not the truth
    source."""
    by_id = {case_id: c0 for case_id, c0, _ in CASES}
    assert set(by_id) == set(TRUTH), "TRUTH and CASES list different images"
    for case_id, c0 in by_id.items():
        t = TRUTH[case_id]
        optics = c0.get("Optics", {})
        assert t["nominalMagnification"] == number(optics.get("NominalMagnification")), case_id
        assert t["stemMagnification"] == stem_value(c0), case_id
        assert t["cameraLengthMeters"] == number(optics.get("CameraLength")), case_id
        for key, field in (("OperatingMode", "operatingMode"), ("ProjectorMode", "projectorMode")):
            v = optics.get(key)
            assert t[field] == (v if isinstance(v, str) else None), (case_id, key)
        entries = dict(c0.get("Detectors", {}))
        ordered = [entries[k] for k in sorted(entries, key=lambda k: int(k.split("-")[1]))]
        assert t["detectorExposures"] == [number(e.get("ExposureTime")) for e in ordered], case_id
        assert t["binaryResultDetector"] == c0.get("BinaryResult", {}).get("Detector"), case_id


def write_emd(path, rows):
    with h5py.File(path, "w") as f:
        f.create_dataset("Version", data=[json.dumps({"version": "11", "format": "Velox"})], dtype=h5py.string_dtype())
        for case_id, c0, c1 in CASES:
            g = f.create_group(f"Data/Image/{case_id}")
            g.create_dataset("Data", data=STACK_VALUES[case_id], track_times=False)    # (y, x, frame)
            columns = []
            for c in (c0, c1):
                b = encode(c)
                columns.append(np.frombuffer(b.ljust(rows, b"\0"), dtype=np.uint8))
            g.create_dataset("Metadata", data=np.stack(columns, axis=1), track_times=False)    # (rows, frames)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=ROOT / "Tests" / "SpectroKitTests" / "Fixtures")
    out = ap.parse_args().out
    out.mkdir(parents=True, exist_ok=True)
    check_truth()
    rows, longest = rows_needed()
    emd = out / EMD
    write_emd(emd, rows)
    (out / TRUTH_JSON).write_text(json.dumps(TRUTH, indent=2) + "\n", encoding="utf-8")
    print(f"{emd}: {emd.stat().st_size} bytes, sha256 {sha256(emd)}; "
          f"Metadata rows {rows} (longest column {longest} bytes)")
    print(f"h5py {h5py.__version__}, numpy {np.__version__}, HDF5 {h5py.version.hdf5_version}")
    print("stored strings and the Double each parses to (the Swift literal must be this decimal text):")

    def show(case_id, path, v):
        if isinstance(v, str):
            n = number(v)
            print(f"  {case_id} {path} {v!r} -> " + (repr(n) if n is not None else "not a number"))

    for case_id, c0, _ in CASES:
        optics = c0.get("Optics", {})
        for key in ("NominalMagnification", "CameraLength"):
            show(case_id, f"Optics.{key}", optics.get(key))
        custom = c0.get("CustomProperties")
        entry = custom.get("StemMagnification") if isinstance(custom, dict) else None
        stem_stored = entry.get("value") if isinstance(entry, dict) else None
        show(case_id, "CustomProperties.StemMagnification.value", stem_stored)
        for k, e in c0.get("Detectors", {}).items():
            show(case_id, f"{k} ExposureTime", e.get("ExposureTime"))


if __name__ == "__main__":
    main()
