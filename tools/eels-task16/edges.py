#!/usr/bin/env python3
"""exSpy pins for SpectroKit EELS task 16 step 3 (docs/design/eels-task-16.md section 6.1): the GOS tables and cross sections of the new edges.

Pins what exSpy 7185a4d1 (put first on sys.path, as tools/eels-edge/pins.py does) / HyperSpy 2.4.0 answer for the bundled edges beyond C, N, O K:
K of Mg, Al, Si and the L edges of Mg, Al, Si, Fe, Cu (Mg, Si, Fe, Cu: L1, L2, L3; Al: L1 and the combined L2,3).

Run (HyperSpy 2.4.0 venv):

    References/python/bin/python -I -B tools/eels-task16/edges.py [--gosh FILE] [--exspy DIR] [--out DIR]

Writes into --out (default Tests/SpectroEELSTests/Fixtures/):
    eels16-edges-pins.json    per edge: element, subshell, table, onsetEV, subshell_factor (occupancy ratio), and per microscope setting the effective angle,
                              the energy grid (offset, scale, size), qint (the integrated GOS at the tabulated energies, barn/eV) and the file of
                              function(E) in barn/eV; per TABLE: the sha256 of the float32 little-endian bytes of gos (97 x 192 row-major), q (192) and
                              free_energies (97) as the GOSH file stores them, and a few exact samples
    eels16-edge-<El>-<sub>-<k>.f64   function(E), float64 little-endian
Floats are Python reprs (round-trip exactly). A second run is byte-identical.
"""
import argparse
import contextlib
import hashlib
import json
import logging
import math
import os
import sys
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--gosh", default=os.path.join(REPO, "..", "References", "SpectroKit", "gos-dft-1.5.0.gosh"))
ap.add_argument("--exspy", default=os.path.join(REPO, "..", "References", "SpectroKit", "exspy-7185a4d1"))
ap.add_argument("--out", default=os.path.join(REPO, "Tests", "SpectroEELSTests", "Fixtures"))
ap.add_argument("--all", action="store_true",
                help="the every-edge pack (extract_gos.py --all): the sha256 of all 231 tables, and one edge per shell and table kind (B K; Ti L1, L2, L3; "
                     "Zr M2, M3; Ba M4, M5) against exSpy, into eelsall-edges-pins.json and eelsall-edge-*.f64")
ARGS = ap.parse_args()
EXSPY = os.path.abspath(ARGS.exspy)
sys.path.insert(0, EXSPY)
logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")

import numpy as np                                   # noqa: E402

with open(os.devnull, "w") as _dn, contextlib.redirect_stdout(_dn), contextlib.redirect_stderr(_dn):
    import h5py                                      # noqa: E402
    import hyperspy                                  # noqa: E402
    import hyperspy.api as hs                        # noqa: E402
    import exspy                                     # noqa: E402
    from exspy.components import EELSCLEdge          # noqa: E402

assert os.path.realpath(os.path.dirname(exspy.__file__)) == os.path.realpath(os.path.join(EXSPY, "exspy")), exspy.__file__
MD5 = "7fee8891c147a4f769668403b54c529b"
EDGES = [("Mg", "K1"), ("Al", "K1"), ("Si", "K1"),
         ("Mg", "L1"), ("Mg", "L2"), ("Mg", "L3"), ("Al", "L1"), ("Al", "L2,3"), ("Si", "L1"), ("Si", "L2"), ("Si", "L3"),
         ("Fe", "L1"), ("Fe", "L2"), ("Fe", "L3"), ("Cu", "L1"), ("Cu", "L2"), ("Cu", "L3")]
NAME = {"K1": "K"}                                   # exSpy names the K edge "K"; the GOSH file's table is K1
TABLE = {"K1": "K1", "L1": "L1", "L2": "L23", "L3": "L23", "L2,3": "L23", "M2": "M23", "M3": "M23", "M4": "M45", "M5": "M45"}
PREFIX = "eels16"
if ARGS.all:
    EDGES = [("B", "K1"), ("Ti", "L1"), ("Ti", "L2"), ("Ti", "L3"), ("Zr", "M2"), ("Zr", "M3"), ("Ba", "M4"), ("Ba", "M5")]
    PREFIX = "eelsall"
SETTINGS = [(200.0, 10.0, 20.0, 0.25, 800), (300.0, 0.0, 50.0, 0.5, 500)]       # E0 keV, alpha mrad, beta mrad, scale eV, channels from onset - 5 eV


def md5_file(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def jnum(x):
    return float(x)


def main():
    assert md5_file(ARGS.gosh) == MD5, "the GOSH file is not the pinned one"
    os.makedirs(ARGS.out, exist_ok=True)
    pins = {"environment": {"hyperspy": hyperspy.__version__, "numpy": np.__version__, "exspyCommit": "7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e",
                            "gosMd5": MD5, "script": hashlib.sha256(open(__file__, "rb").read()).hexdigest()},
            "edges": {}, "tables": {}}
    with h5py.File(ARGS.gosh, "r") as h:
        keys = [(el, TABLE[sub]) for el, sub in EDGES]
        if ARGS.all:
            with open(os.path.join(REPO, "Sources", "SpectroEELS", "Resources", "GOS", "dft-gos-index.json")) as f:
                keys = [(t["element"], t["table"]) for t in json.load(f)["tables"]]
        for el, table in keys:
            key = f"{el}/{table}"
            if key not in pins["tables"]:
                g = h[f"/{el}/{table}"]
                data, q, fe = g["data"][:], g["q"][:], g["free_energies"][:]
                gos = np.squeeze(data.T).astype("<f4")
                pins["tables"][key] = {
                    "gosSHA256": hashlib.sha256(np.ascontiguousarray(gos).tobytes()).hexdigest(),
                    "qSHA256": hashlib.sha256(q.astype("<f4").tobytes()).hexdigest(),
                    "freeEnergiesSHA256": hashlib.sha256(fe.astype("<f4").tobytes()).hexdigest(),
                    "samples": {"gos[0][0]": jnum(gos[0, 0]), f"gos[{gos.shape[0] // 2}][{gos.shape[1] // 2}]": jnum(gos[gos.shape[0] // 2, gos.shape[1] // 2]),
                                f"gos[{gos.shape[0] - 1}][{gos.shape[1] - 1}]": jnum(gos[-1, -1]), "q[0]": jnum(q[0]), f"q[{q.shape[0] - 1}]": jnum(q[-1]),
                                "freeEnergies[0]": jnum(fe[0]), f"freeEnergies[{fe.shape[0] - 1}]": jnum(fe[-1])},
                }
    for el, sub in EDGES:
        with contextlib.redirect_stdout(open(os.devnull, "w")):
            probe = EELSCLEdge(f"{el}_{NAME.get(sub, sub)}", GOS="dft", gos_file_path=ARGS.gosh)
        onset = float(probe.GOS.onset_energy)
        rec = {"element": el, "subshell": sub, "table": TABLE[sub], "onsetEV": onset, "subshellFactor": jnum(probe.GOS.subshell_factor), "settings": []}
        for k, (e0, a, b, scale, n) in enumerate(SETTINGS):
            with contextlib.redirect_stdout(open(os.devnull, "w")):
                e = EELSCLEdge(f"{el}_{NAME.get(sub, sub)}", GOS="dft", gos_file_path=ARGS.gosh)      # a fresh edge per case (exSpy re-integrates only when the effective angle changes)
                e.set_microscope_parameters(E0=e0, alpha=a, beta=b, energy_scale=scale)
            offset = onset - 5.0
            s = hs.signals.Signal1D(np.zeros(n))
            ax = s.axes_manager.signal_axes[0]
            ax.offset, ax.scale, ax.units, ax.is_binned = offset, scale, "eV", True
            E = ax.axis.copy()
            f = np.asarray(e.function(E), dtype="<f8")
            name = f"{PREFIX}-edge-{el}-{sub.replace(',', '')}-{k}.f64"
            f.tofile(os.path.join(ARGS.out, name))
            rec["settings"].append({"beamEnergyKeV": e0, "convergenceMrad": a, "collectionMrad": b, "energyScaleEV": scale,
                                    "axis": {"offsetEV": offset, "scaleEV": scale, "size": n}, "effectiveAngleMrad": jnum(e.effective_angle.value),
                                    "qint": [jnum(v) for v in np.asarray(e.GOS.qint, dtype=float)], "file": name,
                                    "sha256": hashlib.sha256(f.tobytes()).hexdigest()})
        pins["edges"][f"{el}_{sub}"] = rec
    out = os.path.join(ARGS.out, f"{PREFIX}-edges-pins.json")
    with open(out, "w") as f:
        json.dump(pins, f, sort_keys=True, indent=1)
        f.write("\n")
    print(out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    sys.exit(main())
