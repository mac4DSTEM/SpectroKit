"""The unlisted-line check's synthetic pool.

Writes Tests/SpectroEDXTests/Fixtures/eds-unlisted-sim.json: the EXPECTED pooled spectrum (no noise; the Swift test adds seeded
Poisson noise) of a hard case: Ti K-alpha 3000 counts among
strong Ge, Cu and Ga lines, O, Si and Ni, with the unlisted L lines at the intensities seen in the real Velox window (Ge L 5e5,
Ga L 3e5, Cu L 1e5), on the Velox axis (4096 x 20 eV from -1.932 keV), beam 200 kV.
  * Lines: eXSpy xray_lines.json 7185a4d (as SpectroKit's XRayLineData.swift), each family's lines at its
    weight times the family's area; Gaussians integrated over the channel, FWHM by eXSpy's law at 130 eV (Mn K-alpha).
  * Continuum: NOT the fit's form (Kramers x Bernstein): 1500 (3/E) (E0-E)/(E0-3) (1 - exp(-(E/0.5)^2.4)) exp(-(E-3)/12).
  * No escape or sum peaks are planted.
Usage: References/python/bin/python -I -B tools/edx-sim/unlisted_sim.py [out.json]   (standard library only)
"""
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Tests", "SpectroEDXTests", "Fixtures", "eds-unlisted-sim.json")
OFFSET, SCALE, SIZE, BEAM, FWHM_MNKA, MN_KA = -1.93221348, 0.02, 4096, 200.0, 130.0, 5.8987

# (energy keV, weight relative to the family's area) per family; XRayLineData.swift rows, verbatim.
LINES = {
    "O_Ka": [(0.5249, 1.0)],
    "Si_Ka": [(1.7397, 1.0), (1.8389, 0.02779)],
    "Ti_Ka": [(4.5109, 1.0), (4.9318, 0.11673)],
    "Ti_La": [(0.4555, 0.694), (0.5291, 0.166), (0.3952, 1.0), (0.4012, 0.491)],
    "Ni_Ka": [(7.4781, 1.0), (8.2647, 0.1277)],
    "Ni_La": [(0.8511, 1.0), (0.8683, 0.1677), (0.94, 0.00199), (0.7429, 0.14133), (0.7601, 0.09693)],
    "Cu_Ka": [(8.0478, 1.0), (8.9053, 0.13157)],
    "Cu_La": [(0.9295, 1.0), (0.9494, 0.03197), (1.0225, 0.00114), (0.8113, 0.08401), (0.8312, 0.01984)],
    "Ga_Ka": [(9.2517, 1.0), (10.2642, 0.1287)],
    "Ga_La": [(1.098, 1.0), (1.1249, 0.16704), (1.1948, 0.0461), (0.9573, 0.0544), (0.9842, 0.02509)],
    "Ge_Ka": [(9.8864, 1.0), (10.9823, 0.1322)],
    "Ge_La": [(1.188, 1.0), (1.2191, 0.16704), (1.2935, 0.04429), (1.0367, 0.0511), (1.0678, 0.02)],
}
# The truth, with the strong L lines, in counts per family area.
TRUTH = {"O_Ka": 120000, "Si_Ka": 960000, "Ni_Ka": 395000, "Ni_La": 60000, "Ti_Ka": 3000, "Ti_La": 300,
         "Ge_Ka": 267000, "Ge_La": 500000, "Cu_Ka": 60000, "Cu_La": 100000, "Ga_Ka": 30000, "Ga_La": 300000}


def fwhm(e):
    return math.sqrt(2.5 * (e - MN_KA) * 1000.0 + FWHM_MNKA ** 2) / 1000.0


def continuum(e):
    if e <= 0.1:
        return 0.0
    return 1500 * (3.0 / e) * ((BEAM - e) / (BEAM - 3)) * (1 - math.exp(-((e / 0.5) ** 2.4))) * math.exp(-(e - 3) / 12)


centre = [OFFSET + SCALE * i for i in range(SIZE)]
mu = [continuum(e) for e in centre]
for fam, area in TRUTH.items():
    for e0, w in LINES[fam]:
        s = fwhm(e0) / (2 * math.sqrt(2 * math.log(2))) * math.sqrt(2)
        for i, c in enumerate(centre):
            if abs(c - e0) > 8 * s:
                continue
            mu[i] += area * w * 0.5 * (math.erf((c + SCALE / 2 - e0) / s) - math.erf((c - SCALE / 2 - e0) / s))

out = {"generator": "tools/edx-sim/unlisted_sim.py", "offset": OFFSET, "scale": SCALE,
       "size": SIZE, "beam": BEAM, "fwhmMnKa": FWHM_MNKA, "truth": TRUTH, "expected": [round(v, 4) for v in mu]}
with open(OUT, "w") as f:
    json.dump(out, f, separators=(",", ":"))
print("total expected counts", round(sum(mu)), "->", OUT)
