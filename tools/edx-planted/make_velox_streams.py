#!/usr/bin/env python3
"""Planted Velox spectrum-stream EMD files: the EDX checks, design note section 5.1 (counts C1/C2, axis E1).

    make_velox_streams.py [--out DIR]       DIR defaults to Tests/SpectroEDXTests/Fixtures; writes
        velox-stream-<case>.emd             one file per case
        velox-streams-truth.json            the truth of every case (below), sorted keys, Python-repr floats

Run it with the reference venv's interpreter, isolated (h5py 3.16.0, numpy 2.5.4, HDF5 2.0.0):
    References/python/bin/python -I -B tools/edx-planted/make_velox_streams.py
(References/python, tools/reference/setup.sh; any h5py 3.x writes the same bytes. Datasets are written with track_times=False.)

THE TRUTH IS THE DRAW. The generator draws the events itself (numpy.random.default_rng([20261017, 200, case_index])), per
frame and per pixel, as (channel, count) lists, flattens them into the stream (pixel by pixel, events in shuffled order, then
the marker 65535), and writes the lists to the truth file. No reader is consulted. pins.py then decodes the written files
with an independent NumPy decoder and stops if it differs from the draw.

Layout copied from Tests/SpectroCoreTests/Fixtures/velox-tiny.emd (itself a copy of the Velox structure RosettaSciIO reads):
  Version                                   vlen string {"version": "11", "format": "Velox"}
  Data/SpectrumStream/<id>/Data             uint16 (n, 1): events are the words other than 65535, 65535 ends a pixel
  Data/SpectrumStream/<id>/FrameLocationTable   uint64 (frames, 1): the stream offset where each frame starts
  Data/SpectrumStream/<id>/Metadata         uint8 (8192, columns): column 0 is one NUL-padded JSON; every further column is a
                                            DECOY (the same document with another Dispersion, OffsetEnergy and detector name),
                                            so a reader that takes the wrong column gets a wrong axis
  Data/SpectrumStream/<id>/AcquisitionSettings   vlen string {"bincount": "4096", "StreamEncoding": "uint16"}
  Data/SpectrumImage/si00/SpectrumImageSettings  vlen string {"startFramePosition": "1", "endFramePosition": "<frames>"}
  Data/Image/img0/{Data (y, x, frames) uint16, Metadata}   the HAADF image (BinaryResult.Detector "HAADF")
The grid is Scan.ScanSize x Scan.ScanArea of column 0 (measured files; rsciio instead takes the last image's shape).
Axis of the analytical detectors: Dispersion 20 eV, OffsetEnergy -1932.21348 eV, 4096 bins (a measured header, registration
section 9); LiveTime and RealTime "0" (his files).

CASES (the extremes design note 5.1 lists):
  1stream-1frame    ONE stream (Super-X pre-summed: BinaryResult.Detector "SuperXG1" = SuperXG11..G14), 1 frame, grid 3 x 4
                    from ScanSize 8 x 6 and ScanArea (.25,0)-(.75,.5); pixel 0 holds channel 0 (x2) and channel 4095 (x3);
                    pixel 1 holds ZERO events; LiveTime = RealTime = 0
  1stream-3frames   ONE stream, 3 frames, grid 3 x 4; pixel 7 holds channel 2000 with 30000 + 25000 + 15000 = 70000 events
                    (a uint16 count would wrap); one pixel with zero events in frame 2 only
  4streams-2frames  FOUR streams (SuperXG21..G24, one detector each), 2 frames, grid 4 x 4; the four detectors' OffsetEnergy
                    are -1000, -1000, -996, -1000 eV (energyCalibrationAgrees must be false), Dispersion 20
  unterminated      ONE stream, 2 frames, grid 3 x 4, the stream ENDS WITHOUT the last 65535 (its last pixel holds events)
  axis-decoy        grid 2 x 2, 1 frame; BinaryResult.Detector "SuperXG1"; Detector-1 is "DecoySuperXG1-old" (it CONTAINS the
                    name; Dispersion 10, OffsetEnergy -500), Detector-2 is the real "SuperXG11" (20, -1932.21348): rsciio's
                    rule (first, in file order, whose name CONTAINS BinaryResult.Detector) takes the decoy
  axis-order        grid 2 x 2, 1 frame; the keys are in file order Detector-0 (HAADF), Detector-10 "SuperXG11" (20, -1900),
                    Detector-2 "SuperXG12" (10, -500): rsciio takes Detector-10 (file order); a reader that sorts by index takes
                    Detector-2 (a possible DEVIATION of VeloxEMDReader, which sorts `detectors` by index: see README, Findings)
The expected axis of each stream is written BY HAND in EXPECT_AXIS_EV (dispersion eV, offset eV, as rsciio's rule gives);
pins.py computes it with rsciio's own function and stops on a disagreement with these literals.
"""
import argparse
import hashlib
import json
import os
import sys

import h5py
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
SEED0 = 20261017
ROWS = 8192
MARK = 65535
DISP, OFFSET = "20", "-1932.21348"


def det(key, name, kind, dispersion=None, offset=None, extra=None):
    d = {"DetectorName": name, "DetectorType": kind, "Enabled": "true"}
    if kind == "AnalyticalDetector":
        d.update({"Inserted": "true", "ElevationAngle": "0.5", "AzimuthAngle": "1.0", "CollectionAngle": "0.225",
                  "Dispersion": dispersion, "OffsetEnergy": offset, "RealTime": "0", "LiveTime": "0"})
    return key, d


def measured_detectors():
    return [det("Detector-0", "HAADF", "ScanningDetector")] + [
        det(f"Detector-{i}", f"SuperXG1{i}", "AnalyticalDetector", DISP, OFFSET) for i in range(1, 5)]


def metadata_doc(detectors, detector_name, grid, partial_area, decoy=False):
    ny, nx = grid
    if partial_area:
        scan = {"ScanSize": {"width": str(2 * nx), "height": str(2 * ny)},
                "ScanArea": {"left": "0.25", "top": "0", "right": "0.75", "bottom": "0.5"}}
    else:
        scan = {"ScanSize": {"width": str(nx), "height": str(ny)}, "ScanArea": {"left": "0", "top": "0", "right": "1", "bottom": "1"}}
    scan.update({"DwellTime": "1e-5", "FrameTime": "0.001"})
    dets = {}
    for key, d in detectors:
        d = dict(d)
        if decoy and d.get("DetectorType") == "AnalyticalDetector":
            d["Dispersion"], d["OffsetEnergy"], d["DetectorName"] = "13", "-777", "DECOY" + d["DetectorName"]
        dets[key] = d
    return {"Detectors": dets, "BinaryResult": {"Detector": ("DECOY" if decoy else "") + detector_name, "DetectorIndex": "3"},
            "Scan": scan, "Optics": {"AccelerationVoltage": "200000"}}


def column(doc):
    raw = json.dumps(doc).encode("utf-8")
    assert len(raw) < ROWS
    return np.frombuffer(raw + b"\0" * (ROWS - len(raw)), dtype=np.uint8)


# ------------------------------------------------------------------------------------------------ the draws
def draw_events(rng, n_events, bincount):
    """A pixel's events for one frame, as a {channel: count} dict: n_events channels from a peaky distribution."""
    ch = np.concatenate([rng.integers(0, bincount, size=n_events // 2), np.clip(rng.normal(1000, 80, size=n_events - n_events // 2).astype(int), 0, bincount - 1)])
    u, c = np.unique(ch, return_counts=True)
    return {int(a): int(b) for a, b in zip(u, c)}


def build_case(index, name, spec):
    rng = np.random.default_rng([SEED0, 200, index])
    ny, nx = spec["grid"]
    frames = spec["frames"]
    bins = 4096
    streams = []
    for s_i, s in enumerate(spec["streams"]):
        # events[frame][pixel] = {channel: count}
        ev = [[draw_events(rng, int(rng.integers(0, 9)), bins) for _ in range(ny * nx)] for _ in range(frames)]
        for (f, p), hist in spec.get("forced", {}).get(s_i, {}).items():
            ev[f][p] = dict(hist)
        streams.append(ev)
    return streams


CASES = [
    ("1stream-1frame", dict(grid=(3, 4), frames=1, partial=True, streams=[dict(id="aaaa", detector="SuperXG1")],
                            detectors=lambda: measured_detectors(), terminated=True,
                            forced={0: {(0, 0): {0: 2, 4095: 3}, (0, 1): {}}},
                            expect_axis_ev=[("20", "-1932.21348")], agrees=True)),
    ("1stream-3frames", dict(grid=(3, 4), frames=3, partial=False, streams=[dict(id="aaaa", detector="SuperXG1")],
                             detectors=lambda: measured_detectors(), terminated=True,
                             forced={0: {(0, 7): {2000: 30000}, (1, 7): {2000: 25000}, (2, 7): {2000: 15000}, (1, 2): {}}},
                             expect_axis_ev=[("20", "-1932.21348")], agrees=True)),
    ("4streams-2frames", dict(grid=(4, 4), frames=2, partial=False,
                              streams=[dict(id=f"a{i}", detector=f"SuperXG2{i + 1}") for i in range(4)],
                              detectors=lambda: [det("Detector-0", "HAADF", "ScanningDetector")] + [
                                  det(f"Detector-{i + 1}", f"SuperXG2{i + 1}", "AnalyticalDetector", "20", off)
                                  for i, off in enumerate(("-1000", "-1000", "-996", "-1000"))],
                              terminated=True, forced={},
                              expect_axis_ev=[("20", "-1000"), ("20", "-1000"), ("20", "-996"), ("20", "-1000")], agrees=False)),
    ("unterminated", dict(grid=(3, 4), frames=2, partial=False, streams=[dict(id="aaaa", detector="SuperXG1")],
                          detectors=lambda: measured_detectors(), terminated=False,
                          forced={0: {(1, 11): {7: 4, 4000: 1, 4095: 2}}}, expect_axis_ev=[("20", "-1932.21348")], agrees=True)),
    ("axis-decoy", dict(grid=(2, 2), frames=1, partial=False, streams=[dict(id="aaaa", detector="SuperXG1")],
                        detectors=lambda: [det("Detector-0", "HAADF", "ScanningDetector"),
                                           det("Detector-1", "DecoySuperXG1-old", "AnalyticalDetector", "10", "-500"),
                                           det("Detector-2", "SuperXG11", "AnalyticalDetector", "20", "-1932.21348")],
                        terminated=True, forced={}, expect_axis_ev=[("10", "-500")], agrees=False)),
    ("axis-order", dict(grid=(2, 2), frames=1, partial=False, streams=[dict(id="aaaa", detector="SuperXG1")],
                        detectors=lambda: [det("Detector-0", "HAADF", "ScanningDetector"),
                                           det("Detector-10", "SuperXG11", "AnalyticalDetector", "20", "-1900"),
                                           det("Detector-2", "SuperXG12", "AnalyticalDetector", "10", "-500")],
                        terminated=True, forced={}, expect_axis_ev=[("20", "-1900")], agrees=False)),
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def write_case(out, index, name, spec):
    ny, nx = spec["grid"]
    frames = spec["frames"]
    npix = ny * nx
    draws = build_case(index, name, spec)
    rng = np.random.default_rng([SEED0, 201, index])
    detectors = spec["detectors"]()
    path = os.path.join(out, f"velox-stream-{name}.emd")
    truth_streams = []
    with h5py.File(path, "w") as f:
        f.create_dataset("Version", data=[json.dumps({"version": "11", "format": "Velox"})], dtype=h5py.string_dtype())
        ncol = max(2, frames)
        for s_i, s in enumerate(spec["streams"]):
            ev = draws[s_i]
            words, starts = [], []
            for fr in range(frames):
                starts.append(len(words))
                for p in range(npix):
                    chans = np.repeat(np.array(sorted(ev[fr][p]), dtype=np.int64), [ev[fr][p][c] for c in sorted(ev[fr][p])])
                    rng.shuffle(chans)
                    words.extend(int(c) for c in chans)
                    words.append(MARK)
            if not spec["terminated"] and s_i == len(spec["streams"]) - 1:
                assert words[-1] == MARK
                words.pop()
            data = np.array(words, dtype="<u2").reshape(-1, 1)
            g = f.create_group(f"Data/SpectrumStream/{s['id']}")
            g.create_dataset("Data", data=data, track_times=False)
            g.create_dataset("FrameLocationTable", data=np.array(starts, dtype="<u8").reshape(-1, 1), track_times=False)
            cols = [column(metadata_doc(detectors, s["detector"], spec["grid"], spec["partial"]))] + [
                column(metadata_doc(detectors, s["detector"], spec["grid"], spec["partial"], decoy=True)) for _ in range(ncol - 1)]
            g.create_dataset("Metadata", data=np.stack(cols, axis=1), track_times=False)
            g.create_dataset("AcquisitionSettings", data=[json.dumps({"bincount": "4096", "StreamEncoding": "uint16"})], dtype=h5py.string_dtype())
            per_channel = {}
            per_pixel = [0] * npix
            for fr in range(frames):
                for p in range(npix):
                    for c, k in ev[fr][p].items():
                        per_channel[c] = per_channel.get(c, 0) + k
                        per_pixel[p] += k
            truth_streams.append({
                "id": s["id"], "detector": s["detector"], "values": int(data.shape[0]),
                "markers": int(sum(1 for w in words if w == MARK)),
                "events": [[[[c, k] for c, k in sorted(ev[fr][p].items())] for p in range(npix)] for fr in range(frames)],
                "channel_sums": [[c, k] for c, k in sorted(per_channel.items())],
                "pixel_totals": per_pixel, "total": int(sum(per_pixel))})
        s0 = f.create_group("Data/SpectrumImage/si00")
        s0.create_dataset("SpectrumImageSettings", data=[json.dumps({"startFramePosition": "1", "endFramePosition": str(frames)})], dtype=h5py.string_dtype())
        img = f.create_group("Data/Image/img0")
        img.create_dataset("Data", data=((np.arange(npix * frames) * 37 + 11) % 997).astype("<u2").reshape(ny, nx, frames), track_times=False)
        icols = [column(metadata_doc(detectors, "HAADF", spec["grid"], spec["partial"], decoy=(i > 0))) for i in range(ncol)]
        img.create_dataset("Metadata", data=np.stack(icols, axis=1), track_times=False)
    return path, {
        "file": os.path.basename(path), "grid": {"ny": ny, "nx": nx}, "frames": frames, "channels": 4096,
        "partial_scan_area": spec["partial"], "terminated": spec["terminated"],
        "detectors_file_order": [[k, d["DetectorName"], d.get("Dispersion"), d.get("OffsetEnergy")] for k, d in detectors],
        "expect_axis_ev": [list(x) for x in spec["expect_axis_ev"]], "expect_calibration_agrees": spec["agrees"],
        "streams": truth_streams, "sha256": sha256_file(path), "bytes": os.path.getsize(path)}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(REPO, "Tests", "SpectroEDXTests", "Fixtures"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    truth = {"seed0": SEED0, "h5py": h5py.__version__, "numpy": np.__version__, "hdf5": h5py.version.hdf5_version, "cases": {}}
    for i, (name, spec) in enumerate(CASES):
        path, t = write_case(args.out, i, name, spec)
        truth["cases"][name] = t
        print(f"{t['sha256']}  {t['bytes']:>8}  {os.path.basename(path)}")
    with open(os.path.join(args.out, "velox-streams-truth.json"), "w") as fh:
        json.dump(truth, fh, sort_keys=True, indent=1)
        fh.write("\n")
    p = os.path.join(args.out, "velox-streams-truth.json")
    print(f"{sha256_file(p)}  {os.path.getsize(p):>8}  velox-streams-truth.json")


if __name__ == "__main__":
    sys.exit(main())
