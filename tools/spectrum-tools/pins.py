#!/usr/bin/env python3
"""Pins for SpectroKit 0.10.0 spectrum tools: line-profile pooling and display smoothing.

Two parts, each run by the venv that has its reference (versions are asserted):

    References/python/bin/python -I -B tools/spectrum-tools/pins.py --part lineprofile   # scikit-image 0.26.0, SciPy 1.18.1, NumPy 2.5.4
    References/python/bin/python -I -B tools/spectrum-tools/pins.py --part smoothing    # HyperSpy 2.4.0, SciPy 1.18.1, NumPy 2.5.4

Writes (default --out Tests/SpectroCoreTests/Fixtures/), floats as Python reprs (they round-trip exactly):

    spectrum-tools-lineprofile-pins.json
        cube        ny, nx, channels, counts (flat, row-major pixels, channel fastest): the spectra encode their own pixel
                    position (channel 0 = row, 1 = column, 2 = row * column, 3 = row * nx + column, 4 = (7 row + 3 column) mod 11)
        hardVsSkimage      skimage.measure.profile_line(order=0, linewidth=w, reduce_func=np.mean / np.sum) per channel on lines where
                           the geometries coincide (axis-parallel, pixel-centre steps, odd w on a pixel line or even w on a
                           half-pixel line): src, dst, width, mean[step][channel], sum[step][channel]
        bilinearVsSkimage  profile_line(order=1, linewidth=w) on oblique lines inside the image; spacing = length / (n - 1)
                           with n = ceil(length + 1), as profile_line steps
        hardNumpy          a NumPy transcription of the kit's hard geometry (polylines, fractional points, width 2.5, spacing 1.7,
                           a path leaving the grid): path, width, spacing, arcLengths, counts[step], mean[step][channel]
    spectrum-tools-smoothing-pins.json
        spectra     the inputs (seeded noisy peaks, length 150 and 61)
        savgol      scipy.signal.savgol_filter(x, w, p, mode) for mode interp, mirror, nearest, constant, wrap
        hyperspySavgol   the same for mode interp through hyperspy Signal1D.smooth_savitzky_golay (axis scale 0.5)
        gaussian    scipy.ndimage.gaussian_filter1d(x, sigma, truncate=4, mode)
        uniform     scipy.ndimage.uniform_filter1d(x, size, mode)

Deterministic: default_rng(20261022), no other randomness.
"""
import argparse
import hashlib
import json
import math
import os
import platform
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--part", choices=["lineprofile", "smoothing"], required=True)
ap.add_argument("--out", default=os.path.join(REPO, "Tests", "SpectroCoreTests", "Fixtures"))
ARGS = ap.parse_args()
os.makedirs(ARGS.out, exist_ok=True)
warnings.simplefilter("ignore")

import numpy as np   # noqa: E402
import scipy         # noqa: E402

assert np.__version__ == "2.5.4" and scipy.__version__ == "1.18.1", (np.__version__, scipy.__version__)
RNG = np.random.default_rng(20261022)
SELF_SHA = hashlib.sha256(open(os.path.abspath(__file__), "rb").read()).hexdigest()


def L(a):
    return np.asarray(a, dtype=np.float64).tolist()


def dump(name, env, body):
    body["environment"] = dict(env, python=platform.python_version(), numpy=np.__version__, scipy=scipy.__version__,
                               script_sha256=SELF_SHA,
                               command="python -I -B tools/spectrum-tools/pins.py --part %s" % ARGS.part)
    with open(os.path.join(ARGS.out, name), "w") as f:
        json.dump(body, f, indent=1, sort_keys=True)
        f.write("\n")


if ARGS.part == "lineprofile":
    import skimage
    from skimage.measure import profile_line
    assert skimage.__version__ == "0.26.0", skimage.__version__

    NY, NX, CH = 20, 24, 5
    cube = np.zeros((NY, NX, CH))
    for r in range(NY):
        for c in range(NX):
            cube[r, c] = [r, c, r * c, r * NX + c, (7 * r + 3 * c) % 11]

    def skim(src, dst, w, order):
        mean = np.stack([profile_line(cube[:, :, k], src, dst, linewidth=w, order=order, mode="reflect",
                                      reduce_func=np.mean) for k in range(CH)], axis=1)
        tot = np.stack([profile_line(cube[:, :, k], src, dst, linewidth=w, order=order, mode="reflect",
                                     reduce_func=np.sum) for k in range(CH)], axis=1)
        return mean, tot

    hard = []
    for src, dst, w in [((3, 5), (16, 5), 1), ((3, 5), (16, 5), 3), ((3, 9), (16, 9), 5), ((7, 2), (7, 20), 3),
                        ((7, 20), (7, 2), 3), ((7.5, 2), (7.5, 20), 2), ((7.5, 2), (7.5, 20), 4),
                        ((2, 10.5), (14, 10.5), 2), ((2, 10.5), (14, 10.5), 6)]:
        m, s = skim(src, dst, w, 0)
        hard.append(dict(src=list(src), dst=list(dst), width=w, mean=L(m), sum=L(s)))

    bil = []
    for src, dst, w in [((3.2, 2.5), (14.7, 19.1), 1), ((3.2, 2.5), (14.7, 19.1), 3), ((12.4, 4.1), (6.3, 21.6), 4),
                        ((5.0, 3.0), (15.0, 17.0), 5), ((14.5, 20.2), (4.1, 3.3), 2)]:
        length = math.hypot(dst[0] - src[0], dst[1] - src[1])
        n = int(math.ceil(length + 1))
        m, s = skim(src, dst, w, 1)
        assert m.shape[0] == n
        bil.append(dict(src=list(src), dst=list(dst), width=w, spacing=length / (n - 1), steps=n, mean=L(m), sum=L(s)))

    def hard_numpy(path, width, spacing):
        """The kit's hard geometry, vectorised over pixels (see SpectrumLineProfile.swift)."""
        pts = [path[0]] + [p for i, p in enumerate(path[1:]) if p != path[i]]
        segs, cum = [], 0.0
        for a, b in zip(pts[:-1], pts[1:]):
            d = np.array(b, float) - np.array(a, float)
            ln = float(np.hypot(*d))
            segs.append((np.array(a, float), d / ln, ln, cum))
            cum += ln
        nsteps = int(math.floor(cum / spacing + 1e-9)) + 1
        rr, cc = np.meshgrid(np.arange(NY), np.arange(NX), indexing="ij")
        q = np.stack([rr.ravel(), cc.ravel()], axis=1).astype(float)
        best_d2 = np.full(len(q), np.inf)
        best = np.zeros(len(q), int)
        best_t = np.zeros(len(q))
        best_raw = np.zeros(len(q))
        for i, (a, u, ln, st) in enumerate(segs):
            dq = q - a
            raw = dq @ u
            t = np.clip(raw, 0, ln)
            f = dq - np.outer(t, u)
            d2 = (f * f).sum(axis=1)
            better = d2 < best_d2 - 1e-12
            best = np.where(better, i, best)
            best_t = np.where(better, t, best_t)
            best_raw = np.where(better, raw, best_raw)
            best_d2 = np.where(better, d2, best_d2)
        ok = np.ones(len(q), bool)
        ok &= ~((best == 0) & (best_raw < 0))
        ok &= ~((best == len(segs) - 1) & (best_raw > segs[-1][2]))
        starts = np.array([s[3] for s in segs])
        us = np.array([s[1] for s in segs])
        a0 = np.array([s[0] for s in segs])
        cross = us[best, 0] * (q[:, 1] - a0[best, 1]) - us[best, 1] * (q[:, 0] - a0[best, 0])
        sd = np.where(cross < 0, -1, 1) * np.sqrt(best_d2)
        half = width / 2
        ok &= (sd >= -half - 1e-9) & (sd < half - 1e-9)
        s = starts[best] + best_t
        k = np.floor(s / spacing + 0.5 + 1e-9).astype(int)
        ok &= k < nsteps
        counts = np.zeros(nsteps, int)
        tot = np.zeros((nsteps, CH))
        flat = cube.reshape(-1, CH)
        for idx in np.nonzero(ok)[0]:
            counts[k[idx]] += 1
            tot[k[idx]] += flat[idx]
        mean = np.where(counts[:, None] > 0, tot / np.maximum(counts, 1)[:, None], 0.0)
        return dict(path=[list(p) for p in path], width=width, spacing=spacing,
                    arcLengths=L(np.arange(nsteps) * spacing), counts=counts.tolist(), mean=L(mean), sum=L(tot))

    hn = [hard_numpy([(2.0, 3.0), (15.0, 20.0)], 3.0, 1.0),
          hard_numpy([(2.3, 3.7), (9.1, 8.2), (16.4, 20.6)], 2.5, 1.7),
          hard_numpy([(4.0, 2.0), (4.0, 12.0), (14.0, 12.0)], 4.0, 1.0),
          hard_numpy([(10.0, -4.0), (10.0, 30.0)], 5.0, 2.0),
          hard_numpy([(18.5, 21.5), (1.2, 2.2)], 1.5, 0.8)]
    dump("spectrum-tools-lineprofile-pins.json", dict(skimage=skimage.__version__),
         dict(cube=dict(ny=NY, nx=NX, channels=CH, counts=[int(v) for v in cube.ravel()]),
              hardVsSkimage=hard, bilinearVsSkimage=bil, hardNumpy=hn))

else:
    import hyperspy
    from hyperspy._signals.signal1d import Signal1D
    from scipy.signal import savgol_filter
    from scipy.ndimage import gaussian_filter1d, uniform_filter1d
    assert hyperspy.__version__ == "2.4.0", hyperspy.__version__

    def spec(n, peaks):
        x = np.arange(n, dtype=float)
        y = 20 + 0.05 * x
        for c, h, w in peaks:
            y = y + h * np.exp(-0.5 * ((x - c) / w) ** 2)
        return np.round(y + RNG.normal(0, 2.0, n), 6)

    s150 = spec(150, [(40, 300, 3.0), (95, 120, 5.0)])
    s61 = spec(61, [(30, 80, 2.0)])
    spectra = [s150, s61]
    modes = ["interp", "mirror", "nearest", "constant", "wrap"]
    sg = []
    for si, s in enumerate(spectra):
        for w, p in [(5, 2), (9, 3), (11, 2), (21, 4), (15, 1), (3, 2)]:
            for mode in modes:
                sg.append(dict(spectrum=si, window=w, order=p, mode=mode, out=L(savgol_filter(s, w, p, mode=mode))))
    hs_out = []
    for si, s in enumerate(spectra):
        for w, p in [(5, 2), (9, 3), (21, 4)]:
            sig = Signal1D(np.stack([s, s[::-1]]))
            sig.axes_manager.signal_axes[0].scale = 0.5
            sig.smooth_savitzky_golay(polynomial_order=p, window_length=w, differential_order=0)
            hs_out.append(dict(spectrum=si, window=w, order=p, out=L(sig.data[0]), outReversed=L(sig.data[1])))
    ga = []
    for si, s in enumerate(spectra):
        for sigma in [0.7, 2.3, 5.0]:
            for mode in ["reflect", "constant", "nearest", "mirror", "wrap"]:
                ga.append(dict(spectrum=si, sigma=sigma, truncate=4.0, mode=mode,
                               out=L(gaussian_filter1d(s, sigma, truncate=4.0, mode=mode))))
    un = []
    for si, s in enumerate(spectra):
        for size in [1, 3, 4, 7, 8]:
            for mode in ["reflect", "constant", "nearest", "mirror", "wrap"]:
                un.append(dict(spectrum=si, size=size, mode=mode, out=L(uniform_filter1d(s, size, mode=mode))))
    dump("spectrum-tools-smoothing-pins.json", dict(hyperspy=hyperspy.__version__),
         dict(spectra=[L(s) for s in spectra], savgol=sg, hyperspySavgol=hs_out, gaussian=ga, uniform=un))
