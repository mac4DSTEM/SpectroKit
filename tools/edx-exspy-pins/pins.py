# Writes Tests/SpectroCoreTests/Fixtures/eds-pins-exspy-7185a4d1.json from exSpy 7185a4d1 / HyperSpy 2.4.0: the example spectra, line
# windows, intensities, FWHM and index vectors SpectroEDX is compared against.
# Usage: PYTHONPATH=References/exspy-7185a4d1 References/python/bin/python -B tools/edx-exspy-pins/pins.py Tests/SpectroCoreTests/Fixtures/eds-pins-exspy-7185a4d1.json
import warnings; warnings.filterwarnings("ignore")
import sys, json, math, numpy as np, exspy, hyperspy.api as hs
from exspy.utils.eds import get_FWHM_at_Energy
out = {"generator": "tools/edx-exspy-pins/pins.py; exspy 7185a4d1 (2026-10-02), hyperspy 2.4.0", "spectra": {}, "cases": []}
def intens(s, **kw):
    r = s.get_lines_intensity(**kw)
    return [float(x.data[0]) for x in r]
for name in ["EDS_TEM_FePt_nanoparticles", "EDS_SEM_TM002"]:
    s = getattr(exspy.data, name)()
    ax = s.axes_manager.signal_axes[0]
    md = s.metadata.Acquisition_instrument.as_dictionary()
    inst = list(md.values())[0]
    res = inst["Detector"]["EDS"]["energy_resolution_MnKa"]
    beam = inst["beam_energy"]
    out["spectra"][name] = {"offset": ax.offset, "scale": ax.scale, "units": ax.units, "size": ax.size,
        "resolutionMnKa": res, "beamEnergy": beam, "counts": [int(v) for v in s.data]}
    elements = list(s.metadata.Sample.elements)
    s.add_lines()
    lines = list(s.metadata.Sample.xray_lines)
    c = {"spectrum": name, "elements": elements, "lines": lines}
    c["defaultIntensity"] = intens(s)
    iw = s.estimate_integration_windows(); c["integrationWindows"] = [list(map(float, w)) for w in iw]
    for lw in ([2,2],[5,2]):
        bw = s.estimate_background_windows(line_width=lw)
        c[f"bg_{lw[0]}_{lw[1]}"] = {"windows": [list(map(float, w)) for w in bw],
                                    "net": intens(s, background_windows=bw)}
        # per-line merge-free reference: a single line alone
    c["fwhm"] = [float(s._get_line_energy(l, FWHM_MnKa="auto")[1]) for l in lines]
    c["energy"] = [float(s._get_line_energy(l)) for l in lines]
    out["cases"].append(c)
    if name == "EDS_SEM_TM002":
        s2 = getattr(exspy.data, name)(); s2.set_elements(["Mn"]); s2.set_lines(["Mn_Ka"])
        out["tm002_MnKa_2_1"] = intens(s2, integration_windows=2.1)
        bw = s2.estimate_background_windows()
        out["tm002_MnKa_bg"] = {"windows": [list(map(float, w)) for w in bw], "net": intens(s2, background_windows=bw),
                                "plain": intens(s2)}
# FWHM law
out["fwhm"] = [{"res": r, "E": e, "fwhm": get_FWHM_at_Energy(r, e)} for r in (130, 128, 133.312296) for e in (0.2774, 1.4865, 5.8987, 6.4039, 9.4421, 20.0)]
# value2index vectors, incl. exact half cases, negative and out of range
ax = hs.signals.Signal1D(np.zeros(1000)).axes_manager.signal_axes[0]
vecs = []
rng = np.random.default_rng(7)
for off, sc in [(-0.2, 0.01), (0.0, 0.01), (0.0, 0.005), (-0.0958, 0.0100), (0.1, 0.02), (-0.5, 0.0125), (3.0, 0.5), (0.0, 1.0)]:
    ax.size = 1000; ax.offset = off; ax.scale = sc
    cand = list(off + sc*(np.arange(0, 1000, 37) + 0.5)) + list(off + sc*np.arange(0, 1000, 53)) \
         + [off - 0.5*sc, off - 0.51*sc, off - 0.49*sc, off + sc*999.5, off + sc*999.4, off + sc*999.6, 0.0, -0.0, -0.005, 0.005, -0.015, 0.015] \
         + list(rng.uniform(off - 0.1, off + sc*1000 + 0.1, 40))
    for v in cand:
        v = float(v)
        try: idx = int(ax.value2index(v))
        except ValueError: idx = None
        vecs.append({"offset": off, "scale": sc, "size": 1000, "value": v, "index": idx})
out["value2index"] = vecs
# slice semantics (start/stop clamp or IndexError)
sl = []
ax.offset = -0.2; ax.scale = 0.01; ax.size = 1000
for a, b in [(1.0, 2.0), (-1.0, 1.0), (5.0, 20.0), (-3.0, -1.0), (30.0, 40.0), (0.123, 0.1234), (2.0, 1.0), (9.79, 9.80)]:
    try:
        s_ = ax._get_array_slices(slice(a, b)); r = [s_.start, s_.stop]
    except IndexError: r = None
    sl.append({"start": a, "stop": b, "slice": r})
out["slices"] = sl
# line selection
sel = []
sp = exspy.data.EDS_SEM_TM002()
for els, beam in [(["Al","C","Cu","Mn","Zr"], 10.0), (["Al","C","Cu","Mn","Zr"], 30.0), (["Fe","Pt"], 200.0), (["Pt","Au","U","H","Li","Be"], 200.0)]:
    s = exspy.data.EDS_TEM_FePt_nanoparticles()
    s.set_microscope_parameters(beam_energy=beam)
    got = s._get_lines_from_elements(els, only_one=True, only_lines=("a",))
    allv = s._get_lines_from_elements(els, only_one=False, only_lines=None)
    sel.append({"elements": els, "beam": beam, "only_one_a": got, "all": allv})
out["selection"] = sel
s = exspy.data.EDS_SEM_TM002()
out["hHeExspy"] = s._get_lines_from_elements(["H", "He"], only_one=False, only_lines=None)
json.dump(out, open(sys.argv[1] if len(sys.argv) > 1 else "pins.json", "w"), separators=(",", ":"))
print("ok", len(json.dumps(out)))
for c in out["cases"]: print(c["spectrum"], c["lines"], c["defaultIntensity"], c["bg_2_2"]["net"], c["bg_5_2"]["net"])
print(out["tm002_MnKa_2_1"], out["tm002_MnKa_bg"])
print(sel[0], sel[2], sel[3]["only_one_a"])
