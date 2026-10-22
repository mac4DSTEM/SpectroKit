#!/usr/bin/env python3
"""exSpy pins for SpectroKit EELS task 16 step 5 (docs/design/eels-task-16.md section 6.2): the edge model.

Pins what exSpy 0.3.2 / HyperSpy 2.4.0 answer on deterministic synthetic core-loss images: `two_area_background_estimation`, `fit_background`,
`multifit(kind="smart")` (the cascade; its final stage is the whole model over the whole range), the model curve (`as_signal`), and the text
of `quantify`. Planted truth (background A and r, edge intensities) is stored beside each case; agreement with exSpy is agreement, not truth.

Run (HyperSpy 2.4.0 venv):

    python -I -B tools/eels-task16/model.py [--exspy DIR] [--gosh FILE] [--out DIR]

Writes into --out (default Tests/SpectroEELSTests/Fixtures/):
    eels16-model-<case>-core.f64, -ll.f64 (where used), -curve.f64   float64 little-endian, C order, (ny, nx, channels)
    eels16-model-pins.json
Cases: "fel" (Fe L2,3 twin; noise-free and Poisson-noisy), "cno" (C, N, O K), "fecu" (Fe L and Cu L: two masters), "fel-conv" (Fe L convolved
with a low loss). Every output is byte-identical on a second run (default_rng(20261022)).

Layout of eels16-model-pins.json: environment; cases.<name>: {edges, microscope, axis, nx, ny, files, lowLossAxis, truth {A, r, intensity},
  twoArea {A, r}, fitBackground {A, r, rangeEV}, smart {A, r, intensity (per master, in fit order), curveFile}, quantifyText (pixel 0)}.
"""
import argparse
import contextlib
import hashlib
import io
import json
import logging
import math
import os
import sys
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--gosh", default=os.path.join(REPO, "..", "References", "SpectroKit", "gos-dft-1.5.0.gosh"))
ap.add_argument("--exspy", default=os.path.join(REPO, "..", "References", "SpectroKit", "exspy-7185a4d1"))
ap.add_argument("--out", default=os.path.join(REPO, "Tests", "SpectroEELSTests", "Fixtures"))
ARGS = ap.parse_args()
sys.path.insert(0, os.path.abspath(ARGS.exspy))
logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")

import numpy as np                                   # noqa: E402
import hyperspy                                      # noqa: E402
import exspy                                         # noqa: E402
from exspy.components import EELSCLEdge              # noqa: E402

OUT = ARGS.out
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(20261022)
FILES = {}
NX, NY = 3, 2


def write(name, arr):
    a = np.ascontiguousarray(np.asarray(arr, dtype="<f8"))
    a.tofile(os.path.join(OUT, "eels16-model-%s.f64" % name))
    FILES[name] = hashlib.sha256(a.tobytes()).hexdigest()
    return name


def jl(a):
    return np.asarray(a, dtype=float).tolist()


def edge_function(name, mic, scale):
    e = EELSCLEdge(name, GOS="dft", gos_file_path=ARGS.gosh)
    e.set_microscope_parameters(E0=mic[0], alpha=mic[1], beta=mic[2], energy_scale=scale)
    return e


def make_case(name, edges, off, scale, n, mic, a_true, r_true, intensity, noisy, low_loss=None, strength=0.35):
    """edges: exSpy shell names in model order (twins included). `intensity[element]` per pixel for each master (last name of an element)."""
    E = off + scale * np.arange(n)
    ny, nx = NY, NX
    masters = []
    for nme in sorted(edges):
        el = nme.split("_")[0]
        if nme == sorted(x for x in edges if x.startswith(el + "_"))[-1]:
            masters.append(nme)
    funcs = {nme: edge_function(nme, mic, scale) for nme in edges}
    data = np.zeros((ny, nx, n))
    for i in range(ny):
        for j in range(nx):
            p = i * nx + j
            bg = a_true[p] * E ** -r_true[p] * scale
            ed = np.zeros(n)
            for nme in edges:
                el = nme.split("_")[0]
                master = [m for m in masters if m.startswith(el + "_")][0]
                f = funcs[nme].function(E)
                ed += intensity[master][p] * f * (1.0 if low_loss is None else 1.0)
            if low_loss is None:
                ed = ed * scale
            else:
                ll = low_loss[i, j]
                nll = ll.size
                # np.convolve(ll, f(conv axis), "valid") * scale, with exSpy's convolution axis
                size = n + nll - 1
                j0 = int(round(-LL_OFF / scale))
                offset_index = nll - j0 - 1
                conv_axis = np.linspace(off - offset_index * scale, off + scale * (size - 1 - offset_index), size)
                fc = np.zeros(size)
                for nme in edges:
                    el = nme.split("_")[0]
                    master = [m for m in masters if m.startswith(el + "_")][0]
                    fc += intensity[master][p] * funcs[nme].function(conv_axis)
                ed = np.convolve(ll, fc, mode="valid") * scale
            y = bg + ed
            data[i, j] = RNG.poisson(y) if noisy else y
    return E, masters, data


def exspy_model(data, off, scale, mic, edges, ll_data, ll_off):
    s = exspy.signals.EELSSpectrum(np.array(data))
    ax = s.axes_manager.signal_axes[0]
    ax.offset, ax.scale, ax.units, ax.is_binned = off, scale, "eV", True
    s.set_microscope_parameters(beam_energy=mic[0], convergence_angle=mic[1], collection_angle=mic[2])
    ll = None
    if ll_data is not None:
        ll = exspy.signals.EELSSpectrum(np.array(ll_data))
        la = ll.axes_manager.signal_axes[0]
        la.offset, la.scale, la.units, la.is_binned = ll_off, scale, "eV", True
    m = s.create_model(low_loss=ll, auto_background=True, auto_add_edges=False, GOS="dft", gos_file_path=ARGS.gosh)
    by_el = {}
    for nme in edges:
        by_el.setdefault(nme.split("_")[0], []).append(nme)
    for el, shells in by_el.items():
        m._add_edges_from_subshells_names(list(shells))
    return s, m


def maps(m):
    pl = m[0]
    return np.asarray(pl.A.map["values"], dtype=float).reshape(-1), np.asarray(pl.r.map["values"], dtype=float).reshape(-1)


CASES = {}
LL_OFF = -20.0
LL_N = 120


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
            out[i, j] = 1e6 * ((1 - t) * zlp + t * pl)
    return out


def run_case(name, edges, off, scale, n, mic, noisy, conv=False, bg_scale=1.0):
    E = off + scale * np.arange(n)
    p = NX * NY
    r_true = 2.6 + 0.15 * np.arange(p)
    a_true = bg_scale * 6e3 * E[0] ** r_true * (1 + 0.1 * np.arange(p)) / scale        # about 6e3 counts per channel at the first channel
    inten = {}
    masters = sorted({nme for nme in edges if nme == sorted(x for x in edges if x.startswith(nme.split("_")[0] + "_"))[-1]})
    ll = lowloss_image(scale) if conv else None
    for k, mnm in enumerate(masters):
        inten[mnm] = (1.0 + 0.2 * np.arange(p)) * (2.0 if k == 0 else 1.2) * 4e-1 * (1.0 if conv else 1e6)
    E, masters, data = make_case(name, edges, off, scale, n, mic, a_true, r_true, inten, noisy, ll)
    s, m = exspy_model(data, off, scale, mic, edges, ll, LL_OFF)
    rec = {"edges": list(edges), "masters": masters, "microscope": list(mic), "nx": NX, "ny": NY, "noisy": noisy, "convolved": conv,
           "axis": {"offsetEV": off, "scaleEV": scale, "size": n},
           "truth": {"A": jl(a_true), "r": jl(r_true), "intensity": {k: jl(v) for k, v in inten.items()}},
           "coreFile": write("%s-core" % name, data)}
    if conv:
        rec["lowLossFile"] = write("%s-ll" % name, ll)
        rec["lowLossAxis"] = {"offsetEV": LL_OFF, "scaleEV": scale, "size": LL_N}
    m.two_area_background_estimation()
    A, r = maps(m)
    rec["twoArea"] = {"A": jl(A), "r": jl(r)}
    with contextlib.redirect_stdout(io.StringIO()):
        m.fit_background(only_current=False, show_progressbar=False) if False else None
    m.fit_background(only_current=False)
    A, r = maps(m)
    first = min(e.onset_energy.value for e in m.edges)
    rec["fitBackground"] = {"A": jl(A), "r": jl(r), "stopEV": first - 2.0}
    m.multifit(kind="smart", show_progressbar=False)
    A, r = maps(m)
    masters_in_model = [e for e in m.edges if e.intensity.twin is None]
    rec["smart"] = {"A": jl(A), "r": jl(r), "order": [e.name for e in masters_in_model],
                    "intensity": {e.name: jl(np.asarray(e.intensity.map["values"], dtype=float).reshape(-1)) for e in masters_in_model}}
    # `as_signal()` leaves the channels the last fit stage did not use at 0, so the curve is evaluated pixel by pixel over the whole axis
    curve = np.zeros((NY, NX, n))
    for i in range(NY):
        for j in range(NX):
            m.axes_manager.indices = (j, i)
            curve[i, j] = m._get_current_data(onlyactive=True, ignore_channel_switches=True)
    rec["smart"]["curveFile"] = write("%s-curve" % name, curve)
    m.axes_manager.indices = (0, 0)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        m.quantify()
    rec["quantifyText"] = buf.getvalue()
    CASES[name] = rec


run_case("fel-exact", ["Fe_L2", "Fe_L3"], 600.0, 0.5, 600, (200.0, 10.0, 20.0), noisy=False)
run_case("fel", ["Fe_L2", "Fe_L3"], 600.0, 0.5, 600, (200.0, 10.0, 20.0), noisy=True)
run_case("cno", ["C_K", "N_K", "O_K"], 200.0, 0.5, 700, (300.0, 0.0, 30.0), noisy=True)
run_case("fecu", ["Fe_L2", "Fe_L3", "Cu_L2", "Cu_L3"], 600.0, 0.5, 1400, (200.0, 10.0, 20.0), noisy=True)
run_case("fel-conv", ["Fe_L2", "Fe_L3"], 600.0, 0.5, 600, (200.0, 10.0, 20.0), noisy=True, conv=True)

pins = {"environment": {"hyperspy": hyperspy.__version__, "exspy": exspy.__version__, "numpy": np.__version__,
                        "script": hashlib.sha256(open(__file__, "rb").read()).hexdigest()},
        "files": FILES, "cases": CASES}
with open(os.path.join(OUT, "eels16-model-pins.json"), "w") as f:
    json.dump(pins, f, sort_keys=True, indent=1)
    f.write("\n")
print("wrote", len(FILES), "arrays")
