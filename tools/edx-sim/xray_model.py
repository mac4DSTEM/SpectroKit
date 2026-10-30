"""tools/edx-sim/xray_model.py: the line, continuum and detector model under forward.py.

Pure numpy + math (no scipy).

Mean spectrum of one pixel, in counts, on the channel grid (centre of channel i = (i - origin) * dispersion):

    mean = thickness * ( sum_lines Gaussian(E_line, FWHM(E_line)) * G * n_el * s_el * w_line   [bin-integrated]
                       + continuum
                       + Si internal fluorescence )                 + stray

Everything here is a MODEL, not a measurement: the sensitivities s_el (this model's "true" k-factors, 1/s),
the continuum shape and amplitude, the detector efficiency, the Al K-edge step, the Al Ka tail and the Si
internal-fluorescence fraction are choices written into each fixture so a test knows the answer.
"""
import math

import numpy as np

# --- line table: eXSpy `exspy/material/xray_lines.json` (commit 7185a4d, Chantler et al. 2005), copied verbatim:
#     Al :119  Cu :716  Mg :1725  O :1968  Si :2953 (line numbers of the element key). (energy keV, weight rel. to the family's first line)
LINES = {
    "Al": {"Ka": (1.4865, 1.0), "Kb": (1.5596, 0.0132)},
    "Mg": {"Ka": (1.2536, 1.0), "Kb": (1.305, 0.01)},
    "Si": {"Ka": (1.7397, 1.0), "Kb": (1.8389, 0.02779)},
    "Cu": {"Ka": (8.0478, 1.0), "Kb": (8.9053, 0.13157),
           "La": (0.9295, 1.0), "Lb1": (0.9494, 0.03197), "Lb3": (1.0225, 0.00114),
           "Ll": (0.8113, 0.08401), "Ln": (0.8312, 0.01984)},
    "O": {"Ka": (0.5249, 1.0)},
    # Ga L lines (FIB damage), xray_lines.json:1038 block; the K lines are not modelled
    "Ga": {"La": (1.098, 1.0), "Lb1": (1.1249, 0.16704), "Lb3": (1.1948, 0.0461),
           "Ll": (0.9573, 0.0544), "Ln": (0.9842, 0.02509)},
}
MN_KA = 5.8987          # xray_lines.json:1735 block, Mn Ka (keV)
ATOMIC_NUMBER = {"Al": 13, "Mg": 12, "Si": 14, "Cu": 29, "O": 8, "Ga": 31}
AL_K_EDGE = 1.5596      # keV, the Al Kb energy of the table; the absorption step sits here


def fwhm_kev(energy_kev: float, fwhm_mnka_ev: float = 130.0) -> float:
    """eXSpy `utils/eds/_xray_lines.py:138-175` get_FWHM_at_Energy: sqrt(2.5*(E-E_MnKa)*1000 + FWHM_MnKa^2) eV, in keV."""
    return math.sqrt(2.5 * (energy_kev - MN_KA) * 1000.0 + fwhm_mnka_ev ** 2) / 1000.0


# Which sensitivity family a line belongs to (Cu K and Cu L are separate families).
def family(element: str, line: str) -> str:
    return element + "_" + line[0]


# MODEL sensitivities s (counts per unit n*G for the family's first line; detector efficiency baked in). GUESS values.
SENSITIVITY = {"Al_K": 1.00, "Mg_K": 0.55, "Si_K": 1.20, "Cu_K": 0.18, "Cu_L": 0.80, "O_K": 0.30, "Ga_L": 0.70}
G_COUNTS = 32.4            # Al Ka counts per pixel for n_Al = 1, thickness 1 (=> ~32 per matrix pixel)
CONTINUUM_TOTAL_Z13 = 8.0  # continuum counts per pixel (all channels, E > 0) for a pixel with sum(n Z) = 13
AL_KA_TAIL_FRACTION = 0.015
AL_KA_TAIL_LAMBDA_KEV = 0.12
SI_INTERNAL_FRACTION = 0.004   # Si Ka internal-fluorescence counts per count above the Si K edge (1.839 keV)
SI_K_EDGE = 1.839
STRAY_CU_KA_PER_PIXEL = 0.05   # holder/pole-piece Cu Ka, thickness independent, in every pixel
VACUUM_CONTINUUM_PER_PIXEL = 0.4

_erf = np.frompyfunc(math.erf, 1, 1)


def erf(x):
    return _erf(np.asarray(x, dtype=np.float64)).astype(np.float64)


class Axis:
    def __init__(self, n_channels: int, dispersion_ev: float, origin: float):
        self.n, self.disp_kev, self.origin = n_channels, dispersion_ev / 1000.0, origin
        i = np.arange(n_channels, dtype=np.float64)
        self.centre = (i - origin) * self.disp_kev
        self.lo = self.centre - 0.5 * self.disp_kev
        self.hi = self.centre + 0.5 * self.disp_kev

    def gaussian(self, e0: float, fwhm: float) -> np.ndarray:
        """Unit-area Gaussian integrated over each channel (conserves the total for lines inside the axis)."""
        sigma = fwhm / (2 * math.sqrt(2 * math.log(2)))
        s = sigma * math.sqrt(2)
        return 0.5 * (erf((self.hi - e0) / s) - erf((self.lo - e0) / s))


def detector_efficiency(e):
    """Simple SDD efficiency: window/dead-layer roll-off below ~0.4 keV and a silicon-thickness roll-off above ~20 keV."""
    e = np.asarray(e, dtype=np.float64)
    out = np.zeros_like(e)
    ok = e > 0.05
    ee = e[ok]
    out[ok] = np.exp(-(0.35 / ee) ** 2.2) * (1.0 - np.exp(-(27.0 / ee) ** 3))
    return out


class RecipeSpec:
    """One EDX recipe: atoms per unit thickness (n), a thickness factor, and whether the sample exists."""

    def __init__(self, name, n, thickness_factor, oxide_o_per_metal=0.02, vacuum=False):
        self.name, self.n, self.thickness_factor = name, dict(n), thickness_factor
        self.oxide = oxide_o_per_metal
        self.vacuum = vacuum


# ---- phases (atom fractions; Q = Al3Cu2Mg9Si7, beta'' = Mg5Si6, matrix = Al with 0.6 at% Mg and 0.6 at% Si) -------
MATRIX = {"Al": 0.988, "Mg": 0.006, "Si": 0.006}
BETA = {"Mg": 5 / 11, "Si": 6 / 11}
Q_PHASE = {"Al": 3 / 21, "Cu": 2 / 21, "Mg": 9 / 21, "Si": 7 / 21}
PRECIP_VOLUME_FRACTION = 0.5      # projected fraction of a precipitate pixel's thickness that is precipitate
PRECIP_THICKNESS_FACTOR = 1.3     # a precipitate pixel is 1.3x as thick as matrix at the same position



def mix(a, b, v):
    out = {}
    for k in sorted(set(a) | set(b)):                 # sorted: str hashing is randomised per run, and dict order changes float sums
        out[k] = (1 - v) * a.get(k, 0.0) + v * b.get(k, 0.0)
    return out


def edx_spec(recipe: str) -> RecipeSpec:
    if recipe == "vacuum":
        return RecipeSpec(recipe, {}, 1.0, vacuum=True)
    if recipe == "beta_pure":      # K2 pool: full-fraction Mg5Si6 (no matrix), 3 t (at 1.3 t the uncorrected Mg/Si bias is only 2.7 %)
        return RecipeSpec(recipe, dict(BETA), 3.0)
    if recipe == "precip_Q":
        return RecipeSpec(recipe, mix(MATRIX, Q_PHASE, PRECIP_VOLUME_FRACTION), PRECIP_THICKNESS_FACTOR)
    if recipe.startswith("precip_"):
        return RecipeSpec(recipe, mix(MATRIX, BETA, PRECIP_VOLUME_FRACTION), PRECIP_THICKNESS_FACTOR)
    return RecipeSpec(recipe, MATRIX, 1.0)


def phase_of(recipe: str) -> str:
    if recipe == "vacuum":
        return "vacuum"
    if recipe == "precip_Q":
        return "Q"
    if recipe.startswith("precip_") or recipe == "beta_pure":
        return "beta''"
    return "Al"



# --- the window method used by the checks (S2) -------------------------------------------------
def channel_range(axis: Axis, e_lo: float, e_hi: float):
    """Channels whose CENTRE lies in [e_lo, e_hi)."""
    idx = np.nonzero((axis.centre >= e_lo) & (axis.centre < e_hi))[0]
    return idx


def window_counts(spec_counts: np.ndarray, axis: Axis, energy: float, fwhm_mnka_ev=130.0):
    """Simple window method: peak window = centre +- 1 FWHM; background = linear interpolation between two side
    windows [E-2.5F, E-1.5F) and [E+1.5F, E+2.5F). Returns (peak_total, net, bg_left, bg_right, n_peak, n_side)."""
    f = fwhm_kev(energy, fwhm_mnka_ev)
    p = channel_range(axis, energy - f, energy + f)
    l = channel_range(axis, energy - 2.5 * f, energy - 1.5 * f)
    r = channel_range(axis, energy + 1.5 * f, energy + 2.5 * f)
    tot = float(spec_counts[p].sum())
    bl, br = float(spec_counts[l].sum()), float(spec_counts[r].sum())
    # linear background: mean level of each side window sits at its window centre; the peak window is centred between
    # them, so the background under the peak = mean of the two side levels x n_peak
    bg = 0.5 * (bl / len(l) + br / len(r)) * len(p)
    return tot, tot - bg, bl, br, len(p), (len(l), len(r))
