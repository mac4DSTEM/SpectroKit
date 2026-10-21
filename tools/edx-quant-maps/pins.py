"""Pins for the public per-pixel EDX quantification (EDXQuantification.quantifyMaps).

Runs exSpy's own EDSTEMSpectrum.quantification on a small synthetic 3 x 4 (rows x columns) line-intensity image per method
(CL, zeta, cross_section), with and without the absorption correction, composition in weight and atomic units, with a
navigation mask (CL only, as exSpy) and one pixel with a single intensity above the floor. Writes
Tests/SpectroEDXTests/Fixtures/edx-quant-maps-exspy.json.

    ../refs/hyperspy/bin/python -I -B tools/edx-quant-maps/pins.py
"""
import json, pathlib, warnings
import numpy as np
warnings.filterwarnings("ignore")
import hyperspy.api as hs
import exspy
from exspy.signals import EDSTEMSpectrum

ROWS, COLS = 3, 4
OUT = pathlib.Path(__file__).resolve().parents[2] / "Tests/SpectroEDXTests/Fixtures/edx-quant-maps-exspy.json"


def make(elements, lines, tilt=0.0):
    s = EDSTEMSpectrum(np.ones([ROWS, COLS, 64]))
    ax = s.axes_manager.signal_axes[0]
    ax.scale = 1e-2; ax.units = "keV"; ax.name = "Energy"
    s.set_microscope_parameters(beam_energy=200, live_time=2.5, tilt_stage=tilt, azimuth_angle=0,
                                elevation_angle=35, energy_resolution_MnKa=130, beam_current=0.05)
    s.axes_manager[0].scale = 0.5; s.axes_manager[1].scale = 0.5
    s.axes_manager[0].units = "nm"; s.axes_manager[1].units = "nm"
    s.set_elements(elements); s.add_lines(lines)
    return s


def intens(lines, data):
    out = []
    for ln, d in zip(lines, data):
        sig = hs.signals.BaseSignal(np.array(d, dtype=float)).T
        sig.metadata.set_item("Sample.xray_lines", [ln])
        sig.metadata.set_item("Sample.elements", [ln.split("_")[0]])
        out.append(sig)
    return out


def arr(x):
    return np.asarray(x.data if hasattr(x, "data") else x)


rng = np.random.default_rng(20261021)
cases = []
for name, elements, lines, factors in [
    ("AlZn", ["Al", "Zn"], ["Al_Ka", "Zn_Ka"], {"CL": [1.0, 1.9], "zeta": [20.0, 50.0], "cross_section": [3.0, 5.0]}),
    ("AlCrNi", ["Al", "Cr", "Ni"], ["Al_Ka", "Cr_Ka", "Ni_Ka"], {"CL": [0.982, 1.32, 1.60], "zeta": [20.0, 40.0, 60.0], "cross_section": [3.0, 4.0, 5.0]}),
]:
    n = len(lines)
    base = np.array([300.0, 500.0, 700.0][:n])
    data = [base[i] * (0.4 + 1.2 * rng.random((ROWS, COLS))) for i in range(n)]
    # one pixel with a single line above the 0.1 floor, one with all zero (CL only)
    for i in range(1, n):
        data[i][0, 0] = 0.0
    mask = np.zeros((ROWS, COLS), dtype=bool); mask[2, 3] = True; mask[1, 1] = True
    runs = []
    for method in ["CL", "zeta", "cross_section"]:
        for units in ["weight", "atomic"]:
            for absorption, tight in [(False, False), (True, False), (True, True)]:
                s = make(elements, lines)
                it = intens(lines, data)
                kw = dict(composition_units=units, absorption_correction=absorption, navigation_mask=(mask if method == "CL" else None))
                if tight: kw["convergence_criterion"] = 1e-8; kw["max_iterations"] = 200
                if absorption and method == "CL":
                    kw["thickness"] = 80.0
                rec = {"tight": tight, "method": method, "units": units, "absorption": absorption, "factors": factors[method],
                       "thicknessNm": 80.0 if (absorption and method == "CL") else None,
                       "mask": mask.astype(int).tolist() if method == "CL" else None}
                try:
                    res = s.quantification(it, method, factors[method], **kw)
                except Exception as e:  # recorded, never hidden
                    rec["exspyError"] = str(e)[:200]; runs.append(rec); continue
                if method == "CL":
                    if absorption:
                        comp, mt = res
                        rec["massThickness"] = arr(mt).tolist()
                    else:
                        comp = res
                        rec["massThickness"] = None
                elif method == "zeta":
                    comp, mt = res
                    rec["massThickness"] = arr(mt).tolist()
                else:
                    comp, atoms = res
                    rec["atoms"] = [arr(a).tolist() for a in atoms]
                rec["composition"] = [arr(c).tolist() for c in comp]
                runs.append(rec)
    cases.append({"name": name, "elements": elements, "lines": lines, "intensities": [d.tolist() for d in data],
                  "rows": ROWS, "cols": COLS, "takeOffDegrees": float(make(elements, lines).get_take_off_angle()),
                  "beamCurrentNA": 0.05, "liveTimeSeconds": 2.5, "probeAreaNm2": 0.25,
                  "runs": runs})
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({"hyperspy": hs.__version__, "exspy": exspy.__version__, "cases": cases}, indent=1))
print("wrote", OUT, sum(len(c["runs"]) for c in cases), "runs")
