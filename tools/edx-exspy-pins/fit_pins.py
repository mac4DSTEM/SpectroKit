# tools/edx-exspy-pins/fit_pins.py: writes Tests/SpectroCoreTests/Fixtures/eds-fit-exspy-7185a4d1.json from exSpy 7185a4d1 / HyperSpy 2.4.0
# by running its EDSModel (closed loop, FePt, SciPy NNLS references).
# Usage: PYTHONPATH=References/exspy-7185a4d1 References/python/bin/python -B tools/edx-exspy-pins/fit_pins.py [out.json]
import warnings; warnings.filterwarnings("ignore")
import logging; logging.disable(logging.WARNING)
import json, os, sys, numpy as np, hyperspy.api as hs, exspy
import exspy.utils.eds as eds_utils
from scipy.optimize import nnls
out = {"generator": "tools/edx-exspy-pins/fit_pins.py; exspy 7185a4d1 (2026-10-02), hyperspy 2.4.0, scipy nnls for the reference NNLS", "cases": {}}

def describe(name, s, m, mask=None, nnls_ref=True):
    ax = s.axes_manager.signal_axes[0]
    x = ax.axis
    binned = bool(ax.is_binned)
    scale = ax.scale if binned else 1.0
    res = float(s._get_line_energy("Mn_Ka", FWHM_MnKa="auto")[1])  # placeholder, replaced below
    md = s.metadata.Acquisition_instrument.as_dictionary()
    inst = list(md.values())[0]
    res = float(inst["Detector"]["EDS"]["energy_resolution_MnKa"])
    beam = float(s._get_beam_energy())
    c = {"offset": ax.offset, "scale": ax.scale, "size": ax.size, "binned": binned,
         "resolutionMnKa": res, "beamEnergy": beam,
         "elements": list(s.metadata.Sample.elements), "data": [float(v) for v in s.data]}
    sw = np.array(m._channel_switches, dtype=bool)
    c["channelMask"] = [int(i) for i in np.where(sw)[0]]
    # groups: main line + its tied sub-lines, columns at A = 1
    names_main = [c_.name for c_ in m.xray_lines]
    groups = []
    cols = []
    saved = {mm.name: mm.A.value for mm in m.xray_lines}
    for main in m.xray_lines:
        main.A.value = 1.0
    for main in m.xray_lines:
        members = [main] + [f for f in m.family_lines if f.A.twin is main.A]
        col = np.zeros(ax.size)
        for mem in members:
            col += np.asarray(mem.function(x), dtype=float) * scale
        groups.append({"name": main.name, "members": [mem.name for mem in members],
                       "energies": [float(mem.centre.value) for mem in members],
                       "fwhm": [float(mem.fwhm) for mem in members],
                       "weights": [float(mem.A.value) for mem in members]})
        cols.append(col)
    for main in m.xray_lines:
        main.A.value = saved[main.name]
    c["groups"] = groups
    c["columns"] = [[float(v) for v in col] for col in cols]
    return c, cols, x, scale, sw

# --- closed loop
s = eds_utils.xray_lines_model(elements=["Fe", "Cr", "Zn"], beam_energy=200, weight_percents=[20, 50, 30],
    energy_resolution_MnKa=130, energy_axis={"units": "keV", "size": 400, "scale": 0.01, "name": "E", "offset": 5.0})
s = s + 0.002
m = s.create_model()
c, cols, x, scale, sw = describe("closedLoop", s, m)
m.fit()
c["fitted"] = {g.name: float(g.A.value) for g in m.xray_lines}
c["intensities"] = [float(i.data[0]) for i in m.get_lines_intensity()]
poly = [c_ for c_ in m if c_.name.startswith("background_order")][0]
c["polyCoeffs"] = [float(getattr(poly, f"a{k}").value) for k in range(7)]
model = m.as_signal().data
c["model"] = [float(v) for v in model[sw]]  # fitted channels only (hyperspy leaves NaN elsewhere)
c["rss"] = float(np.sum((s.data - model)[sw] ** 2))
c["redChisq"] = float(np.asarray(m.red_chisq.data).ravel()[0])
c["polyBasis"] = "a_k x^k times scale (binned), x in keV"
# assert columns+poly reproduce hyperspy's model
mm = sum(c["fitted"][g["name"]] * col for g, col in zip(c["groups"], cols)) + sum(
    c["polyCoeffs"][k] * x ** k for k in range(7)) * scale
assert np.allclose(mm, model, rtol=1e-9, atol=1e-9), np.abs(mm - model).max()
out["cases"]["closedLoop"] = c

# --- FePt
s = exspy.data.EDS_TEM_FePt_nanoparticles(); s.add_elements(["Cu"])
m = s.create_model(True); m.set_signal_range(5.5, 10.0)
c, cols, x, scale, sw = describe("fept", s, m)
m.fit()
c["fitted"] = {g.name: float(g.A.value) for g in m.xray_lines}
Im = m.get_lines_intensity(xray_lines=["Fe_Ka", "Pt_La"])
c["pinFe"] = float(Im[0].data[0]); c["pinPt"] = float(Im[1].data[0])
poly = [c_ for c_ in m if c_.name.startswith("background_order")][0]
c["polyCoeffs"] = [float(getattr(poly, f"a{k}").value) for k in range(7)]
model = m.as_signal().data
c["model"] = [float(v) for v in model[sw]]  # fitted channels only (hyperspy leaves NaN elsewhere)
c["rss"] = float(np.sum((s.data - model)[sw] ** 2))
c["redChisq"] = float(np.asarray(m.red_chisq.data).ravel()[0])
c["nFree"] = int(len([p for comp in m for p in comp.parameters if p.free and p.twin is None]))
mm = sum(c["fitted"][g["name"]] * col for g, col in zip(c["groups"], cols)) + sum(
    c["polyCoeffs"][k] * x ** k for k in range(7)) * scale
assert np.allclose(mm[sw], model[sw], rtol=1e-6, atol=1e-6), np.abs(mm - model)[sw].max()
# reference NNLS on hyperspy's own columns (poly columns free sign via +/- split), on the fitted channels
A = np.column_stack(cols + [x ** k * scale for k in range(7)])
Aj = A[sw]; yj = np.asarray(s.data, float)[sw]
# scale the poly columns for conditioning
sc = np.linalg.norm(Aj, axis=0); sc[sc == 0] = 1
Aq = np.column_stack([Aj[:, :len(cols)] / sc[:len(cols)],
                      Aj[:, len(cols):] / sc[len(cols):], -Aj[:, len(cols):] / sc[len(cols):]])
xq, rn = nnls(Aq, yj, maxiter=100000)
amp = xq[:len(cols)] / sc[:len(cols)]
c["nnlsRef"] = {g["name"]: float(a) for g, a in zip(c["groups"], amp)}
c["nnlsRefRss"] = float(rn ** 2)
# unbounded LS via lstsq on the same design (what hyperspy "lm" converges to) for comparison
xl, *_ = np.linalg.lstsq(Aj[:, :] / sc, yj, rcond=None)
c["lsRef"] = {g["name"]: float(a) for g, a in zip(c["groups"], xl[:len(cols)] / sc[:len(cols)])}
c["lsRefNegative"] = [g["name"] for g in c["groups"] if c["lsRef"][g["name"]] < 0]
out["cases"]["fept"] = c
# --- standalone NNLS cases (reference: scipy.optimize.nnls, Lawson-Hanson)
rng = np.random.default_rng(20261005)
cases = []
for (m_, n_, neg) in [(60, 5, True), (80, 7, True), (40, 4, True)]:
    A_ = rng.random((m_, n_))
    A_[:, 1] = A_[:, 0] + 0.05 * rng.random(m_)          # nearly collinear pair
    xt = np.abs(rng.normal(size=n_)); xt[1] = -2.0       # a negative truth: unbounded LS goes negative
    y_ = A_ @ xt + 0.05 * rng.normal(size=m_)
    xn, rn_ = nnls(A_, y_, maxiter=10000)
    xl_, *_ = np.linalg.lstsq(A_, y_, rcond=None)
    assert (xl_ < 0).any() and (xn >= 0).all() and (xn == 0).any()
    cases.append({"rows": m_, "cols": n_, "A": [[float(v) for v in A_[:, j]] for j in range(n_)],  # column lists
                  "y": [float(v) for v in y_], "nnls": [float(v) for v in xn], "lstsq": [float(v) for v in xl_]})
# cases where Lawson-Hanson's inner loop must back-track (a column that entered turns negative): found by an
# instrumented Python port of the algorithm (gen/lh_search.py), reference solution still scipy's nnls
def lh_backtracks(A, y):
    m, n = A.shape; P = np.zeros(n, bool); x = np.zeros(n); back = 0
    for _ in range(3*n+100):
        w = A.T @ (y - A @ x)
        Z = np.where(~P)[0]
        if len(Z) == 0 or w[Z].max() <= 1e-12: break
        t = Z[np.argmax(w[Z])]; P[t] = True
        while True:
            idx = np.where(P)[0]
            s = np.zeros(n); s[idx] = np.linalg.lstsq(A[:, idx], y, rcond=None)[0]
            if (s[idx] > 0).all(): x = s; break
            back += 1
            neg = idx[s[idx] <= 0]
            alpha = np.min(x[neg] / (x[neg] - s[neg]))
            x = x + alpha * (s - x)
            P[idx[x[idx] <= 1e-14]] = False; x[~P] = 0
    return x, back
rng2 = np.random.default_rng(424242)
nb = 0
for trial in range(4000):
    m_, n_ = int(rng2.integers(30, 90)), int(rng2.integers(4, 9))
    A = rng2.random((m_, n_))
    for j in range(1, n_):
        if rng2.random() < 0.6: A[:, j] = A[:, j - 1] * rng2.uniform(0.5, 1.5) + 0.15 * rng2.random(m_)
    xt = rng2.normal(size=n_) * 2
    y_ = A @ xt + 0.3 * rng2.normal(size=m_)
    xs, back = lh_backtracks(A, y_)
    xr, _ = nnls(A, y_, maxiter=100000)
    if back >= 2 and np.allclose(xs, xr, atol=1e-8) and (xr == 0).any() and (xr > 0).any():
        xl_, *_ = np.linalg.lstsq(A, y_, rcond=None)
        cases.append({"rows": m_, "cols": n_, "A": [[float(v) for v in A[:, j]] for j in range(n_)], "y": [float(v) for v in y_],
                      "nnls": [float(v) for v in xr], "lstsq": [float(v) for v in xl_], "backtracks": back})
        nb += 1
        if nb == 3: break
out["nnlsCases"] = cases
out["cases"]["fept"]["hyperspyRssGapToMin"] = out["cases"]["fept"]["rss"] - out["cases"]["fept"]["nnlsRefRss"]
print("hyperspy rss", out["cases"]["fept"]["rss"], "min rss", out["cases"]["fept"]["nnlsRefRss"])
print("fept nFree", c["nFree"], "redChisq", c["redChisq"], "pin", c["pinFe"], c["pinPt"])
print("nnls ref Fe/Pt", c["nnlsRef"]["Fe_Ka"], c["nnlsRef"]["Pt_La"], "lstsq", c["lsRef"]["Fe_Ka"], c["lsRef"]["Pt_La"])
print("negative in lstsq:", c["lsRefNegative"])
print("closed loop fitted", out["cases"]["closedLoop"]["fitted"], out["cases"]["closedLoop"]["redChisq"])
import os, sys
_out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Tests", "SpectroCoreTests", "Fixtures", "eds-fit-exspy-7185a4d1.json")
json.dump(out, open(_out, "w"), separators=(",", ":"))
