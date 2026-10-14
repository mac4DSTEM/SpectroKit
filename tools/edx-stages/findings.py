#!/usr/bin/env python3
"""Readings behind README.md "Findings": prints numbers from the fixtures (run after make_planted.py, make_velox_streams.py, pins.py).
    References/exspy-venv/bin/python -I -B tools/edx-stages/findings.py [--fixtures DIR]
Also the NOT-an-oracle surrogate of registration 7.3 (probes/probe3.py design: one candidate Mg against {Al, Si}, unweighted NNLS,
Kramers x Bernstein (9,5), Currie L_D) run on THIS generator's noise-free means, with SciPy's nnls, to check the generator against 7.3's table."""
import argparse, importlib.util, json, math, os, sys
import numpy as np
from scipy.optimize import nnls
HERE = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser(); ap.add_argument("--fixtures", default=os.path.join(REPO, "Tests", "SpectroEDXTests", "Fixtures")); A = ap.parse_args()
spec = importlib.util.spec_from_file_location("mp", os.path.join(HERE, "make_planted.py")); MP = importlib.util.module_from_spec(spec); spec.loader.exec_module(MP)
pins = json.load(open(os.path.join(A.fixtures, "pins.json"))); man = json.load(open(os.path.join(A.fixtures, "edx-planted.json")))
means = np.fromfile(os.path.join(A.fixtures, "edx-planted-means.f64"), dtype="<f8").reshape(-1, man["nwin"])
resid = np.fromfile(os.path.join(A.fixtures, "edx-planted-resid.i16"), dtype="<i2").reshape(-1, man["nwin"])
cells = {c["id"]: c for c in man["cells"]}
print("== C: files")
for k, v in pins["counts"]["files"].items():
    print(k, v.get("status"), v.get("grid_scansize_x_scanarea"), v.get("grid_last_image"), v.get("frames_default"), v.get("total_events"))
print("published", pins["counts"]["published"]); print("exspy sum", pins["counts"]["exspy_sum"])
print("== E: rsciio rule on planted", {k: [(a.get('dispersion_keV'), a.get('offset_keV')) for a in v] for k, v in pins["axis"]["rsciio_rule"]["planted"].items()})
rows = pins["axis"]["calibration"]["rows"]
cal = {c["id"]: c for c in json.load(open(os.path.join(A.fixtures, "edx-calibration.json")))["cells"]}
print("exSpy offset mode: (offset_after - offset_before) in eV vs -delta, by N")
for N in ("N6", "N7"):
    errs = {}; fails = 0; n = 0
    for r in rows:
        c = cal[r["cell"]]
        if not r["cell"].endswith(N): continue
        m = r["modes"]["offset"]
        if "error" in m: fails += 1; continue
        d = float(c["delta_eV"]); g = float(c["gain"])
        got = (m["offset_after"] - m["offset_before"]) * 1000
        errs.setdefault((d, g), []).append(got + d); n += 1
    allerr = np.array([x for v in errs.values() for x in v])
    print(N, "n", n, "fails", fails, "err(got+delta) eV: mean %.3f max|.| %.3f" % (allerr.mean(), np.abs(allerr).max()))
    for gg in (-3e-4, 0.0, 3e-4):
        e = np.array([x for (d, g), v in errs.items() if g == gg for x in v]); print("   gain", gg, "mean %.3f max|.| %.3f" % (e.mean(), np.abs(e).max()))
for mode in ("scale", "resolution"):
    bad = sum("error" in r["modes"][mode] for r in rows); print(mode, "errors", bad, "of", len(rows))
sc = [(float(cal[r["cell"]]["true_axis"]["scale_keV"]), r["modes"]["scale"]["scale_after"], float(cal[r["cell"]]["gain"])) for r in rows if "error" not in r["modes"]["scale"] and r["cell"].endswith("N7")]
for gg in (-3e-4, 0, 3e-4):
    x = [(a, b) for a, b, g in sc if g == gg]; print("scale mode N7 gain", gg, "true scale mean %.7f exSpy mean %.7f" % (np.mean([a for a, _ in x]), np.mean([b for _, b in x])))
print("== P: window method (exSpy windows) Mg net at rho=0, noise-free mean and realisations")
inten = np.fromfile(os.path.join(A.fixtures, "edx-pins-intensity.f64"), dtype="<f8").reshape(-1, 6); idx = {c["cell"]: c for c in pins["lines"]["intensity"]["cells"]}
def mgnet(cid):
    c = idx[cid]; b = inten[c["row0"]:c["row0"] + c["n"]]; return b[:, 1]
for sname in ("U130", "M"):
    for fam in ("s", "L"):
        for N in (4, 5, 6, 7):
            cid = MP.cell_id(sname, fam, 10.0 ** N, 0.0)
            if cid in idx:
                r = mgnet(cid); print(cid, "mean-spectrum Mg net %.1f" % r[0], ("realisations %.1f +- %.1f (n=%d)" % (r[1:].mean(), r[1:].std(ddof=1), len(r) - 1)) if len(r) > 2 else "")
print("== P: find_peaks1D_ohaver, Mg (1.2536 +-0.02) found fraction by cell/setting")
byk = {}
for c in pins["peaks"]["cases"]:
    hit = any(abs(p[0] - 1.2536) < 0.02 for p in c["peaks"]); byk.setdefault((c["cell"], c["setting"]), []).append((hit, len(c["peaks"])))
for k, v in byk.items(): print(k, "Mg found %d/5, mean #peaks %.1f" % (sum(h for h, _ in v), np.mean([n for _, n in v])))
print("== surrogate (7.3) on this generator's noise-free means: Mg net/truth")
OFF, SC, NCH = MP.OFF, MP.SC, MP.NCH; E = MP.E_AXIS
cols_b, CH = MP.bernstein_columns()
def col(el, R, dE=0.0):
    c = np.zeros(NCH)
    for e, w in MP.TABLE[el]: c += w * MP.gauss_bins(e + dE, MP.fwhm_fn(e, R), False)
    return c
CC = list(cols_b)
def sur(y, R=130.0):
    cols = [col("Al", R), col("Si", R), col("Mg", R)] + CC
    D = np.array(cols)[:, CH].T; yy = y[CH]; nrm = np.linalg.norm(D, axis=0); Dn = D / nrm
    th, _ = nnls(Dn, yy, maxiter=20000); mu = Dn @ th; ia = 2
    K = np.linalg.pinv(Dn); s0 = math.sqrt(np.sum(K[ia] ** 2 * np.maximum(mu - Dn[:, ia] * th[ia], 0)))
    return th[ia] / nrm[ia], 2.71 + 4.65 * s0
def full(cid):
    c = cells[cid]; y = np.zeros(NCH); y[man["k0"]:man["k0"] + man["nwin"]] = means[c["mean_row"]]; return y
# own NNLS vs SciPy on the family projection
cs = MP.continuum_shape("realA", False); d = cols_b[:, CH].T; nr = np.linalg.norm(d, axis=0)
a = MP.nnls(d / nr, cs[CH]); b, _ = nnls(d / nr, cs[CH], maxiter=20000); print("own NNLS vs SciPy max|diff| %.2e" % np.abs(a - b).max())
for (sname, fam, label) in (("M", "s", "matched"), ("S+1", "s", "shift +1 eV"), ("S+2", "s", "+2"), ("S+3", "s", "+3"), ("S+5", "s", "+5"), ("S+10", "s", "+10"), ("S-10", "s", "-10"), ("W2", "s", "Al width x1.02"), ("W6", "s", "x1.06"), ("U130", "s", "Fano"), ("U130", "L", "Fano, rho_c .008"), ("T2", "s", "tail 2%")):
    out = []
    for rho in (0.002, 0.01):
        cid = MP.cell_id(sname, fam, 1e7, rho)
        if cid in cells:
            net, ld = sur(full(cid)); out.append("rho %.3f net/truth %.2f (L_D %.0f)" % (rho, net / (1e7 * rho), ld))
    print("%-18s %s" % (label, " | ".join(out)))
