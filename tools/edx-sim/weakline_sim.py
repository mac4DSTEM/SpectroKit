"""Weak-line recovery pools from the EDX forward model (forward.py beside this script).

Writes Tests/SpectroEDXTests/Fixtures/eds-weakline-sim.json: for Mg planted at 0, 0.1, 0.3, 1, 10 % of the Al K-alpha counts (Al_Ka + its tail),
the EXPECTED pooled spectrum of 1e4 identical matrix pixels (80 nm, 2.70 g/cm3, lam 1), and the planted truth. The Swift test adds Poisson noise.
Usage: References/python/bin/python -I -B tools/edx-sim/weakline_sim.py [out.json]   (numpy only)
"""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xray_model as xm, forward as fw
MAC = os.path.join(HERE, "..", "..", "Sources", "SpectroEDX", "Resources", "Spectroscopy", "FFastMAC.csv")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Tests", "SpectroEDXTests", "Fixtures", "eds-weakline-sim.json")
NPIX = 10000
axis = xm.Axis(4096, 5.0, 95.6)
f = fw.Forward(axis, MAC)

def run(mg_atoms):
    n = {"Al": 0.988, "Si": 0.006}
    if mg_atoms > 0: n["Mg"] = mg_atoms
    spec = xm.RecipeSpec("pool", n, 1.0)
    r = f.run([spec], np.array([0]), np.array([fw.THICKNESS_BASE_NM]), np.array([fw.PHASE_DENSITY["Al"]]), np.array([1.0]),
              np.array([0.0]), np.array([0]), 1, keep_pixel_arrays=True)
    names = [c.name for c in f.comps]
    amp = {nm: float(r["amp"][i, 0]) * NPIX for i, nm in enumerate(names)}
    return r["exp_sum"][0] * NPIX, amp

levels = [0.0, 0.001, 0.003, 0.01, 0.1]
out = {"generator": "tools/edx-sim/weakline_sim.py over tools/edx-sim/forward.py", "npix": NPIX,
       "offset": -95.6 * 0.005, "scale": 0.005, "size": 4096, "beam": 200.0, "fwhmMnKa": 130.0, "levels": []}
m = 0.006
for fr in levels:
    if fr == 0:
        e, a = run(0.0)
    else:
        for _ in range(4):                       # Mg is ~linear in its atom fraction; rescale to the target ratio
            e, a = run(m)
            ref = a["Al_Ka"] + a["Al_Ka_tail"]
            m *= fr * ref / a["Mg_Ka"]
        e, a = run(m)
    ref = a["Al_Ka"] + a["Al_Ka_tail"]
    out["levels"].append({"fraction": fr, "expected": [float(v) for v in e], "mgKa": a["Mg_Ka"], "alKaWithTail": ref,
                          "alKa": a["Al_Ka"], "alTail": a["Al_Ka_tail"], "siKa": a["Si_Ka"], "total": float(e.sum()),
                          "mgOverAl": a["Mg_Ka"] / ref})
    print(fr, "Mg", a["Mg_Ka"], "Al(+tail)", ref, "ratio", a["Mg_Ka"] / ref, "total", float(e.sum()))
json.dump(out, open(OUT, "w"), separators=(",", ":"))
