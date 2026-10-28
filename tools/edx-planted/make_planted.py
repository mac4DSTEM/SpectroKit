#!/usr/bin/env python3
"""Planted Al-Mg-Si EDX spectra with known areas: the EDX checks, design note section 5.2.

NumPy only (no HyperSpy, no exSpy, no SciPy): the truth. Line energies and weights are typed in below (the exSpy table
values are ASSERTED against exSpy by pins.py, they are not read from it); a Lawson-Hanson NNLS is written out for the
in-family continuum (check_surrogate.py compares it with SciPy's).

Run:
    python3 tools/edx-planted/make_planted.py [--out DIR]          (DIR defaults to Tests/SpectroEDXTests/Fixtures)
Writes into DIR:
    edx-planted-means.f64    noise-free expected counts, one row per cell, float64 little-endian, C order, (ncell, NWIN)
    edx-planted-resid.i16    Poisson realisations as RESIDUALS, int16 little-endian, C order, (nreal_total, NWIN):
                             counts = rint(mean row of the cell) + residual   (rint = round half to even; Swift
                             `.rounded(.toNearestOrEven)`), so a 2.3e6-count channel needs 2 bytes, not 8
    edx-planted.json         manifest: axis, window, constants, every cell (id, set, family, N_Al, rho_Mg, mean row,
                             first residual row, n realisations, seed, per-realisation full-spectrum totals), sha256
    edx-planted-truth.json   per cell: the planted areas (Mg, Al, Si, O, Ar, sum_AlAl) in counts and the generator's parameters
    edx-calibration.json + edx-calibration-counts.u32
                             the calibration set (E3): rows of RAW counts, uint32 little-endian, window [CAL_K0, CAL_K0+CAL_NWIN)
Floats in JSON are Python reprs (they round-trip exactly). Everything is deterministic: two runs write identical bytes.

THE AXIS: a measured Super-X header, E_k = -1.93221348 + 0.02 k keV, k = 0..4095 (OffsetEnergy -1932.21348 eV,
Dispersion 20 eV). The expected counts of channel k are the model's mass over [E_k - 0.01, E_k + 0.01) keV: E_k is the
channel's CENTRE (rsciio's convention; the "half channel" set HALF takes the bin as [E_k, E_k + 0.02) instead).
Only channels [K0, K0+NWIN) = [96, 1152) (E = -0.012 .. 21.1 keV, the proposer's 0.2-20 keV range inside) are stored; the
generator draws and totals all 4096.

THE MODEL (all lines Gaussian; every area is exact, in counts; N_Al = Al Ka + Kb counts):
  lines   'table' : exSpy 7185a4d1 table (Mg Ka 1.2536 / Kb 1.305 w 0.01; Al 1.4865 / 1.5596 w 0.0132; Si 1.7397 / 1.8389
                    w 0.02779; O Ka 0.5249): what the shipped model fits, so set M has no line-table mismatch (criterion 3).
          'booklet': X-ray Data Booklet energies and Kb/Ka ratios (Mg 1.2536 / 1.3022 w 0.02; Al 1.4865 / 1.5575 w 0.013;
                    Si 1.7400 / 1.8359 w 0.02), independent of exSpy's table; used by U, B and the calibration set.
  areas   Al = N_Al, Mg = rho_Mg N_Al, Si = 0.01 N_Al (the line's share by its weight: area_i = N w_i / sum w); X adds
          O Ka 0.003 N_Al and the Al+Al pile-up at 2 x 1.4865 = 2.9730 keV with 1e-3 N_Al (Ar is NOT present: truth Ar = 0).
  widths  'fn'  : exSpy's Fiori-Newbury law FWHM = sqrt(2.5 (E - 5.8987) 1000 + R^2) / 1000, R = R_MnKa (the model's law;
                  the model runs at 130);
          'fano': FWHM^2 = 8 ln2 (s_n^2 + eps F E), eps 3.76 eV, F 0.11, s_n^2 so FWHM(Mn Ka 5898.7 eV) = R_MnKa.
                  (READING: the design note writes 2.3548^2; 8 ln2 = 5.545177 is the exact constant, relative difference
                  1.6e-5 of the FWHM slope; the registered 79.0 / 82.3 / 85.8 eV at R = 130 reproduce, see README.)
  continuum  Kramers (E0 - E)/E, E0 = 200 keV, times a roll-off, zero below 0.15 keV, sampled at the channel energy,
          scaled so the raw sum over 0.2-20 keV is frac x N_Al: frac = 0.03 (family 's', rho_c = 0.0008 in +-1 FWHM around
          Mg Ka) or 0.3 (family 'L', rho_c = 0.008).
          'realA': roll-off 1 - exp(-(E/0.30)^2.5)   (the physical stand-in);
          'realC': roll-off 1 - exp(-(E/0.5)^2.4)    (set C1: the shape Continuum.swift's comment says orders (9,5) were tuned on);
          'realAabs': realA times 0.92 for E >= 1.5596 keV (set C2: an 8 % Al K absorption step on the continuum shape, BEFORE
                  the normalisation to frac x N_Al: READING, the design note does not say before or after);
          'family': the realA shape projected (non-negative least squares on unit-norm columns, 0.2-20 keV channels) onto the
                  model's own family: Kramers x Bernstein, orders (9, 5) split at 1.5596 keV, the t of a channel
                  (E - a)/(b - a) at its centre energy: in the model's cone by construction (the "in-family" continuum).
  tail    an exponential shelf below Al Ka, e-folding 0.15 keV, a fraction `tail` of the Al Ka area moved from the
          Gaussian into the shelf (area conserved), point-sampled at the channel energy.
  shift   line energy = e (1 + gain) + delta/1000 keV, for every line (continuum untouched), the model keeps the file axis.

SETS (generator parameters; 'M' is everything matched, every other set changes ONE thing):
  M   matched: table lines, fn widths R = 130, family continuum, no tail, no shift
  S+d S-d  delta = +-1, 2, 3, 5, 10 eV (10 sets)           HALF  bin mass over [E_k, E_k + 0.02) (continuum evaluated at E_k + 0.01)
  T1 T2 T5  tail 1, 2, 5 %                                  U125 U130 U140 U150  fano widths, booklet lines, realA continuum
  C1 C2     continuum mismatch (above)                      B    booklet lines, fn widths, family continuum (line-table mismatch alone)
  W1 W2 W4 W6  fn widths with R solved (bisection) so FWHM at Al Ka is x1.01 / 1.02 / 1.04 / 1.06 of R = 130's
              (EXTRA: the 7.3 table's width rows, not a registered set)
  X   M plus O Ka 0.003 N_Al and the Al+Al pile-up (the sum-peak conflict path)
CELLS: M/s: N in {1e4,1e5,1e6,1e7} x rho in {0,.001,.002,.005,.01,.02,.05}, 100 realisations; M/L: the same 28 means, 20
realisations at N in {1e6,1e7} x rho in {0,.002,.01,.05}; U130 (s and L): N in {1e5,1e6,1e7} x rho in {0,.002,.01,.05}, 20
realisations; U125/140/150 (s): N 1e7 x rho in {.002,.01,.05}, 20; every other set (s): N in {1e5,1e6,1e7} x rho in
{0,.002,.01,.05} as MEANS and N 1e7 x rho in {.002,.01,.05} with 5 realisations; their family-L means at N 1e7 x rho in {.002,.01}.
SEEDS: numpy.random.default_rng([20261017, set_index, family_index, log10(N), rho_index]); one stream per cell, realisation j
(1-based) is row j-1 of rng.poisson(mean, size=(n, 4096)) (a prefix of the 100-row draw: 5 and 20 are its first rows).
CALIBRATION SET (E3, edx-calibration.json): delta in {-12,-5,-1,0,1,5,8,12} eV x gain in {-3,0,+3}e-4 x R_MnKa in
{125,130,140,150} (fano widths, booklet lines, realA continuum, family s), rho_Mg 0.05; N_Al 1e6 (3 realisations) and 1e7 (1),
seed [20261017, 100, delta_index, gain_index, R_index, N_index]. Truth: the axis that puts the lines at their nominal energies,
E'(k) = (E_k - delta/1000)/(1 + gain): offset' = (OFF - delta/1000)/(1 + gain), scale' = SC/(1 + gain).
"""
import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))

OFF, SC, NCH = -1.93221348, 0.02, 4096
K0, NWIN = 96, 1056
CAL_K0, CAL_NWIN = 96, 192
SEED0 = 20261017
E0_KEV = 200.0
MN_KA = 5.8987
ALK_EDGE = 1.5596
FAMILY_FRAC = {"s": 0.03, "L": 0.3}
FAMILY_INDEX = {"s": 0, "L": 1}
RHO_ALL = [0.0, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05]
N_ALL = [1e4, 1e5, 1e6, 1e7]
RHO_SI, RHO_O, RHO_SUM = 0.01, 0.003, 1e-3
C8LN2 = 8.0 * math.log(2.0)

TABLE = {"Mg": [(1.2536, 1.0), (1.305, 0.01)], "Al": [(1.4865, 1.0), (1.5596, 0.0132)],
         "Si": [(1.7397, 1.0), (1.8389, 0.02779)], "O": [(0.5249, 1.0)]}
BOOKLET = {"Mg": [(1.2536, 1.0), (1.3022, 0.02)], "Al": [(1.4865, 1.0), (1.5575, 0.013)],
           "Si": [(1.7400, 1.0), (1.8359, 0.02)], "O": [(0.5249, 1.0)]}

E_AXIS = OFF + SC * np.arange(NCH)


# ------------------------------------------------------------------------------------------------ widths
def fwhm_fn(e_keV, r):
    return math.sqrt(2.5 * (e_keV - MN_KA) * 1000.0 + r * r) / 1000.0


def fwhm_fano(e_keV, r):
    eps, fano = 3.76, 0.11
    s2n = r * r / C8LN2 - eps * fano * MN_KA * 1000.0
    return math.sqrt(C8LN2 * (s2n + eps * fano * e_keV * 1000.0)) / 1000.0


def r_for_al_scale(scale):
    """R_MnKa with fn FWHM at Al Ka = scale x (R = 130's), by bisection (60 halvings, as probe14)."""
    target = scale * fwhm_fn(1.4865, 130.0)
    lo, hi = 100.0, 200.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if fwhm_fn(1.4865, mid) < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


# ------------------------------------------------------------------------------------------------ shapes
_SHAPES = {}


def gauss_bins(centre, fwhm, left):
    """Gaussian mass per channel (+-10 sigma, zero elsewhere); channel k covers [E_k - .01, E_k + .01) or, if `left`, [E_k, E_k + .02)."""
    key = (repr(centre), repr(fwhm), left)
    if key in _SHAPES:
        return _SHAPES[key]
    sigma = fwhm / (2.0 * math.sqrt(2.0 * math.log(2.0)))
    out = np.zeros(NCH)
    lo_k = max(int(math.floor((centre - 10 * sigma - OFF) / SC)) - 2, 0)
    hi_k = min(int(math.ceil((centre + 10 * sigma - OFF) / SC)) + 3, NCH)
    k = np.arange(lo_k, hi_k)
    lo_edge = E_AXIS[k] - (0.0 if left else SC / 2)
    hi_edge = lo_edge + SC
    s2 = sigma * math.sqrt(2.0)
    erf_lo = np.array([math.erf((x - centre) / s2) for x in lo_edge])
    erf_hi = np.array([math.erf((x - centre) / s2) for x in hi_edge])
    out[k] = 0.5 * (erf_hi - erf_lo)
    _SHAPES[key] = out
    return out


def roll_a(e):
    return 1.0 - np.exp(-(e / 0.30) ** 2.5)


def roll_c(e):
    return 1.0 - np.exp(-(e / 0.5) ** 2.4)


def kramers(e):
    return (E0_KEV - e) / e


def continuum_shape(kind, left):
    """Unit continuum shape (raw sum over 0.2-20 keV = 1) sampled at the channel energies."""
    e = E_AXIS + (SC / 2 if left else 0.0)
    en = np.clip(e, 1e-3, None)
    roll = roll_c(en) if kind == "realC" else roll_a(en)
    c = np.where((e > 0.15) & (e < E0_KEV), kramers(en) * roll, 0.0)
    if kind == "realAabs":
        c = np.where(e >= ALK_EDGE, c * 0.92, c)
    sel = (E_AXIS > 0.2) & (E_AXIS < 20.0)
    return c / c[sel].sum()


def bernstein_columns(lo=0.2, hi=20.0, edge=ALK_EDGE, orders=(9, 5)):
    ch = np.where((E_AXIS >= lo) & (E_AXIS <= hi))[0]
    cols = []
    for s, (a, b, n) in enumerate(((lo, edge, orders[0]), (edge, hi, orders[1]))):
        idx = [i for i in ch if E_AXIS[i] >= a and (E_AXIS[i] < b if s == 0 else E_AXIS[i] <= b)]
        for k in range(n + 1):
            c = np.zeros(NCH)
            for i in idx:
                t = (E_AXIS[i] - a) / (b - a)
                c[i] = math.comb(n, k) * t ** k * (1 - t) ** (n - k) * (E0_KEV - E_AXIS[i]) / E_AXIS[i]
            cols.append(c)
    return np.array(cols), ch


def nnls(a, b, maxiter=5000):
    """Lawson-Hanson active set, written out (NumPy only). min |a x - b|, x >= 0."""
    m, n = a.shape
    p = np.zeros(n, bool)
    x = np.zeros(n)
    w = a.T @ (b - a @ x)
    tol = 10 * max(m, n) * np.finfo(float).eps * np.linalg.norm(a, 1)
    it = 0
    while (~p).any() and w[~p].max() > tol and it < maxiter:
        j = int(np.argmax(np.where(~p, w, -np.inf)))
        p[j] = True
        while True:
            s = np.zeros(n)
            s[p] = np.linalg.lstsq(a[:, p], b, rcond=None)[0]
            if s[p].min() > 0:
                x = s
                break
            neg = p & (s <= 0)
            alpha = np.min(x[neg] / (x[neg] - s[neg]))
            x = x + alpha * (s - x)
            p = p & (x > 1e-14)
            x[~p] = 0.0
        w = a.T @ (b - a @ x)
        it += 1
    return x


_FAMILY = {}


def family_shape():
    """The unit realA continuum projected on the model's Bernstein-Kramers cone (zero outside 0.2-20 keV)."""
    if "f" not in _FAMILY:
        cols, ch = bernstein_columns()
        d = cols[:, ch].T
        nrm = np.linalg.norm(d, axis=0)
        c = continuum_shape("realA", False)
        th = nnls(d / nrm, c[ch])
        f = np.zeros(NCH)
        f[ch] = (d / nrm) @ th
        _FAMILY["f"] = f
    return _FAMILY["f"]


# ------------------------------------------------------------------------------------------------ sets
def base_params():
    return dict(lines="table", width="fn", R=130.0, cont="family", delta=0.0, gain=0.0, tail=0.0, left=False, extras=False)


def make_sets():
    sets = [("M", base_params())]
    for d in (1, 2, 3, 5, 10):
        for sign, tag in ((1, "S+"), (-1, "S-")):
            p = base_params()
            p["delta"] = float(sign * d)
            sets.append((f"{tag}{d}", p))
    p = base_params(); p["left"] = True; sets.append(("HALF", p))
    for t in (1, 2, 5):
        p = base_params(); p["tail"] = t / 100.0; sets.append((f"T{t}", p))
    for r in (125, 130, 140, 150):
        p = base_params(); p.update(lines="booklet", width="fano", R=float(r), cont="realA"); sets.append((f"U{r}", p))
    p = base_params(); p["cont"] = "realC"; sets.append(("C1", p))
    p = base_params(); p["cont"] = "realAabs"; sets.append(("C2", p))
    p = base_params(); p["lines"] = "booklet"; sets.append(("B", p))
    for sc, tag in ((1.01, "W1"), (1.02, "W2"), (1.04, "W4"), (1.06, "W6")):
        p = base_params(); p["R"] = r_for_al_scale(sc); sets.append((tag, p))
    p = base_params(); p["extras"] = True; sets.append(("X", p))
    return sets


def cell_plan(sets):
    """[(set_name, family, N, rho, n_real)] in a fixed order."""
    names = [n for n, _ in sets]
    plan = []
    for n in N_ALL:
        for rho in RHO_ALL:
            plan.append(("M", "s", n, rho, 100))
    for n in N_ALL:
        for rho in RHO_ALL:
            plan.append(("M", "L", n, rho, 20 if (n in (1e6, 1e7) and rho in (0.0, 0.002, 0.01, 0.05)) else 0))
    for name in names:
        if name == "M":
            continue
        for fam in ("s", "L"):
            if fam == "s":
                for n in (1e5, 1e6, 1e7):
                    for rho in (0.0, 0.002, 0.01, 0.05):
                        if name == "U130":
                            nr = 20
                        elif name in ("U125", "U140", "U150"):
                            nr = 20 if (n == 1e7 and rho > 0) else 0
                        else:
                            nr = 5 if (n == 1e7 and rho > 0) else 0
                        plan.append((name, "s", n, rho, nr))
            else:
                if name == "U130":
                    for n in (1e5, 1e6, 1e7):
                        for rho in (0.0, 0.002, 0.01, 0.05):
                            plan.append((name, "L", n, rho, 20))
                else:
                    for rho in (0.002, 0.01):
                        plan.append((name, "L", 1e7, rho, 0))
    return plan


def spec_names(p, N, rho):
    return {"Al": N, "Mg": rho * N, "Si": RHO_SI * N}


def mean_spectrum(p, family, N, rho):
    """Expected counts per channel (all 4096), and the planted areas."""
    lines = TABLE if p["lines"] == "table" else BOOKLET
    r = p["R"]
    wf = (lambda e: fwhm_fn(e, r)) if p["width"] == "fn" else (lambda e: fwhm_fano(e, r))
    mu = np.zeros(NCH)
    areas = {"Mg": 0.0, "Al": 0.0, "Si": 0.0, "O": 0.0, "Ar": 0.0, "sum_AlAl": 0.0}
    ev = E_AXIS + (SC / 2 if p["left"] else 0.0)
    comps = [("Al", N), ("Mg", rho * N), ("Si", RHO_SI * N)]
    if p["extras"]:
        comps.append(("O", RHO_O * N))
    for el, n_el in comps:
        tot = sum(w for _, w in lines[el])
        for idx, (e, w) in enumerate(lines[el]):
            area = n_el * w / tot
            cen = e * (1.0 + p["gain"]) + p["delta"] / 1000.0
            g = gauss_bins(cen, wf(e), p["left"])
            if p["tail"] > 0 and el == "Al" and idx == 0:
                sh = np.where(ev < cen, np.exp((ev - cen) / 0.15), 0.0)
                sh = sh / sh.sum()
                mu += area * ((1.0 - p["tail"]) * g + p["tail"] * sh)
            else:
                mu += area * g
        areas[el] = n_el
    if p["extras"]:
        e = 2 * 1.4865
        mu += RHO_SUM * N * gauss_bins(e * (1.0 + p["gain"]) + p["delta"] / 1000.0, wf(e), p["left"])
        areas["sum_AlAl"] = RHO_SUM * N
    frac = FAMILY_FRAC[family]
    if p["cont"] == "family":
        mu += frac * N * family_shape()
    else:
        mu += frac * N * continuum_shape(p["cont"], p["left"])
    return mu, areas


def srepr(x):
    return repr(float(x))


def cell_id(name, fam, n, rho):
    return f"{name}.{fam}.N{int(round(math.log10(n)))}.rho{srepr(rho).replace('.', 'p')}"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def write_json(path, obj):
    with open(path, "w") as fh:
        json.dump(obj, fh, sort_keys=True, indent=1)
        fh.write("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(REPO, "Tests", "SpectroEDXTests", "Fixtures"))
    args = ap.parse_args()
    out = args.out
    os.makedirs(out, exist_ok=True)
    sets = make_sets()
    pmap = dict(sets)
    set_index = {n: i for i, (n, _) in enumerate(sets)}
    plan = cell_plan(sets)

    means = []
    resid_rows = []
    cells = []
    truth = {}
    row_resid = 0
    for (name, fam, n, rho, nreal) in plan:
        p = pmap[name]
        mu, areas = mean_spectrum(p, fam, n, rho)
        cid = cell_id(name, fam, n, rho)
        window = mu[K0:K0 + NWIN]
        cell = {"id": cid, "set": name, "family": fam, "N_Al": srepr(n), "rho_Mg": srepr(rho), "mean_row": len(means),
                "n_real": nreal, "resid_row0": row_resid if nreal else None, "mean_total_full": srepr(mu.sum())}
        means.append(window)
        if nreal:
            seed = [SEED0, set_index[name], FAMILY_INDEX[fam], int(round(math.log10(n))), RHO_ALL.index(rho)]
            rng = np.random.default_rng(seed)
            draws = rng.poisson(np.clip(mu, 0.0, None), size=(nreal, NCH))
            rint = np.rint(window)
            res = draws[:, K0:K0 + NWIN].astype(np.float64) - rint
            assert np.abs(res).max() < 32000, (cid, np.abs(res).max())
            resid_rows.append(res.astype("<i2"))
            cell["seed"] = seed
            cell["real_total_full"] = [int(draws[j].sum()) for j in range(nreal)]
            cell["real_total_window"] = [int(draws[j, K0:K0 + NWIN].sum()) for j in range(nreal)]
            row_resid += nreal
        cells.append(cell)
        truth[cid] = {"areas": {k: srepr(v) for k, v in areas.items()}, "params": {k: (srepr(v) if isinstance(v, float) else v) for k, v in p.items()}}
    means_arr = np.ascontiguousarray(np.array(means, dtype="<f8"))
    resid_arr = np.ascontiguousarray(np.concatenate(resid_rows, axis=0).astype("<i2"))
    files = {}
    for fname, arr in (("edx-planted-means.f64", means_arr), ("edx-planted-resid.i16", resid_arr)):
        with open(os.path.join(out, fname), "wb") as fh:
            fh.write(arr.tobytes())
        files[fname] = {"sha256": sha256_file(os.path.join(out, fname)), "bytes": os.path.getsize(os.path.join(out, fname)),
                        "shape": list(arr.shape), "dtype": str(arr.dtype)}

    # ---- calibration set
    deltas, gains, rs = [-12, -5, -1, 0, 1, 5, 8, 12], [-3e-4, 0.0, 3e-4], [125, 130, 140, 150]
    cal_rows, cal_cells = [], []
    row = 0
    for di, d in enumerate(deltas):
        for gi, g in enumerate(gains):
            for ri, r in enumerate(rs):
                for ni, (n, nreal) in enumerate(((1e6, 3), (1e7, 1))):
                    p = base_params()
                    p.update(lines="booklet", width="fano", R=float(r), cont="realA", delta=float(d), gain=g)
                    mu, areas = mean_spectrum(p, "s", n, 0.05)
                    rng = np.random.default_rng([SEED0, 100, di, gi, ri, ni])
                    draws = rng.poisson(np.clip(mu, 0.0, None), size=(nreal, NCH))
                    cal_rows.append(draws[:, CAL_K0:CAL_K0 + CAL_NWIN].astype("<u4"))
                    cal_cells.append({
                        "id": f"CAL.d{d}.g{srepr(g)}.R{r}.N{int(round(math.log10(n)))}", "delta_eV": srepr(d), "gain": srepr(g),
                        "R_MnKa": srepr(r), "N_Al": srepr(n), "rho_Mg": srepr(0.05), "row0": row, "n_real": nreal,
                        "seed": [SEED0, 100, di, gi, ri, ni], "areas": {k: srepr(v) for k, v in areas.items()},
                        "true_axis": {"offset_keV": srepr((OFF - d / 1000.0) / (1.0 + g)), "scale_keV": srepr(SC / (1.0 + g))}})
                    row += nreal
    cal_arr = np.ascontiguousarray(np.concatenate(cal_rows, axis=0).astype("<u4"))
    with open(os.path.join(out, "edx-calibration-counts.u32"), "wb") as fh:
        fh.write(cal_arr.tobytes())
    files["edx-calibration-counts.u32"] = {"sha256": sha256_file(os.path.join(out, "edx-calibration-counts.u32")),
                                           "bytes": cal_arr.nbytes, "shape": list(cal_arr.shape), "dtype": "<u4"}
    write_json(os.path.join(out, "edx-calibration.json"), {
        "what": "edx-calibration-counts.u32: rows of raw counts, window [k0, k0+nwin) of the 4096-channel axis; line energy = e(1+gain)+delta/1000 keV; true_axis is E'(k) that puts the lines at nominal energies",
        "axis": {"offset_keV": srepr(OFF), "scale_keV": srepr(SC), "channels": NCH}, "k0": CAL_K0, "nwin": CAL_NWIN,
        "lines": "booklet", "widths": "fano", "continuum": "realA", "family": "s", "cells": cal_cells,
        "counts": files["edx-calibration-counts.u32"]})

    manifest = {
        "what": "planted Al-Mg-Si spectra, design note section 5.2; see tools/edx-planted/make_planted.py for every definition",
        "axis": {"offset_keV": srepr(OFF), "scale_keV": srepr(SC), "channels": NCH}, "k0": K0, "nwin": NWIN,
        "seed0": SEED0, "decode": "counts = rint(means[mean_row]) + resid[resid_row0 + j], j = 0..n_real-1 (rint: half to even)",
        "line_tables": {"table": {k: [[srepr(e), srepr(w)] for e, w in v] for k, v in TABLE.items()},
                        "booklet": {k: [[srepr(e), srepr(w)] for e, w in v] for k, v in BOOKLET.items()}},
        "family_frac": {k: srepr(v) for k, v in FAMILY_FRAC.items()}, "files": files,
        "sets": {n: {k: (srepr(v) if isinstance(v, float) else v) for k, v in p.items()} for n, p in sets},
        "cells": cells}
    write_json(os.path.join(out, "edx-planted.json"), manifest)
    write_json(os.path.join(out, "edx-planted-truth.json"), truth)
    print(f"{len(cells)} cells, {int(sum(c['n_real'] for c in cells))} realisations, {len(cal_cells)} calibration cells ({cal_arr.shape[0]} rows)")
    for f in sorted(os.listdir(out)):
        if f.startswith("edx-planted") or f.startswith("edx-calibration"):
            print(f"{sha256_file(os.path.join(out, f))}  {os.path.getsize(os.path.join(out, f)):>9}  {f}")


if __name__ == "__main__":
    sys.exit(main())
