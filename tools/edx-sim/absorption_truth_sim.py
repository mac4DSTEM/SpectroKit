"""Truth-geometry absorption pool from the EDX forward model (forward.py beside this script).

Writes Tests/SpectroEDXTests/Fixtures/eds-absorption-truth.json: the EXPECTED pooled spectrum of 1e4 identical recipe-A matrix pixels
(Al 98.8 / Mg 0.6 / Si 0.6 at%, 80 nm, 2.70 g/cm3, uniform thickness; the simulator's own four-segment geometry, depth weight beta 0.2,
oxide O in the medium), the noise-free K-alpha areas the forward model made (after pile-up, tail and escape bookkeeping), the
absorption-free areas, the per-segment/effective transmissions, and the simulator's true k (Gp * s_family * eps, absorption-free).
The Swift test (SpectroscopyAbsorptionTruthTests) adds Poisson noise and types the SIMULATOR's k, because the simulator's
sensitivities (Al 1.0, Mg 0.55, Si 1.2) are not SpectroKit's Bote-Salvat model.
Usage: References/python/bin/python -I -B tools/edx-sim/absorption_truth_sim.py [out.json]   (numpy only)
"""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xray_model as xm, forward as fw
MAC = os.path.join(HERE, "..", "..", "Sources", "SpectroEDX", "Resources", "Spectroscopy", "FFastMAC.csv")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Tests", "SpectroEDXTests", "Fixtures", "eds-absorption-truth.json")
NPIX = 10000
axis = xm.Axis(4096, 5.0, 95.6)
f = fw.Forward(axis, MAC)
spec = xm.RecipeSpec("A", {"Al": 0.988, "Mg": 0.006, "Si": 0.006}, 1.0)
r = f.run([spec], np.array([0]), np.array([fw.THICKNESS_BASE_NM]), np.array([fw.PHASE_DENSITY["Al"]]), np.array([1.0]),
          np.array([0.0]), np.array([0]), 1, keep_pixel_arrays=True)
names = [c.name for c in f.comps]
amp = {nm: float(r["amp"][i, 0]) * NPIX for i, nm in enumerate(names)}
li = {nm: i for i, nm in enumerate(r["line_names"])}
free = {k: float(r["a_free"][li[k], 0]) * NPIX for k in ("Al_Ka", "Mg_Ka", "Si_Ka")}
teff = {k: float(r["t_eff"][li[k], 0]) for k in ("Al_Ka", "Mg_Ka", "Si_Ka")}
tseg = {k: [float(v) for v in r["t_seg"][:, li[k], 0]] for k in ("Al_Ka", "Mg_Ka", "Si_Ka")}
# the simulator's true k per atom per nm^2 (absorption-free): Gp * s * eps(E_line), Ka weight 1
kc = {}
for el, fam in (("Al", "Al_K"), ("Mg", "Mg_K"), ("Si", "Si_K")):
    e = xm.LINES[el]["Ka"][0]
    kc[el] = f.gp * xm.SENSITIVITY[fam] * float(xm.detector_efficiency(np.array([e]))[0])
x, mbar, wf = r["med"][0]
out = {"generator": "tools/edx-sim/absorption_truth_sim.py over tools/edx-sim/forward.py", "npix": NPIX,
       "offset": -95.6 * 0.005, "scale": 0.005, "size": 4096, "beam": 200.0, "fwhmMnKa": 130.0,
       "thickness_nm": fw.THICKNESS_BASE_NM, "density_g_cm3": fw.PHASE_DENSITY["Al"],
       "truth_at_pct": {"Al": 98.8, "Mg": 0.6, "Si": 0.6},
       "segments": {"azimuth_deg": list(fw.SEG_AZ), "elevation_deg": fw.SEG_ELEV, "alpha_deg": fw.TILT_ALPHA, "solid_angle": list(fw.SEG_WEIGHT)},
       "medium_atom_fractions_incl_O": x, "medium_weight_fractions_incl_O": wf,
       "areas_with_absorption": {k: amp[k] for k in ("Al_Ka", "Mg_Ka", "Si_Ka")},
       "areas_absorption_free": free, "t_eff": teff, "t_by_segment": tseg,
       # detector Si internal fluorescence planted at Si Ka (forward.py Si_Ka_internal): a fit of Si Ka sees it too
       "area_si_ka_internal": amp["Si_Ka_internal"],
       "true_k_counts_per_atom_nm2": kc, "expected": [float(v) for v in r["exp_sum"][0] * NPIX]}
json.dump(out, open(OUT, "w"), separators=(",", ":"))
print({k: v for k, v in out.items() if k != "expected"})
