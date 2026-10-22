#!/usr/bin/env python3
"""exSpy / HyperSpy pins for SpectroKit EELS task 16, sections 2, 3 and 4 of docs/design/eels-task-16.md.

Written before the Swift code. Pins what exSpy 0.3.2 / HyperSpy 2.4.0 answer on deterministic synthetic spectrum images with
known shifts: zero-loss alignment and mask (section 2), power-law extrapolation and Hanning taper (section 3),
Fourier-log and Fourier-ratio deconvolution and `optimal_fft_size` (section 4). Not covered: GOS tables, the edge model fit,
Richardson-Lucy. Agreement with exSpy is agreement, not truth; the planted truth (shifts, edge shape) is stored beside each case.

Run (any venv with `pip install hyperspy==2.4.0 exspy==0.3.2`; NumPy 2.5.4, SciPy 1.18.1 were used):

    python -I -B tools/eels-task16/pins.py [--out DIR]

Writes into --out (default Tests/SpectroEELSTests/Fixtures/):

    eels16-<name>.f64   float64 little-endian, C order, NaN kept (named in eels16-pins.json under "files" with shape and sha256)
    eels16-pins.json    everything else; floats are Python reprs (they round-trip exactly), NaN is null

Images are (ny, nx, channels) = (3, 4, n), pixel p = row * 4 + col. Axis of channel k: offset + scale * k.
Every output is byte-identical on a second run (default_rng(20261021); no other randomness).

Layout of eels16-pins.json:
  environment      versions, sha256 of this script, the generator command
  files            name -> {shape, sha256} for every .f64
  zlp.*            section 2. inputs: "ll" (shifted ZLP + plasmon + tail), "llSpike" (a spike larger than the ZLP at 12 eV),
                   "core" (a second image carrying the same shifts, for also_align); truth: per-pixel ZLP centre in eV.
      centre       estimate_zero_loss_peak_centre, with and without mask (masked -> null)
      mask         get_zero_loss_peak_mask for widths 5.0 and 2.0, with and without signal_mask
      estimateShift   estimate_shift1D(start, end, reference_indices=(0,0), number_of_interpolation_points=5) in eV
      align        one record per align_zero_loss_peak variant: kwargs, offset, size, scale, the re-estimated centre of the
                   aligned image, the shift arrays shift1D received in order (pass 1 coarse, pass 2 align1D subpixel), the
                   aligned image file, the also_align image file where used
      shift1D      shift1D on a ramp with fractional shifts, crop True and False: offset, size, data
  taper            hanning_taper cases: side, channels, offset -> returned channels and tapered data
  powerLaw         power_law_extrapolation cases (binned/unbinned, window, size, fix_neg_r): A, r from PowerLaw.estimate_parameters
                   on the zero-extended signal, the extrapolated data, the exact power law at the new channels (truth)
  optimalFFTSize   hyperspy.misc.math_tools.optimal_fft_size(n, real) for n in 1..200 plus selected larger n
  fourierLog       cases: size, taperedChannels, result with add_zlp / crop False/True; planted truth (single scattering S)
  fourierRatio     cases: size, fwhm (estimate_peak_width), thresholds, I0, taperedChannels, result; planted truth (edge)
"""
import argparse
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
ap.add_argument("--out", default=os.path.join(REPO, "Tests", "SpectroEELSTests", "Fixtures"))
ARGS = ap.parse_args()
OUT = ARGS.out
os.makedirs(OUT, exist_ok=True)

logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")

import numpy as np                                   # noqa: E402
import scipy                                         # noqa: E402
import hyperspy                                      # noqa: E402
import hyperspy.api as hs                            # noqa: E402
import exspy                                         # noqa: E402
from hyperspy.misc.math_tools import optimal_fft_size   # noqa: E402
from hyperspy._signals.signal1d import Signal1D      # noqa: E402

assert hyperspy.__version__ == "2.4.0" and exspy.__version__ == "0.3.2", (hyperspy.__version__, exspy.__version__)

NY, NX = 3, 4
RNG = np.random.default_rng(20261021)
FILES = {}
PINS = {}


def jnum(x):
    """float (or None) for JSON: NaN -> null."""
    if x is None:
        return None
    x = float(x)
    return None if math.isnan(x) else x


def jlist(a):
    a = np.asarray(a, dtype=np.float64)
    if a.ndim == 0:
        return jnum(a)
    return [jlist(v) for v in a]


def write(name, arr):
    """Write eels16-<name>.f64 and record it; returns the array as float64 C-order."""
    a = np.ascontiguousarray(np.asarray(arr, dtype="<f8"))
    path = os.path.join(OUT, "eels16-%s.f64" % name)
    a.tofile(path)
    FILES[name] = {"shape": list(a.shape), "sha256": hashlib.sha256(a.tobytes()).hexdigest()}
    return a


def eels(data, offset, scale, binned=True, title="x"):
    s = exspy.signals.EELSSpectrum(np.array(data, dtype=np.float64))
    ax = s.axes_manager.signal_axes[0]
    ax.offset = offset
    ax.scale = scale
    ax.units = "eV"
    ax.is_binned = binned
    s.metadata.General.title = title
    return s


def gauss(x, c, fwhm, area):
    sg = fwhm / 2.3548200450309493
    return area / (sg * math.sqrt(2 * math.pi)) * np.exp(-0.5 * ((x - c) / sg) ** 2)


# ----------------------------------------------------------------------------------------------------------------- section 2
# Shifted low-loss image: ZLP (FWHM 0.9 eV) at a per-pixel centre, a plasmon at 15 eV, a power-law tail.
N_LL, OFF_LL, SC_LL = 600, -20.0, 0.1
E_LL = OFF_LL + SC_LL * np.arange(N_LL)
GLOBAL = 0.37
CENTRES = (GLOBAL + np.array([[-1.07, -0.43, 0.0, 0.58], [0.91, 1.43, -1.46, 0.27], [-0.81, 0.12, 0.73, -0.19]])).astype(np.float64)
AMP = 1e6 * (1 + 0.1 * np.arange(NY * NX).reshape(NY, NX) / 12)


def lowloss_shifted(spike=False):
    d = np.zeros((NY, NX, N_LL))
    for i in range(NY):
        for j in range(NX):
            d[i, j] = (gauss(E_LL, CENTRES[i, j], 0.9, AMP[i, j]) + gauss(E_LL, 15.0, 4.0, 0.3 * AMP[i, j])
                       + np.where(E_LL >= 2, 5e4 * np.maximum(E_LL, 2) ** -2.5, 0))
            if spike:
                d[i, j, int(round((12.0 - OFF_LL) / SC_LL))] = 3.0 * d[i, j].max()
    return d


ll = write("zlp-ll", lowloss_shifted())
llspike = write("zlp-ll-spike", lowloss_shifted(spike=True))
# A core-loss-like second image that carries the same shifts (also_align): 300 channels at 0.5 eV from 100 eV.
N_CO, OFF_CO, SC_CO = 300, 100.0, 0.5
core = np.stack([np.stack([1e4 * np.maximum(OFF_CO + SC_CO * np.arange(N_CO), 1) ** -1.5 * (1 + 0.1 * (i * NX + j)) for j in range(NX)]) for i in range(NY)])
write("zlp-core", core)
PINS["zlp"] = {
    "ll": {"file": "zlp-ll", "nx": NX, "ny": NY, "channels": N_LL, "offsetEV": OFF_LL, "scaleEV": SC_LL},
    "llSpike": {"file": "zlp-ll-spike", "spikeEV": 12.0},
    "core": {"file": "zlp-core", "channels": N_CO, "offsetEV": OFF_CO, "scaleEV": SC_CO},
    "truth": {"zlpCentreEV": jlist(CENTRES), "globalOffsetEV": GLOBAL, "zlpFWHMEV": 0.9},
}

MASK = np.zeros((NY, NX), dtype=bool)
MASK[0, 1] = MASK[2, 2] = True


def nav_mask(m):
    """exSpy wants a navigation mask as a signal with signal dimension 0 (an ndarray is compared with (nx, ny))."""
    return None if m is None else hs.signals.BaseSignal(np.asarray(m)).T


def fresh(kind="ll"):
    d = {"ll": ll, "llSpike": llspike}[kind]
    return eels(d, OFF_LL, SC_LL, title=kind)


centre = {}
for name, kind, mask in [("plain", "ll", None), ("masked", "ll", MASK), ("spike", "llSpike", None)]:
    c = fresh(kind).estimate_zero_loss_peak_centre(mask=nav_mask(mask))
    centre[name] = jlist(c.data)
PINS["zlp"]["centre"] = centre

zmask = {}
for width in (5.0, 2.0):
    for sm_name, sm in [("none", None), ("signal", (E_LL > 30))]:
        m = fresh().get_zero_loss_peak_mask(zero_loss_peak_mask_width=width, signal_mask=sm)
        zmask["w%.1f-%s" % (width, sm_name)] = {"mask": [bool(v) for v in m], "signalMask": None if sm is None else [bool(v) for v in sm]}
PINS["zlp"]["mask"] = zmask

est = {}
for name, (a, b, ip) in {"default": (-3.0, 3.0, 5), "wide": (-4.0, 4.0, 5), "ip0": (-3.0, 3.0, 0), "ip9": (-3.0, 3.0, 9)}.items():
    s = fresh()
    ref = s.estimate_shift1D(a, b, reference_indices=(0, 0), number_of_interpolation_points=ip, show_progressbar=False)
    est[name] = {"fromEV": a, "toEV": b, "interpolationPoints": ip, "shiftEV": jlist(ref)}
PINS["zlp"]["estimateShift"] = est

# align_zero_loss_peak variants. shift1D is wrapped to record the shift arrays it receives, in order.
RECORD = []
_orig_shift = Signal1D.shift1D


def _wrapped(self, shift_array, *a, **k):
    RECORD.append(np.array(shift_array, dtype=np.float64).copy())
    return _orig_shift(self, shift_array, *a, **k)


Signal1D.shift1D = _wrapped
VARIANTS = {
    "default": dict(kind="ll", kw={}),
    "no-subpixel": dict(kind="ll", kw=dict(subpixel=False)),
    "no-calibrate": dict(kind="ll", kw=dict(calibrate=False)),
    "no-crop": dict(kind="ll", kw=dict(crop=False)),
    "no-crop-no-calibrate": dict(kind="ll", kw=dict(crop=False, calibrate=False)),
    "mask": dict(kind="ll", kw=dict(mask=MASK)),
    "signal-range": dict(kind="ll", kw=dict(signal_range=(-5.0, 5.0))),
    "spike-no-range": dict(kind="llSpike", kw={}),
    "spike-range": dict(kind="llSpike", kw=dict(signal_range=(-5.0, 5.0))),
    "also-align": dict(kind="ll", kw={}, also=True),
    "interp-ip3": dict(kind="ll", kw=dict(number_of_interpolation_points=3)),
}
align = {}
for name, v in VARIANTS.items():
    s = fresh(v["kind"])
    also = [eels(core, OFF_CO, SC_CO, title="core")] if v.get("also") else []
    RECORD.clear()
    kw = dict(v["kw"])
    if "mask" in kw:
        kw["mask"] = nav_mask(kw["mask"])
    s.align_zero_loss_peak(also_align=also, print_stats=False, show_progressbar=False, **kw)
    ax = s.axes_manager.signal_axes[0]
    rec = {"kind": v["kind"], "kwargs": {k: (None if k == "mask" else (list(x) if isinstance(x, tuple) else x)) for k, x in v["kw"].items()},
           "maskUsed": "mask" in v["kw"],
           "offsetEV": float(ax.offset), "scaleEV": float(ax.scale), "channels": int(ax.size),
           "reestimatedCentreEV": jlist(s.estimate_zero_loss_peak_centre(mask=kw.get("mask")).data),
           "shiftPasses": [jlist(r) for r in RECORD],
           "file": "zlp-align-%s" % name}
    write(rec["file"], s.data)
    if also:
        cax = also[0].axes_manager.signal_axes[0]
        rec["alsoAligned"] = {"file": "zlp-align-%s-core" % name, "offsetEV": float(cax.offset), "channels": int(cax.size)}
        write(rec["alsoAligned"]["file"], also[0].data)
    align[name] = rec
Signal1D.shift1D = _orig_shift
PINS["zlp"]["align"] = align

# shift1D alone: a ramp-plus-bump signal, fractional shifts in channels * scale (eV).
ramp = np.array([np.sin(np.arange(40) / 5.0) + 0.05 * np.arange(40) * (k + 1) for k in range(4)])   # (4, 40)
sh = np.array([0.0, 0.35, -0.72, 1.6])                                                             # eV, scale 0.5 -> 0, 0.7, -1.44, 3.2 channels
shift = {}
for crop in (True, False):
    s = eels(ramp, 5.0, 0.5, binned=False)
    s.shift1D(sh, crop=crop, show_progressbar=False)
    ax = s.axes_manager.signal_axes[0]
    shift["crop" if crop else "nocrop"] = {"offsetEV": float(ax.offset), "channels": int(ax.size), "file": "zlp-shift1d-%s" % ("crop" if crop else "nocrop")}
    write(shift["crop" if crop else "nocrop"]["file"], s.data)
write("zlp-shift1d-input", ramp)
PINS["zlp"]["shift1D"] = {"inputFile": "zlp-shift1d-input", "offsetEV": 5.0, "scaleEV": 0.5, "shiftEV": jlist(sh), "cases": shift}

# --------------------------------------------------------------------------------------------------------------- section 3
# Hanning taper (HyperSpy Signal1D.hanning_taper).
taper = {}
tdata = 1.0 + np.arange(2 * 300).reshape(2, 300) * 0.01 + 5.0
write("taper-input", tdata)
for name, kw in {"both": {}, "left": dict(side="left"), "right": dict(side="right"), "channels25": dict(channels=25),
                 "offset10": dict(offset=10), "left-ch40-off5": dict(side="left", channels=40, offset=5)}.items():
    s = eels(tdata, 0.0, 1.0)
    n = s.hanning_taper(**kw)
    taper[name] = {"kwargs": kw, "taperedChannels": int(n), "file": "taper-%s" % name}
    write(taper[name]["file"], s.data)
for n in (50, 100, 999, 1024, 2000, 5000):                      # default channels = max(20, round(0.02 n))
    s = eels(np.ones((1, n)), 0.0, 1.0)
    taper["default-n%d" % n] = {"kwargs": {}, "n": n, "taperedChannels": int(s.hanning_taper())}
PINS["taper"] = {"input": {"file": "taper-input", "channels": 300, "rows": 2}, "cases": taper}

# Power-law extrapolation (exSpy power_law_extrapolation).
N_PL, OFF_PL, SC_PL = 200, 300.0, 0.5
E_PL = OFF_PL + SC_PL * np.arange(N_PL)
A_PL = np.array([[1e9, 5e8, 2e10], [3e12, 8e7, 4e5]])
R_PL = np.array([[3.0, 2.5, 3.5], [4.0, 1.7, -0.4]])        # last pixel: r < 0 (rising) for fix_neg_r
pl = {}
for binned in (True, False):
    d = A_PL[..., None] * E_PL ** (-R_PL[..., None]) * (SC_PL if binned else 1.0)
    write("pl-input-%s" % ("binned" if binned else "unbinned"), d)
    for ws, es, fix in [(20, 1024, False), (20, 100, True), (50, 100, False), (20, 100, False)]:
        s = eels(d, OFF_PL, SC_PL, binned=binned)
        out = s.power_law_extrapolation(window_size=ws, extrapolation_size=es, fix_neg_r=fix)
        # A, r exactly as exSpy gets them: PowerLaw.estimate_parameters on the zero-extended copy over the last window
        ext = s.deepcopy()
        ext.data = np.zeros(list(d.shape[:-1]) + [N_PL + es])
        ext.data[..., :N_PL] = d
        ext.get_dimensions_from_data()
        comp = hs.model.components1D.PowerLaw()
        comp._axes_manager = s.axes_manager
        ax = s.axes_manager.signal_axes[0]
        A, r = comp.estimate_parameters(ext, ax.index2value(ax.size - ws), ax.index2value(ax.size - 1), out=True)
        name = "%s-w%d-e%d%s" % ("binned" if binned else "unbinned", ws, es, "-fixneg" if fix else "")
        e_new = OFF_PL + SC_PL * np.arange(N_PL, N_PL + es)
        exact = A_PL[..., None] * e_new ** (-R_PL[..., None]) * (SC_PL if binned else 1.0)
        pl[name] = {"binned": binned, "windowChannels": ws, "extrapolationChannels": es, "fixNegativeR": fix,
                    "A": jlist(A), "AUsed": jlist(np.where(r <= 0, 0, A) if fix else A), "r": jlist(r), "inputFile": "pl-input-%s" % ("binned" if binned else "unbinned"),
                    "file": "pl-%s" % name, "exactFile": "pl-exact-%s" % name, "channels": int(out.axes_manager.signal_axes[0].size)}
        write(pl[name]["file"], out.data)
        write(pl[name]["exactFile"], exact)
PINS["powerLaw"] = {"offsetEV": OFF_PL, "scaleEV": SC_PL, "channels": N_PL, "truthA": jlist(A_PL), "truthR": jlist(R_PL), "cases": pl}

# --------------------------------------------------------------------------------------------------------------- section 4
PINS["optimalFFTSize"] = {
    "ns": [int(n) for n in list(range(1, 201)) + [255, 256, 257, 511, 1000, 1023, 1024, 1025, 1500, 2047, 2048, 2049, 2200, 4093, 4097, 10007, 65537]],
}
PINS["optimalFFTSize"]["real"] = [int(optimal_fft_size(n, True)) for n in PINS["optimalFFTSize"]["ns"]]
PINS["optimalFFTSize"]["complex"] = [int(optimal_fft_size(n, False)) for n in PINS["optimalFFTSize"]["ns"]]

# Planted plural-scattering low loss: ZLP at 0 eV for every pixel, thickness t/lambda per pixel, J = I0 ifft(Z' exp(fft S / I0)).
N_P, OFF_P, SC_P = 1600, -20.0, 0.1                                     # -20 .. 139.9 eV, long enough that the plural tail has decayed
E_P = OFF_P + SC_P * np.arange(N_P)
TAU = np.array([[0.2, 0.4, 0.6, 0.8], [1.0, 1.2, 0.1, 0.3], [0.5, 0.7, 0.9, 1.1]])
I0_P = 1e6
PAD = 8192                                                              # circular grid long enough that nothing wraps
z1 = gauss(E_P, 0.0, 0.9, 1.0)                                          # unit-area ZLP per eV
S1 = gauss(E_P, 12.0, 4.0, 1.0) + gauss(E_P, 24.0, 7.0, 0.5)           # single-scattering shape (unit area 1.5)
S1 = np.where(E_P > 2.0, S1, 0.0)
zl = np.zeros((NY, NX, N_P))
jl = np.zeros((NY, NX, N_P))
ss = np.zeros((NY, NX, N_P))
for i in range(NY):
    for j in range(NX):
        tau = TAU[i, j]
        S = tau * I0_P * S1 / S1.sum() * 1.0                            # counts: area tau * I0 over the channels
        Z = I0_P * z1 / z1.sum()                                        # counts: area I0
        Zf, Sf = np.fft.rfft(Z, PAD), np.fft.rfft(S, PAD)
        J = np.fft.irfft(Zf * np.exp(Sf / I0_P), PAD)[:N_P]
        zl[i, j], jl[i, j], ss[i, j] = Z, J, S
write("plural-zlp", zl)
write("plural-ll", jl)
write("plural-single", ss)
# Fourier-log returns Z (x) S / I0 (the single-scattering distribution broadened by the ZLP), not S: that is the truth to compare with
ssb = np.stack([np.stack([np.convolve(ss[i, j], zl[i, j] / zl[i, j].sum())[:N_P] for j in range(NX)]) for i in range(NY)])
write("plural-single-broadened", ssb)
plural = {"nx": NX, "ny": NY, "channels": N_P, "offsetEV": OFF_P, "scaleEV": SC_P, "tauOverLambda": jlist(TAU), "i0": I0_P,
          "zlpFile": "plural-zlp", "lowLossFile": "plural-ll", "singleScatteringFile": "plural-single", "singleScatteringBroadenedFile": "plural-single-broadened",
          "note": "J = I0 ifft(fft(Z/I0) exp(fft(S)/I0)) on a 8192 circular grid, cropped; truth S is the single-scattering counts, S x Z/I0 is what Fourier-log returns"}

fl = {}
for name, kw in {"default": {}, "add-zlp": dict(add_zlp=True), "crop": dict(crop=True), "add-zlp-crop": dict(add_zlp=True, crop=True)}.items():
    j = eels(jl, OFF_P, SC_P, title="J")
    z = eels(zl, OFF_P, SC_P, title="Z")
    tapped = j.deepcopy().hanning_taper()
    out = j.fourier_log_deconvolution(z, **kw)
    size = optimal_fft_size(N_P + N_P - 1, True)
    ax = out.axes_manager.signal_axes[0]
    fl[name] = {"kwargs": kw, "fftSize": int(size), "taperedChannels": int(tapped), "channels": int(ax.size),
                "offsetEV": float(ax.offset), "file": "fl-%s" % name}
    write(fl[name]["file"], out.data)
# zlp shorter than the spectrum and longer than it (sizes differ; zlp.data is broadcast against j only when sizes match,
# so the shapes here keep the channel counts equal and the case documents that exSpy requires it)
PINS["fourierLog"] = {"plural": plural, "cases": fl}

# Fourier ratio: core loss = edge (single scattering, background removed) convolved with J/I0 (ZLP weight 1), 300 channels at 0.1 eV from 280 eV.
N_C, OFF_C = 300, 280.0
e = np.arange(N_C) * SC_P
edge = np.where(e >= 4.0, 2e3 * np.exp(-(e - 4.0) / 25.0), 0.0)         # a smooth step with an exponential tail, counts per channel
core_p = np.zeros((NY, NX, N_C))
edge_p = np.zeros((NY, NX, N_C))
ZERO = int(round(-OFF_P / SC_P))                                        # channel of 0 eV in the low loss
for i in range(NY):
    for j in range(NX):
        ed = edge * (1.0 + 0.2 * (i * NX + j))
        full = np.convolve(ed, jl[i, j] / I0_P)
        core_p[i, j] = full[ZERO:ZERO + N_C]
        edge_p[i, j] = ed
write("plural-core", core_p)
write("plural-edge", edge_p)
fr = {}
for name, kw in {"default": {}, "fixed-threshold-6": dict(threshold=6.0), "fwhm-1.5": dict(fwhm=1.5, threshold=6.0),
                 "no-extrap-ll": dict(threshold=6.0, extrapolate_lowloss=False),
                 "no-extrap-cl": dict(threshold=6.0, extrapolate_coreloss=False),
                 "no-extrap": dict(threshold=6.0, extrapolate_lowloss=False, extrapolate_coreloss=False)}.items():
    c = eels(core_p, OFF_C, SC_P, title="core")
    l = eels(jl, OFF_P, SC_P, title="J")
    kws = dict(kw)
    ctx = {}
    # the pieces exSpy computes internally, recomputed with the same calls
    ll2 = l.power_law_extrapolation(window_size=100, extrapolation_size=100) if kw.get("extrapolate_lowloss", True) else l.deepcopy()
    cl2 = c.power_law_extrapolation(window_size=20, extrapolation_size=100) if kw.get("extrapolate_coreloss", True) else c.deepcopy()
    tap_ll, tap_cl = ll2.hanning_taper(), cl2.hanning_taper()
    size = optimal_fft_size(ll2.axes_manager.signal_axes[0].size + c.axes_manager.signal_axes[0].size - 1)   # exSpy sizes from the ORIGINAL core loss (`self`), not the extrapolated copy
    thr = kw.get("threshold")
    thr_used = l.estimate_elastic_scattering_threshold() if thr is None else None
    I0 = ll2.estimate_elastic_scattering_intensity(threshold=thr_used if thr is None else thr)
    fwhm_ref = float(l.get_current_signal().estimate_peak_width()._get_current_data()[0]) if kw.get("fwhm") is None else kw["fwhm"]
    out = c.fourier_ratio_deconvolution(l, **kws)
    fr[name] = {"kwargs": kw, "fftSize": int(size), "lowLossChannelsAfterExtrapolation": int(ll2.axes_manager.signal_axes[0].size),
                "coreLossChannelsAfterExtrapolation": int(cl2.axes_manager.signal_axes[0].size),
                "taperedChannelsLowLoss": int(tap_ll), "taperedChannelsCoreLoss": int(tap_cl),
                "fwhmEV": jnum(fwhm_ref), "thresholdEV": None if thr_used is None else jlist(thr_used.data),
                "i0": jlist(I0.data), "channels": int(out.axes_manager.signal_axes[0].size), "offsetEV": float(out.axes_manager.signal_axes[0].offset),
                "file": "fr-%s" % name}
    write(fr[name]["file"], out.data)
# FWHM of every pixel's ZLP (estimate_peak_width on the whole image; NaN where the cubic spline does not have exactly two roots)
fw = eels(jl, OFF_P, SC_P).estimate_peak_width()
fwhm_all = jlist(fw.data)
PINS["fourierRatio"] = {"note": "exSpy's Gaussian is a density per eV (A=1, sum over channels = 1/scale), so the result is the planted edge "
                        "smoothed by the Gaussian AND multiplied by 1/scale: interior of fr-fixed-threshold-6 equals smoothed truth / scale to 3 %",
                        "plural": plural, "core": {"file": "plural-core", "channels": N_C, "offsetEV": OFF_C, "scaleEV": SC_P,
                                                   "truthEdgeFile": "plural-edge", "zeroLossChannel": ZERO},
                        "fwhmAllPixelsEV": fwhm_all, "cases": fr}

# ----------------------------------------------------------------------------------------------------------------- environment
with open(__file__, "rb") as fh:
    PINS["environment"] = {
        "exspy": exspy.__version__, "hyperspy": hyperspy.__version__, "numpy": np.__version__, "scipy": scipy.__version__,
        "python": platform.python_version(), "scriptSha256": hashlib.sha256(fh.read()).hexdigest(),
        "command": "python -I -B tools/eels-task16/pins.py",
        "note": "spectra are synthetic and deterministic; HyperSpy ran without numba (non-accelerated paths, identical results)",
    }
PINS["files"] = FILES
with open(os.path.join(OUT, "eels16-pins.json"), "w") as fh:
    json.dump(PINS, fh, indent=1, sort_keys=True, allow_nan=False)
    fh.write("\n")
print("wrote", len(FILES), "arrays")
