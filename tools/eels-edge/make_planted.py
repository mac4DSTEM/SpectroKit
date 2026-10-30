#!/usr/bin/env python3
"""Planted core-loss EELS images with a known areal density: SpectroKit EELS edge quantification, design note section 5.

NumPy only (no HyperSpy, no exSpy, no SciPy): the truth. The one thing taken from exSpy is the cross-section SHAPE, read
from the fixture pins.py --sigma-only wrote (edge-sigma-CK.f64): it is the same on both sides by construction, so this
truth tests the background, the windows and the ratio, not the GOS.

Run (after extract_gos.py and `pins.py --sigma-only`):
    python3 tools/eels-edge/make_planted.py [--fixtures DIR] [--out DIR]
Reads  edge-sigma-CK.f64/.json and the thickness fixtures' planted-noiseless.f64/.json from --fixtures (default Tests/SpectroEELSTests/Fixtures).
Writes into --out (default --fixtures):
    edge-core-{case}-{noiseless,noisy}.f64   15 core-loss spectra, shape (3, 5, 2000)
    edge-low-{case}-{noiseless,noisy}.f64    the same pixels' low-loss spectra, shape (3, 5, 3400)
    edge-planted.json                        manifest: layout, axes, sha256 of every file, the model constants
    edge-planted-truth.json                  n_true, (A, r), I_low and the generator's predicted method bias
  and the SECOND (realistic) set, n_true in [200, 500, 1000, 2000, 5000], seed 20261016, same everything else:
    edge-{core,low}-R-{case}-{kind}.f64, edge-planted-R.json, edge-planted-truth-R.json
  cases: ss (single scattering), ps03, ps07, ps13 (plural scattering, tau 0.3, 0.7, 1.3).
  float64 little-endian, C order (rows = backgrounds, cols = densities, channels); pixel index p = row * 5 + col.

THE MODEL
---------
Core-loss axis: E_k = 150 + 0.25 k eV, k = 0..1999 (150 to 649.75 eV). Counts are per channel (binned axis). Channel k is
the energy bin [E_k, E_k + 0.25) eV (READING, --bin left, the default: the design note does not say whether E_k is a
channel's centre or its left edge. HyperSpy's two-area estimator treats the sum of channels [i1, i3) as the integral from
x1 = E_i1 to x3 = E_i3, i.e. E_k is the LEFT edge; with that reading the method is exact for a power law up to the
point-sample-for-integral term, which is what "channel sums standing in for integrals" describes. --bin centre makes the
bin [E_k - 0.125, E_k + 0.125): the method then carries a half-channel shift and its bias is large (README Findings,
reported, never used for the fixtures).)
Pixels: 3 backgrounds x 5 densities. Row r: (A, r) in [(1e9, 3.0), (5e8, 2.5), (2e10, 3.5)]; column c: n_true in
[2, 5, 10, 20, 50] atoms/nm^2 of carbon.
  Background B[k] = integral over the channel's bin of A E^-r dE = A/(1-r) (hi^(1-r) - lo^(1-r)), EXACT (analytic).
  Cross section: exSpy's function(E) (barn/eV, C K, E0 200 keV, alpha 10 mrad, beta 20 mrad, scale 0.25 eV; the planted
  microscope setting, stated here and in pins.py) from the fixture; per channel sigma_ch[k] = function(E_k) * 0.25 barn
  (a point sample times the scale, like exSpy's model; 0 below the 284 eV onset). The fixture holds 2040 channels
  (to 659.75 eV) because the zero-loss peak's negative-energy tail pulls channels beyond 650 eV into the convolution.
  UNITS: 1 barn = 1e-28 m^2 = 1e-10 nm^2. An areal density n [atoms/nm^2] and a low-loss intensity I_low [counts] give
        edge counts per channel = I_low * n * sigma_ch[k] [barn] * 1e-10 [nm^2/barn]
  (design note section 5's "n_true * I_low * sigma(E) * scale" with the barn -> nm^2 factor made explicit; section 3.4's
  n = I_k / (I_low sigma_k) * 1e10 is the inverse).
  With I_0 = 1e7 and n <= 50 the edge is a few counts per channel on a background of tens to hundreds: see README Findings.

CASES
  ss : single scattering. Low-loss = a delta of I_0 = 1e7 counts at 0 eV (fine channel 200). Edge = I_0 n sigma_ch 1e-10.
  ps03/ps07/ps13 : plural scattering. Low-loss = the thickness fixtures' planted low-loss pixel of tau 0.3 / 0.7 / 1.3 (pixel 3 / 5 / 7
       of planted-noiseless.f64), normalised to its own total and scaled so the TOTAL low-loss counts are I_t = 1e7 (READING:
       the design note fixes I_0 = 1e7 for single scattering only; here the total, not the zero-loss, is 1e7).
       Edge = (low-loss) convolved with the unit response n sigma_ch 1e-10 (so a flat sum over a long window gives
       n sigma_k I_t; Egerton eq. 4.66 divides by the part of I_t below Delta instead).
  All 15 pixels of an image share the case's low-loss spectrum.

HOW THE 0.05 eV LOW-LOSS IS MAPPED ONTO THE 0.25 eV CORE-LOSS GRID
  Fine channel j (loss L_j = -10 + 0.05 j, j = 0..3399; 0 eV is j = 200). 0 eV is aligned to the CENTRE of a coarse channel:
  coarse channel c (loss 0.25 c, c = -40..640) takes the five fine channels j = 198 + 5c .. 202 + 5c (centres within
  +-0.1 eV of 0.25 c): c = (j - 198) // 5. The rebin is an exact sum (counts are conserved; the two end bins hold 3 fine channels
  each, nothing is lost). Then the convolution is a plain discrete convolution on the core-loss grid:
        edge[m] = sum_c LLc[c] * resp[m - c],   resp[k] = n sigma_ch[k] 1e-10  (k = 0..2039; 0 outside)
  because E_m - 0.25 c = E_{m-c} exactly. The sums run c ascending, one NumPy vector add each (no BLAS, no FFT):
  byte-reproducible. The ZLP's Gaussian (sigma 0.25 eV) is thus resolved on 0.25 eV channels, which broadens the edge onset a
  little relative to a continuous convolution; the predicted bias uses the SAME mapped arrays, so the two agree.
  The fine low-loss itself is stored (edge-low-*), and I_low(Delta) is computed from it as registered: the sum of fine
  channels from the first to the value-sliced index of energy Delta (end exclusive).

THE PREDICTED METHOD BIAS (from the components; the method is never run)
  For each window (default [E_k-50, E_k-5], wide [E_k-80, E_k-10], narrow [E_k-30, E_k-3] with E_k = 284) and each Delta in
  {30, 50, 100, 150}: indices by HyperSpy's rules (value_range_to_indices, the parity rule, i3; value2index's rounding is
  ported), I1 = sum over channels [i1, i3), I2 over [i3, i2) of the TWO COMPONENTS summed separately (exact background +
  n * edge response; the edge response is zero below the onset by construction of sigma_ch for ss, and its negative-energy
  tails are included exactly for ps), then the two-area formulas r, A (HyperSpy power_law.py:156-158), then
        I_b,est  = sum over the edge window [E_k, E_k+Delta) of A_est E^-r_est * 0.25   (the model's point value x scale)
        I_b,true = sum over the same channels of the exact bin integrals
        I_k,est  = I_k,edge + I_b,true - I_b,est         (what the subtraction leaves; I_k,edge = n * sum of the edge response)
        n_pred   = I_k,est * 1e10 / (I_low(Delta) * sigma_k(Delta)),   bias = n_pred - n_true.
  The bias thus has three parts, each recorded: the background's channel-sum-for-integral and two-area error
  (biasBackground = (I_b,true - I_b,est) * 1e10 / (I_low sigma_k)) and the plural-scattering edge-window mismatch
  (biasEdge = I_k,edge * 1e10 / (I_low sigma_k) - n_true; zero up to rounding for ss). The I_0 route is recorded beside it with
  I_0 = the fine low-loss sum below a fixed threshold (2.5, 4.5, 6.0 eV: channels [0, value2index(theta))).

NOISE: numpy.random.default_rng(20261015); for case in (ss, ps03, ps07, ps13): core = poisson(noiseless core), then
low = poisson(noiseless low), each once on the whole float64 array in C order; stored as float64.
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
ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--fixtures", default=os.path.join(REPO, "Tests", "SpectroEELSTests", "Fixtures"))
ap.add_argument("--out", default=None)
ap.add_argument("--bin", choices=["left", "centre"], default="left",
                help="channel k is the bin [E_k, E_k + 0.25) (left, default) or [E_k - 0.125, E_k + 0.125) (centre)")
ARGS = ap.parse_args()
OUT = ARGS.out or ARGS.fixtures

OFF_C, SC_C, N_C, N_SIG = 150.0, 0.25, 2000, 2040
OFF_L, SC_L, N_L, K_ZERO = -10.0, 0.05, 3400, 200
ONSET = 284.0
BACKGROUNDS = [(1e9, 3.0), (5e8, 2.5), (2e10, 3.5)]
DENSITIES = [2.0, 5.0, 10.0, 20.0, 50.0]
ROWS, COLS = 3, 5
I_TOT = 1.0e7
CASES = [("ss", None, None), ("ps03", 0.3, 3), ("ps07", 0.7, 5), ("ps13", 1.3, 7)]   # (name, tau, slice-1 pixel)
SEED = 20261015
DELTAS = [30, 50, 100, 150]
WINDOWS = {"default": (-50.0, -5.0), "wide": (-80.0, -10.0), "narrow": (-30.0, -3.0)}   # relative to the onset
THETAS = [2.5, 4.5, 6.0]
BARN_NM2 = 1e-10


# ---------------------------------------------------------------- JSON / raw writers
def _scalar(v):
    if isinstance(v, (bool, np.bool_)):
        return "true" if v else "false"
    if v is None:
        return "null"
    if isinstance(v, (int, np.integer)):
        return str(int(v))
    if isinstance(v, (float, np.floating)):
        v = float(v)
        if not math.isfinite(v):
            raise ValueError("non-finite float in JSON")
        return repr(v)
    return json.dumps(v, ensure_ascii=False)


def _dump(v, ind, out):
    pad = "  " * ind
    if isinstance(v, np.ndarray):
        v = v.tolist()
    if isinstance(v, dict):
        out.append("{\n")
        items = list(v.items())
        for i, (k, x) in enumerate(items):
            out.append(pad + "  " + json.dumps(k) + ": ")
            _dump(x, ind + 1, out)
            out.append(",\n" if i + 1 < len(items) else "\n")
        out.append(pad + "}")
    elif isinstance(v, (list, tuple)):
        if all(not isinstance(x, (dict, list, tuple)) for x in v):
            out.append("[" + ", ".join(_scalar(x) for x in v) + "]")
        else:
            out.append("[\n")
            for i, x in enumerate(v):
                out.append(pad + "  ")
                _dump(x, ind + 1, out)
                out.append(",\n" if i + 1 < len(v) else "\n")
            out.append(pad + "]")
    else:
        out.append(_scalar(v))


def write_json(path, obj):
    out = []
    _dump(obj, 0, out)
    data = ("".join(out) + "\n").encode()
    with open(path, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest()


def write_raw(path, arr):
    data = np.ascontiguousarray(arr, dtype="<f8").tobytes()
    with open(path, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest(), len(data)


def read_raw(path, shape):
    return np.frombuffer(open(path, "rb").read(), dtype="<f8").reshape(shape).copy()


# ---------------------------------------------------------------- HyperSpy's rules, ported (axes.py:1315-1349, 648-690)
def v2i(v, offset, scale, size):
    q = (v - offset) / scale
    index = (1.0 / 1e12) * float(math.trunc(q * 1e12))
    if v >= 0:
        r = math.ceil(index - 0.5) if index >= 0 else math.floor(index + 0.5)
    else:
        r = math.floor(index + 0.5) if index >= 0 else math.ceil(index - 0.5)
    if not (0 <= r < size):
        raise ValueError("out of the axis limits")
    return int(r)


def value_range_to_indices(v1, v2, offset, scale, size):
    low, high = offset, offset + scale * (size - 1)
    i1, i2 = 0, size - 1
    if low < v1 <= high:
        i1 = v2i(v1, offset, scale, size)
    if high > v2 >= low:
        i2 = v2i(v2, offset, scale, size)
    return i1, i2


def two_area_indices(ea, eb):
    i1, i2 = value_range_to_indices(ea, eb, OFF_C, SC_C, N_C)
    if not (i2 + i1) % 2 == 0:
        i2 -= 1
    if i2 == i1:
        i2 += 2
    return i1, i2, (i2 + i1) // 2


def bin_integral(A, r, E):
    lo = E if ARGS.bin == "left" else E - SC_C / 2
    hi = lo + SC_C
    return A / (1.0 - r) * (hi ** (1.0 - r) - lo ** (1.0 - r))


def run_set(tag, dens, seed, manifest_name, truth_name):
    os.makedirs(OUT, exist_ok=True)
    fx = ARGS.fixtures
    sj = json.load(open(os.path.join(fx, "edge-sigma-CK.json")))
    func = read_raw(os.path.join(fx, "edge-sigma-CK.f64"), (N_SIG,))
    assert sj["energyAxis"]["offset"] == OFF_C and sj["energyAxis"]["scale"] == SC_C and sj["shape"] == [N_SIG]
    sig_ch = func * SC_C                                      # barn per channel
    resp = sig_ch * BARN_NM2                                  # unit response (per atom/nm^2 and per count)
    s1 = read_raw(os.path.join(fx, "planted-noiseless.f64"), (2, 5, N_L)).reshape(10, N_L)

    E_c = OFF_C + SC_C * np.arange(N_C)
    nb = ROWS * COLS
    A_px = np.array([BACKGROUNDS[p // COLS][0] for p in range(nb)])
    r_px = np.array([BACKGROUNDS[p // COLS][1] for p in range(nb)])
    n_px = np.array([dens[p % COLS] for p in range(nb)])
    bg = np.array([bin_integral(A_px[p], r_px[p], E_c) for p in range(nb)])        # (15, 2000)

    rng = np.random.default_rng(seed)
    files, truth_cases = {}, {}
    for name, tau, s1px in CASES:
        if tau is None:
            ll = np.zeros(N_L)
            ll[K_ZERO] = I_TOT
        else:
            px = s1[s1px]
            ll = px / np.sum(px) * I_TOT
        # exact rebin onto the core-loss grid: c = (j - 198) // 5, c = -40..640
        cbin = (np.arange(N_L) - 198) // 5 + 40
        llc = np.bincount(cbin, weights=ll, minlength=681)
        assert abs(np.sum(llc) - np.sum(ll)) <= 1e-9 * np.sum(ll)
        unit = np.zeros(N_C)                                  # edge response of the case per atom/nm^2
        for ci in np.flatnonzero(llc):
            c = int(ci) - 40
            lo, hi = max(0, c), min(N_C, c + N_SIG)
            if lo < hi:
                unit[lo:hi] += llc[ci] * resp[lo - c:hi - c]
        edge = np.array([n_px[p] * unit for p in range(nb)])                          # (15, 2000)
        core = bg + edge
        low = np.tile(ll, (nb, 1))
        core_img, low_img = core.reshape(ROWS, COLS, N_C), low.reshape(ROWS, COLS, N_L)
        noisy_core = rng.poisson(core_img).astype(np.float64)
        noisy_low = rng.poisson(low_img).astype(np.float64)
        for kind, c_arr, l_arr in (("noiseless", core_img, low_img), ("noisy", noisy_core, noisy_low)):
            for what, arr, shp in (("core", c_arr, [ROWS, COLS, N_C]), ("low", l_arr, [ROWS, COLS, N_L])):
                fn = f"edge-{what}-{tag}{name}-{kind}.f64"
                h, nbytes = write_raw(os.path.join(OUT, fn), arr)
                files[f"{what}-{tag}{name}-{kind}"] = {"file": fn, "shape": shp, "bytes": nbytes, "sha256": h}

        # ------------------------------------------------ predicted bias from the components
        i_low_d = {d: float(np.sum(ll[:v2i(float(d), OFF_L, SC_L, N_L)])) for d in DELTAS}
        i0_th = {t: float(np.sum(ll[:v2i(t, OFF_L, SC_L, N_L)])) for t in THETAS}
        win_out = {}
        for wname, (da, db) in WINDOWS.items():
            ea, eb = ONSET + da, ONSET + db
            i1, i2, i3 = two_area_indices(ea, eb)
            x1, x2, x3 = (OFF_C + SC_C * i1, OFF_C + SC_C * i2, OFF_C + SC_C * i3)
            I1 = np.array([np.sum(bg[p, i1:i3]) + np.sum(edge[p, i1:i3]) for p in range(nb)])
            I2 = np.array([np.sum(bg[p, i3:i2]) + np.sum(edge[p, i3:i2]) for p in range(nb)])
            r_est = 2 * (np.log(I1) - np.log(I2)) / (np.log(x2) - np.log(x1))
            k = 1 - r_est
            A_est = k * I2 / (x2 ** k - x3 ** k)
            edge_in_window = float(np.max([np.sum(np.abs(edge[p, i1:i2])) / np.sum(bg[p, i1:i2]) for p in range(nb)]))
            by_delta = {}
            for d in DELTAS:
                w0 = v2i(ONSET, OFF_C, SC_C, N_C)
                w1 = v2i(ONSET + d, OFF_C, SC_C, N_C)
                sigk = float(np.sum(sig_ch[w0:w1]))
                ik_edge = np.array([np.sum(edge[p, w0:w1]) for p in range(nb)])
                ib_true = np.array([np.sum(bg[p, w0:w1]) for p in range(nb)])
                ib_est = np.array([np.sum(A_est[p] * E_c[w0:w1] ** -r_est[p] * SC_C) for p in range(nb)])
                il = i_low_d[d]
                denom = il * sigk
                n_pred = (ik_edge + ib_true - ib_est) * 1e10 / denom
                entry = {"i0": w0, "i1": w1, "sigmaK": sigk, "iLow": il,
                         "ikEdge": ik_edge, "ibTrue": ib_true, "ibEst": ib_est,
                         "nPredicted": n_pred, "bias": n_pred - n_px,
                         "biasRelativeToNTrue": (n_pred - n_px) / n_px,
                         "biasBackground": (ib_true - ib_est) * 1e10 / denom,
                         "biasEdge": ik_edge * 1e10 / denom - n_px,
                         "i0Route": {}}
                for t in THETAS:
                    np_i0 = (ik_edge + ib_true - ib_est) * 1e10 / (i0_th[t] * sigk)
                    entry["i0Route"][repr(t)] = {"i0": i0_th[t], "nPredicted": np_i0, "bias": np_i0 - n_px,
                                                 "biasRelativeToNTrue": (np_i0 - n_px) / n_px}
                by_delta[str(d)] = entry
            win_out[wname] = {"valueRangeEV": [ea, eb], "i1": i1, "i2": i2, "i3": i3, "x1": x1, "x2": x2, "x3": x3,
                              "I1": I1, "I2": I2, "r": r_est, "A": A_est,
                              "maxEdgeToBackgroundInWindow": edge_in_window, "byDelta": by_delta}
        truth_cases[name] = {"tau": tau, "lowLossTotal": float(np.sum(ll)),
                             "iLowByDelta": {str(d): i_low_d[d] for d in DELTAS},
                             "i0ByThetaEV": {repr(t): i0_th[t] for t in THETAS},
                             "windows": win_out}

    axis_c = {"offset": OFF_C, "scale": SC_C, "size": N_C, "units": "eV", "binned": True}
    axis_l = {"offset": OFF_L, "scale": SC_L, "size": N_L, "units": "eV", "binned": True}
    layout = {"dtype": "float64", "byteOrder": "little",
              "order": "C: rows (backgrounds), cols (densities), channels; pixel index p = row * 5 + col"}
    model = {"edge": "C K", "onsetEV": ONSET, "microscope": {"beamEnergyKeV": 200.0, "convergenceAngleMrad": 10.0,
                                                           "collectionAngleMrad": 20.0},
             "backgroundsAr": BACKGROUNDS, "densitiesPerNm2": dens, "totalLowLossCounts": I_TOT,
             "channelConvention": ("channel k = bin [E_k, E_k + 0.25) eV" if ARGS.bin == "left" else "channel k = bin [E_k - 0.125, E_k + 0.125) eV"),
             "sigmaFixture": {"file": "edge-sigma-CK.f64", "sha256": hashlib.sha256(open(os.path.join(fx, "edge-sigma-CK.f64"), "rb").read()).hexdigest()}}
    write_json(os.path.join(OUT, manifest_name), {
        "schema": "spectrokit.eels.edge-planted/1", "generator": "tools/eels-edge/make_planted.py",
        "numpyVersion": np.__version__, "registration": "the EELS edge design note section 5",
        "coreLossAxis": axis_c, "lowLossAxis": axis_l, **layout, "cases": [c[0] for c in CASES],
        "tauByCase": {c[0]: c[1] for c in CASES}, "model": model,
        "noise": {"seed": seed, "order": "for case in (ss, ps03, ps07, ps13): poisson(core) then poisson(low), "
                                         "each once on the whole (3, 5, N) float64 array"},
        "files": files,
        "licence": "SpectroKit's own (GPL-3.0-only); generated; the cross-section shape is exSpy's dft-GOS result (CC-BY-4.0 data)"})
    truth = {"schema": "spectrokit.eels.edge-planted-truth/1", "generator": "tools/eels-edge/make_planted.py",
             "numpyVersion": np.__version__,
             "image": {"rows": ROWS, "cols": COLS, "order": "row-major; row = background, col = density"},
             "pixels": [{"row": p // COLS, "col": p % COLS, "nTrue": float(n_px[p]), "A": float(A_px[p]), "r": float(r_px[p])}
                        for p in range(nb)],
             "units": "n in atoms/nm^2; sigma in barn; counts = I_low * n * sigma_barn * 1e-10; n = I_k * 1e10 / (I_low * sigma_k)",
             "coreLossAxis": axis_c, "lowLossAxis": axis_l, "model": model, "cases": truth_cases}
    write_json(os.path.join(OUT, truth_name), truth)

    # ---- console summary
    for name in truth_cases:
        for wname in WINDOWS:
            for d in DELTAS:
                e = truth_cases[name]["windows"][wname]["byDelta"][str(d)]
                rel = e["biasRelativeToNTrue"]
                print(f"{tag or '-':2} {name:5} {wname:8} D{d:<4} bias[n]  min {e['bias'].min():+.5f} max {e['bias'].max():+.5f}  "
                      f"rel min {rel.min():+.4%} max {rel.max():+.4%}")


DENSITIES_R = [200.0, 500.0, 1000.0, 2000.0, 5000.0]
SEED_R = 20261016


def main():
    run_set("", DENSITIES, SEED, "edge-planted.json", "edge-planted-truth.json")
    # the second, "realistic" set: a ~2-50 nm carbon film (200 .. 5000 atoms/nm^2); separate manifest and truth file
    run_set("R-", DENSITIES_R, SEED_R, "edge-planted-R.json", "edge-planted-truth-R.json")


if __name__ == "__main__":
    sys.exit(main())
