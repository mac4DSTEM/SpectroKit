"""Element-proposer pools from the EDX forward model (forward.py beside this script).

Writes Tests/SpectroCoreTests/Fixtures/eds-proposer-sim.json: the EXPECTED pooled spectrum of 256 identical pixels at a counts/pixel dose, for the
Al matrix (80 nm) at 10 and 100 counts/px and the beta'' precipitate pixel (104 nm) at 300 counts/px, with every planted component's
expected counts (lines, escapes, the Al K-alpha tail, the SUM PEAKS, Si internal fluorescence, stray Cu). The sum peaks grow as the square of the rate.
The Swift test adds Poisson noise. Usage: References/python/bin/python -I -B tools/edx-sim/proposer_sim.py [out.json]   (numpy only)
"""
import json, math, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xray_model as xm, forward as fw
MAC = os.path.join(HERE, "..", "..", "Sources", "SpectroEDX", "Resources", "Spectroscopy", "FFastMAC.csv")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Tests", "SpectroCoreTests", "Fixtures", "eds-proposer-sim.json")
NPIX = 256
axis = xm.Axis(4096, 5.0, 95.6)
f = fw.Forward(axis, MAC)
names = [c.name for c in f.comps]

def region(recipe, thickness, rho, scale):
    spec = xm.edx_spec(recipe)
    r = f.run([spec], np.array([0]), np.array([thickness]), np.array([rho]), np.array([scale]), np.array([0.0]),
              np.array([0]), 1, keep_pixel_arrays=True)
    return r["exp_sum"][0], {nm: float(r["amp"][i, 0]) for i, nm in enumerate(names)}

def at_dose(recipe, thickness, rho, target):
    lo, hi = 1e-4, 12.0
    for _ in range(60):
        mid = math.sqrt(lo * hi)
        if region(recipe, thickness, rho, mid)[0].sum() >= target: hi = mid
        else: lo = mid
    return math.sqrt(lo * hi)

out = {"generator": "tools/edx-sim/proposer_sim.py over tools/edx-sim/forward.py", "npix": NPIX,
       "offset": -95.6 * 0.005, "scale": 0.005, "size": 4096, "beam": 200.0, "fwhmMnKa": 130.0, "regions": []}
for label, recipe, (t, rho), dose in [
        ("matrix 10 counts/px", "A", (fw.THICKNESS_BASE_NM, fw.PHASE_DENSITY["Al"]), 10.0),
        ("matrix 100 counts/px", "A", (fw.THICKNESS_BASE_NM, fw.PHASE_DENSITY["Al"]), 100.0),
        ("beta'' 300 counts/px", "precip_endon_0", (fw.THICKNESS_BASE_NM * fw.PRECIP_T, 0.5 * fw.PHASE_DENSITY["Al"] + 0.5 * fw.PHASE_DENSITY["beta"]), 300.0)]:
    s = at_dose(recipe, t, rho, dose)
    e, a = region(recipe, t, rho, s)
    print(label, "rate scale", s, "counts/px", e.sum(), {k: round(v * NPIX, 1) for k, v in a.items() if k.startswith("sum_") or k in ("Al_Ka", "Mg_Ka", "Si_Ka", "O_Ka", "Cu_Ka")})
    out["regions"].append({"label": label, "countsPerPixel": float(e.sum()), "expected": [round(float(v) * NPIX, 5) for v in e],
                           "components": {k: v * NPIX for k, v in a.items()}, "sumPeakEnergies": {c.name: c.energy for c in f.comps if c.kind == "sum"}})
json.dump(out, open(OUT, "w"), separators=(",", ":"))
