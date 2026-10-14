#!/usr/bin/env python3
"""EELS slice 2's diagnostic comparison (docs/eels-slice-2-registration.md section 8; never a gate): the port's C, N and O K
areal-density maps (eels-real-data edge) against GMS's own signal maps in the owner's EELS_2 folder, read by the pinned
RosettaSciIO 049e7d70. GMS's maps are background-subtracted signal integrals (its units, its windows), not areal
densities: what is compared is the spatial pattern (Pearson and Spearman correlation) and the ratio GMS / port (median,
quartiles), never equality. Numbers only.

    References/exspy-venv/bin/python -I -B tools/eels-real-data/gms_compare.py <EELS Map folder> <edge outdir> <out.json>
"""
import argparse
import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser()
ap.add_argument("maps")
ap.add_argument("edgedir")
ap.add_argument("out")
ap.add_argument("--references", default=str(ROOT / "References"))
a = ap.parse_args()
spec = importlib.util.spec_from_file_location("truth", ROOT / "tools" / "eels-reader" / "truth.py")
truth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(truth)
file_reader, _, _ = truth.load_rsciio(a.references)
import numpy as np  # noqa: E402
from scipy.stats import spearmanr  # noqa: E402

res = {"tool": "gms_compare.py", "reference": f"RosettaSciIO {truth.RSCIIO_COMMIT}", "maps": {}}
for el in ("C", "N", "O"):
    for gms_name in (f"{el} K Signal (EELS).dm4", f"{el} K Signal (EELS)_1.dm4"):
        p = Path(a.maps) / gms_name
        if not p.exists():
            continue
        sigs = file_reader(str(p))
        img = [s for s in sigs if np.asarray(s["data"]).ndim == 2][-1]
        g = np.asarray(img["data"], dtype=float)
        for route in ("ilowDelta", "i0"):
            meta = json.loads((Path(a.edgedir) / f"{el}K-{route}.json").read_text())
            raw = (Path(a.edgedir) / f"{el}K-{route}.f64").read_bytes()
            v = np.frombuffer(raw, dtype="<f8").reshape(meta["ny"], meta["nx"], 5)[..., 0]
            entry = {"gmsShape": list(g.shape), "portShape": list(v.shape), "gmsUnits": img["metadata"].get("Signal", {}).get("quantity")}
            if g.shape == v.shape:
                m = np.isfinite(g) & np.isfinite(v)
                pos = m & (v > 0) & (g > 0)
                ratio = g[pos] / v[pos]
                entry.update({
                    "pixelsCompared": int(m.sum()),
                    "pearson": float(np.corrcoef(g[m], v[m])[0, 1]),
                    "spearman": float(spearmanr(g[m], v[m]).statistic),
                    "ratioGmsOverPort": {"q25": float(np.percentile(ratio, 25)), "median": float(np.median(ratio)),
                                         "q75": float(np.percentile(ratio, 75)), "pixels": int(pos.sum())},
                    "gmsMedian": float(np.median(g[m])), "portMedianAtomsPerNM2": float(np.median(v[m])),
                })
            res["maps"][f"{gms_name} vs {el}K-{route}"] = entry
Path(a.out).write_text(json.dumps(res, indent=2, sort_keys=True) + "\n")
print(json.dumps(res, indent=1)[:3000])
