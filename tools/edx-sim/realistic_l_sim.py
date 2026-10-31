"""Realistic-L synthetic pool (fit robustness with strong unlisted L lines), a seeded fixture.

Writes Tests/SpectroEDXTests/Fixtures/eds-realistic-l-sim.json: the Velox file's energy axis (offset -1.93221348 keV, 20 eV, 4096 channels),
a 200 kV beam, 130 eV at Mn Ka, the EXPECTED continuum per channel, the planted line areas (counts per pooled spectrum, by the fit's
group id), the listed sets and the Poisson seeds. The Swift test adds the lines with SpectroKit's own line shapes (EDSLineModel) and draws Poisson counts with SplitMix64 from each seed, so every number is reproducible.

Continuum (a DIFFERENT functional form from the fit's Kramers x Bernstein; unlisted_sim.py's form plus a step):
    B(E) = 1500 (3/E) ((E0 - E)/(E0 - 3)) (1 - exp(-(E/0.5)^2.4)) exp(-(E - 3)/12) x (1 - 0.03 Phi((E - 1.839)/sigma)),  0 at E <= 0.1 keV
the 3 % downward step at the Si K edge standing for the detector's Si dead layer and the Si-rich specimen, seen through the detector:
Phi the normal CDF, sigma the line-width law's at 1.839 keV for 130 eV at Mn Ka (a measured edge is never a jump between two channels).
Lines: the unlisted L lines at intensities seen in a measured region's windows (Ge La 5e5, Ga La 3e5, Cu La 1e5); Ti Ka planted at 3000.
`plantSn` is an optional extra plant, Sn L-alpha 3.44 keV and Sn K-alpha 25.27 keV (the K line outside the
default 20 keV fit range, the L line inside it); the tests add it only where they name it, so the other keys are unchanged.
Usage: References/python/bin/python -I -B tools/edx-sim/realistic_l_sim.py [out.json]   (standard library only)
"""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Tests", "SpectroEDXTests", "Fixtures", "eds-realistic-l-sim.json")
OFFSET, SCALE, SIZE, BEAM = -1.93221348, 0.02, 4096, 200.0

SI_EDGE = 1.839
# The step seen through the detector: a Gaussian-blurred step, sigma from the line-width law at the edge (130 eV at Mn Ka).
SIGMA_EDGE = math.sqrt(2.5 * (SI_EDGE - 5.8987) * 1000 + 130.0 ** 2) / 1000 / (2 * math.sqrt(2 * math.log(2)))

def continuum(e):
    if e <= 0.1:
        return 0.0
    b = 1500 * (3 / e) * ((BEAM - e) / (BEAM - 3)) * (1 - math.exp(-((e / 0.5) ** 2.4))) * math.exp(-(e - 3) / 12)
    return b * (1.0 - 0.03 * 0.5 * (1 + math.erf((e - SI_EDGE) / (math.sqrt(2) * SIGMA_EDGE))))

energies = [OFFSET + SCALE * i for i in range(SIZE)]
out = {
    "generator": "tools/edx-sim/realistic_l_sim.py", "offset": OFFSET, "scale": SCALE, "size": SIZE, "beam": BEAM, "fwhmMnKa": 130.0,
    "continuum": [round(continuum(e), 6) for e in energies],
    "areas": {"O_Ka": 120000, "Si_Ka": 960000, "Ni_Ka": 395000, "Ni_La": 60000, "Ti_Ka": 3000, "Ti_La": 300,
              "Ge_Ka": 267000, "Ge_La": 500000, "Cu_Ka": 60000, "Cu_La": 100000, "Ga_Ka": 30000, "Ga_La": 300000},
    "planted": ["O", "Si", "Ti", "Ni", "Ge", "Cu", "Ga"],
    "listedFour": ["O", "Si", "Ti", "Ni"],
    "listedSeven": ["O", "Si", "Ti", "Ni", "Ge", "Cu", "Ga"],
    "seeds": [0, 1, 2, 3, 4],
    "plantSn": {"Sn_La": 20000, "Sn_Ka": 8000},
}
json.dump(out, open(OUT, "w"), separators=(",", ":"))
