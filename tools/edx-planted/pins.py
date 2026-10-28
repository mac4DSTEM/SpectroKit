#!/usr/bin/env python3
"""exSpy / HyperSpy / RosettaSciIO pins for SpectroKit's EDX stage gates (registration section 4), written before the Swift tests.

Agreement with exSpy is agreement, not truth: the truth is make_planted.py and make_velox_streams.py. The only absolute
statements here are the NumPy decode of the Velox streams (asserted equal to RosettaSciIO's published constants and to the
planted draws) and the planted-truth readings in README.md.

Run (reference venv, isolated; exSpy is NOT installed, its pinned checkout is put first on sys.path and the signal classes
are built directly, as tools/eels-thickness/pins.py does). Run make_planted.py and make_velox_streams.py first:

    References/python/bin/python -I -B tools/edx-planted/pins.py [--fixtures DIR] [--out DIR]

Reads  edx-planted*.{json,f64,i16}, edx-calibration*.{json,u32}, velox-stream-*.emd, velox-streams-truth.json from --fixtures
(default Tests/SpectroEDXTests/Fixtures) and, from the pinned RosettaSciIO checkout, the public Velox files (the four zips,
sha256 checked against rsciio/tests/registry.txt, read in memory / unzipped to a temporary directory that is removed).
Writes into --out (default --fixtures):
    pins.json                  see below; numbers are exact integers or Python reprs (json.dumps of floats)
    edx-axis-e2.f64            the E2 query values (float64 LE); their indices are in pins.json
    edx-pins-intensity.f64     get_lines_intensity of every planted spectrum, (nspectra, 6) float64, see pins.json lines.intensity
Everything is deterministic (no times, no absolute paths): two runs write identical bytes, pins.json records its own inputs' sha256.

pins.json
  versions, commits               what ran
  counts.published                RosettaSciIO's constants (test_emd_velox.py:463-467), asserted against the decode
  counts.files[label]             for each public Velox file with a SpectrumStream: grid (ScanSize x ScanArea; the last 3-D integer
                                  image's shape as rsciio takes it, for the report), bincount, frames (markers, endFramePosition,
                                  the default range), per stream: id, BinaryResult.Detector, values, markers, events, channel_sums
                                  (sparse [channel, count]), pixel_totals; dense_sha256 = sha256 of the summed-over-streams cube as
                                  uint32 LE in (y, x, channel) C order (Swift: denseCounts()), total events
  counts.planted[case]            the planted files decoded the same way, asserted equal to the draw, plus frame ranges
  counts.exspy_sum                EDSTEMSpectrum.sum of a planted 4 x 5 x 64 uint16 image: dtype, equality with uint64 NumPy, max, live_time factor
  counts.big_pool                 exact arithmetic for totals above 2^32 (no fixture: the Swift test builds the pool)
  axis.rsciio_rule                _get_dispersion_offset (cut out of the pinned _emd_velox.py with ast, file sha256 asserted) applied to every
                                  stream's column-0 metadata of every public file and every planted file: dispersion, offset (keV, repr), units
  axis.e2                         HyperSpy UniformDataAxis(4096, 0.02, -1.93221348).value2index at every table line energy (Z 5-50), +-1e-13 around
                                  every channel midpoint, the ends; values in edx-axis-e2.f64, indices (null where HyperSpy raises) here
  axis.slices                     value_range_to_indices / _get_array_slices for (lo, hi) windows around table lines
  axis.calibration                exSpy calibrate_energy_axis("offset"|"scale"|"resolution") on the calibration set (offset/scale of the cropped axis
                                  before and after, energy_resolution_MnKa, or the exception text)
  lines.near                      get_xray_lines_near_energy on 60 energies x widths 0.05, 0.2, 0.5 x only_lines None / ["a"]
  lines.line_energy               _get_line_energy for Mg_Ka, Al_Ka, Si_Ka at R_MnKa 125..150
  lines.windows                   estimate_integration_windows (factor 2.0) and estimate_background_windows, merged and unmerged, for the planted line lists
  lines.intensity                 get_lines_intensity for [Al_Ka, Mg_Ka, Si_Ka]: row order = edx-planted.json cells order, per cell the noise-free mean
                                  (rint NOT applied: the float mean) then its realisations; columns Al/Mg/Si with background windows, then Al/Mg/Si without
  peaks                           find_peaks1D_ohaver on U130 / family L cells (N 1e5, 1e6, 1e7 x rho .002, .01, .05), realisations 1..5, two settings
Spectra for lines.intensity and peaks are the stored 1056-channel window placed at channels 96..1151 of a 4096-channel zero array.
"""
import argparse
import ast
import contextlib
import hashlib
import importlib.util
import json
import logging
import math
import os
import re
import shutil
import sys
import tempfile
import types
import warnings
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--exspy", default=os.path.join(REPO, "References", "exspy-7185a4d1"))
ap.add_argument("--rsciio", default=os.path.join(REPO, "References", "rosettasciio"))
ap.add_argument("--fixtures", default=os.path.join(REPO, "Tests", "SpectroEDXTests", "Fixtures"))
ap.add_argument("--out", default=None)
ARGS = ap.parse_args()
FIX = os.path.abspath(ARGS.fixtures)
OUT = os.path.abspath(ARGS.out or ARGS.fixtures)
EXSPY = os.path.abspath(ARGS.exspy)
RSCIIO = os.path.abspath(ARGS.rsciio)
os.makedirs(OUT, exist_ok=True)

sys.path.insert(0, EXSPY)
logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")

import numpy as np                                     # noqa: E402
import h5py                                            # noqa: E402

with open(os.devnull, "w") as _dn, contextlib.redirect_stdout(_dn), contextlib.redirect_stderr(_dn):
    import hyperspy                                    # noqa: E402
    import hyperspy.api as hs                          # noqa: E402
    from hyperspy.axes import UniformDataAxis          # noqa: E402
    import exspy                                       # noqa: E402
    from exspy.signals import EDSTEMSpectrum           # noqa: E402
    from exspy.utils.eds import get_xray_lines_near_energy   # noqa: E402
    from exspy.material import elements as EXSPY_ELEMENTS    # noqa: E402
    import rsciio                                      # noqa: E402

assert os.path.realpath(os.path.dirname(exspy.__file__)) == os.path.realpath(os.path.join(EXSPY, "exspy")), exspy.__file__

EXSPY_COMMIT = "7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e"
RSCIIO_COMMIT = "049e7d7070e84779b499adaf3295beee9facb004"
REGISTRY_SHA256 = "31417482938f80160be2c03525ba58dd810c7f16b1790f597470ece8dd0b1bcb"
VELOX_PY_SHA256 = "1a3e12f2d550c5378c5e3ee0e02c963f0ef547af9dd4bde9bd1c2ee2df56a8e3"
ZIPS = ["fei_emd_files.zip", "velox_EELS_EDS.zip", "velox_emd_v11_elementSelection.zip", "velox_emd_version11.zip"]
LOOSE = ["FFTComplexEven.emd", "FFTComplexOdd.emd", "fei_example_complex_fft.emd", "fei_example_dpc_titles.emd", "fei_example_tem_stack.emd"]
PUBLISHED = {"streams": [865236, 913682, 867647, 916174], "total": 3562739}   # test_emd_velox.py:463-467 (s[-1] .. s[-4])
MARK = 65535


def fail(msg):
    print("FAIL:", msg, file=sys.stderr)
    sys.exit(1)


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


@contextlib.contextmanager
def quiet():
    with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
        yield


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


MP = load_module("make_planted", os.path.join(HERE, "make_planted.py"))
OFF, SC, NCH, K0, NWIN = MP.OFF, MP.SC, MP.NCH, MP.K0, MP.NWIN


def enc(x):
    return None if x is None else float(x)


# ------------------------------------------------------------------------------------------------- inputs / pins
def check_inputs():
    reg = os.path.join(RSCIIO, "rsciio", "tests", "registry.txt")
    if sha256_file(reg) != REGISTRY_SHA256:
        fail("registry.txt is not the pinned file")
    registry = {}
    for line in open(reg, encoding="utf-8"):
        m = re.match(r"^'([^']+)'\s+([0-9a-f]{64})\s*$", line)
        if m:
            registry[m.group(1)] = m.group(2)
    velox = os.path.join(RSCIIO, "rsciio", "emd", "_emd_velox.py")
    if sha256_file(velox) != VELOX_PY_SHA256:
        fail("_emd_velox.py is not the pinned file")
    assert os.path.realpath(os.path.dirname(rsciio.__file__)) != os.path.realpath(os.path.join(RSCIIO, "rsciio")), "unexpected: the venv rsciio is the pinned one"
    return registry, velox


def rsciio_dispersion_offset(velox_path):
    source = open(velox_path, encoding="utf-8").read()
    found = []
    for node in ast.parse(source).body:
        if isinstance(node, ast.ClassDef):
            for sub in node.body:
                if isinstance(sub, ast.FunctionDef) and sub.name == "_get_dispersion_offset":
                    found.append(sub)
    if len(found) != 1:
        fail("_get_dispersion_offset is not a single method of the pinned _emd_velox.py")
    fn = found[0]
    mod = ast.Module(body=[fn], type_ignores=[])
    ns = {"_logger": logging.getLogger("rsciio-axis")}
    exec(compile(mod, velox_path, "exec"), ns)
    f = ns["_get_dispersion_offset"]
    stub = types.SimpleNamespace(rebin_energy=1)
    return (lambda om: f(stub, om)), ast.get_source_segment(source, fn)


def column_json(ds, col):
    return json.loads(bytes(ds[:, col]).split(b"\0")[0].decode("utf-8"))


def parse_json_str(x):
    x = x.decode("utf-8") if isinstance(x, bytes) else x
    return json.loads(x)


def stream_words(g):
    return np.asarray(g["Data"][:, 0], dtype=np.uint16)


def derive_grid(meta):
    try:
        w, h = int(meta["Scan"]["ScanSize"]["width"]), int(meta["Scan"]["ScanSize"]["height"])
        a = meta["Scan"]["ScanArea"]
        nx = w * (float(a["right"]) - float(a["left"]))
        ny = h * (float(a["bottom"]) - float(a["top"]))
        if abs(nx - round(nx)) < 0.01 and abs(ny - round(ny)) < 0.01 and nx >= 1 and ny >= 1:
            return int(round(ny)), int(round(nx))
    except (KeyError, TypeError, ValueError):
        pass
    return None


def last_image_grid(f):
    """rsciio's rule: the shape of the LAST (name order) Data/Image entry with a rank-3 Data."""
    last = None
    if "Data/Image" in f:
        for name in sorted(f["Data/Image"]):
            d = f["Data/Image"][name].get("Data")
            if d is not None and len(d.shape) == 3:
                last = (int(d.shape[0]), int(d.shape[1]), np.issubdtype(d.dtype, np.integer))
    return last


def decode_stream(words, npix, first, last, channels):
    """The independent NumPy decoder: 65535 ends a pixel; frame = markers before // pixels, pixel = markers before % pixels;
    events of frames first <= f < last. Returns (pixel indices, channels) of the counted events and the out-of-range count."""
    m = words == MARK
    before = np.cumsum(m) - m
    frame = before // npix
    ok = (~m) & (frame >= first) & (frame < last)
    ch = words[ok].astype(np.int64)
    pix = (before[ok] % npix).astype(np.int64)
    bad = ch >= channels
    return pix[~bad], ch[~bad], int(bad.sum())


def stream_summary(words, npix, first, last, channels):
    pix, ch, bad = decode_stream(words, npix, first, last, channels)
    sums = np.bincount(ch, minlength=channels)
    totals = np.bincount(pix, minlength=npix)
    return pix, ch, sums, totals, bad


def sparse(sums):
    nz = np.nonzero(sums)[0]
    return [[int(c), int(sums[c])] for c in nz]


def analyse_file(path, label, axis_fn, detail=True):
    out = {"label": label, "sha256": sha256_file(path)}
    with h5py.File(path, "r") as f:
        if "Data/SpectrumStream" not in f:
            out["status"] = "no SpectrumStream"
            return out, []
        names = sorted(f["Data/SpectrumStream"])
        if not names:
            out["status"] = "empty SpectrumStream"
            return out, []
        g0 = f["Data/SpectrumStream"][names[0]]
        meta0 = column_json(g0["Metadata"], 0)
        grid = derive_grid(meta0)
        li = last_image_grid(f)
        settings = parse_json_str(g0["AcquisitionSettings"][0])
        channels = int(settings["bincount"])
        sip = None
        if "Data/SpectrumImage" in f:
            for n in sorted(f["Data/SpectrumImage"]):
                if "SpectrumImageSettings" in f["Data/SpectrumImage"][n]:
                    sip = parse_json_str(f["Data/SpectrumImage"][n]["SpectrumImageSettings"][0])
                    break
        out["grid_scansize_x_scanarea"] = None if grid is None else {"ny": grid[0], "nx": grid[1]}
        out["grid_last_image"] = None if li is None else {"ny": li[0], "nx": li[1], "integer": bool(li[2])}
        out["bincount"] = channels
        out["settings"] = sip
        if grid is None:
            if li is None or not li[2]:
                out["status"] = "grid unresolved"
                return out, []
            grid = (li[0], li[1])
            out["grid_source"] = "last image (rsciio)"
        npix = grid[0] * grid[1]
        words = [stream_words(f["Data/SpectrumStream"][n]) for n in names]
        markers = [int((w == MARK).sum()) for w in words]
        frames_guess = -(-markers[0] // npix)
        end = None if sip is None or "endFramePosition" not in sip else int(sip["endFramePosition"])
        last = end if end is not None else frames_guess
        out["markers"] = markers
        out["frames_from_markers"] = frames_guess
        out["frames_default"] = last
        dense_idx = np.zeros(npix * channels, dtype=np.int64)
        streams = []
        axes = []
        for n, w, mk in zip(names, words, markers):
            g = f["Data/SpectrumStream"][n]
            pix, ch, sums, totals, bad = stream_summary(w, npix, 0, last, channels)
            dense_idx += np.bincount(pix * channels + ch, minlength=npix * channels)
            meta = column_json(g["Metadata"], 0)
            streams.append({"id": n, "detector": (meta.get("BinaryResult") or {}).get("Detector"), "values": int(w.size), "markers": mk,
                            "events": int(sums.sum()), "out_of_range": bad, "channel_sums": sparse(sums), "pixel_totals": [int(x) for x in totals],
                            "FrameLocationTable": [int(x) for x in g["FrameLocationTable"][:, 0]] if "FrameLocationTable" in g else None})
            try:
                d, o, u = axis_fn(meta)
                axes.append({"stream": n, "dispersion_keV": enc(d), "offset_keV": enc(o), "units": u})
            except Exception as e:                                   # rsciio would raise
                axes.append({"stream": n, "error": type(e).__name__})
        assert dense_idx.max() < 2 ** 32
        out["streams"] = streams
        out["total_events"] = int(sum(s["events"] for s in streams))
        out["dense_sha256"] = sha256_bytes(dense_idx.astype("<u4").tobytes())
        out["status"] = "ok"
    return out, axes


# ------------------------------------------------------------------------------------------------- the stages
def counts_section(registry, velox_path, axis_fn):
    sec = {"published": {"streams_in_stream_order_of_the_4detector_file": None, "constants": PUBLISHED}, "files": {}, "planted": {}}
    axis_files = {}
    tmp = tempfile.mkdtemp(prefix="edx-stages-")
    try:
        data = os.path.join(RSCIIO, "rsciio", "tests", "data", "emd")
        paths = []
        for name in ZIPS:
            zp = os.path.join(data, name)
            if sha256_file(zp) != registry["emd/" + name]:
                fail(f"{name}: sha256 differs from the registry")
            with zipfile.ZipFile(zp) as z:
                for info in z.infolist():
                    if info.is_dir() or not info.filename.endswith(".emd"):
                        continue
                    target = os.path.join(tmp, name[:-4], info.filename)
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    with open(target, "wb") as fh:
                        fh.write(z.read(info))
                    paths.append((f"{name[:-4]}.zip/{info.filename}", target))
        for name in LOOSE:
            p = os.path.join(data, name)
            if sha256_file(p) != registry["emd/" + name]:
                fail(f"{name}: sha256 differs from the registry")
            paths.append((f"loose/{name}", p))
        for label, p in sorted(paths):
            res, axes = analyse_file(p, label, axis_fn)
            if res.get("status") == "ok":
                sec["files"][label] = res
                axis_files[label] = axes
            else:
                sec["files"][label] = {k: res[k] for k in res if k in ("label", "sha256", "status")}
        fei = sec["files"].get("fei_emd_files.zip/fei_SI_EDS-HAADF-4detectors_2frames.emd")
        if fei is None or fei.get("status") != "ok":
            fail("the 4-detector file is missing from the pinned checkout")
        ev = [s["events"] for s in fei["streams"]]
        sec["published"]["streams_in_stream_order_of_the_4detector_file"] = ev
        if sorted(ev) != sorted(PUBLISHED["streams"]) or sum(ev) != PUBLISHED["total"]:
            fail(f"the NumPy decode {ev} differs from the published constants {PUBLISHED}")
        if fei["markers"] != [512] * 4:
            fail(f"markers {fei['markers']}")
    finally:
        shutil.rmtree(tmp)
    # planted files
    truth = json.load(open(os.path.join(FIX, "velox-streams-truth.json")))
    axis_planted = {}
    for case, t in sorted(truth["cases"].items()):
        p = os.path.join(FIX, t["file"])
        if sha256_file(p) != t["sha256"]:
            fail(f"{t['file']} is not the file the truth describes (run make_velox_streams.py)")
        res, axes = analyse_file(p, case, axis_fn)
        axis_planted[case] = axes
        ny, nx, frames = t["grid"]["ny"], t["grid"]["nx"], t["frames"]
        npix = ny * nx
        assert res["grid_scansize_x_scanarea"] == {"ny": ny, "nx": nx}, (case, res["grid_scansize_x_scanarea"])
        ranges = {}
        with h5py.File(p, "r") as f:
            names = sorted(f["Data/SpectrumStream"])
            for rng_ in sorted({(0, frames)} | {(a, b) for a in range(frames) for b in range(a + 1, frames + 1)}):
                per = []
                for si, n in enumerate(names):
                    w = stream_words(f["Data/SpectrumStream"][n])
                    _, _, sums, totals, bad = stream_summary(w, npix, rng_[0], rng_[1], 4096)
                    assert bad == 0
                    # the draw
                    ev = t["streams"][si]["events"]
                    exp_sums = np.zeros(4096, dtype=np.int64)
                    exp_tot = np.zeros(npix, dtype=np.int64)
                    for fr in range(rng_[0], rng_[1]):
                        for px in range(npix):
                            for c, k in ev[fr][px]:
                                exp_sums[c] += k
                                exp_tot[px] += k
                    if not (np.array_equal(sums, exp_sums) and np.array_equal(totals, exp_tot)):
                        fail(f"planted {case} stream {n} frames {rng_}: the NumPy decode differs from the draw")
                    per.append({"channel_sums": sparse(sums), "pixel_totals": [int(x) for x in totals]})
                ranges[f"{rng_[0]}..{rng_[1]}"] = per
        # the full-range summary must equal the truth's own sums
        for si, s in enumerate(res["streams"]):
            if s["channel_sums"] != t["streams"][si]["channel_sums"] or s["pixel_totals"] != t["streams"][si]["pixel_totals"]:
                fail(f"planted {case}: summary differs from truth")
        res["frame_ranges"] = ranges
        res["truth_file"] = t["file"]
        sec["planted"][case] = res
    # exSpy sum
    rng = np.random.default_rng(2)
    d = rng.poisson(0.5, size=(4, 5, 64)).astype(np.uint16)
    d[0, 0, 3] = 65535
    d[1, 1, 3] = 65535
    with quiet():
        s = EDSTEMSpectrum(d)
        s.set_microscope_parameters(beam_energy=200.0, live_time=2.0, energy_resolution_MnKa=130.0)
        t = s.sum()
    sec["exspy_sum"] = {"input": "numpy default_rng(2).poisson(0.5, (4,5,64)) as uint16, [0,0,3] = [1,1,3] = 65535",
                        "dtype": str(t.data.dtype), "equals_numpy_uint64_sum": bool(np.array_equal(t.data, d.sum(axis=(0, 1), dtype=np.uint64))),
                        "max": int(t.data.max()), "live_time_in": 2.0,
                        "live_time_out": float(t.metadata.Acquisition_instrument.TEM.Detector.EDS.live_time),
                        "numpy_default_sum_dtype": str(d.sum(axis=(0, 1)).dtype), "channel3": int(t.data[3])}
    sec["big_pool"] = {"what": "no fixture: the Swift test builds this pool; all values exact in Double (< 2^53)",
                       "channel": 100, "pixel_counts": [4000000000, 4000000000, 4294967295],
                       "sum": 4000000000 + 4000000000 + 4294967295, "sum_gt_2e32": 4000000000 + 4000000000 + 4294967295 > 2 ** 32,
                       "mask_first_two": 8000000000, "mask_last": 4294967295}
    return sec, axis_files, axis_planted


def axis_section(axis_files, axis_planted, velox_path, rule_source):
    sec = {"rsciio_rule": {"function_sha256": sha256_bytes(rule_source.encode()), "files": axis_files, "planted": axis_planted}}
    truth = json.load(open(os.path.join(FIX, "velox-streams-truth.json")))
    for case, t in truth["cases"].items():           # hand-written literals in make_velox_streams.py vs rsciio's own function
        got = [(a.get("dispersion_keV"), a.get("offset_keV")) for a in axis_planted[case]]
        want = [(float(d) / 1000.0, float(o) / 1000.0) for d, o in t["expect_axis_ev"]]
        if got != want:
            fail(f"axis rule on planted {case}: {got} differs from the hand-written {want}")
    # E2
    lines_all = []
    for el in sorted((k for k in EXSPY_ELEMENTS.as_dictionary() if not k.startswith('_')), key=lambda k: EXSPY_ELEMENTS[k].General_properties.Z):
        z = EXSPY_ELEMENTS[el].General_properties.Z
        if 5 <= z <= 50:
            for ln, v in EXSPY_ELEMENTS[el].Atomic_properties.Xray_lines.as_dictionary().items():
                if v["energy (keV)"] > 0:
                    lines_all.append((f"{el}_{ln}", float(v["energy (keV)"])))
    ax = UniformDataAxis(size=NCH, scale=SC, offset=OFF, units="keV")
    mid = [OFF + SC * (k + 0.5) for k in range(NCH - 1)]
    ends = [OFF - 1e-13, OFF, OFF + 1e-13, OFF + SC * (NCH - 1) - 1e-13, OFF + SC * (NCH - 1), OFF + SC * (NCH - 1) + 1e-13,
            OFF - 0.01, OFF + SC * (NCH - 1) + 0.01, OFF - 1.0, 100.0]
    vals = [e for _, e in lines_all] + [m + d for m in mid for d in (-1e-13, 0.0, 1e-13)] + ends
    idx = []
    for v in vals:
        try:
            idx.append(int(ax.value2index(v)))
        except Exception:
            idx.append(None)
    arr = np.array(vals, dtype="<f8")
    path = os.path.join(OUT, "edx-axis-e2.f64")
    arr.tofile(path)
    sec["e2"] = {"axis": {"size": NCH, "scale": SC, "offset": OFF}, "file": "edx-axis-e2.f64", "sha256": sha256_file(path), "count": len(vals),
                 "layout": "table line energies (names in line_names), then 3 values per channel midpoint (-1e-13, 0, +1e-13) for k = 0..4094, then the ends",
                 "line_names": [n for n, _ in lines_all], "n_lines": len(lines_all), "n_midpoints": len(mid), "index": idx, "rounding": "HyperSpy default (round)"}
    # slicing windows
    pairs = []
    for i, (n, e) in enumerate(lines_all):
        if i % 11 == 0:
            for w in (0.05, 0.3):
                pairs.append((n, e - w, e + w))
    slices = []
    sig = hs.signals.Signal1D(np.zeros(NCH))
    sax = sig.axes_manager.signal_axes[0]
    sax.offset, sax.scale, sax.units = OFF, SC, "keV"
    for n, lo, hi in pairs:
        try:
            i1, i2 = ax.value_range_to_indices(lo, hi)
            sl = ax._get_array_slices(slice(lo, hi))
            with quiet():
                cropped = sig.isig[lo:hi]
            assert (sl.start, sl.stop) == (i1, i2) and cropped.data.size == i2 - i1, (n, lo, hi, i1, i2, sl)
            slices.append({"line": n, "lo": lo, "hi": hi, "i1": int(i1), "i2": int(i2), "size": int(i2 - i1)})
        except AssertionError:
            raise
        except Exception as e:
            slices.append({"line": n, "lo": lo, "hi": hi, "error": type(e).__name__})
    sec["slices"] = slices
    sec["calibration"] = calibration_pins()
    return sec


def calibration_pins():
    man = json.load(open(os.path.join(FIX, "edx-calibration.json")))
    cnt = np.fromfile(os.path.join(FIX, "edx-calibration-counts.u32"), dtype="<u4").reshape(-1, man["nwin"])
    if sha256_file(os.path.join(FIX, "edx-calibration-counts.u32")) != man["counts"]["sha256"]:
        fail("edx-calibration-counts.u32 differs from its manifest")
    rows = []
    for c in man["cells"]:
        for j in range(c["n_real"]):
            y = np.zeros(NCH)
            y[man["k0"]:man["k0"] + man["nwin"]] = cnt[c["row0"] + j]
            entry = {"cell": c["id"], "realisation": j + 1, "modes": {}}
            for mode in ("offset", "scale", "resolution"):
                with quiet():
                    s = EDSTEMSpectrum(y.copy())
                    ax = s.axes_manager.signal_axes[0]
                    ax.offset, ax.scale, ax.units = OFF, SC, "keV"
                    s.set_microscope_parameters(beam_energy=200.0, energy_resolution_MnKa=130.0)
                    s.set_elements(["Mg", "Al", "Si"])
                    s.set_lines(["Mg_Ka", "Al_Ka", "Si_Ka"])
                    s = s.isig[0.3:3.0]
                    ax = s.axes_manager.signal_axes[0]
                    before = (float(ax.offset), float(ax.scale))
                    m = s.create_model(auto_background=True, auto_add_lines=True)
                    m.fit()
                    try:
                        m.calibrate_energy_axis(mode, xray_lines=["Mg_Ka", "Al_Ka", "Si_Ka"])
                        ax = s.axes_manager.signal_axes[0]
                        entry["modes"][mode] = {"offset_before": before[0], "scale_before": before[1], "offset_after": float(ax.offset),
                                                "scale_after": float(ax.scale),
                                                "energy_resolution_MnKa": float(s.metadata.Acquisition_instrument.TEM.Detector.EDS.energy_resolution_MnKa)}
                    except Exception as e:
                        entry["modes"][mode] = {"error": type(e).__name__, "message": str(e).replace("\n", " ")[:160]}
            rows.append(entry)
    return {"setup": "isig[0.3:3.0], lines Mg_Ka Al_Ka Si_Ka, create_model(auto_background=True, auto_add_lines=True), fit, then calibrate_energy_axis(mode, xray_lines); model energy_resolution_MnKa 130; offsets/scales are those of the CROPPED axis (its offset is the first kept channel's energy)",
            "rows": rows}


def lines_section():
    sec = {}
    # table assertion: make_planted's typed values equal exSpy's
    for el, ls in MP.TABLE.items():
        xl = EXSPY_ELEMENTS[el].Atomic_properties.Xray_lines.as_dictionary()
        for (e, w), name in zip(ls, ("Ka", "Kb")):
            assert float(xl[name]["energy (keV)"]) == e and float(xl[name]["weight"]) == w, (el, name, xl[name], e, w)
    sec["table_asserted_equal_to_make_planted"] = True
    # near
    energies = [1.2536, 1.4865, 1.7397, 0.5249, 2.9577, 6.4038, 0.2774, 0.6769, 0.9297, 8.0478, 1.0, 3.0]
    allv = sorted({e for _, e in [(0, float(v["energy (keV)"])) for el in EXSPY_ELEMENTS.as_dictionary() if not el.startswith('_') for v in EXSPY_ELEMENTS[el].Atomic_properties.Xray_lines.as_dictionary().values()] if 0.2 < e < 10})
    ties = []
    for a, b in zip(allv[:-1], allv[1:]):
        if 1.0 < a < 4.0 and 0 < b - a < 0.15:
            mid = (a + b) / 2
            if abs(mid - a) == abs(mid - b) and mid not in ties:
                ties.append(mid)
        if len(ties) >= 8:
            break
    energies += ties[:8]
    k = 0
    while len(energies) < 60:
        energies.append(round(0.35 + 0.17 * k, 4))
        k += 1
    energies = energies[:60]
    LINE_ENERGY = {f"{el}_{ln}": float(v["energy (keV)"]) for el in EXSPY_ELEMENTS.as_dictionary() if not el.startswith("_")
                   for ln, v in EXSPY_ELEMENTS[el].Atomic_properties.Xray_lines.as_dictionary().items()}
    near = []
    for e in energies:
        for width in (0.05, 0.2, 0.5):
            for only in (None, ["a"]):
                r = list(get_xray_lines_near_energy(e, width=width, only_lines=only))
                # exSpy iterates a hash-ordered element dict (differs per process), so the order of EXACTLY tied |dE| lines is
                # not reproducible: canonical order = (|dE| as exSpy computes it, name); tied groups are reported
                dE = {n: abs(LINE_ENERGY[n] - e) for n in r}
                r = sorted(r, key=lambda n: (dE[n], n))
                tied = sum(1 for a, b in zip(r[:-1], r[1:]) if dE[a] == dE[b])
                near.append({"energy": e, "width": width, "only_lines": only, "lines": r, "tied_adjacent_pairs": tied})
    sec["near"] = {"order_note": "exSpy order of exactly tied |dE| lines varies between processes (hash-ordered element dict); lines are in canonical order (|dE|, name)", "n_energies": len(energies), "ties_exact": len(ties[:8]), "cases": near}
    # line energy and FWHM
    le = []
    with quiet():
        s = EDSTEMSpectrum(np.zeros(NCH))
        ax = s.axes_manager.signal_axes[0]
        ax.offset, ax.scale, ax.units = OFF, SC, "keV"
        for r in (125.0, 130.0, 135.0, 140.0, 145.0, 150.0):
            for xl in ("Mg_Ka", "Al_Ka", "Si_Ka"):
                e, w = s._get_line_energy(xl, FWHM_MnKa=r)
                le.append({"line": xl, "R_MnKa": r, "energy": float(e), "fwhm": float(w)})
    sec["line_energy"] = le
    # windows
    wins = []
    lists = [["Al_Ka", "Mg_Ka", "Si_Ka"], ["Mg_Ka"], ["Al_Ka", "Al_Kb"], ["Mg_Ka", "Mg_Kb", "Al_Ka", "Al_Kb", "Si_Ka", "Si_Kb"]]
    for r in (125.0, 130.0, 140.0, 150.0):
        for ll in lists:
            with quiet():
                s = EDSTEMSpectrum(np.zeros(NCH))
                ax = s.axes_manager.signal_axes[0]
                ax.offset, ax.scale, ax.units = OFF, SC, "keV"
                s.set_microscope_parameters(beam_energy=200.0, energy_resolution_MnKa=r)
                s.set_elements(sorted({x.split("_")[0] for x in ll}))
                s.set_lines(ll)
                xl = list(s._get_xray_lines())
                iw = np.array(s.estimate_integration_windows(2.0, xray_lines=xl))
                merged = np.array(s.estimate_background_windows(xray_lines=xl))
                unmerged = [np.array(s.estimate_background_windows(xray_lines=[x]))[0].tolist() for x in xl]
            wins.append({"R_MnKa": r, "lines": xl, "integration": iw.tolist(), "background_merged": merged.tolist(), "background_unmerged": unmerged})
    sec["windows"] = wins
    return sec


def load_cell_arrays():
    man = json.load(open(os.path.join(FIX, "edx-planted.json")))
    for fname, meta in man["files"].items():
        if sha256_file(os.path.join(FIX, fname)) != meta["sha256"]:
            fail(f"{fname} differs from edx-planted.json (run make_planted.py)")
    means = np.fromfile(os.path.join(FIX, "edx-planted-means.f64"), dtype="<f8").reshape(-1, man["nwin"])
    resid = np.fromfile(os.path.join(FIX, "edx-planted-resid.i16"), dtype="<i2").reshape(-1, man["nwin"])
    return man, means, resid


def full_rows(man, means, resid, c, with_mean=True):
    rows = []
    if with_mean:
        rows.append(means[c["mean_row"]])
    if c["n_real"]:
        base = np.rint(means[c["mean_row"]])
        for j in range(c["n_real"]):
            rows.append(base + resid[c["resid_row0"] + j])
    arr = np.zeros((len(rows), NCH))
    arr[:, man["k0"]:man["k0"] + man["nwin"]] = np.array(rows)
    return arr


def intensity_section(man, means, resid):
    lines = ["Al_Ka", "Mg_Ka", "Si_Ka"]
    out_rows = []
    index = []
    with quiet():
        probe = EDSTEMSpectrum(np.zeros((1, NCH)))
    for c in man["cells"]:
        arr = full_rows(man, means, resid, c)
        with quiet():
            s = EDSTEMSpectrum(arr)
            ax = s.axes_manager.signal_axes[0]
            ax.offset, ax.scale, ax.units = OFF, SC, "keV"
            s.set_microscope_parameters(beam_energy=200.0, energy_resolution_MnKa=130.0)
            s.set_elements(["Al", "Mg", "Si"])
            s.set_lines(lines)
            xl = list(s._get_xray_lines())
            bw = s.estimate_background_windows(xray_lines=xl)
            iw = s.estimate_integration_windows(2.0, xray_lines=xl)
            lo_k = min(int(ax.value2index(np.min(bw))), int(ax.value2index(np.min(iw))))
            hi_k = max(int(ax.value2index(np.max(bw))), int(ax.value2index(np.max(iw))))
            assert man["k0"] <= lo_k and hi_k < man["k0"] + man["nwin"], (c["id"], lo_k, hi_k)
            with_bw = s.get_lines_intensity(xray_lines=xl, background_windows=bw)
            without = s.get_lines_intensity(xray_lines=xl)
        cols = [np.asarray(i.data, dtype=float).ravel() for i in with_bw] + [np.asarray(i.data, dtype=float).ravel() for i in without]
        block = np.stack(cols, axis=1)
        index.append({"cell": c["id"], "row0": len(out_rows), "n": int(block.shape[0]), "line_order": xl})
        out_rows.extend(block.tolist())
    arr = np.array(out_rows, dtype="<f8")
    path = os.path.join(OUT, "edx-pins-intensity.f64")
    arr.tofile(path)
    return {"file": "edx-pins-intensity.f64", "sha256": sha256_file(path), "shape": list(arr.shape),
            "columns": "with background windows (line_order), then without", "settings": "R_MnKa 130, integration factor 2.0, merged background windows from estimate_background_windows(xray_lines=all three)",
            "cells": index}


def peaks_section(man, means, resid):
    cells = {c["id"]: c for c in man["cells"]}
    out = []
    for n in (1e5, 1e6, 1e7):
        for rho in (0.002, 0.01, 0.05):
            cid = MP.cell_id("U130", "L", n, rho)
            c = cells[cid]
            arr = full_rows(man, means, resid, c, with_mean=False)
            for j in range(5):
                for label, kw in (("default", {}), ("amp0.002max_med3", {"amp_thresh": None, "medfilt_radius": 3})):
                    y = arr[j]
                    kwargs = {"peakgroup": 10}
                    if label == "default":
                        kwargs["medfilt_radius"] = 5
                    else:
                        kwargs["amp_thresh"] = float(0.002 * y.max())
                        kwargs["medfilt_radius"] = 3
                    with quiet():
                        sig = hs.signals.Signal1D(y.astype(float))
                        ax = sig.axes_manager.signal_axes[0]
                        ax.offset, ax.scale, ax.units = OFF, SC, "keV"
                        p = sig.find_peaks1D_ohaver(**kwargs)[0]
                    out.append({"cell": cid, "realisation": j + 1, "setting": label, "amp_thresh": kwargs.get("amp_thresh"), "medfilt_radius": kwargs["medfilt_radius"],
                                "peaks": [[float(a), float(h), float(w)] for a, h, w in zip(p["position"], p["height"], p["width"])] if len(p) else []})
    return {"setting_defaults": "peakgroup 10, subchannel True; 'default' = amp_thresh None (10 % of max), medfilt_radius 5", "cases": out}


def main():
    registry, velox_path = check_inputs()
    axis_fn, rule_source = rsciio_dispersion_offset(velox_path)
    pins = {"versions": {"hyperspy": hyperspy.__version__, "numpy": np.__version__, "h5py": h5py.__version__,
                         "rsciio_installed": rsciio.__version__, "python": "%d.%d.%d" % sys.version_info[:3]},
            "commits": {"exspy": EXSPY_COMMIT, "rosettasciio": RSCIIO_COMMIT},
            "inputs_sha256": {"registry.txt": REGISTRY_SHA256, "_emd_velox.py": VELOX_PY_SHA256,
                              "edx-planted.json": sha256_file(os.path.join(FIX, "edx-planted.json")),
                              "velox-streams-truth.json": sha256_file(os.path.join(FIX, "velox-streams-truth.json")),
                              "edx-calibration.json": sha256_file(os.path.join(FIX, "edx-calibration.json"))}}
    counts, axis_files, axis_planted = counts_section(registry, velox_path, axis_fn)
    pins["counts"] = counts
    pins["axis"] = axis_section(axis_files, axis_planted, velox_path, rule_source)
    pins["lines"] = lines_section()
    man, means, resid = load_cell_arrays()
    pins["lines"]["intensity"] = intensity_section(man, means, resid)
    pins["peaks"] = peaks_section(man, means, resid)
    path = os.path.join(OUT, "pins.json")
    with open(path, "w") as fh:
        json.dump(pins, fh, sort_keys=True, indent=1)
        fh.write("\n")
    for f in ("pins.json", "edx-axis-e2.f64", "edx-pins-intensity.f64"):
        print(f"{sha256_file(os.path.join(OUT, f))}  {os.path.getsize(os.path.join(OUT, f)):>9}  {f}")


if __name__ == "__main__":
    main()
