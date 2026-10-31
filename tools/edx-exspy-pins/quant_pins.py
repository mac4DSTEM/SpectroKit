# Generates eds-quant-pins-exspy-7185a4d1.json: eXSpy `EDSTEMSpectrum.quantification` (Cliff-Lorimer and zeta-factor,
# with and without the thin-film absorption correction) on eXSpy's own FePt example and on synthetic intensity sets.
# Every number in the fixture is eXSpy's output; nothing is computed by the Swift side's formulas.
# Usage: PYTHONPATH=References/exspy-7185a4d1 References/python/bin/python -B tools/edx-exspy-pins/quant_pins.py Tests/SpectroEDXTests/Fixtures/eds-quant-pins-exspy-7185a4d1.json
import warnings; warnings.filterwarnings("ignore")
import sys, json, logging, numpy as np, exspy, hyperspy.api as hs
from exspy.signals import EDSTEMSpectrum
import exspy.signals._eds_tem as eds_tem_module

# eXSpy logs "Convergence reached after N interations" at INFO; capture N.
class _Grab(logging.Handler):
    def __init__(self): super().__init__(); self.n = None
    def emit(self, rec):
        msg = rec.getMessage()
        if msg.startswith("Convergence reached after"): self.n = int(msg.split()[3])
_grab = _Grab()
eds_tem_module._logger.addHandler(_grab); eds_tem_module._logger.setLevel(logging.INFO)

MIN_INTENSITY = 0.1   # eXSpy _quantification.py: the denominator floor

def make_intensities(s, values):
    """List of 1-element signals carrying `values` and eXSpy's own xray_lines metadata (alphabetical, as get_lines_intensity)."""
    r = s.get_lines_intensity()
    assert len(r) == len(values)
    for sig, v in zip(r, values): sig.data[:] = v
    return r

def quant(s, intensities, method, factors, units, absorption, thickness=None, convergence=0.5, max_iterations=30):
    _grab.n = None
    kw = dict(composition_units=units, absorption_correction=absorption, convergence_criterion=convergence,
              max_iterations=max_iterations, show_progressbar=False)
    if method == "CL" and absorption: kw["thickness"] = float(thickness)
    res = s.quantification(intensities, method, factors, **kw)
    if method == "zeta" or (method == "CL" and absorption):
        comp, mt = res; mt = float(np.asarray(mt.data).ravel()[0])
    else:
        comp, mt = res, None
    return [float(c.data.ravel()[0]) for c in comp], mt, _grab.n

def run(s, intensities, method, factors, absorption, thickness=None, label=""):
    out = {"method": method, "factors": [float(f) for f in factors], "absorption": absorption, "label": label}
    if method == "CL" and absorption: out["thicknessNm"] = float(thickness)
    if method == "zeta":
        tem = s.metadata.Acquisition_instrument.TEM
        out["beamCurrentNA"] = float(tem.beam_current); out["liveTimeS"] = float(tem.Detector.EDS.live_time)
        out["dose"] = float(s._get_dose("zeta", "auto", "auto"))
    try:
        w, mt, it = quant(s, intensities, method, factors, "weight", absorption, thickness)
        a, mt2, _ = quant(s, intensities, method, factors, "atomic", absorption, thickness)
        out.update(weightPercent=w, atomicPercent=a, massThickness=mt, iterations=it)
        if absorption:   # the fixed point eXSpy's loop approaches, for the tolerance derivation
            fw, fmt, fit = quant(s, intensities, method, factors, "weight", absorption, thickness, 1e-10, 500)
            out.update(fixedPointWeightPercent=fw, fixedPointMassThickness=fmt, fixedPointIterations=fit)
    except Exception as e:
        out.update(exspyError=str(e)[:200])
    return out

def synthetic_signal(beam_current, live_time, elements, lines):
    s = EDSTEMSpectrum(np.zeros(1024))
    ax = s.axes_manager.signal_axes[0]; ax.scale = 1e-2; ax.units = "keV"; ax.name = "Energy"
    s.set_microscope_parameters(beam_energy=200, live_time=live_time, tilt_stage=0.0, azimuth_angle=0,
                                elevation_angle=35, energy_resolution_MnKa=130, beam_current=beam_current)
    s.set_elements(elements); s.add_lines(lines)
    return s

def lines_of(s): return list(s.metadata.Sample.xray_lines)
def case_header(name, source, s, lines, values):
    return {"name": name, "source": source, "lines": lines, "elements": [l.split("_")[0] for l in lines],
            "lineEnergiesKeV": [float(s._get_line_energy(l)) for l in lines], "intensities": [float(v) for v in values],
            "takeOffDegrees": float(s.get_take_off_angle()), "runs": []}

out = {"generator": "tools/edx-exspy-pins/quant_pins.py; exspy 7185a4d1 (2026-10-02), hyperspy 2.4.0, rosettasciio 0.14.0",
       "minIntensity": MIN_INTENSITY, "cases": []}

# (a) eXSpy's own FePt nanoparticles, k-factors from exspy/doc/user_guide/eds.rst:708 ("kfactors = [1.450226, 5.075602] #For Fe Ka and Pt La"),
#     background-subtracted windows line_width=[5.0, 2.0] exactly as eds.rst:709-711. The documentation gives no zeta-factors for this
#     specimen: the zeta runs take the docstring example zfactors = [628.10, 539.89] (exspy/utils/eds/_quantification.py, quantification_zeta_factor)
#     and the dose parameters eds.rst:733-736 names (beam_current=0.5 nA, 1.5 s) and exspy/tests/signals/test_eds_tem.py:172-179 (0.05 nA, 2.5 s).
for tag, use_bw in [("fept_bw5_2", True), ("fept_raw", False)]:
    s = exspy.data.EDS_TEM_FePt_nanoparticles(); s.add_lines()
    lines = lines_of(s)
    if use_bw:
        bw = s.estimate_background_windows(line_width=[5.0, 2.0]); ints = s.get_lines_intensity(background_windows=bw)
    else:
        ints = s.get_lines_intensity()
    vals = [float(i.data[0]) for i in ints]
    c = case_header(tag, "EDS_TEM_FePt_nanoparticles" + (", background_windows line_width=[5,2]" if use_bw else ", default windows"), s, lines, vals)
    k = [1.450226, 5.075602]
    c["runs"].append(run(s, ints, "CL", k, False, label="doc k-factors"))
    if use_bw:
        for t in (50.0, 200.0): c["runs"].append(run(s, ints, "CL", k, True, t, label=f"CL absorption {t} nm"))
        z = [628.10, 539.89]
        s.set_microscope_parameters(beam_current=0.5, live_time=1.5)
        c["runs"].append(run(s, ints, "zeta", z, False, label="doc dose 0.5 nA 1.5 s"))
        c["runs"].append(run(s, ints, "zeta", z, True, label="doc dose 0.5 nA 1.5 s"))
        s.set_microscope_parameters(beam_current=0.05, live_time=2.5)
        c["runs"].append(run(s, ints, "zeta", z, False, label="test dose 0.05 nA 2.5 s"))
        c["runs"].append(run(s, ints, "zeta", z, True, label="test dose 0.05 nA 2.5 s"))
    out["cases"].append(c)

# (b) synthetic intensity sets. k: Al/Cr/Ni from the CL docstring ([1, 1.47, 1.72] for Al_Ka, Cr_Ka, Ni_Ka); Al/Zn from test_eds_tem.py's
#     own derived value; the Fe entry and zeta values are arbitrary but fixed (the pin is the arithmetic, not the physics of the numbers).
def synth(name, els, lines, vals, k, z, cl_abs=(100.0,), zeta_abs=True):
    s = synthetic_signal(0.05, 2.5, els, lines); L = lines_of(s); assert L == lines, (L, lines)
    ints = make_intensities(s, vals)
    c = case_header(name, "synthetic", s, L, vals)
    c["runs"].append(run(s, ints, "CL", k, False))
    for t in cl_abs: c["runs"].append(run(s, ints, "CL", k, True, t, label=f"CL absorption {t} nm"))
    c["runs"].append(run(s, ints, "zeta", z, False))
    if zeta_abs: c["runs"].append(run(s, ints, "zeta", z, True))
    out["cases"].append(c)

synth("synth2_AlZn", ["Al", "Zn"], ["Al_Ka", "Zn_Ka"], [12000.0, 8000.0], [1.0, 2.0009344042484134], [20.0, 50.0], (1.0, 300.0))
synth("synth3_AlCrNi", ["Al", "Cr", "Ni"], ["Al_Ka", "Cr_Ka", "Ni_Ka"], [9000.0, 4000.0, 15000.0], [1.0, 1.47, 1.72], [20.0, 35.0, 50.0], (100.0, 400.0))
synth("synth4_AlCrFeNi", ["Al", "Cr", "Fe", "Ni"], ["Al_Ka", "Cr_Ka", "Fe_Ka", "Ni_Ka"], [9000.0, 4000.0, 7000.0, 15000.0],
      [1.0, 1.47, 1.35, 1.72], [20.0, 35.0, 42.0, 50.0], (100.0, 400.0))
# near-zero intensity: first element below the 0.1 floor (the reference line moves), first element just above it, one element at 0.
synth("nearzero_first_below_floor", ["Al", "Cr", "Ni"], ["Al_Ka", "Cr_Ka", "Ni_Ka"], [0.05, 5000.0, 8000.0], [1.0, 1.47, 1.72], [20.0, 35.0, 50.0], (100.0,))
synth("nearzero_first_above_floor", ["Al", "Cr", "Ni"], ["Al_Ka", "Cr_Ka", "Ni_Ka"], [0.11, 5000.0, 8000.0], [1.0, 1.47, 1.72], [20.0, 35.0, 50.0], (100.0,))
synth("nearzero_middle_zero", ["Al", "Cr", "Ni"], ["Al_Ka", "Cr_Ka", "Ni_Ka"], [6000.0, 0.0, 8000.0], [1.0, 1.47, 1.72], [20.0, 35.0, 50.0], (100.0,))
# one line above the floor: eXSpy reports 100 % of it (our DEVIATION: refusal, parity switch .exspyHundredPercent); none above: all zeros.
synth("single_line_above_floor", ["Al", "Zn"], ["Al_Ka", "Zn_Ka"], [0.05, 8000.0], [1.0, 2.0009344042484134], [20.0, 50.0], (), False)
synth("no_line_above_floor", ["Al", "Zn"], ["Al_Ka", "Zn_Ka"], [0.05, 0.02], [1.0, 2.0009344042484134], [20.0, 50.0], (), False)

# Where eXSpy's SIGNED convergence maximum stops one or more iterations before the absolute largest change would (found by a seeded random
# search over 3- and 4-element sets; the changes of a normalised composition sum to zero, so the two differ only with >= 3 elements).
synth("criterion_split_3el", ["Cu", "Mg", "Ni"], ["Cu_Ka", "Mg_Ka", "Ni_Ka"], [8778.0, 12544.0, 9366.0], [0.923, 0.905, 1.179], [20.0, 30.0, 45.0], (100.0,))
synth("criterion_split_4el", ["Al", "Fe", "Ni", "Zn"], ["Al_Ka", "Fe_Ka", "Ni_Ka", "Zn_Ka"], [29303.0, 6073.0, 1337.0, 1295.0],
      [1.812, 2.046, 1.868, 2.063], [20.0, 42.0, 50.0, 60.0], (600.0,))

json.dump(out, open(sys.argv[1] if len(sys.argv) > 1 else "quant_pins.json", "w"), indent=1)
for c in out["cases"]:
    print(c["name"], c["lines"], c["intensities"])
    for r in c["runs"]:
        print("  ", r["method"], "abs" if r["absorption"] else "   ", r.get("label", ""), r.get("exspyError", ""), r.get("weightPercent"),
              "it", r.get("iterations"), "fix", r.get("fixedPointIterations"), "mt", r.get("massThickness"))
