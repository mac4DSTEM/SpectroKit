"""Detector Si dead-layer pool from the EDX forward model (forward.py beside this script).

Writes Tests/SpectroEDXTests/Fixtures/eds-dead-layer-truth.json: the EXPECTED pooled spectrum of 1e4 identical recipe-A matrix pixels,
the same sample and geometry as eds-absorption-truth.json (Al 98.8 / Mg 0.6 / Si 0.6 at%, 80 nm, 2.70 g/cm3, the simulator's four
segments, depth weight beta 0.2, oxide O in the medium), seen through a detector with a KNOWN Si dead layer: eps(E) of every line
and of the continuum is multiplied by exp(-mu_Si(E) rho_Si t_dead) (mu_Si from FFAST, rho_Si 2.33 g/cm3, t_dead = DEAD_LAYER_UM).
That puts a step down in the continuum at the Si K edge (1.839 keV), 0.1 keV above Si K-alpha: 11 % at 0.3 um.
0.3 um is a thick dead layer (SDD dead layers are typically 0.1 um or less), chosen so the step moves an unmodelled fit's Si
K-alpha by more than twice its counting sigma on this pool (at 0.1 um the step is 4 % and its effect below 1 sigma). The optional
second argument sets another thickness.
Stored: the dead-layer thickness, its transmission at the three K-alpha lines and just below/above the Si K edge, the noise-free
K-alpha areas after the forward model's bookkeeping (pile-up, tail, escape), the Si K-alpha internal-fluorescence area (a second
Si K-alpha peak at the same energy: what a fit sees at Si K-alpha is the sum), and the expected spectrum.
Usage: <python with numpy> -I -B tools/edx-sim/dead_layer_sim.py [out.json]   (numpy only)
"""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xray_model as xm, forward as fw
MAC = os.path.join(HERE, "..", "..", "Sources", "SpectroEDX", "Resources", "Spectroscopy", "FFastMAC.csv")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Tests", "SpectroEDXTests", "Fixtures", "eds-dead-layer-truth.json")
DEAD_LAYER_UM = float(sys.argv[2]) if len(sys.argv) > 2 else 0.3
NPIX = 10000
axis = xm.Axis(4096, 5.0, 95.6)
f = fw.Forward(axis, MAC, dead_layer_um=DEAD_LAYER_UM)
spec = xm.RecipeSpec("A", {"Al": 0.988, "Mg": 0.006, "Si": 0.006}, 1.0)
r = f.run([spec], np.array([0]), np.array([fw.THICKNESS_BASE_NM]), np.array([fw.PHASE_DENSITY["Al"]]), np.array([1.0]),
          np.array([0.0]), np.array([0]), 1, keep_pixel_arrays=True)
names = [c.name for c in f.comps]
amp = {nm: float(r["amp"][i, 0]) * NPIX for i, nm in enumerate(names)}
ka = ("Al_Ka", "Mg_Ka", "Si_Ka")
t_dl = {k: float(f.dead_layer_T(np.array([xm.LINES[k[:2]]["Ka"][0]]))[0]) for k in ka}
edge = {"below_1.835": float(f.dead_layer_T(np.array([1.835]))[0]), "above_1.845": float(f.dead_layer_T(np.array([1.845]))[0])}
out = {"generator": "tools/edx-sim/dead_layer_sim.py over tools/edx-sim/forward.py", "npix": NPIX,
       "offset": -95.6 * 0.005, "scale": 0.005, "size": 4096, "beam": 200.0, "fwhmMnKa": 130.0,
       "thickness_nm": fw.THICKNESS_BASE_NM, "density_g_cm3": fw.PHASE_DENSITY["Al"],
       "truth_at_pct": {"Al": 98.8, "Mg": 0.6, "Si": 0.6},
       "dead_layer_um": DEAD_LAYER_UM, "dead_layer_density_g_cm3": fw.SI_DENSITY,
       "dead_layer_transmission": t_dl, "dead_layer_transmission_at_si_k_edge": edge,
       "areas": {k: amp[k] for k in ka}, "si_ka_internal_fluorescence": amp["Si_Ka_internal"],
       "expected": [float(v) for v in r["exp_sum"][0] * NPIX]}
json.dump(out, open(OUT, "w"), separators=(",", ":"))
print({k: v for k, v in out.items() if k != "expected"})
