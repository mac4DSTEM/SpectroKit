"""Generator of the threshold edge cases (synthetic low-loss images and exSpy 7185a4d1 / HyperSpy 2.4.0 answers).
Credit: an independent review of the thickness port (2026-10-14). Copied unchanged except this header and the output/root paths. The committed regression
fixtures (Tests/SpectroEELSTests/Fixtures/refuter/) are cases of its output: R22, R26, R52, R58 (random cases R00..R59, seed 424242).
Run: References/python/bin/python -I -B tools/eels-thickness/random_cases.py OUTDIR
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


cases=[]
rng = np.random.default_rng(424242)
def add(name, rows, cols, offset, scale, size, data, routes, zlp=None):
    cases.append(dict(name=name, rows=rows, cols=cols, offset=offset, scale=scale, size=size, data=np.asarray(data, float).reshape(rows*cols, size), routes=routes, zlp=zlp))
for k in range(60):
    scale = float(rng.choice([0.02, 0.05, 0.1, 0.25, 0.5]))
    offset = -float(rng.choice([3.0, 5.0, 8.0, 12.0])) * (1 + 0.1*rng.random())
    size = int((abs(offset) + float(rng.uniform(35, 60))) / scale)
    N = float(10 ** rng.uniform(2.3, 5.5)); rows=int(rng.integers(1,5)); cols=int(rng.integers(1,5))
    Ep = float(rng.uniform(10, 25)); tau = rng.uniform(0.05, 2.8, rows*cols)
    noise = "poisson" if k % 4 != 3 else None
    sig = float(max(0.15, 2.0*scale))
    d = synth(rng, rows, cols, offset, scale, size, tau, N, rng.uniform(-0.3, 0.3, rows*cols), sig, Ep=Ep, G=float(rng.uniform(2, 8)), noise=noise)
    if k % 7 == 0: d = np.maximum(d - 2, 0)
    routes=[dict(kind="estimated"), dict(kind="estimated", windowLength=0), dict(kind="estimated", windowLength=7), dict(kind="estimated", windowLength=9, polynomialOrder=2), dict(kind="fixed", value=3.0)]
    add("R%02d"%k, rows, cols, offset, scale, size, d, routes)
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
