"""Python side of the benchmark: the same closed-form inputs as Tests/SpectroKitParityTests/BenchmarkQuantificationTests.swift and
Tests/SpectroKitParityTests/BenchmarkThicknessTests.swift, timed with one warm-up and five runs.

    ../refs/hyperspy/bin/python -I -B tools/benchmarks/bench.py OUT_DIR [small,typical]
"""
import json, sys, time, warnings, pathlib
import numpy as np
warnings.filterwarnings("ignore")
import hyperspy.api as hs
import exspy
from exspy.signals import EDSTEMSpectrum, EELSSpectrum

out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
wanted = (sys.argv[2] if len(sys.argv) > 2 else "small,typical").split(",")
Q = {"small": (8, 8), "typical": (256, 256), "large": (1024, 1024)}
T = {"small": (8, 8), "typical": (64, 64), "large": (256, 256)}


def timeit(f):
    f()
    ts = []
    for _ in range(5):
        t0 = time.perf_counter(); f(); ts.append(time.perf_counter() - t0)
    return ts


rows = []
lines = ["Al_Ka", "Cr_Ka", "Ni_Ka"]
base = np.array([300.0, 500.0, 700.0])
for name in wanted:
    if name not in Q: continue
    r, c = Q[name]; n = r * c
    p = np.arange(n, dtype=float)[:, None]; e = np.arange(3, dtype=float)[None, :]
    x = p * 0.6180339887498949 + e * 0.31
    data = (base * (0.4 + 1.2 * (x - np.floor(x)))).T.reshape(3, r, c)
    s = EDSTEMSpectrum(np.ones([r, c, 8]))
    s.axes_manager.signal_axes[0].scale = 1e-2; s.axes_manager.signal_axes[0].units = "keV"
    s.set_microscope_parameters(beam_energy=200, live_time=2.5, tilt_stage=0.0, azimuth_angle=0, elevation_angle=35,
                                energy_resolution_MnKa=130, beam_current=0.05)
    s.axes_manager[0].scale = 0.5; s.axes_manager[1].scale = 0.5
    s.axes_manager[0].units = "nm"; s.axes_manager[1].units = "nm"
    s.set_elements(["Al", "Cr", "Ni"]); s.add_lines(lines)
    ints = []
    for i, ln in enumerate(lines):
        sig = hs.signals.BaseSignal(data[i]).T
        sig.metadata.set_item("Sample.xray_lines", [ln]); sig.metadata.set_item("Sample.elements", [ln[:2]])
        ints.append(sig)
    cases = [
        ("CL", dict(method="CL", factors=[0.982, 1.32, 1.60], navigation_mask=None)),
        ("CL+absorption", dict(method="CL", factors=[0.982, 1.32, 1.60], absorption_correction=True, thickness=80.0, navigation_mask=None)),
        ("zeta", dict(method="zeta", factors=[20, 40, 60])),
        ("zeta+absorption", dict(method="zeta", factors=[20, 40, 60], absorption_correction=True)),
        ("cross_section", dict(method="cross_section", factors=[3, 4, 5])),
    ]
    for label, kw in cases:
        # the Swift side asks for weight percent for CL/zeta and does both conversions; Python converts to atomic by default
        rows.append({"function": f"quantification maps: {label}", "size": name, "pixels": n,
                     "python_s": timeit(lambda kw=kw: s.quantification(ints, composition_units="weight", **kw))})

for name in wanted:
    if name not in T: continue
    ny, nx = T[name]; n = ny * nx; nch = 2048
    E = -5 + 0.05 * np.arange(nch)
    shape = 2e4 * np.exp(-E * E / (2 * 0.36)) + 300 * np.exp(-(E - 15) ** 2 / 50) + 20 * np.exp(-(E - 45) ** 2 / 288)
    pp = np.arange(n) * 0.6180339887498949
    m = 0.5 + (pp - np.floor(pp))
    d = (m[:, None] * shape[None, :]).reshape(ny, nx, nch)
    s = EELSSpectrum(d)
    ax = s.axes_manager.signal_axes[0]; ax.offset = -5; ax.scale = 0.05; ax.units = "eV"
    s.set_microscope_parameters(beam_energy=200, convergence_angle=10, collection_angle=20)
    rows.append({"function": "t/lambda log ratio: fixed 3 eV", "size": name, "pixels": n,
                 "python_s": timeit(lambda: s.estimate_thickness(threshold=3.0))})
    rows.append({"function": "t/lambda log ratio: estimated", "size": name, "pixels": n,
                 "python_s": timeit(lambda: s.estimate_thickness(threshold=s.estimate_elastic_scattering_threshold()))})

(out / "python.json").write_text(json.dumps({"hyperspy": hs.__version__, "exspy": exspy.__version__,
                                              "numpy": np.__version__, "python": sys.version.split()[0], "rows": rows}, indent=1))
print("wrote", out / "python.json")
