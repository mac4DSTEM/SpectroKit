#!/usr/bin/env python3
"""exSpy pins for SpectroKit's EELS slice 2 (registration sections 4.1-4.4): what exSpy 7185a4d1 / HyperSpy 2.4.0 answer.

Agreement with exSpy is agreement, not truth: the truth is make_planted.py and edge-planted-truth.json.

Run (HyperSpy 2.4.0 venv; the pinned exSpy checkout is NOT installed, it is put first on sys.path and EELSCLEdge is built
directly, as tools/eels-thickness/pins.py does; pyEELSMODEL at its pin is put second):

    References/exspy-venv/bin/python -I -B tools/eels-edge/pins.py --sigma-only     # phase A: the planted cross section
    (python3 tools/eels-edge/make_planted.py)                                       # reads phase A's fixture
    References/exspy-venv/bin/python -I -B tools/eels-edge/pins.py                  # phase B: everything else

Options: --exspy DIR  --pyeels DIR  --gos-dft FILE  --gos-dirac FILE  --gosh-dir DIR  --fixtures DIR  --out DIR

PHASE A (--sigma-only) writes edge-sigma-CK.f64/.json: exSpy's EELSCLEdge("C_K", GOS="dft").function(E) in barn/eV on
E = 150 + 0.25 k eV, k = 0..2039 (2040 channels; the planted core-loss axis is the first 2000), for THE PLANTED MICROSCOPE
SETTING E0 = 200 keV, alpha = 10 mrad, beta = 20 mrad, scale 0.25 eV (the same setting as slice 1's planted images).

PHASE B writes edge-pins.json (floats are Python reprs; all arrays are lists):
  environment : versions, sha256 of this script, md5 of the GOS files, commits.
  grid        : E0 {60, 80, 200, 300} keV x alpha {0, 1, 10, 30} mrad x beta {5, 20, 50, 100} mrad (the FULL product, 64)
                x C, N, O K (192 cases). Per case: effective angle (exSpy's effective_angle(E0, GOS.onset, alpha, beta));
                qint per tabulated energy (edge.GOS.qint after _integrate_GOS; barn/eV) with the energy axis it belongs to
                (float32 in exSpy, widened); the extrapolation power law (r, A); and per scale {0.1, 0.25, 1.0} eV the
                axis offset = onset - 10, the channel count n = round(170/scale) + 1 (so E runs onset-10 .. onset+160
                INCLUSIVE), function(E) per channel, and per Delta {30, 50, 100, 150} the channel indices [i0, i1) of
                isig[onset : onset + Delta] (HyperSpy's own value slicing on a Signal1D, end exclusive) and
                sigmaK = sum(function[i0:i1] * scale) (barn; np.sum, pairwise).
  splineC     : the not-a-knot cubic spline's knots t, coefficients c, degree k for C K, 200/10/20 (scale-free), and the
                intermediates of integrateq for that case: per tabulated energy (qmin, qmax) as passed to get_qaxis_and_gos.
  pyEELSMODEL : sigma_k from pyEELSMODEL's KohlLossEdge (shape fix: gos squeezed on its trailing axis) and exSpy's on the same
                axis (150 eV from, scale 1.0 (600 ch) and 0.25 (2400 ch), both to 750 eV), C/N/O K, Delta 50/100/150,
                (E0, alpha, beta) in (200,0,20) (200,10,20) (300,0,50) (80,0,10), with the ratio.
  dirac       : sigma_k Dirac / dft for C K on the full E0 x alpha x beta grid, scale 0.25 from 150 eV, Delta 50/100/150
                (diagnostic, section 4.4; Dirac file md5 checked).
  plantedR    : the same for the second (realistic) planted set, n_true 200-5000 (edge-planted-R.json), same structure.
  planted     : for every planted image of make_planted.py (4 cases x noiseless/noisy), for the three pre-edge windows
                default [E_k-50, E_k-5], wide [E_k-80, E_k-10], narrow [E_k-30, E_k-3] (E_k = 284), HyperSpy's
                `remove_background(signal_range=(E_a, E_b), background_type="Power law", fast=True, return_model=True)`
                (which calls PowerLaw.estimate_parameters(signal, E_a, E_b) then result = signal - model.as_signal();
                signal1d.py:1102-1152, power_law.py:100-187): i1, i2, i3, x1, x2, x3 (same for every pixel), per pixel
                I1, I2, r, A (HyperSpy's model values), the background per channel over [E_k, E_k+150) (as_signal:
                hyperspy/model.py:794; the point value A x^-r times the axis scale, models/model1d.py:387), and per Delta:
                I_k = sum(result[window]), I_b = sum(background[window]), sigmaK (C K, 200/10/20, 0.25), I_low(Delta)
                (low-loss fine channels [0, value-sliced index of Delta), end exclusive), n = I_k * 1e10 / (I_low * sigmaK),
                and the I_0 route for fixed thresholds 2.5, 4.5, 6.0 eV (I_0 = sum of channels [0, index of theta)).
                Also per Delta: varIk and sigmaN, the first-order counting-statistics estimate of registration section 6
                computed from the image's own counts (sigma_n = |n| sqrt(Var(I_k)/I_k^2 + 1/I_low); derivatives of I_b
                taken analytically through r, k, A).
"""
import argparse
import contextlib
import hashlib
import json
import logging
import math
import os
import platform
import sys
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--sigma-only", action="store_true", help="phase A: write only the planted cross-section fixture")
ap.add_argument("--exspy", default=os.path.join(REPO, "References", "exspy-7185a4d1"))
ap.add_argument("--pyeels", default=os.path.join(REPO, "References", "pyEELSMODEL-pin"))
ap.add_argument("--gos-dft", default=os.path.join(REPO, "References", "gos-dft-1.5.0.gosh"))
ap.add_argument("--gos-dirac", default=os.path.join(REPO, "References", "gos-dirac.gosh"))
ap.add_argument("--gosh-dir", default=os.path.join(REPO, "References", "gosh-dir"))
ap.add_argument("--fixtures", default=os.path.join(REPO, "Tests", "SpectroEELSTests", "Fixtures"))
ap.add_argument("--out", default=None)
ARGS = ap.parse_args()
OUT = ARGS.out or ARGS.fixtures
EXSPY = os.path.abspath(ARGS.exspy)

sys.path.insert(0, EXSPY)
sys.path.insert(1, os.path.abspath(ARGS.pyeels))
logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")

import numpy as np                                   # noqa: E402
import scipy                                         # noqa: E402

with open(os.devnull, "w") as _dn, contextlib.redirect_stdout(_dn), contextlib.redirect_stderr(_dn):
    import h5py                                      # noqa: E402
    import hyperspy                                  # noqa: E402
    import hyperspy.api as hs                        # noqa: E402
    import exspy                                     # noqa: E402
    from exspy.components import EELSCLEdge          # noqa: E402

assert os.path.realpath(os.path.dirname(exspy.__file__)) == os.path.realpath(os.path.join(EXSPY, "exspy")), exspy.__file__
EXSPY_COMMIT = "7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e"
PYEELS_COMMIT = "eed9f0721d5b"
MD5_DFT = "7fee8891c147a4f769668403b54c529b"
MD5_DIRAC = "01a855d3750d2c063955248358dbee8d"

ONSETS = {"C": 284.0, "N": 401.0, "O": 532.0}
PLANTED = {"E0": 200.0, "alpha": 10.0, "beta": 20.0, "scale": 0.25}
OFF_C, SC_C, N_C, N_SIG = 150.0, 0.25, 2000, 2040
OFF_L, SC_L, N_L = -10.0, 0.05, 3400
GRID_E0 = [60.0, 80.0, 200.0, 300.0]
GRID_ALPHA = [0.0, 1.0, 10.0, 30.0]
GRID_BETA = [5.0, 20.0, 50.0, 100.0]
GRID_SCALE = [0.1, 0.25, 1.0]
DELTAS = [30, 50, 100, 150]
THETAS = [2.5, 4.5, 6.0]
WINDOWS = {"default": (-50.0, -5.0), "wide": (-80.0, -10.0), "narrow": (-30.0, -3.0)}
CASES = ["ss", "ps03", "ps07", "ps13"]
PYEELS_SETTINGS = [(200.0, 0.0, 20.0), (200.0, 10.0, 20.0), (300.0, 0.0, 50.0), (80.0, 0.0, 10.0)]


# ---------------------------------------------------------------- writers
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
        if all(not isinstance(x, (dict, list, tuple, np.ndarray)) for x in v):
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


def sha_file(path, algo="sha256"):
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def read_raw(path, shape):
    return np.frombuffer(open(path, "rb").read(), dtype="<f8").reshape(shape).copy()


@contextlib.contextmanager
def quiet():
    with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
        yield


# ---------------------------------------------------------------- exSpy / HyperSpy helpers
def make_edge(el, E0, alpha, beta, scale, gos="dft"):
    path = ARGS.gos_dft if gos == "dft" else ARGS.gos_dirac
    with quiet():
        e = EELSCLEdge(f"{el}_K", GOS=gos, gos_file_path=path)
        e.set_microscope_parameters(E0=E0, alpha=alpha, beta=beta, energy_scale=scale)
    assert hasattr(e, "tab_xsection") and e.GOS.energy_shift == 0.0
    # NOTE (exSpy quirk): _integrate_GOS only runs if the effective angle CHANGED from its previous value, so an edge object
    # must not be reused across E0 at alpha = 0 (effective angle = beta): a fresh edge is made per case.
    return e


def dummy_signal(offset, scale, size):
    s = hs.signals.Signal1D(np.arange(size, dtype=float))
    ax = s.axes_manager.signal_axes[0]
    ax.offset, ax.scale, ax.units, ax.is_binned = offset, scale, "eV", True
    return s


def hs_slice(s, a, b):
    """Channel indices [i0, i1) of s.isig[a:b] by HyperSpy's own value slicing (a or b None = open)."""
    with quiet():
        d = s.isig[a:b].data
    if d.size == 0:
        raise ValueError("empty slice")
    i0 = int(d[0])
    assert d.tolist() == list(range(i0, i0 + d.size))
    return i0, i0 + d.size


def axis_E(offset, scale, size):
    return dummy_signal(offset, scale, size).axes_manager.signal_axes[0].axis.copy()   # offset + scale * arange


def sigma_k(f, scale, i0, i1):
    return float(np.sum(f[i0:i1] * scale))


# ---------------------------------------------------------------- phase A
def phase_a():
    e = make_edge("C", PLANTED["E0"], PLANTED["alpha"], PLANTED["beta"], PLANTED["scale"])
    E = axis_E(OFF_C, SC_C, N_SIG)
    f = e.function(E)
    h, nb = write_raw(os.path.join(OUT, "edge-sigma-CK.f64"), f)
    write_json(os.path.join(OUT, "edge-sigma-CK.json"), {
        "schema": "spectrokit.eels.raw-f64/1", "file": "edge-sigma-CK.f64", "shape": [N_SIG], "dtype": "float64",
        "byteOrder": "little", "order": "C",
        "what": "exSpy EELSCLEdge('C_K', GOS='dft').function(E): partial cross section in barn/eV per channel energy",
        "energyAxis": {"offset": OFF_C, "scale": SC_C, "size": N_SIG, "units": "eV", "binned": True},
        "microscope": {"beamEnergyKeV": PLANTED["E0"], "convergenceAngleMrad": PLANTED["alpha"],
                       "collectionAngleMrad": PLANTED["beta"], "energyScaleEV": PLANTED["scale"],
                       "effectiveAngleMrad": e.effective_angle.value},
        "bytes": nb, "sha256": h,
        "provenance": {"generator": "tools/eels-edge/pins.py --sigma-only", "exspyCommit": EXSPY_COMMIT,
                       "hyperspy": hyperspy.__version__, "numpy": np.__version__, "scipy": scipy.__version__,
                       "gosMd5": sha_file(ARGS.gos_dft, "md5"), "gosDoi": "10.5281/zenodo.7645765", "gosLicence": "CC-BY-4.0"}})
    print("phase A:", os.path.join(OUT, "edge-sigma-CK.f64"), nb, "bytes", h)


# ---------------------------------------------------------------- phase B pieces
def grid_block():
    cases, dummies = [], {}
    for s_ in GRID_SCALE:
        n = int(round(170.0 / s_)) + 1
        dummies[s_] = n
    for el, onset in ONSETS.items():
        for E0 in GRID_E0:
            for a in GRID_ALPHA:
                for b in GRID_BETA:
                    e = make_edge(el, E0, a, b, 0.25)
                    g = e.GOS
                    entry = {"element": el, "subshell": "K1", "onsetEV": onset, "E0": E0, "alpha": a, "beta": b,
                             "effectiveAngleMrad": e.effective_angle.value,
                             "tabulatedEnergies": g.energy_axis, "qint": g.qint,
                             "powerLawR": e._power_law_r, "powerLawA": e._power_law_A, "byScale": []}
                    for s_ in GRID_SCALE:
                        n = dummies[s_]
                        off = onset - 10.0
                        sig = dummy_signal(off, s_, n)
                        E = sig.axes_manager.signal_axes[0].axis.copy()
                        f = e.function(E)
                        deltas = {}
                        for d in DELTAS:
                            i0, i1 = hs_slice(sig, onset, onset + d)
                            deltas[str(d)] = {"i0": i0, "i1": i1, "sigmaK": sigma_k(f, s_, i0, i1)}
                        entry["byScale"].append({"scale": s_, "offset": off, "nChannels": n, "function": f, "byDelta": deltas})
                    cases.append(entry)
    return cases


def spline_block():
    e = make_edge("C", 200.0, 10.0, 20.0, 0.25)
    g = e.GOS
    tck = e.tab_xsection
    rec = []
    orig = g.get_qaxis_and_gos

    def wrap(ienergy, qmin, qmax):
        rec.append((ienergy, qmin, qmax))
        return orig(ienergy, qmin, qmax)

    g.get_qaxis_and_gos = wrap
    e._integrate_GOS()
    g.get_qaxis_and_gos = orig
    assert np.array_equal(g.qint, make_edge("C", 200.0, 10.0, 20.0, 0.25).GOS.qint)
    return {"case": {"element": "C", "E0": 200.0, "alpha": 10.0, "beta": 20.0}, "knots": tck.t, "coefficients": tck.c,
            "degree": int(tck.k), "extrapolationR": e._power_law_r, "extrapolationA": e._power_law_A,
            "integrateq": {"order": "per tabulated energy index", "qmin": [r[1] for r in rec], "qmax": [r[2] for r in rec],
                           "energyAxisDtype": str(g.energy_axis.dtype), "gosArrayDtype": str(g.gos_array.dtype)}}


def pyeels_block():
    from pyEELSMODEL.components.CLedge.kohl_coreloss_edge import KohlLossEdge
    from pyEELSMODEL.core.spectrum import Spectrumshape
    out = []
    for scale, n in ((1.0, 600), (0.25, 2400)):
        sig = dummy_signal(150.0, scale, n)
        E = sig.axes_manager.signal_axes[0].axis.copy()
        sh = Spectrumshape(scale, 150.0, n)
        for el, onset in ONSETS.items():
            for E0, a, b in PYEELS_SETTINGS:
                e = make_edge(el, E0, a, b, scale)
                fx = e.function(E)
                with quiet():
                    k = KohlLossEdge(sh, 1.0, E0 * 1e3, a * 1e-3, b * 1e-3, el, "K1", dir_path=ARGS.gosh_dir)
                    k.gos = np.squeeze(k.gos, axis=-1)
                    fp = k.calculate_cross_section()
                for d in (50, 100, 150):
                    i0, i1 = hs_slice(sig, onset, onset + d)
                    sx, sp = sigma_k(fx, scale, i0, i1), sigma_k(fp, scale, i0, i1)
                    out.append({"element": el, "E0": E0, "alpha": a, "beta": b, "scale": scale, "nChannels": n, "delta": d,
                                "i0": i0, "i1": i1, "sigmaExSpy": sx, "sigmaPyEELSMODEL": sp, "ratio": sp / sx})
    return {"pyEELSMODELCommit": PYEELS_COMMIT, "axisOffset": 150.0, "axisEndEV": 750.0,
            "shapeFix": "k.gos = np.squeeze(k.gos, axis=-1) (loader keeps (192, 97, 1); NumPy 2.5 refuses its scalar assignment)",
            "cases": out}


def dirac_block():
    assert sha_file(ARGS.gos_dirac, "md5") == MD5_DIRAC
    sig = dummy_signal(150.0, 0.25, 2400)
    E = sig.axes_manager.signal_axes[0].axis.copy()
    out = []
    for E0 in GRID_E0:
        for a in GRID_ALPHA:
            for b in GRID_BETA:
                fd = make_edge("C", E0, a, b, 0.25, "dft").function(E)
                fr = make_edge("C", E0, a, b, 0.25, "dirac").function(E)
                for d in (50, 100, 150):
                    i0, i1 = hs_slice(sig, 284.0, 284.0 + d)
                    sd, sr = sigma_k(fd, 0.25, i0, i1), sigma_k(fr, 0.25, i0, i1)
                    out.append({"E0": E0, "alpha": a, "beta": b, "delta": d, "sigmaDft": sd, "sigmaDirac": sr, "ratioDiracOverDft": sr / sd})
    return {"diagnostic": True, "diracMd5": MD5_DIRAC, "cases": out}


def sigma_n_block(res, bg, I1, I2, x1, x2, x3, i0w, i1w, ik, ib, i_low, sk):
    """First-order counting-statistics sigma_n (registration section 6), per pixel, from the image's own counts:
    Var(I_k) = (I_k + I_b) + (dI_b/dI1)^2 I1 + (dI_b/dI2)^2 I2, sigma_n = |n| sqrt(Var / I_k^2 + 1 / I_low).
    dI_b/dI_j analytic through r = 2 (ln I1 - ln I2) / D, k = 1 - r, A = k I2 / (x2^k - x3^k), I_b = scale A sum_c E_c^-r."""
    D = np.log(x2) - np.log(x1)
    r = 2 * (np.log(I1) - np.log(I2)) / D
    k = 1 - r
    den = x2 ** k - x3 ** k
    A = k * I2 / den
    E = OFF_C + SC_C * np.arange(i0w, i1w)
    S = np.sum(E[None, :] ** -r[:, None], axis=1)
    dS = -np.sum(E[None, :] ** -r[:, None] * np.log(E)[None, :], axis=1)
    dr1, dr2 = 2 / (D * I1), -2 / (D * I2)
    dAdk = I2 / den - k * I2 * (x2 ** k * np.log(x2) - x3 ** k * np.log(x3)) / den ** 2
    dA1 = dAdk * (-dr1)
    dA2 = k / den + dAdk * (-dr2)
    dIb1 = SC_C * (dA1 * S + A * dS * dr1)
    dIb2 = SC_C * (dA2 * S + A * dS * dr2)
    ikv, ibv = np.asarray(ik), np.asarray(ib)
    var = (ikv + ibv) + dIb1 ** 2 * I1 + dIb2 ** 2 * I2
    n = ikv * 1e10 / (np.asarray(i_low) * sk)
    return np.abs(n) * np.sqrt(var / ikv ** 2 + 1.0 / np.asarray(i_low)), var


def planted_block(manifest, tag):
    man = json.load(open(os.path.join(ARGS.fixtures, manifest)))
    sj = json.load(open(os.path.join(ARGS.fixtures, "edge-sigma-CK.json")))
    ck = make_edge("C", **{"E0": 200.0, "alpha": 10.0, "beta": 20.0, "scale": 0.25})
    sig_core = dummy_signal(OFF_C, SC_C, N_C)
    E_core = sig_core.axes_manager.signal_axes[0].axis.copy()
    f_ck = ck.function(E_core)
    assert np.array_equal(f_ck, read_raw(os.path.join(ARGS.fixtures, "edge-sigma-CK.f64"), (N_SIG,))[:N_C])
    sig_low = dummy_signal(OFF_L, SC_L, N_L)
    w0, _ = hs_slice(sig_core, 284.0, 284.0 + 30)
    sigk = {}
    for d in DELTAS:
        i0, i1 = hs_slice(sig_core, 284.0, 284.0 + d)
        sigk[d] = (i0, i1, sigma_k(f_ck, SC_C, i0, i1))
    low_idx = {d: hs_slice(sig_low, None, float(d))[1] for d in DELTAS}
    th_idx = {t: hs_slice(sig_low, None, t)[1] for t in THETAS}
    images, worst_ar = [], 0.0
    for case in CASES:
        for kind in ("noiseless", "noisy"):
            fc, fl_ = man["files"][f"core-{tag}{case}-{kind}"], man["files"][f"low-{tag}{case}-{kind}"]
            assert sha_file(os.path.join(ARGS.fixtures, fc["file"])) == fc["sha256"]
            assert sha_file(os.path.join(ARGS.fixtures, fl_["file"])) == fl_["sha256"]
            core = read_raw(os.path.join(ARGS.fixtures, fc["file"]), fc["shape"])
            low = read_raw(os.path.join(ARGS.fixtures, fl_["file"]), fl_["shape"]).reshape(15, N_L)
            i_low = {d: [float(np.sum(low[p, :low_idx[d]])) for p in range(15)] for d in DELTAS}
            i0 = {t: [float(np.sum(low[p, :th_idx[t]])) for p in range(15)] for t in THETAS}
            wins = {}
            for wname, (da, db) in WINDOWS.items():
                ea, eb = 284.0 + da, 284.0 + db
                s = hs.signals.Signal1D(core.copy())
                ax = s.axes_manager.signal_axes[0]
                ax.offset, ax.scale, ax.units, ax.is_binned = OFF_C, SC_C, "eV", True
                with quiet():
                    result, model = s.remove_background(signal_range=(ea, eb), background_type="Power law", fast=True,
                                                        return_model=True, show_progressbar=False)
                    bg = model.as_signal(out_of_range_to_nan=False, show_progressbar=False).data.reshape(15, N_C)
                    comp = model[0]
                    A_hs = np.asarray(comp.A.map["values"]).reshape(15)
                    r_hs = np.asarray(comp.r.map["values"]).reshape(15)
                res = result.data.reshape(15, N_C)
                # the estimate's own pieces, by the same lines as power_law.py:116-158
                i1, i2 = ax.value_range_to_indices(ea, eb)
                if not (i2 + i1) % 2 == 0:
                    i2 -= 1
                if i2 == i1:
                    i2 += 2
                i3 = (i2 + i1) // 2
                x1, x2, x3 = ax.index2value(i1), ax.index2value(i2), ax.index2value(i3)
                with quiet():
                    I1 = s.isig[i1:i3].integrate1D(2j).data.reshape(15)
                    I2 = s.isig[i3:i2].integrate1D(2j).data.reshape(15)
                r_chk = 2 * (np.log(I1) - np.log(I2)) / (np.log(x2) - np.log(x1))
                A_chk = (1 - r_chk) * I2 / (x2 ** (1 - r_chk) - x3 ** (1 - r_chk))
                worst_ar = max(worst_ar, float(np.max(np.abs(r_chk / r_hs - 1))), float(np.max(np.abs(A_chk / A_hs - 1))))
                by_delta = {}
                for d in DELTAS:
                    i0w, i1w, sk = sigk[d]
                    ik = [float(np.sum(res[p, i0w:i1w])) for p in range(15)]
                    ib = [float(np.sum(bg[p, i0w:i1w])) for p in range(15)]
                    sn, var = sigma_n_block(res, bg, I1, I2, x1, x2, x3, i0w, i1w, ik, ib, i_low[d], sk)
                    ent = {"i0": i0w, "i1": i1w, "sigmaK": sk, "iK": ik, "iB": ib, "iLow": i_low[d],
                           "varIk": var, "sigmaN": sn,
                           "n": [ik[p] * 1e10 / (i_low[d][p] * sk) for p in range(15)], "i0Route": {}}
                    for t in THETAS:
                        ent["i0Route"][repr(t)] = {"i0": i0[t], "n": [ik[p] * 1e10 / (i0[t][p] * sk) for p in range(15)]}
                    by_delta[str(d)] = ent
                wins[wname] = {"valueRangeEV": [ea, eb], "i1": i1, "i2": i2, "i3": i3, "x1": x1, "x2": x2, "x3": x3,
                               "I1": I1, "I2": I2, "r": r_hs, "A": A_hs,
                               "backgroundFromChannel": w0, "backgroundNChannels": sigk[150][1] - w0,
                               "background": bg[:, w0:sigk[150][1]], "byDelta": by_delta}
            images.append({"case": case, "kind": kind, "coreFile": fc["file"], "coreSha256": fc["sha256"],
                           "lowFile": fl_["file"], "lowSha256": fl_["sha256"], "windows": wins})
    return {"setting": PLANTED, "effectiveAngleMrad": ck.effective_angle.value,
            "thresholdChannelsLowLoss": {repr(t): th_idx[t] for t in THETAS},
            "deltaChannelsLowLoss": {str(d): low_idx[d] for d in DELTAS},
            "worstRelativeDifferenceOwnFormulaVsHyperSpyModelArAndR": worst_ar, "images": images}


def main():
    if ARGS.sigma_only:
        os.makedirs(OUT, exist_ok=True)
        return phase_a()
    assert sha_file(ARGS.gos_dft, "md5") == MD5_DFT
    env = {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__,
           "hyperspy": hyperspy.__version__, "h5py": h5py.__version__, "exspyCommit": EXSPY_COMMIT,
           "pyEELSMODELCommit": PYEELS_COMMIT, "gosDftMd5": MD5_DFT, "gosDiracMd5": MD5_DIRAC,
           "scriptSha256": sha_file(os.path.abspath(__file__)),
           "sigmaFixtureSha256": sha_file(os.path.join(ARGS.fixtures, "edge-sigma-CK.f64")),
           "plantedManifestSha256": sha_file(os.path.join(ARGS.fixtures, "edge-planted.json")),
           "plantedRManifestSha256": sha_file(os.path.join(ARGS.fixtures, "edge-planted-R.json"))}
    obj = {"schema": "spectrokit.eels.edge-pins/1", "registration": "docs/eels-slice-2-registration.md sections 4.1-4.4",
           "environment": env,
           "units": "function(E) and qint in barn/eV, sigmaK in barn, n in atoms/nm^2 (n = I_k * 1e10 / (I_low * sigmaK))",
           "grid": grid_block(), "splineC": spline_block(), "pyEELSMODEL": pyeels_block(), "dirac": dirac_block(),
           "planted": planted_block("edge-planted.json", ""),
           "plantedR": planted_block("edge-planted-R.json", "R-")}
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, "edge-pins.json")
    h = write_json(p, obj)
    print(p, os.path.getsize(p), "bytes", h)


if __name__ == "__main__":
    sys.exit(main())
