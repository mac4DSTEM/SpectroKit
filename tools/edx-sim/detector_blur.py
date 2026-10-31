"""tools/edx-sim/detector_blur.py: the detector's resolution on the continuum, as a real detector records it. numpy only.

A detector records every photon with its Gaussian resolution, the continuum included, so an absorption edge in the continuum reaches
the spectrum as a blurred step (about 75 eV FWHM at the Al K edge for 130 eV at Mn K-alpha), never as a jump between two channels.
forward.py draws its lines as Gaussians but its continuum unblurred; the scripts here replace the continuum part of the expected
spectrum by its blurred copy:

    expected_blurred = expected - C + blur(C)

C the forward model's own continuum for the same pixels (`continuum`), blur the detector Gaussian applied photon by photon: the counts
of channel j spread over the axis with sigma from the line-width law at E_j (`xray_model.fwhm_kev`), the kernel normalised over the
channels it reaches (counts conserved). The Si internal-fluorescence peak forward.py derives from the counts above 1.839 keV is kept
as forward.py made it: blurring moves about 1e-4 of the continuum across that energy (5e-6 for the Al matrix, 1.1e-4 for the
beta'' precipitate pixel).
"""
import math

import numpy as np

import forward as fw
import xray_model as xm

SIGMA_PER_FWHM = 1.0 / (2.0 * math.sqrt(2.0 * math.log(2.0)))


def blur(values, centre_kev, fwhm_mnka_ev=130.0, reach_sigma=6.0):
    """`values` (one count per channel) seen through the detector: each channel's counts spread as a Gaussian of the line-width law's
    sigma at that channel's energy, over +-reach_sigma, normalised over the channels reached."""
    v = np.asarray(values, dtype=np.float64)
    e = np.asarray(centre_kev, dtype=np.float64)
    de = float(e[1] - e[0])
    out = np.zeros_like(v)
    for j in np.nonzero(v)[0]:
        s = xm.fwhm_kev(max(float(e[j]), 0.0), fwhm_mnka_ev) * SIGMA_PER_FWHM
        reach = int(math.ceil(reach_sigma * s / de))
        lo, hi = max(0, j - reach), min(len(e), j + reach + 1)
        w = np.exp(-0.5 * ((e[lo:hi] - e[j]) / s) ** 2)
        out[lo:hi] += v[j] * w / w.sum()
    return out


def continuum(f, spec, t_nm, rho, lam):
    """forward.Forward.run's continuum (counts per channel) of ONE pixel of recipe `spec`, thickness t_nm, density rho, live
    fraction lam: Kc N_tot sum_el x_el Z_el (E0 - E)/E eps(E) T_eff(E) dE lam, the same arrays forward.py uses."""
    if spec.vacuum:
        sh = f.gen * f.eps_ch
        return lam * fw.VACUUM_CONT * sh / sh.sum()
    x_el, mbar, wf = f.medium(spec)
    n_tot = rho * t_nm * fw.NA * 1e-21 / mbar
    z = sum(xm.ATOMIC_NUMBER[el] * x_el.get(el, 0.0) for el in ("Al", "Mg", "Si", "Cu", "O"))
    kappa = f.mu_rho(wf, np.maximum(f.axis.centre, 0.05)) * 1e-7
    x = kappa * rho * t_nm
    t = np.zeros_like(x)
    for j, c in enumerate(f.cos):
        t += fw.SEG_WEIGHT[j] * f.tables.f(x / abs(c), 1 if c > 0 else -1)
    return lam * f.kc * n_tot * z * f.gen * f.eps_ch * f.axis.disp_kev * t


def blurred(f, spec, t_nm, rho, lam, expected, npix=1):
    """`expected` (the forward model's expected spectrum of npix identical pixels) with its continuum blurred by the detector."""
    c = continuum(f, spec, t_nm, rho, lam) * npix
    return np.asarray(expected, dtype=np.float64) - c + blur(c, f.axis.centre, f.fwhm_ev)
