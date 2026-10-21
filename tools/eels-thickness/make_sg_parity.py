"""Savitzky-Golay bit-parity fixture: SciPy's own answers, for the port to match bit for bit.

Run (byte-reproducible; SciPy 1.18.1 / NumPy 2.5.4 from ../References/python/hyperspy):
    ../References/python/hyperspy/bin/python -I -B tools/eels-thickness/make_sg_parity.py OUTDIR [big]
writes OUTDIR/sg-parity.json and OUTDIR/sg-parity.f64 (little-endian doubles). Without "big": the committed fixture (< 2 MB).
With "big": the one-off evidence run (a few hundred MB, not committed; the tests read it from $SG_PARITY_BIG_DIR).

HyperSpy 2.4.0's smooth_savitzky_golay(differential_order=1) calls scipy.signal.savgol_filter ONCE on the whole data array
(hyperspy/signal.py _map_all), along the last axis, deriv=1, delta=axis.scale, mode="interp". The edge fits of that call are one
least-squares call with one right-hand side per spectrum, and LAPACK's dgelsd gives different bits for different numbers of
right-hand sides. So the fixture holds IMAGES (a 1-D spectrum, 2-D arrays (pixels, n) and 3-D arrays (ny, nx, n)), each with
SciPy's filter output for the whole image, for window_length in {5,7,9,11,13,21,31,49} x polyorder in {1,2,3,4} x delta in
{0.05, 0.25, 1.0} (all of them on two images, a subset on the others), and scipy.signal.savgol_coeffs for every setting.
Also scipy.ndimage.convolve1d(x, w, mode="constant") for hand-made weight vectors that exercise the symmetric / anti-symmetric /
general paths of SciPy's correlate1d (pairs within and beyond DBL_EPSILON, windows of up to 49 taps).
"""
import sys, os, json
import numpy as np
import scipy
from scipy.signal import savgol_filter, savgol_coeffs
from scipy.ndimage import convolve1d

out = sys.argv[1]; big = len(sys.argv) > 2 and sys.argv[2] == "big"
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(20261014)
ALL = [(wl, po, d) for wl in (5, 7, 9, 11, 13, 21, 31, 49) for po in (1, 2, 3, 4) for d in (0.05, 0.25, 1.0)]
SUBSET = [(5, 3, 0.05), (5, 1, 1.0), (7, 2, 0.25), (11, 4, 1.0), (13, 3, 0.05), (21, 3, 0.25), (21, 1, 0.05), (31, 4, 0.25),
          (49, 2, 1.0), (9, 4, 0.25), (5, 4, 0.05), (11, 2, 0.05)]
FEW = [(5, 3, 0.05), (11, 4, 1.0), (21, 3, 0.25)]

def spectrum(n, k):
    kind = k % 6
    if kind == 0: return rng.normal(size=n) * 100
    if kind == 1:
        e = np.arange(n); return rng.poisson(1000 * np.exp(-0.5 * ((e - n / 3) / (n / 8)) ** 2) + 5).astype(float)
    if kind == 2: return rng.integers(0, 6, n).astype(float)            # small integers: many exact ties in the derivative
    if kind == 3: return 7.0 + 0.001 * np.arange(n) + 0.0 * rng.normal(size=n)
    if kind == 4: return rng.poisson(1e6 * rng.random(n)).astype(float) - 3.0   # large dynamic range, negative values
    return rng.integers(-50, 50, n).astype(float)

def image(ny, nx, n):
    return np.array([spectrum(n, k) for k in range(ny * nx)]).reshape(ny, nx, n)

# (ny, nx, n, array rank handed to scipy, settings)
if not big:
    plan = [(1, 1, 100, 1, ALL), (1, 7, 60, 2, SUBSET), (7, 1, 60, 2, SUBSET), (3, 5, 60, 3, ALL), (4, 6, 60, 3, SUBSET),
            (20, 30, 30, 3, FEW)]
else:
    plan = [(1, 1, 100, 1, ALL)]
    for k in range(40):
        ny, nx = int(rng.integers(1, 26)), int(rng.integers(1, 26))
        rank = 1 if ny * nx == 1 else (2 if ny == 1 or nx == 1 else 3)
        plan.append((ny, nx, int(rng.integers(49, 81)), rank, ALL if k < 12 else SUBSET))
    for (ny, nx) in ((16, 32), (17, 31), (23, 23), (30, 20), (8, 128), (32, 16), (1, 600), (700, 1), (25, 40), (45, 12)):  # 512-ish and 1000-ish pixel counts
        plan.append((ny, nx, 60, 1 if ny * nx == 1 else (2 if ny == 1 or nx == 1 else 3), SUBSET))
    plan.append((350, 400, 30, 3, [(5, 3, 0.05), (21, 3, 0.25)]))     # 140000 pixels: past the 131072 split of the port

blocks = []; pos = 0
def put(a):
    global pos
    a = np.ascontiguousarray(a, dtype="<f8").reshape(-1); blocks.append(a); off = pos; pos += a.size; return off
meta = {"scipy": scipy.__version__, "numpy": np.__version__, "images": [], "coefficients": [], "convolutions": []}
for (wl, po, d) in ALL:
    meta["coefficients"].append({"wl": wl, "po": po, "delta": d, "offset": put(savgol_coeffs(wl, po, deriv=1, delta=d))})
first3d = None
for (ny, nx, n, rank, settings) in plan:
    data = image(ny, nx, n)
    arr = data.reshape(n) if rank == 1 else (data.reshape(ny * nx, n) if rank == 2 else data)
    if rank == 3 and first3d is None: first3d = (data, len(meta["images"]))
    im = {"ny": ny, "nx": nx, "n": n, "rank": rank, "offset": put(data), "settings": []}
    for (wl, po, d) in settings:
        if wl > n: continue                                   # mode='interp' needs window_length <= n
        im["settings"].append({"wl": wl, "po": po, "delta": d, "outOffset": put(savgol_filter(arr, wl, po, deriv=1, delta=d))})
    meta["images"].append(im)

wrng = np.random.default_rng(5)
def sym(h): w = wrng.normal(size=h + 1); return np.concatenate([w[:0:-1], w])
def anti0(h): w = wrng.normal(size=h + 1); return np.concatenate([-w[:0:-1], [0.0], w[1:]])
def antic(h): w = wrng.normal(size=h + 1); return np.concatenate([-w[:0:-1], [w[0]], w[1:]])
def with_pair(h, d, sign):          # (anti)symmetric except one pair off by d (|d| below or above DBL_EPSILON)
    w = anti0(h) if sign < 0 else sym(h); w[0] += d; return w
cases = []
for h in (1, 2, 3, 4, 10, 15, 16, 24):
    cases += [("symmetric", sym(h)), ("antisymmetric zero centre", anti0(h)), ("antisymmetric centre", antic(h)),
              ("symmetric tiny", sym(h) * 1e-17), ("general", wrng.normal(size=2 * h + 1)),
              ("anti pair 1.5e-16", with_pair(h, 1.5e-16, -1)), ("anti pair 3e-16", with_pair(h, 3e-16, -1)),
              ("sym pair 1.5e-16", with_pair(h, 1.5e-16, +1)), ("sym pair 3e-16", with_pair(h, 3e-16, +1))]
data, imi = first3d
for label, w in cases:
    for pix in (0, 1, 2, 5, 9):
        x = data.reshape(-1, data.shape[-1])[pix]
        meta["convolutions"].append({"label": label, "wl": int(w.size), "image": imi, "pixel": pix, "weightsOffset": put(w),
                                     "outOffset": put(convolve1d(x, w, mode="constant"))})
np.concatenate(blocks).astype("<f8").tofile(os.path.join(out, "sg-parity.f64"))
with open(os.path.join(out, "sg-parity.json"), "w") as f: json.dump(meta, f, indent=0, sort_keys=True); f.write("\n")
print("images", len(meta["images"]), "settings", sum(len(i["settings"]) for i in meta["images"]), "convolutions", len(meta["convolutions"]), "doubles", pos)
