"""Gate B refuter, 2026-10-14: generator of the refuter cases (synthetic low-loss images and exSpy 7185a4d1 / HyperSpy 2.4.0 answers).
Credit: the Gate B refuter of EELS slice 1. Copied unchanged except this header and the output/root paths. The committed regression
fixtures (Tests/SpectroEELSTests/Fixtures/refuter/) are cases of its output: B1_negative_counts, B3_flat_and_ramp, B5_ramps (this script, seed 777001).
Run: References/python/bin/python -I -B tools/eels-thickness/refuter_cases.py OUTDIR
"""
import sys, os, json, math, contextlib, logging, warnings
import pathlib; S = str(pathlib.Path(__file__).resolve().parents[2])
sys.path.insert(0, S + "/References/exspy-7185a4d1")
logging.disable(logging.CRITICAL); warnings.simplefilter("ignore")
import numpy as np
with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
    import hyperspy.api as hs
    from exspy.signals import EELSSpectrum
    from exspy.utils.eels import iMFP_Iakoubovskii, iMFP_angular_correction
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)

@contextlib.contextmanager
def quiet():
    with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
        yield

def build(data, rows, cols, offset, scale, size, binned=True):
    data = np.asarray(data, float)
    if rows == 1 and False: pass
    if rows == 1:
        shape = (cols, size)
        axes = [dict(size=cols, navigate=True, name="x"), dict(size=size, offset=offset, scale=scale, units="eV", name="E", navigate=False, is_binned=binned)]
    elif cols == 1:
        shape = (rows, size)
        axes = [dict(size=rows, navigate=True, name="y"), dict(size=size, offset=offset, scale=scale, units="eV", name="E", navigate=False, is_binned=binned)]
    else:
        shape = (rows, cols, size)
        axes = [dict(size=rows, navigate=True, name="y"), dict(size=cols, navigate=True, name="x"), dict(size=size, offset=offset, scale=scale, units="eV", name="E", navigate=False, is_binned=binned)]
    with quiet():
        return EELSSpectrum(data.reshape(shape).copy(), axes=axes)

def nav_signal(s, vals):
    vals = np.asarray(vals, float)
    with quiet():
        t = s._get_navigation_signal().transpose(signal_axes=0)
        t.data[:] = vals.reshape(t.data.shape)
        t.set_signal_type("")
    return t

def drude(E, Ep, G):
    E = np.asarray(E, float); out = np.zeros_like(E); m = E > 0
    out[m] = E[m]*G*Ep**2/((E[m]**2-Ep**2)**2+(E[m]*G)**2); return out

def synth(rng, rows, cols, offset, scale, size, tau, N, zlp_centre, zlp_sigma, Ep=15.0, G=3.0, noise=None, extra_bg=0.0):
    E = offset + scale*np.arange(size)
    out = np.zeros((rows*cols, size))
    for p in range(rows*cols):
        c = zlp_centre[p] if hasattr(zlp_centre, "__len__") else zlp_centre
        z = np.exp(-0.5*((E-c)/zlp_sigma)**2); z /= z.sum()
        S1 = drude(E-0.0, Ep, G); S1 /= S1.sum()
        # poisson plural scattering via FFT-free direct convolution on channel grid
        t = tau[p] if hasattr(tau, "__len__") else tau
        tot = np.zeros(size); term = z.copy(); w = math.exp(-t)
        tot += w*term
        for n in range(1, 14):
            term = np.convolve(term, S1)[:size]; w *= t/n; tot += w*term
        spec = N*tot + extra_bg
        if noise == "poisson": spec = rng.poisson(spec).astype(float)
        out[p] = spec
    return out

cases = []
rng = np.random.default_rng(777001)
def add(name, rows, cols, offset, scale, size, data, routes, binned=True, zlp=None, note=""):
    cases.append(dict(name=name, rows=rows, cols=cols, offset=offset, scale=scale, size=size, data=np.asarray(data, float).reshape(rows*cols, size), routes=routes, zlp=zlp, note=note))

def std_routes(fixed=(2.5, 4.5, 6.0), extra=()):
    r = [dict(kind="estimated")]
    r.append(dict(kind="estimated", windowLength=0))
    r += [dict(kind="fixed", value=v) for v in fixed]
    r += list(extra)
    return r

# (i) ZLP off-centre by fractions / several channels, varied per pixel; unusual axis
rows, cols, size = 3, 4, 2501
offset, scale = -7.3, 0.037
shifts = np.linspace(-0.2, 0.6, rows*cols) + rng.uniform(-0.01, 0.01, rows*cols)
tau = np.linspace(0.2, 2.5, rows*cols)
d = synth(rng, rows, cols, offset, scale, size, tau, 2e5, shifts, 0.22)
add("A1_zlp_shift_frac", rows, cols, offset, scale, size, d,
    std_routes(extra=[dict(kind="estimated", windowLength=7), dict(kind="estimated", windowLength=9, polynomialOrder=4),
                      dict(kind="estimated", start=0.5, window=6.0), dict(kind="estimated", tolerance=0.0),
                      dict(kind="estimated", tolerance=1e9), dict(kind="estimated", tolerance=3.0)]))
# several-channel offset, all at once, poisson noise
shifts2 = rng.uniform(-0.5, 0.9, 6*5)
d = synth(rng, 6, 5, -5.0, 0.05, 999, rng.uniform(0.1, 1.5, 30), 3e3, shifts2, 0.3, noise="poisson")
add("A2_shift_poisson_odd", 6, 5, -5.0, 0.05, 999, d, std_routes(fixed=(1.0, 2.0, 3.3, 7.77)))
# (ii) 1 eV/ch from -20, 301 channels
d = synth(rng, 4, 4, -20.0, 1.0, 301, np.linspace(0.1, 2.0, 16), 1e5, rng.uniform(-0.6, 0.6, 16), 1.5, Ep=15.0, G=6.0, noise="poisson")
add("A3_1eV_per_ch", 4, 4, -20.0, 1.0, 301, d, std_routes(fixed=(2.0, 5.0, 8.0, 3.5, 4.5, 40.0, 200.0, 300.0, 400.0, -25.0, -20.0, -19.6))[:-3] + [dict(kind="fixed", value=v) for v in (400.0, -20.0, -19.6, -19.4)])
# short spectrum: threshold near the end; window beyond the axis end
d = synth(rng, 3, 3, -2.0, 0.5, 40, np.linspace(0.3, 1.0, 9), 1e4, 0.0, 0.8, Ep=9.0, G=3.0)
add("A4_short40", 3, 3, -2.0, 0.5, 40, d,
    [dict(kind="estimated"), dict(kind="estimated", windowLength=0), dict(kind="estimated", window=30.0), dict(kind="estimated", window=4.5),
     dict(kind="estimated", windowLength=5, window=5.0), dict(kind="estimated", windowLength=11, window=6.0), dict(kind="estimated", windowLength=13, window=6.0),
     dict(kind="fixed", value=3.0), dict(kind="fixed", value=17.5), dict(kind="fixed", value=17.6), dict(kind="fixed", value=100.0), dict(kind="fixed", value=-2.0), dict(kind="fixed", value=-2.2)])
# (iii) heavy noise, low counts, zeros, thick
d = synth(rng, 5, 5, -8.0, 0.1, 700, rng.uniform(2.0, 3.0, 25), 300, rng.uniform(-0.1, 0.1, 25), 0.3, Ep=22.0, G=5.0, noise="poisson")
add("A5_lowcount_thick", 5, 5, -8.0, 0.1, 700, d, std_routes(fixed=(1.5, 3.0, 5.0)) + [dict(kind="estimated", windowLength=11), dict(kind="estimated", windowLength=21, polynomialOrder=2)])
# (iv) 1xN, Nx1, 1x1
d = synth(rng, 1, 7, -6.0, 0.08, 800, np.linspace(0.3, 1.8, 7), 5e4, rng.uniform(-0.3, 0.3, 7), 0.25, noise="poisson")
add("A6_1x7", 1, 7, -6.0, 0.08, 800, d, std_routes(fixed=(2.0, 4.0)))
d = synth(rng, 7, 1, -6.0, 0.08, 800, np.linspace(0.3, 1.8, 7), 5e4, rng.uniform(-0.3, 0.3, 7), 0.25, noise="poisson")
add("A7_7x1", 7, 1, -6.0, 0.08, 800, d, std_routes(fixed=(2.0, 4.0)))
d = synth(rng, 1, 1, -6.0, 0.08, 800, [1.1], 5e4, 0.05, 0.25, noise="poisson")
add("A8_1x1", 1, 1, -6.0, 0.08, 800, d, std_routes(fixed=(2.0, 4.0)))
# fragile: negative counts (background subtracted), flat spectrum, ZLP tail already flat at start
d = synth(rng, 3, 3, -10.0, 0.05, 1500, np.linspace(0.3, 1.5, 9), 1e4, 0.0, 0.25, noise="poisson") - 3.0
add("B1_negative_counts", 3, 3, -10.0, 0.05, 1500, d, std_routes(fixed=(3.0,)))
d = np.full((4, 600), 7.0); d[1] += np.arange(600)*0.0
add("B2_flat", 2, 2, -5.0, 0.05, 600, d, std_routes(fixed=(2.0,)))
d = np.full((2, 600), 7.0); d[1] = 7.0 + 0.001*np.arange(600)
add("B3_flat_and_ramp", 1, 2, -5.0, 0.05, 600, d, std_routes(fixed=(2.0,)))
# very wide ZLP so derivative is ~0 at the first search channel (threshold index 0/1 behaviours)
E = -10 + 0.05*np.arange(1500); base = 1e5*np.exp(-0.5*(E/1.5)**2)
d = np.stack([base, base*1.3, base + 1000*drude(E, 15, 3)])
add("B4_wide_zlp", 1, 3, -10.0, 0.05, 1500, d, std_routes(fixed=(2.0,)) + [dict(kind="estimated", start=0.0, window=10.0), dict(kind="estimated", start=0.0, window=0.5), dict(kind="estimated", start=-10.0, window=10.0), dict(kind="estimated", start=30, window=10)])
# monotone ramp up: |d|>tol...; and a spectrum where min |d| at index 1
d = np.stack([np.linspace(0, 1e4, 600)**1.0, 1e4*np.exp(-np.arange(600)/80.0), np.sin(np.arange(600)/9.0)*100+500])
add("B5_ramps", 1, 3, -5.0, 0.05, 600, d, std_routes(fixed=(2.0,)))
# half-channel threshold ties on the fixed route + per-pixel route + zero-loss route
d = synth(rng, 2, 3, -10.0, 0.05, 3400, [0.3, 0.6, 0.9, 1.2, 1.5, 1.8], 1e6, 0.0, 0.25)
fixed = [2.475, 2.425, 2.5, 2.49999999, 2.5000001, 2.45, 2.55, 0.0, -0.025, -10.0, -10.025, -10.0000000001, 159.95, 159.9749, 159.975, 160.0, 160.1, 1e-13, 5.0000000001]
pp = [2.475, 3.0, float("nan"), 4.0123, -10.0, 170.0]
zl = synth(rng, 2, 3, -10.0, 0.05, 3400, [0.0]*6, 1e6, 0.0, 0.25)  # zlp twin-ish (tau 0: pure ZLP)
# zlp with a different channel count
zl2 = zl[:, :1000]
add("C1_ties_perpixel_zlp", 2, 3, -10.0, 0.05, 3400, d,
    [dict(kind="fixed", value=v) for v in fixed] + [dict(kind="perPixel", values=[None if math.isnan(v) else v for v in pp]),
     dict(kind="perPixel", values=[2.475, 3.0, 1.0, 4.0123, 1.0, 100.0]),
     dict(kind="zlp"), dict(kind="zlp", short=True)],
    zlp=dict(data=zl, size=3400, offset=-10.0, scale=0.05, short=zl2))
# the half-channel grid on a different axis (scale 0.1, offset -3.3) tested densely
d = synth(rng, 2, 2, -3.3, 0.1, 500, [0.5, 1.0, 1.5, 2.0], 1e5, 0.1, 0.3)
grid = [round(-3.3 + 0.1*(k+0.5), 12) for k in range(0, 499, 7)] + [round(-3.3+0.1*k, 12) for k in range(0, 500, 11)] + [-3.3 + 0.1*k + 0.05*(1+1e-13) for k in range(10, 400, 37)] + [-3.3 + 0.1*k + 0.05*(1-1e-13) for k in range(10, 400, 37)]
add("C2_halfchannel_grid", 2, 2, -3.3, 0.1, 500, d, [dict(kind="fixed", value=v) for v in grid] + [dict(kind="perPixel", values=[grid[i] for i in (3, 5, 9, 11)]), dict(kind="perPixel", values=[grid[i] for i in (30, 31, 32, 33)])])
# unbinned: the port does not do Simpson; check just that exSpy and port differ only as registered -> skip
# large-ish image for tol global effect + pairwise > 128 blocks with odd sizes
d = synth(rng, 4, 4, -9.1, 0.0333, 4097, rng.uniform(0.1, 2.5, 16), 8e5, rng.uniform(-0.3, 0.3, 16), 0.2, noise="poisson")
add("D1_4097_poisson", 4, 4, -9.1, 0.0333, 4097, d, std_routes(fixed=(2.0, 4.321)))
# even window lengths, polyorder variants
d = synth(rng, 3, 3, -10.0, 0.05, 1500, np.linspace(0.3, 1.5, 9), 1e6, 0.0, 0.25)
add("E1_sg_variants", 3, 3, -10.0, 0.05, 1500, d,
    [dict(kind="estimated", windowLength=w, polynomialOrder=o) for (w, o) in [(4, 3), (6, 3), (7, 3), (9, 3), (3, 3), (5, 1), (5, 2), (5, 4), (5, 5), (3, 2), (2, 1), (1, 0), (201, 3), (200, 3), (-5, 3), (5, 0), (5, -1)]]
    + [dict(kind="estimated", window=0.4), dict(kind="estimated", window=0.45), dict(kind="estimated", window=0.5), dict(kind="estimated", start=0.95, window=0.55), dict(kind="estimated", window=-1.0), dict(kind="estimated", window=0.0)])

def run_route(c, r, s, zlp_sig):
    kind = r["kind"]
    res = {}
    try:
        with quiet():
            if kind == "estimated":
                kw = {}
                for k_py, k in (("window", "window"), ("tol", "tolerance"), ("window_length", "windowLength"), ("polynomial_order", "polynomialOrder"), ("start", "start")):
                    if k in r: kw[k_py] = r[k]
                thr = s.estimate_elastic_scattering_threshold(**kw)
                tvals = np.asarray(thr.data, float).reshape(-1)
                res["thrEV"] = [None if math.isnan(v) else v for v in tvals]
                th = thr
            elif kind == "fixed":
                th = float(r["value"])
            elif kind == "perPixel":
                th = nav_signal(s, [float("nan") if v is None else v for v in r["values"]])
            if kind == "zlp":
                z = zlp_sig["short"] if r.get("short") else zlp_sig["full"]
                ax = s.axes_manager.signal_axes[0]
                i0 = np.asarray(z.integrate1D(ax.index_in_array).data, float)
                tl = np.asarray(s.estimate_thickness(zlp=z).data, float)
                it = np.asarray(s.integrate1D(ax.index_in_array).data, float)
            else:
                ax = s.axes_manager.signal_axes[0]
                it = np.asarray(s.integrate1D(ax.index_in_array).data, float)
                i0 = np.asarray(s.estimate_elastic_scattering_intensity(threshold=th).data, float)
                tl = np.asarray(s.estimate_thickness(threshold=th).data, float)
        f = lambda a: [None if not math.isfinite(v) else float(v) for v in np.asarray(a).reshape(-1)]
        # inf kept apart
        res["i0"] = f(i0); res["it"] = f(it); res["tl"] = f(tl)
        res["tlRaw"] = [("nan" if math.isnan(v) else ("inf" if v > 0 else "-inf") if math.isinf(v) else None) for v in np.asarray(tl).reshape(-1)]
    except Exception as e:
        res["error"] = type(e).__name__ + ": " + str(e)[:200]
    return res

index = []
for c in cases:
    cd = os.path.join(OUT, c["name"]); os.makedirs(cd, exist_ok=True)
    c["data"].astype("<f8").tofile(os.path.join(cd, "data.f64"))
    s = build(c["data"], c["rows"], c["cols"], c["offset"], c["scale"], c["size"])
    zsig = None
    if c["zlp"]:
        z = c["zlp"]
        c["zlp"]["data"].astype("<f8").tofile(os.path.join(cd, "zlp.f64"))
        c["zlp"]["short"].astype("<f8").tofile(os.path.join(cd, "zlp_short.f64"))
        zsig = dict(full=build(z["data"], c["rows"], c["cols"], z["offset"], z["scale"], z["size"]),
                    short=build(z["short"], c["rows"], c["cols"], z["offset"], z["scale"], z["short"].shape[1]))
    exp = []
    for r in c["routes"]:
        exp.append(dict(route=r, exspy=run_route(c, r, s, zsig)))
    spec = dict(name=c["name"], rows=c["rows"], cols=c["cols"], offset=c["offset"], scale=c["scale"], size=c["size"],
                zlpSize=(c["zlp"]["size"] if c["zlp"] else None), zlpShortSize=(c["zlp"]["short"].shape[1] if c["zlp"] else None), routes=c["routes"])
    json.dump(spec, open(os.path.join(cd, "spec.json"), "w"))
    json.dump(exp, open(os.path.join(cd, "exspy.json"), "w"))
    index.append(c["name"])
json.dump(index, open(os.path.join(OUT, "index.json"), "w"))
print("cases", index)

# lambda / angular correction new points
pts = [(45.0, 3.3, 7.0, 4.51), (100.0, 0.5, 45.0, 11.34), (250.0, 22.0, 2.0, 2.33), (200.0, 10.0, 10.0, 2.7), (30.0, 40.0, 40.0, 0.9)]
mf = []
for (e0, a, b, rho) in pts:
    mf.append(dict(e0=e0, alpha=a, beta=b, rho=rho, lam=float(iMFP_Iakoubovskii(electron_energy=e0, density=rho)),
                   corr=float(iMFP_angular_correction(beam_energy=e0, alpha=a, beta=b, density=rho))))
json.dump(mf, open(os.path.join(OUT, "mfp.json"), "w"))
print(mf)
