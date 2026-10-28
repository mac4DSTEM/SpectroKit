"""Pins for SpectroKit 0.10.0 (EDS and results): the k-factor import.

exSpy has no table of Cliff-Lorimer k-factors; what it fixes is the CONVENTION: `quantification_cliff_lorimer(intensities, kfactors)`
takes the k-factors "in same order as intensities eg. kfactors = [1, 1.47, 1.72] for ['Al_Ka', 'Cr_Ka', 'Ni_Ka']" and returns weight
fractions with C_A / C_B = (k_A / k_B) (I_A / I_B). This script records, for that docstring example and one more set, the planted
table TEXT in the layouts the importer reads (tab, semicolon, comma, decimal comma, header or none, a units line) together with the
k list the text stands for and exSpy's own weight fractions for several intensity vectors. The Swift test parses each text, checks
the list, and runs the parsed list through the kit's Cliff-Lorimer against exSpy's numbers.

The sum/escape model, the sigma propagation and the region result have no Python counterpart: they are tested against planted truth
only (Tests/SpectroEDXTests), not pinned here.

    References/python/bin/python -I -B tools/edx-0100/pins.py
"""
import json, pathlib, warnings
import numpy as np
warnings.filterwarnings("ignore")
from exspy._misc.eds.utils import quantification_cliff_lorimer

OUT = pathlib.Path(__file__).resolve().parents[2] / "Tests/SpectroEDXTests/Fixtures/edx-0100-exspy.json"

SETS = [
    {"name": "docstring", "elements": ["Al", "Cr", "Ni"], "lines": ["Al_Ka", "Cr_Ka", "Ni_Ka"], "k": [1.0, 1.47, 1.72]},
    {"name": "FeCuZn", "elements": ["Fe", "Cu", "Zn"], "lines": ["Fe_Ka", "Cu_Ka", "Zn_Ka"], "k": [1.0, 1.31, 1.52]},
]
INTENSITIES = [[1000.0, 800.0, 600.0], [250.0, 4000.0, 90.0], [12.0, 7.0, 5.0], [5e5, 3e5, 2e5]]


def texts(s):
    el, ln, k = s["elements"], [l.split("_")[1] for l in s["lines"]], s["k"]

    def fmt(v, dec):
        return f"{v:.2f}".replace(".", dec)

    t = {}
    t["tab_header"] = "Element\tLine\tk-factor\n" + "\n".join(f"{e}\t{l}\t{fmt(v, '.')}" for e, l, v in zip(el, ln, k)) + "\n"
    t["semicolon_decimal_comma"] = "Element;Line;k\n" + "\n".join(f"{e};{l};{fmt(v, ',')}" for e, l, v in zip(el, ln, k)) + "\n"
    t["comma_no_header"] = "\n".join(f"{e},{l},{fmt(v, '.')}" for e, l, v in zip(el, ln, k)) + "\n"
    t["units_line_combined"] = "Units: k-factors relative to " + el[0] + "\n" + "\n".join(f"{e} {l[0]}\t{fmt(v, '.')}" for e, l, v in zip(el, ln, k)) + "\n"
    return t


out = {"exspy": "exspy 0.3.2 with hyperspy 2.4.0 (utils.eds quantification_cliff_lorimer)", "sets": []}
for s in SETS:
    exp = []
    for I in INTENSITIES:
        r = quantification_cliff_lorimer(np.array(I).reshape(-1, 1), s["k"])
        exp.append({"intensities": I, "weight_fraction": [float(x) for x in np.asarray(r).reshape(-1)]})
    out["sets"].append({**s, "texts": texts(s), "expected": exp})
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(out, indent=1) + "\n")
print("wrote", OUT, [len(x["expected"]) for x in out["sets"]])
