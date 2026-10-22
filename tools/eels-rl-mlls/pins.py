#!/usr/bin/env python3
"""HyperSpy / exSpy pins for SpectroKit 0.10.0 EELS: Richardson-Lucy deconvolution and the multiple linear least squares (MLLS) edge fit.

Pins what HyperSpy 2.4.0 / exSpy 0.3.2 answer on deterministic synthetic spectrum images:

  * `EELSSpectrum.richardson_lucy_deconvolution(psf, iterations)` with a shared PSF (navigation size 0) and with one PSF per pixel;
    a flat-topped PSF (argmax tie), an off-centre PSF, a spectrum with zeros (exSpy returns NaN), 0 / 5 / 15 / 40 iterations.
  * `Model1D.fit(optimizer="lstsq")` of an exSpy EELS model whose power-law exponent is fixed: the amplitudes of the power law (A) and
    of the edges (intensity), their standard errors (`p_std`, from `_calculate_covariance`), the residual and the model curve, on
    noise-free and Poisson-noisy images, with and without the low-loss convolution, over the whole axis and over an explicit window.
    The exponent comes from (a) the planted per-pixel value ("given") or (b) `two_area_background_estimation()` ("twoArea").

Run (the suite's HyperSpy 2.4.0 / exSpy 0.3.2 venv, NumPy 2.5.4, SciPy 1.18.1):

    ../References/python/hyperspy/bin/python -I -B tools/eels-rl-mlls/pins.py [--gosh FILE] [--out DIR]

Writes into --out (default Tests/SpectroEELSTests/Fixtures/):

    eelsrm-<name>.f64   float64 little-endian, C order, NaN kept (named in eelsrm-pins.json under "files" with shape and sha256)
    eelsrm-pins.json    everything else; floats are Python reprs (they round-trip exactly), NaN is null

Images are (ny, nx, channels); pixel p = row * nx + col. Axis of channel k: offset + scale * k.
Every output is byte-identical on a second run (default_rng(20261022); no other randomness).

Layout of eelsrm-pins.json:
  environment            versions, sha256 of this script
  files                  name -> {shape, sha256}
  rl.<case>              {nx, ny, channels, iterations, signalFile, psfFile, psfShared, resultFile, nanPixels}
  mlls.<case>.<window>.<mode>
                         {edges, masters, microscope, axis, nx, ny, coreFile, lowLossFile?, lowLossAxis?, window {startEV, endEV, i1, i2},
                          r (per pixel), A, AStd, intensity {master: [per pixel]}, intensityStd, rss, dof, order, curveFile, truth}
"""
import argparse
import hashlib
import json
import logging
import math
import os
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])


def find_gosh():
    """`../References/SpectroKit/gos-dft-1.5.0.gosh` from the repo, or from the nearest parent that has a References folder (a worktree)."""
    d = REPO
    while d != os.path.dirname(d):
        p = os.path.join(d, "..", "References", "SpectroKit", "gos-dft-1.5.0.gosh")
        if os.path.exists(p):
            return os.path.normpath(p)
        d = os.path.dirname(d)
    return os.path.normpath(os.path.join(REPO, "..", "References", "SpectroKit", "gos-dft-1.5.0.gosh"))


ap.add_argument("--gosh", default=find_gosh())
ap.add_argument("--out", default=os.path.join(REPO, "Tests", "SpectroEELSTests", "Fixtures"))
ARGS = ap.parse_args()
logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")

import numpy as np                                   # noqa: E402
import scipy                                         # noqa: E402
import hyperspy                                      # noqa: E402
import exspy                                         # noqa: E402
from exspy.components import EELSCLEdge              # noqa: E402

assert hyperspy.__version__ == "2.4.0" and exspy.__version__ == "0.3.2", (hyperspy.__version__, exspy.__version__)

OUT = ARGS.out
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(20261022)
FILES = {}
NY, NX = 2, 3


def jnum(x):
    x = float(x)
    return None if math.isnan(x) else x


def jl(a):
    a = np.asarray(a, dtype=float)
    if a.ndim == 0:
        return jnum(a)
    return [jl(v) for v in a]


def write(name, arr):
    a = np.ascontiguousarray(np.asarray(arr, dtype="<f8"))
    a.tofile(os.path.join(OUT, "eelsrm-%s.f64" % name))
    FILES[name] = {"shape": list(a.shape), "sha256": hashlib.sha256(a.tobytes()).hexdigest()}
    return name


def eels(data, offset, scale, binned=True):
    s = exspy.signals.EELSSpectrum(np.array(data, dtype=float))
    ax = s.axes_manager.signal_axes[0]
    ax.offset, ax.scale, ax.units, ax.is_binned = offset, scale, "eV", binned
    return s


# ------------------------------------------------------------------------------------------------------------------------------
# Richardson-Lucy
# ------------------------------------------------------------------------------------------------------------------------------
RL = {}


def rl_truth(n, scale):
    """Two sharp peaks and a decaying pedestal on a positive floor."""
    e = np.arange(n) * scale
    return (5.0 + 400.0 * np.exp(-e / 6.0)
            + 900.0 * np.exp(-0.5 * ((e - 4.0) / 0.25) ** 2)
            + 600.0 * np.exp(-0.5 * ((e - 5.0) / 0.25) ** 2)
            + 300.0 * np.exp(-0.5 * ((e - 11.0) / 0.4) ** 2))


def psf_asym(n, centre, sigma, tail):
    """Gaussian at `centre` (channels) plus an exponential tail on the high side; unit area."""
    k = np.arange(n, dtype=float)
    g = np.exp(-0.5 * ((k - centre) / sigma) ** 2)
    t = np.where(k > centre, np.exp(-(k - centre) / tail), 0.0) * 0.3
    p = g + t
    return p / p.sum()


def forward(sig, psf):
    """The blur the deconvolution undoes: np.convolve(psf, sig) cut at the PSF maximum (the slice RL itself uses)."""
    imax = int(np.argmax(psf))
    return np.convolve(psf, sig)[imax:imax + sig.size]


def rl_case(name, n, iterations, shared, noisy, flat_top=False, zeros=False, centre=37.0, scale=0.1):
    truth = rl_truth(n, scale)
    data = np.zeros((NY, NX, n))
    psfs = np.zeros((n,)) if shared else np.zeros((NY, NX, n))
    for p in range(NY * NX):
        i, j = divmod(p, NX)
        psf = psf_asym(n, centre, 1.0 if zeros else (3.0 if shared else 2.2 + 0.4 * p), 1e-3 if zeros else 5.0)
        if flat_top:
            psf = np.round(psf * 1e4)                       # integer valued: the maximum is attained twice
            k = int(np.argmax(psf))
            psf[k + 1] = psf[k]
            psf /= psf.sum()
        if shared:
            psfs[:] = psf
        else:
            psfs[i, j] = psf
        sig = forward(truth * (1.0 + 0.1 * p), psf)
        if noisy:
            sig = RNG.poisson(sig).astype(float)
        if zeros and p % 2 == 0:
            sig = sig.copy()
            sig[100:] = 0.0                                 # zeros beyond the PSF's reach (it underflows to exactly 0): 0 / 0 in the first iterate, so exSpy's NaN
        data[i, j] = sig
    s = eels(data, 0.0, scale)
    ps = eels(psfs, 0.0, scale)
    out = s.richardson_lucy_deconvolution(ps, iterations=iterations, show_progressbar=False)
    res = np.asarray(out.data, dtype=float)
    assert res.shape == data.shape
    RL[name] = {"nx": NX, "ny": NY, "channels": n, "iterations": iterations, "psfShared": bool(shared), "noisy": noisy, "scaleEV": scale,
                "signalFile": write("rl-%s-signal" % name, data), "psfFile": write("rl-%s-psf" % name, psfs),
                "resultFile": write("rl-%s-result" % name, res),
                "nanPixels": [int(p) for p in range(NY * NX) if not np.all(np.isfinite(res.reshape(NY * NX, n)[p]))]}


rl_case("shared-15", 240, 15, True, False)
rl_case("shared-15-noisy", 240, 15, True, True)
rl_case("shared-5", 240, 5, True, False)
rl_case("shared-40-noisy", 240, 40, True, True)
rl_case("pixel-15", 240, 15, False, False)
rl_case("pixel-15-noisy", 240, 15, False, True)
rl_case("pixel-0", 240, 0, False, False)
rl_case("flat-top", 240, 15, True, False, flat_top=True)
rl_case("early-centre", 240, 15, True, False, centre=3.0)
rl_case("zeros", 240, 15, False, False, zeros=True)

# ------------------------------------------------------------------------------------------------------------------------------
# MLLS: Model1D.fit(optimizer="lstsq") with the exponent fixed
# ------------------------------------------------------------------------------------------------------------------------------
LL_OFF = -20.0
LL_N = 120
MLLS = {}


def edge_function(name, mic, scale):
    e = EELSCLEdge(name, GOS="dft", gos_file_path=ARGS.gosh)
    e.set_microscope_parameters(E0=mic[0], alpha=mic[1], beta=mic[2], energy_scale=scale)
    return e


def lowloss_image(scale):
    e = LL_OFF + scale * np.arange(LL_N)
    sg = 1.2 / 2.3548200450309493
    zlp = np.exp(-0.5 * (e / sg) ** 2)
    zlp /= zlp.sum()
    pl = np.exp(-0.5 * ((e - 15.0) / 3.0) ** 2)
    pl /= pl.sum()
    out = np.zeros((NY, NX, LL_N))
    for i in range(NY):
        for j in range(NX):
            t = 0.2 + 0.1 * (i * NX + j)
            out[i, j] = (1 - t) * zlp + t * pl      # unit area: the loss function (a 1e6 area makes the edge columns 1e15 times the power-law's,
            # and numpy's lstsq (rcond = eps max(M, N)) then drops the power law)
    return out


def masters_of(edges):
    return sorted({nme for nme in edges if nme == sorted(x for x in edges if x.startswith(nme.split("_")[0] + "_"))[-1]})


def make_data(edges, off, scale, n, mic, a_true, r_true, intensity, noisy, low_loss):
    E = off + scale * np.arange(n)
    masters = masters_of(edges)
    funcs = {nme: edge_function(nme, mic, scale) for nme in edges}
    data = np.zeros((NY, NX, n))
    for i in range(NY):
        for j in range(NX):
            p = i * NX + j
            bg = a_true[p] * E ** -r_true[p] * scale
            if low_loss is None:
                ed = np.zeros(n)
                for nme in edges:
                    master = [m for m in masters if m.startswith(nme.split("_")[0] + "_")][0]
                    ed += intensity[master][p] * funcs[nme].function(E)
                ed = ed * scale
            else:
                size = n + LL_N - 1
                j0 = int(round(-LL_OFF / scale))
                offset_index = LL_N - j0 - 1
                conv_axis = np.linspace(off - offset_index * scale, off + scale * (size - 1 - offset_index), size)
                fc = np.zeros(size)
                for nme in edges:
                    master = [m for m in masters if m.startswith(nme.split("_")[0] + "_")][0]
                    fc += intensity[master][p] * funcs[nme].function(conv_axis)
                ed = np.convolve(low_loss[i, j], fc, mode="valid") * scale
            y = bg + ed
            data[i, j] = RNG.poisson(y) if noisy else y
    return masters, data


def exspy_model(data, off, scale, mic, edges, ll_data):
    s = eels(data, off, scale)
    s.set_microscope_parameters(beam_energy=mic[0], convergence_angle=mic[1], collection_angle=mic[2])
    ll = eels(ll_data, LL_OFF, scale) if ll_data is not None else None
    m = s.create_model(low_loss=ll, auto_background=True, auto_add_edges=False, GOS="dft", gos_file_path=ARGS.gosh)
    by_el = {}
    for nme in edges:
        by_el.setdefault(nme.split("_")[0], []).append(nme)
    for el, shells in by_el.items():
        m._add_edges_from_subshells_names(list(shells))
    return s, m


def mlls_run(m, n, masters, mode, r_given, start, end):
    """Window, exponent per pixel (planted or two-area), then Model1D.fit(optimizer="lstsq") with the exponent fixed."""
    pl = m[0]
    m.reset_signal_range()
    if start is not None or end is not None:
        m.set_signal_range(start, end)
    switches = np.asarray(m._channel_switches, dtype=bool).copy()
    idx = np.where(switches)[0]
    window = {"startEV": start, "endEV": end, "i1": int(idx[0]), "i2": int(idx[-1]) + 1}
    A, Astd, R = [], [], []
    inten = {nme: [] for nme in masters}
    inten_std = {nme: [] for nme in masters}
    rss, dof = [], []
    curve = np.zeros((NY, NX, n))
    for i in range(NY):
        for j in range(NX):
            m.axes_manager.indices = (j, i)
            p = i * NX + j
            pl.r.free = True
            if mode == "twoArea":
                m.two_area_background_estimation(E1=start)
            else:
                pl.r.value = r_given[p]
            pl.r.free = False
            pl.A.value = 1.0
            m.fit(optimizer="lstsq")
            A.append(pl.A.value); Astd.append(pl.A.std); R.append(pl.r.value)
            for e in m.edges:
                if e.intensity.twin is None:
                    inten[e.name].append(e.intensity.value)
                    inten_std[e.name].append(e.intensity.std)
            cur = m._get_current_data(onlyactive=True, ignore_channel_switches=True)
            curve[i, j] = cur
            res = (m.signal._get_current_data() - cur)[switches]
            rss.append(float(np.sum(res ** 2)))
            dof.append(int(switches.sum() - len(m.p0)))
    pl.r.free = True
    m.reset_signal_range()
    return {"window": window, "r": jl(R), "A": jl(A), "AStd": jl(Astd),
            "intensity": {k: jl(v) for k, v in inten.items()}, "intensityStd": {k: jl(v) for k, v in inten_std.items()},
            "rss": jl(rss), "dof": dof, "order": [e.name for e in m.edges if e.intensity.twin is None]}, curve


def run_case(name, edges, off, scale, n, mic, noisy, windows, conv=False):
    E = off + scale * np.arange(n)
    p = NX * NY
    r_true = 2.6 + 0.15 * np.arange(p)
    a_true = 6e3 * E[0] ** r_true * (1 + 0.1 * np.arange(p)) / scale
    masters = masters_of(edges)
    inten = {}
    for k, mnm in enumerate(masters):
        inten[mnm] = (1.0 + 0.2 * np.arange(p)) * (2.0 if k == 0 else 1.2) * 4e-1 * 1e6
    ll = lowloss_image(scale) if conv else None
    masters, data = make_data(edges, off, scale, n, mic, a_true, r_true, inten, noisy, ll)
    s, m = exspy_model(data, off, scale, mic, edges, ll)
    base = {"edges": list(edges), "masters": masters, "microscope": list(mic), "nx": NX, "ny": NY, "noisy": noisy, "convolved": conv,
            "axis": {"offsetEV": off, "scaleEV": scale, "size": n},
            "truth": {"A": jl(a_true), "r": jl(r_true), "intensity": {k: jl(v) for k, v in inten.items()}},
            "coreFile": write("mlls-%s-core" % name, data)}
    if conv:
        base["lowLossFile"] = write("mlls-%s-ll" % name, ll)
        base["lowLossAxis"] = {"offsetEV": LL_OFF, "scaleEV": scale, "size": LL_N}
    for wname, (start, end) in windows.items():
        for mode in ("given", "twoArea"):
            rec, curve = mlls_run(m, n, masters, mode, r_true, start, end)
            rec["curveFile"] = write("mlls-%s-%s-%s-curve" % (name, wname, mode), curve)
            rec.update(base)
            rec["mode"] = mode
            MLLS["%s.%s.%s" % (name, wname, mode)] = rec


run_case("fel", ["Fe_L2", "Fe_L3"], 600.0, 0.5, 600, (200.0, 10.0, 20.0), True, {"full": (None, None), "win": (610.0, 850.0)})
run_case("fel-exact", ["Fe_L2", "Fe_L3"], 600.0, 0.5, 600, (200.0, 10.0, 20.0), False, {"full": (None, None)})
run_case("cno", ["C_K", "N_K", "O_K"], 200.0, 0.5, 700, (300.0, 0.0, 30.0), True, {"full": (None, None), "win": (230.0, 549.0)})
run_case("fecu", ["Fe_L2", "Fe_L3", "Cu_L2", "Cu_L3"], 600.0, 0.5, 1400, (200.0, 10.0, 20.0), True, {"full": (None, None)})
run_case("fel-conv", ["Fe_L2", "Fe_L3"], 600.0, 0.5, 600, (200.0, 10.0, 20.0), True, {"full": (None, None)}, conv=True)

pins = {"environment": {"hyperspy": hyperspy.__version__, "exspy": exspy.__version__, "numpy": np.__version__, "scipy": scipy.__version__,
                        "script": hashlib.sha256(open(__file__, "rb").read()).hexdigest()},
        "files": FILES, "rl": RL, "mlls": MLLS}
with open(os.path.join(OUT, "eelsrm-pins.json"), "w") as f:
    json.dump(pins, f, sort_keys=True, indent=1)
    f.write("\n")
print("wrote", len(FILES), "arrays,", len(RL), "RL cases,", len(MLLS), "MLLS runs")
