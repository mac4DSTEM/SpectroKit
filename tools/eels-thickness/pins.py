#!/usr/bin/env python3
"""exSpy pins for SpectroKit's EELS slice 1 (registration section 4): what exSpy 7185a4d1 answers, written before the port.

Agreement with exSpy is agreement, not truth: the truth is make_planted.py and the planted-truth fixture.

Run (needs HyperSpy 2.4.0 and the pinned exSpy checkout, which is NOT installed: it is put first on sys.path and the
signal classes are built directly, because HyperSpy's loader does not know exSpy's):

    References/python/bin/python -I tools/eels-thickness/pins.py [--exspy DIR] [--fixtures DIR] [--out DIR]

Reads  planted-noiseless.f64 / planted-noisy.f64 (written by make_planted.py; run that first) from --fixtures, and exSpy's
own line scan and zero-loss twin from the exSpy checkout (exspy/tests/signals/data/EELS_{LL,ZLP}_linescan_simulated_
thickness_variation.hspy, GPL-3.0-or-later test data, copied as a fixture with attribution).
Writes into --out (default Tests/SpectroEELSTests/Fixtures/):

    exspy-linescan-ll.f64  / .json   17 spectra x 1024 channels as a 1 x 17 image, float64 little-endian, C order
    exspy-linescan-zlp.f64 / .json   its zero-loss twin
    pins.json                        everything exSpy answers, see below; floats are Python reprs (they round-trip exactly)

Per case (planted noiseless, planted noisy, exSpy's line scan) pins.json holds, per pixel in row-major order:
  estimated  : exSpy's estimated threshold (defaults window 10, tol None, window_length 5, polynomial_order 3, start 1) as
               the energy exSpy returns, the channel exSpy turns it into, I_0, I_t, t/lambda; the global tol; the
               sub-range; each pixel's minimum |derivative|;
  estimatedGradient : the same with window_length = 0 (HyperSpy's `derivative`, numpy.gradient);
  fixed      : thresholds 2.5, 4.5, 6.0 eV: channel, I_0, I_t, t/lambda;
  zeroLoss   : the zero-loss route where a zero-loss spectrum exists (the line scan only);
  absoluteThickness : for rho 2.70 g/cm3, E0 200 keV, alpha 10, beta 20 mrad: with density and lambda = 120 nm, with density
               only (lambda from Iakoubovskii), and with lambda only (no density, no angular correction), for every route;
  stepByStep : the Savitzky-Golay derivative on the cropped range for one pixel, and where the threshold falls.
And iMFP_Iakoubovskii / iMFP_angular_correction on the registered grid, the value-to-index rule with file:line and a
self-check of the rule, and a diagnostics block (not pins) comparing the routes with the planted truth.
"""
import argparse
import contextlib
import hashlib
import json
import logging
import math
import os
import subprocess
import sys
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--exspy", default=os.path.join(REPO, "References", "exspy-7185a4d1"),
                help="the pinned exSpy checkout (default: References/exspy-7185a4d1)")
ap.add_argument("--fixtures", default=os.path.join(REPO, "Tests", "SpectroEELSTests", "Fixtures"),
                help="where make_planted.py wrote the planted images")
ap.add_argument("--out", default=None, help="output directory (default: --fixtures)")
ARGS = ap.parse_args()
OUT = ARGS.out or ARGS.fixtures
EXSPY = os.path.abspath(ARGS.exspy)

sys.path.insert(0, EXSPY)                      # the checkout first: this is the oracle
logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")

import numpy as np                             # noqa: E402
import scipy                                   # noqa: E402
import scipy.signal                            # noqa: E402

with open(os.devnull, "w") as _dn, contextlib.redirect_stdout(_dn), contextlib.redirect_stderr(_dn):
    import hyperspy                            # noqa: E402
    import hyperspy.api as hs                  # noqa: E402
    import exspy                               # noqa: E402
    from exspy.signals import EELSSpectrum     # noqa: E402
    from exspy.utils.eels import iMFP_Iakoubovskii, iMFP_angular_correction  # noqa: E402
    import rsciio                              # noqa: E402

EXSPY_COMMIT = "7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e"
assert os.path.realpath(os.path.dirname(exspy.__file__)) == os.path.realpath(os.path.join(EXSPY, "exspy")), exspy.__file__


@contextlib.contextmanager
def quiet():
    with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
        yield


# ---------------------------------------------------------------- the registered inputs
FIXED_THRESHOLDS = [2.5, 4.5, 6.0]
DENSITY, E0, ALPHA, BETA, LAMBDA_NM = 2.70, 200.0, 10.0, 20.0, 120.0
GRID_RHO = [1.0, 2.7, 7.9, 19.3]
GRID_E0 = [60.0, 80.0, 120.0, 200.0, 300.0]
GRID_ALPHA = [1.0, 10.0, 30.0]
GRID_BETA = [5.0, 20.0, 100.0]
DEFAULTS = {"window": 10.0, "tol": None, "windowLength": 5, "polynomialOrder": 3, "start": 1.0}
PLANTED_TAU = [0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0, 1.3, 1.6, 2.0]
LINESCAN_LL = "exspy/tests/signals/data/EELS_LL_linescan_simulated_thickness_variation.hspy"
LINESCAN_ZLP = "exspy/tests/signals/data/EELS_ZLP_linescan_simulated_thickness_variation.hspy"


# ---------------------------------------------------------------- JSON / raw writers (repr floats, NaN -> null)
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
            raise ValueError("non-finite float in JSON (use None)")
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    raise TypeError(type(v))


def _dump(v, ind, out):
    pad = "  " * ind
    if isinstance(v, dict):
        if not v:
            out.append("{}")
            return
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
    data = ("".join(out) + "\n").encode("utf-8")
    with open(path, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest()


def write_raw(path, arr):
    data = np.ascontiguousarray(arr, dtype="<f8").tobytes()
    with open(path, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest(), len(data)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fl(a):
    """Flat list of Python floats, NaN -> None."""
    return [None if (isinstance(x, float) and math.isnan(x)) else x for x in np.asarray(a, dtype=float).reshape(-1).tolist()]


# ---------------------------------------------------------------- HyperSpy's value-to-index rule, ported and checked
def rule_value2index(v, offset, scale, size):
    """hyperspy/axes.py UniformDataAxis.value2index (lines 1315-1349 of 2.4.0), scale > 0, scalar v, default rounding."""
    q = (v - offset) / scale
    index = (1.0 / 1e12) * float(math.trunc(q * 1e12))                  # 1 / multiplier * np.trunc(q * multiplier)
    if v >= 0:                                                          # round half towards zero
        r = math.ceil(index - 0.5) if index >= 0 else math.floor(index + 0.5)
    else:                                                               # round half away from zero
        r = math.floor(index + 0.5) if index >= 0 else math.ceil(index - 0.5)
    if not (0 <= r < size):
        raise ValueError("out of the axis limits")
    return int(r)


def check_rule(axis):
    """The rule against HyperSpy itself on: every channel energy, every half-way energy, those nudged by +-1e-13 and
    +-1e-9, and 20000 values from a fixed RNG. Returns (cases, mismatches)."""
    offset, scale, size = axis.offset, axis.scale, axis.size
    ks = np.arange(size)
    base = offset + scale * ks
    half = offset + scale * (ks + 0.5)
    vals = np.concatenate([base, half, base + 1e-13, base - 1e-13, half + 1e-13, half - 1e-13, base + 1e-9, base - 1e-9,
                           half + 1e-9, half - 1e-9,
                           np.random.default_rng(1).uniform(offset, offset + scale * (size - 1), 20000)])
    n = bad = 0
    for v in vals.tolist():
        try:
            want = ("ok", axis.value2index(v))
        except ValueError:
            want = ("err", None)
        try:
            got = ("ok", rule_value2index(v, offset, scale, size))
        except ValueError:
            got = ("err", None)
        n += 1
        bad += want != got
    return n, bad



# ---------------------------------------------------------------- the arithmetic behind the derivatives, as recipes the port can follow
SG_FMA_ORDER = (0, 4, 3, 2, 1)       # found by search on this machine, verified on every interior value (see check)


def sg_interior_recipe(cropped, coeffs):
    """scipy.signal.savgol_filter (window 5) interior values rebuilt: out[i] = fma chain over the convolution taps,
    acc = 0; for j in (0, 4, 3, 2, 1): acc = fma(f[i + 2 - j], coeffs[j], acc). Edges (2 each side) are a polynomial fit
    (numpy polyfit, i.e. LAPACK least squares) and are not rebuilt."""
    n = cropped.shape[1]
    out = np.full(cropped.shape, np.nan)
    for r in range(cropped.shape[0]):
        row = cropped[r]
        for i in range(2, n - 2):
            acc = 0.0
            for j in SG_FMA_ORDER:
                acc = math.fma(float(row[i + 2 - j]), coeffs[j], acc)
            out[r, i] = acc
    return out


def gradient_recipe(cropped, x):
    """numpy.gradient(f, x, edge_order=1) rebuilt in plain IEEE double arithmetic (numpy/lib/_function_base_impl.py:1265-1357):
    dx = diff(x); if all dx are equal the spacing is a scalar: interior (f[i+1] - f[i-1]) / (2 * dx), else with dx1 = dx[i-1],
    dx2 = dx[i]:  a = -dx2 / (dx1 * (dx1 + dx2)),  b = (dx2 - dx1) / (dx1 * dx2),  c = dx1 / (dx2 * (dx1 + dx2)),
    out[i] = a * f[i-1] + b * f[i] + c * f[i+1]  (left to right, no fused multiply-add);
    edges: (f[1] - f[0]) / dx[0] and (f[-1] - f[-2]) / dx[-1]."""
    xs = [float(v) for v in x]
    dx = [xs[i + 1] - xs[i] for i in range(len(xs) - 1)]
    uniform = all(d == dx[0] for d in dx)
    n = cropped.shape[1]
    out = np.zeros(cropped.shape)
    for r in range(cropped.shape[0]):
        f = [float(v) for v in cropped[r]]
        out[r, 0] = (f[1] - f[0]) / dx[0]
        out[r, n - 1] = (f[n - 1] - f[n - 2]) / dx[-1]
        for i in range(1, n - 1):
            if uniform:
                out[r, i] = (f[i + 1] - f[i - 1]) / (2.0 * dx[0])
            else:
                dx1, dx2 = dx[i - 1], dx[i]
                a = -dx2 / (dx1 * (dx1 + dx2))
                b = (dx2 - dx1) / (dx1 * dx2)
                c = dx1 / (dx2 * (dx1 + dx2))
                out[r, i] = a * f[i - 1] + b * f[i] + c * f[i + 1]
    return out, uniform


# ---------------------------------------------------------------- building signals
def build_signal(data, rows, cols, offset, scale, size, units, binned, name="Energy loss"):
    data = np.asarray(data, dtype=np.float64)
    if rows == 1:                                                       # a line scan: one navigation axis
        shape = (cols, size)
        axes = [dict(size=cols, navigate=True, name="x"),
                dict(size=size, offset=offset, scale=scale, units=units, name=name, navigate=False, is_binned=binned)]
    else:
        shape = (rows, cols, size)
        axes = [dict(size=rows, navigate=True, name="y"), dict(size=cols, navigate=True, name="x"),
                dict(size=size, offset=offset, scale=scale, units=units, name=name, navigate=False, is_binned=binned)]
    with quiet():
        return EELSSpectrum(data.reshape(shape).copy(), axes=axes)


def hspy_to_exspy(path):
    with quiet():
        sig = hs.load(path)
        return EELSSpectrum(sig.data, axes=sig.axes_manager._get_axes_dicts(), metadata=sig.metadata.as_dictionary())


def set_microscope(s):
    with quiet():
        s.set_microscope_parameters(beam_energy=E0, convergence_angle=ALPHA, collection_angle=BETA)


# ---------------------------------------------------------------- one route's numbers
def sums(s, threshold=None, zlp=None):
    """exSpy's own I_0, I_t, t/lambda for a threshold signal, a number, or a zero-loss spectrum."""
    ax = s.axes_manager.signal_axes[0]
    with quiet():
        it = s.integrate1D(ax.index_in_array).data
        if zlp is not None:
            i0 = zlp.integrate1D(ax.index_in_array).data
            tl = s.estimate_thickness(zlp=zlp).data
        else:
            i0 = s.estimate_elastic_scattering_intensity(threshold=threshold).data
            tl = s.estimate_thickness(threshold=threshold).data
    return np.asarray(i0, dtype=float), np.asarray(it, dtype=float), np.asarray(tl, dtype=float)


def absolute(s, threshold=None, zlp=None):
    out = {}
    kw = dict(zlp=zlp) if zlp is not None else dict(threshold=threshold)
    with quiet():
        out["tOverLambda"] = np.asarray(s.estimate_thickness(**kw).data, dtype=float)
        out["thicknessNMDensityAndLambda"] = np.asarray(
            s.estimate_thickness(density=DENSITY, mean_free_path=LAMBDA_NM, **kw).data, dtype=float)
        out["thicknessNMDensityOnly"] = np.asarray(s.estimate_thickness(density=DENSITY, **kw).data, dtype=float)
        out["thicknessNMLambdaOnly"] = np.asarray(s.estimate_thickness(mean_free_path=LAMBDA_NM, **kw).data, dtype=float)
    return out


def estimated_block(s, window_length, nav_shape, extra_pixels):
    """exSpy's estimated threshold with window_length (5: Savitzky-Golay, 0: HyperSpy's derivative)."""
    ax = s.axes_manager.signal_axes[0]
    with quiet():
        thr = s.estimate_elastic_scattering_threshold(window_length=window_length)
    tv = np.asarray(thr.data, dtype=float)
    i0, it, tl = sums(s, threshold=thr)
    assert np.array_equal(tl, np.log(it / i0), equal_nan=True)
    min_index, max_index = ax.value_range_to_indices(DEFAULTS["start"], DEFAULTS["start"] + DEFAULTS["window"])
    chan = [None if math.isnan(v) else ax.value2index(v) for v in tv.reshape(-1).tolist()]
    data = s.data.reshape(-1, ax.size)

    # my own recomputation of the same steps, which must reproduce exSpy bit for bit
    cropped = data[:, min_index:max_index]
    delta = ax.scale
    if window_length:
        der = scipy.signal.savgol_filter(cropped, window_length, DEFAULTS["polynomialOrder"], deriv=1, delta=delta, axis=-1)
        with quiet():
            c = s.isig[min_index:max_index].deepcopy()
            c.smooth_savitzky_golay(polynomial_order=DEFAULTS["polynomialOrder"], window_length=window_length,
                                    differential_order=1)
        assert np.array_equal(c.data.reshape(-1, max_index - min_index), der)
    else:
        with quiet():
            c = s.isig[min_index:max_index].deepcopy().derivative(-1)
        der = c.data.reshape(-1, max_index - min_index)
    sub_axis = c.axes_manager.signal_axes[0].axis
    # the cropped axis is offset_c + scale * arange(n), offset_c = (offset + scale * arange(size))[min_index]
    offset_c = float((ax.offset + ax.scale * np.arange(ax.size))[min_index])
    assert all(sub_axis[i] == offset_c + ax.scale * i for i in range(len(sub_axis)))
    if window_length:
        coeffs = scipy.signal.savgol_coeffs(window_length, DEFAULTS["polynomialOrder"], deriv=1, delta=delta).tolist()
        rebuilt = sg_interior_recipe(cropped, coeffs) if window_length == 5 else None
        n_c = cropped.shape[1]
        interior = der[:, 2:n_c - 2]
        mism = int(np.sum(rebuilt[:, 2:n_c - 2] != interior)) if rebuilt is not None else None
        recipe = {"coefficients": coeffs, "fmaOrder": list(SG_FMA_ORDER),
                  "interiorValuesChecked": int(interior.size), "interiorMismatches": mism}
    else:
        rebuilt, uniform = gradient_recipe(cropped, sub_axis)
        assert np.array_equal(rebuilt, der), "numpy.gradient recipe does not reproduce HyperSpy's derivative"
        recipe = {"uniformSpacingBranch": uniform, "valuesChecked": int(der.size), "mismatches": 0}
    mins = np.abs(der).min(axis=1)
    tol = float(np.max(mins))
    infl = (np.abs(der) <= tol).argmax(axis=1)
    for p in range(data.shape[0]):
        if infl[p] == 0:
            assert math.isnan(tv.reshape(-1)[p])
        else:
            assert tv.reshape(-1)[p] == sub_axis[infl[p]], (p, tv.reshape(-1)[p], sub_axis[infl[p]])
            assert chan[p] == min_index + infl[p], (p, chan[p], min_index + infl[p])
            # I_0 is the sum of channels [0, chan)
            assert i0.reshape(-1)[p] == data[p, :chan[p]].sum()
    assert np.array_equal(it.reshape(-1), data.sum(axis=1))
    # how far each pixel's pinned channel is from flipping: the channel is the first one with |d| <= tol, so it flips if an
    # earlier |d| comes down to tol or the chosen |d| goes above it; tol itself is the largest per-pixel minimum.
    absder = np.abs(der)
    eps = 1e-12 * float(np.max(absder))
    define = int(np.argmax(mins))
    order = np.sort(mins)[::-1]
    tie = bool(len(order) > 1 and (order[0] - order[1]) <= 2 * eps)
    margin_at, margin_before, sensitive = [], [], set()
    for p in range(data.shape[0]):
        if infl[p] == 0:
            margin_at.append(None)
            margin_before.append(None)
            continue
        at = None if p == define else float(tol - absder[p, infl[p]])
        before = float(absder[p, :infl[p]].min() - tol)
        margin_at.append(at)
        margin_before.append(before)
        if (at is not None and at <= 2 * eps) or before <= 2 * eps:
            sensitive.add(p)
    if tie:
        sensitive.update(int(i) for i in np.argsort(-mins, kind="stable")[:2])
    stability = {
        "meaning": "absolute margins in derivative units (counts/eV): marginAtThreshold = tol - |d| at the pinned channel "
                   "(null for the pixel that defines tol, whose |d| equals tol exactly); marginBeforeThreshold = smallest |d| "
                   "before the pinned channel minus tol. A pixel is sensitive when a margin is within 2 * epsilonAbs "
                   "(epsilonAbs = 1e-12 * the largest |d| of the image, a rounding-level perturbation), or when the "
                   "two largest per-pixel minima are within 2 * epsilonAbs (tolTie) so that which one defines tol is "
                   "decided by rounding. For a sensitive pixel the pinned channel is decided by rounding of the "
                   "derivative: a port can differ from it without being wrong.",
        "epsilonAbs": eps, "definesTolPixel": define, "tolTie": tie,
        "marginAtThreshold": margin_at, "marginBeforeThreshold": margin_before,
        "sensitivePixels": sorted(sensitive),
    }
    block = {
        "windowLength": window_length,
        "derivative": "scipy.signal.savgol_filter(window_length, polynomial_order=3, deriv=1, delta=axis.scale, mode='interp') "
                      "on the cropped range" if window_length else
                      "numpy.gradient(cropped, cropped_axis_values) on the cropped range (HyperSpy BaseSignal.derivative)",
        "subRange": {"startValueEV": DEFAULTS["start"], "endValueEV": DEFAULTS["start"] + DEFAULTS["window"],
                     "firstChannel": min_index, "endChannelExclusive": max_index, "channels": max_index - min_index,
                     "energyOfFirstChannelEV": float(sub_axis[0]), "energyOfLastChannelEV": float(sub_axis[-1])},
        "croppedAxis": {"offset": offset_c, "scale": float(ax.scale), "rule": "energy_i = offset + scale * i, i = 0..channels-1"},
        "recipe": recipe,
        "tol": tol,
        "stability": stability,
        "minAbsDerivative": fl(mins),
        "inflexionIndex": [int(i) for i in infl],
        "thresholdEV": fl(tv),
        "thresholdChannel": chan,
        "i0": fl(i0), "it": fl(it), "tOverLambda": fl(tl),
    }
    steps = []
    for (r, c_) in extra_pixels:
        p = r * nav_shape[1] + c_
        entry = {"pixel": {"row": r, "col": c_, "index": p},
                 "firstChannel": min_index, "channels": max_index - min_index,
                 "energyEV": [float(x) for x in sub_axis],
                 "derivative": [float(x) for x in der[p]],
                 "minAbsDerivative": float(mins[p]),
                 "channelOfMinimum": int(min_index + np.abs(der[p]).argmin()),
                 "tolGlobal": tol,
                 "firstSubRangeIndexAtOrBelowTol": int(infl[p]),
                 "thresholdEV": None if math.isnan(tv.reshape(-1)[p]) else float(tv.reshape(-1)[p]),
                 "thresholdChannel": chan[p]}
        steps.append(entry)
    return block, steps, thr, (i0, it, tl)


def analyse(name, file, s, rows, cols, zlp, extra_pixels, truth_tau):
    ax = s.axes_manager.signal_axes[0]
    assert ax.is_binned and ax.is_uniform
    nav_shape = (rows, cols)
    case = {
        "name": name, "file": file,
        "rows": rows, "cols": cols, "pixelOrder": "row-major (pixel index = row * cols + col)",
        "energyAxis": {"offset": float(ax.offset), "scale": float(ax.scale), "size": int(ax.size), "units": str(ax.units),
                       "binned": bool(ax.is_binned)},
    }
    if truth_tau is not None:
        case["truthTOverLambda"] = [float(x) for x in truth_tau]
    est, steps, thr, est_nums = estimated_block(s, DEFAULTS["windowLength"], nav_shape, extra_pixels)
    case["estimated"] = est
    grad, steps_grad, thr_g, _ = estimated_block(s, 0, nav_shape, extra_pixels)
    case["estimatedGradient"] = grad
    for st, sg in zip(steps, steps_grad):
        st["gradientDerivative"] = sg["derivative"]
        st["gradientMinAbsDerivative"] = sg["minAbsDerivative"]
        st["gradientTolGlobal"] = sg["tolGlobal"]
        st["gradientFirstSubRangeIndexAtOrBelowTol"] = sg["firstSubRangeIndexAtOrBelowTol"]
        st["gradientThresholdEV"] = sg["thresholdEV"]
        st["gradientThresholdChannel"] = sg["thresholdChannel"]
    case["stepByStep"] = steps

    fixed = []
    fixed_nums = {}
    data = s.data.reshape(-1, ax.size)
    for th in FIXED_THRESHOLDS:
        i0, it, tl = sums(s, threshold=th)
        ch = ax.value2index(th)
        assert ch == rule_value2index(th, ax.offset, ax.scale, ax.size)
        assert np.array_equal(i0.reshape(-1), np.array([data[p, :ch].sum() for p in range(data.shape[0])]))
        fixed.append({"thetaEV": th, "channel": ch, "i0": fl(i0), "it": fl(it), "tOverLambda": fl(tl)})
        fixed_nums[th] = (i0, it, tl)
    case["fixed"] = fixed

    z_nums = None
    case["zeroLoss"] = None
    if zlp is not None:
        zax = zlp.axes_manager.signal_axes[0]
        assert zax.is_binned and zax.size == ax.size and zax.offset == ax.offset and zax.scale == ax.scale
        i0, it, tl = sums(s, zlp=zlp)
        case["zeroLoss"] = {"file": "exspy-linescan-zlp.f64", "i0": fl(i0), "it": fl(it), "tOverLambda": fl(tl)}
        z_nums = (i0, it, tl)

    # absolute thickness
    md = s.metadata.Acquisition_instrument.TEM
    lam = float(iMFP_Iakoubovskii(density=DENSITY, electron_energy=float(md.beam_energy)))
    corr = float(iMFP_angular_correction(density=DENSITY, beam_energy=float(md.beam_energy),
                                         alpha=float(md.convergence_angle), beta=float(md.Detector.EELS.collection_angle)))
    routes = []

    def add(route, theta, **kw):
        a = absolute(s, **kw)
        # my reading of the arithmetic: (t/lambda * correction) * lambda, in this order
        tl = a["tOverLambda"]
        assert np.allclose(a["thicknessNMDensityOnly"], (tl * corr) * lam, rtol=1e-14, atol=0, equal_nan=True)
        assert np.allclose(a["thicknessNMDensityAndLambda"], (tl * corr) * LAMBDA_NM, rtol=1e-14, atol=0, equal_nan=True)
        assert np.array_equal(a["thicknessNMLambdaOnly"], tl * LAMBDA_NM, equal_nan=True)
        routes.append({"route": route, "thetaEV": theta, **{k: fl(v) for k, v in a.items()}})

    add("estimated", None, threshold=thr)
    for th in FIXED_THRESHOLDS:
        add("fixed", th, threshold=th)
    if zlp is not None:
        add("zeroLoss", None, zlp=zlp)
    case["absoluteThickness"] = {
        "densityGPerCm3": DENSITY, "beamEnergyKeV": float(md.beam_energy), "convergenceAngleMrad": float(md.convergence_angle),
        "collectionAngleMrad": float(md.Detector.EELS.collection_angle), "lambdaGivenNM": LAMBDA_NM,
        "lambdaIakoubovskiiNM": lam, "angularCorrection": corr,
        "arithmetic": "with a density: t/lambda * correction, then * lambda (given, else Iakoubovskii); with lambda only: "
                      "t/lambda * lambda, no correction (exspy/signals/_eels.py:827-851)",
        "routes": routes,
    }
    nums = {"estimated": est_nums, **{f"fixed{th}": fixed_nums[th] for th in FIXED_THRESHOLDS}}
    if z_nums:
        nums["zeroLoss"] = z_nums
    return case, nums


def imfp_tables():
    iak = {"columns": ["densityGPerCm3", "electronEnergyKeV", "lambdaNM"], "rows": []}
    for rho in GRID_RHO:
        for e in GRID_E0:
            iak["rows"].append([rho, e, float(iMFP_Iakoubovskii(density=rho, electron_energy=e))])
    ang = {"columns": ["densityGPerCm3", "beamEnergyKeV", "alphaMrad", "betaMrad", "correction"], "rows": []}
    for rho in GRID_RHO:
        for e in GRID_E0:
            for a in GRID_ALPHA:
                for b in GRID_BETA:
                    ang["rows"].append([rho, e, a, b, float(iMFP_angular_correction(density=rho, beam_energy=e, alpha=a, beta=b))])
    return {"order": "rho outermost, then E0, alpha, beta innermost",
            "grid": {"densityGPerCm3": GRID_RHO, "energyKeV": GRID_E0, "alphaMrad": GRID_ALPHA, "betaMrad": GRID_BETA},
            "iakoubovskii": iak, "angularCorrection": ang}


# ---------------------------------------------------------------- main
def main():
    os.makedirs(OUT, exist_ok=True)

    # the planted images (verify the files against their headers)
    planted = {}
    for name in ("planted-noiseless", "planted-noisy"):
        raw = os.path.join(ARGS.fixtures, name + ".f64")
        hdr = json.load(open(os.path.join(ARGS.fixtures, name + ".json")))
        digest = sha256_file(raw)
        assert digest == hdr["sha256"], (name, digest, hdr["sha256"])
        a = hdr["energyAxis"]
        data = np.fromfile(raw, dtype="<f8").reshape(hdr["shape"])
        s = build_signal(data, hdr["shape"][0], hdr["shape"][1], a["offset"], a["scale"], a["size"], a["units"], a["binned"])
        set_microscope(s)
        planted[name] = (s, hdr, digest)

    # exSpy's line scan and its zero-loss twin
    ll_path, zlp_path = os.path.join(EXSPY, LINESCAN_LL), os.path.join(EXSPY, LINESCAN_ZLP)
    ll, zl = hspy_to_exspy(ll_path), hspy_to_exspy(zlp_path)
    lax = ll.axes_manager.signal_axes[0]
    assert ll.data.shape == (17, 1024) and zl.data.shape == (17, 1024) and ll.data.dtype == np.float64
    assert lax.is_binned and lax.offset == -100.0 and lax.scale == 0.5
    truth_ls = np.arange(0.3, 2, 0.1)
    commit_ok = False
    try:
        head = subprocess.run(["git", "-C", EXSPY, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        commit_ok = head == EXSPY_COMMIT
    except Exception:
        head = None
    licence = ("exSpy test data, GPL-3.0-or-later (exSpy's LICENSE is the GPL v3; its source headers grant version 3 or "
               "any later version). Copyright 2007-2026 The eXSpy developers. Copied unchanged (only re-encoded as raw "
               "float64) as a test fixture of SpectroKit (GPL-3.0), with attribution; the .hspy carries no header of its own.")
    micro_ls = {"beamEnergyKeV": 200.0, "convergenceAngleMrad": 10.0, "collectionAngleMrad": 20.0,
                "source": "Acquisition_instrument.TEM metadata of the exSpy file"}
    ls_files = {}
    for tag, sig, path, rel, fname in (("ll", ll, ll_path, LINESCAN_LL, "exspy-linescan-ll"),
                                       ("zlp", zl, zlp_path, LINESCAN_ZLP, "exspy-linescan-zlp")):
        digest, nbytes = write_raw(os.path.join(OUT, fname + ".f64"), sig.data)
        write_json(os.path.join(OUT, fname + ".json"), {
            "schema": "spectrokit.eels.raw-f64/1", "file": fname + ".f64", "shape": [1, 17, 1024], "dtype": "float64",
            "byteOrder": "little", "order": "C: rows, cols, channels (one row; the 17 spectra of the line scan are the columns)",
            "energyAxis": {"offset": float(lax.offset), "scale": float(lax.scale), "size": int(lax.size),
                           "units": str(lax.units), "binned": bool(lax.is_binned)},
            "microscope": micro_ls, "bytes": nbytes, "sha256": digest,
            "truthTOverLambda": {"expression": "numpy.arange(0.3, 2, 0.1) (as exSpy's tests write it)",
                                 "values": [float(x) for x in truth_ls]},
            "provenance": {"sourceFile": rel, "sourceBytes": os.path.getsize(path), "sourceSha256": sha256_file(path),
                           "sourceTitle": str(sig.metadata.General.title),
                           "exspyCommit": EXSPY_COMMIT, "licence": licence,
                           "reencoding": "HyperSpy 2.4.0 hs.load(...).data (float64, C order, no change of values)"},
        })
        ls_files[tag] = (digest, nbytes)

    pairs = [("planted-noiseless", planted["planted-noiseless"][0], "planted-noiseless.f64", 2, 5, None, [(1, 1)], PLANTED_TAU),
             ("planted-noisy", planted["planted-noisy"][0], "planted-noisy.f64", 2, 5, None, [(1, 1)], PLANTED_TAU),
             ("exspy-linescan", ll, "exspy-linescan-ll.f64", 1, 17, zl, [(0, 8)], truth_ls)]
    cases, nums = [], {}
    for name, s, file, rows, cols, z, extra, truth in pairs:
        case, nn = analyse(name, file, s, rows, cols, z, extra, truth)
        digest = planted[name][2] if name in planted else ls_files["ll"][0]
        case["sha256"] = digest
        if name == "exspy-linescan":
            case["zeroLoss"]["sha256"] = ls_files["zlp"][0]
        cases.append(case)
        nums[name] = nn

    # diagnostics (not pins): the routes against the planted truth and the registered gates 2 and 3
    truth_json = json.load(open(os.path.join(ARGS.fixtures, "planted-truth.json")))
    diag = {"note": "not pins: how exSpy's routes compare with the planted truth, to see what the gates will be asked to hold"}
    pred = {}
    for px in truth_json["pixels"]:
        for c in px["components"]:
            pred[(px["row"] * 5 + px["col"], c["theta"])] = c["bias"]
    tau = np.array(PLANTED_TAU)
    clean, noisy = nums["planted-noiseless"], nums["planted-noisy"]
    d_clean, d_noisy, g3 = {}, {}, {}
    for route in clean:
        tl = clean[route][2].reshape(-1)
        d_clean[route] = {"errorVsTau": fl(tl - tau), "maxAbsErrorVsTau": float(np.max(np.abs(tl - tau)))}
        if route.startswith("fixed"):
            th = float(route[5:])
            p = np.array([pred[(i, th)] for i in range(10)])
            d_clean[route]["maxAbsDifferenceFromPredictedBias"] = float(np.max(np.abs((tl - tau) - p)))
        tn = noisy[route][2].reshape(-1)
        i0n, itn = noisy[route][0].reshape(-1), noisy[route][1].reshape(-1)
        sigma = np.sqrt(1.0 / i0n - 1.0 / itn)
        ratio = np.abs(tn - tl) / sigma
        d_noisy[route] = {"errorVsTau": fl(tn - tau), "maxAbsErrorVsTau": float(np.max(np.abs(tn - tau)))}
        g3[route] = {"sigmaCountingNoisyPixel": fl(sigma), "absNoisyMinusNoiselessOverSigma": fl(ratio),
                     "max": float(np.max(ratio)), "pixelsAbove4Sigma": [int(i) for i in np.flatnonzero(ratio > 4)]}
    diag["planted"] = {"noiseless": d_clean, "noisy": d_noisy, "gate3Preview": g3}
    ls = nums["exspy-linescan"]
    diag["linescan"] = {r: {"maxAbsErrorVsTruth": float(np.max(np.abs(ls[r][2].reshape(-1) - truth_ls)))} for r in ls}

    # the rule, checked
    rule_cases = {}
    for label, axis in (("planted axis (-10 eV, 0.05, 3400)", planted["planted-noiseless"][0].axes_manager.signal_axes[0]),
                        ("line scan axis (-100 eV, 0.5, 1024)", lax)):
        n, bad = check_rule(axis)
        rule_cases[label] = {"values": n, "mismatches": bad}
        assert bad == 0, (label, bad)

    pins = {
        "schema": "spectrokit.eels.pins/1",
        "generator": "tools/eels-thickness/pins.py",
        "notTruth": "These are exSpy's answers. Agreement with exSpy is agreement, not truth (CLAUDE.md); "
                    "the truth is planted-truth.json. A difference from a pin is a failure of the port, never a tolerance to widen.",
        "reference": {"exspyCommit": EXSPY_COMMIT, "exspyCheckoutHeadVerified": commit_ok,
                      "hyperspy": hyperspy.__version__, "rsciio": rsciio.__version__, "numpy": np.__version__,
                      "scipy": scipy.__version__, "python": sys.version.split()[0],
                      "exspyClassesBuiltDirectly": "exspy.signals.EELSSpectrum(sig.data, axes=sig.axes_manager._get_axes_dicts(), "
                                                   "metadata=sig.metadata.as_dictionary())"},
        "agreementRequired": {"thresholdChannel": "equal for every pixel", "i0AndItRelative": 1e-12, "tOverLambdaAbsolute": 1e-12,
                              "lambdaAndAngularCorrectionRelative": 1e-13},
        "parameters": {"defaults": DEFAULTS, "fixedThresholdsEV": FIXED_THRESHOLDS, "densityGPerCm3": DENSITY,
                       "beamEnergyKeV": E0, "convergenceAngleMrad": ALPHA, "collectionAngleMrad": BETA,
                       "lambdaGivenNM": LAMBDA_NM,
                       "microscopeOnPlantedImages": "set with set_microscope_parameters(beam_energy=200, convergence_angle=10, "
                                                    "collection_angle=20); the line scan carries these in its file"},
        "rules": rules_block(rule_cases),
        "cases": cases,
        "iMFP": imfp_tables(),
        "diagnostics": diag,
    }
    h = write_json(os.path.join(OUT, "pins.json"), pins)
    print("pins.json", h)
    for c in cases:
        e = c["estimated"]
        print(c["name"], "tol", e["tol"], "thresholdChannel", e["thresholdChannel"])


def rules_block(rule_cases):
    H = "hyperspy 2.4.0 (../References/python/hyperspy/lib/python3.14/site-packages/hyperspy)"
    return {
        "valueToIndex": {
            "where": f"{H}/axes.py:1283-1349, UniformDataAxis.value2index(value, rounding=round), the default rounding; "
                     "helpers hyperspy/misc/_array_tools.py:457 (round_half_towards_zero) and :535 (round_half_away_from_zero), "
                     "reached through hyperspy/misc/array_tools.py:42",
            "rule": "q = (value - offset) / scale; index = (1/1e12) * trunc(q * 1e12)  [axes.py:1315-1318: 1 / multiplier * "
                    "np.trunc(q * multiplier), a MULTIPLY by 1e-12, not a division]; if value >= 0 (positive scale, "
                    "axes.py:1323-1327): round half TOWARDS zero, i.e. ceil(index - 0.5) for index >= 0 (a half goes DOWN: "
                    "289.5 -> 289); otherwise (value < 0): round half AWAY from zero, floor(index + 0.5) (a half goes UP). "
                    "The sign test is on the ENERGY value, not on the index. Result outside 0 <= index < size raises "
                    "ValueError (axes.py:1344-1349). The truncation to 12 decimals makes a value within 1e-12 channels of "
                    "a half-way point count as exactly half-way.",
            "selfCheck": {"ported": "tools/eels-thickness/pins.py rule_value2index (pure Python)",
                          "against": "HyperSpy's own value2index on every channel energy, every half-way energy, those nudged by "
                                     "+-1e-13 and +-1e-9, and 20000 RNG values",
                          "axes": rule_cases},
        },
        "valueRangeToIndices": {
            "where": f"{H}/axes.py:648-691, called at exspy/signals/_eels.py:712",
            "rule": "i1 = value2index(v1) only if low_value < v1 <= high_value, else 0; i2 = value2index(v2) only if "
                    "high_value > v2 >= low_value, else size - 1 (axes.py:667, 676-679). The threshold search then crops "
                    "isig[i1:i2] with INTEGERS (end exclusive): channels [i1, i2). With the defaults start 1.0, window 10.0: "
                    "[value2index(1.0), value2index(11.0)). If v2 is at or above the last channel's energy the crop ends at "
                    "size - 1, so the last channel is NOT in it. i2 < i1 + 10 raises ValueError (_eels.py:713-714).",
        },
        "isigFloatSlice": {
            "where": f"{H}/axes.py:401-471 (BaseDataAxis._get_array_slices), stop at :453-466; used by "
                     "exspy/signals/_eels.py:598 (self.isig[:threshold].integrate1D(-1)) for a number threshold",
            "rule": "isig[:theta] has stop = value2index(theta) (the rule above), end EXCLUSIVE, so I_0 is the sum of channels "
                    "[0, value2index(theta)); the channel nearest theta is not in it. If value2index raises (theta above the "
                    "last energy) the slice runs to the end (stop = None, axes.py:462-466) and I_0 = I_t; theta below the "
                    "first energy raises IndexError (axes.py:457-461). theta exactly at the last channel's energy gives "
                    "stop = size - 1.",
        },
        "perPixelZeroLossSum": {
            "where": "exspy/signals/_eels.py:608-621",
            "rule": "NaN threshold gives NaN. Otherwise ind = axis.value2index(threshold) (the same rule; out-of-range RAISES "
                    "here, it is not caught) and I_0 = data[:ind].sum() when the axis is binned (numpy pairwise sum of the "
                    "float64 channels [0, ind)); Simpson's rule when not binned (not ported).",
        },
        "totalIntensity": {
            "where": "exspy/signals/_eels.py:805; hyperspy/signal.py:5092-5132 (integrate1D)",
            "rule": "I_t = sum over ALL channels (axis binned); Simpson when unbinned (not ported). With a zero-loss spectrum "
                    "I_0 = zlp.integrate1D, the sum of that spectrum (_eels.py:808-809).",
        },
        "savitzkyGolay": {
            "where": f"exspy/signals/_eels.py:717-722; {H}/_signals/signal1d.py:933-941 (smooth_savitzky_golay)",
            "rule": "scipy.signal.savgol_filter(row, window_length=5, polyorder=3, deriv=1, delta=axis.scale) with SciPy's "
                    "default mode='interp' and axis=-1, applied to the CROPPED rows. The edges are polynomial fits of the "
                    "first/last window_length points.",
        },
        "gradientDerivative": {
            "where": f"exspy/signals/_eels.py:723-724 (window_length 0: s = s.derivative(-1)); {H}/signal.py:4846-4853",
            "rule": "numpy.gradient(cropped_rows, cropped_axis_values, axis=-1), edge_order=1; the x array is the cropped "
                    "axis array offset_c + scale * arange(n) with offset_c = axis[min_index], so the spacings differ from "
                    "scale by a few ulps (numpy's non-uniform formula).",
        },
        "tolAndThreshold": {
            "where": "exspy/signals/_eels.py:725-736",
            "rule": "tol = max over pixels of (min over the cropped channels of |derivative|), ONE number for the image (a "
                    "pixel's threshold depends on every other pixel's data); inflexion = argmax(|derivative| <= tol) per "
                    "pixel (the FIRST such channel); threshold = cropped_axis_values[inflexion] (offset_c + scale * inflexion, "
                    "so it can differ from the full axis value by an ulp); inflexion == 0 gives NaN. The channel exSpy then "
                    "uses is value2index(threshold) = min_index + inflexion, asserted for every pixel here.",
        },
        "ratioAndThickness": {
            "where": "exspy/signals/_eels.py:817-851",
            "rule": "t/lambda = log(I_t / I_0). With a density: t/lambda *= iMFP_angular_correction(beam_energy, alpha, beta, "
                    "density), then lambda = the given mean_free_path or iMFP_Iakoubovskii(density, beam_energy), then "
                    "t = (t/lambda) * lambda. With a mean_free_path and no density: t = (t/lambda) * lambda, no correction. "
                    "With neither: relative t/lambda.",
        },
    }


if __name__ == "__main__":
    main()
