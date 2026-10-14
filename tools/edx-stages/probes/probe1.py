import sys, os, math, warnings, logging, contextlib
R=__import__("os").path.normpath(__import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, R+"/References/exspy-7185a4d1")
logging.disable(logging.CRITICAL); warnings.simplefilter("ignore")
import numpy as np
with open(os.devnull,"w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
    import hyperspy.api as hs
    from exspy.signals import EDSTEMSpectrum
    import exspy
from math import erf, sqrt
OFF, SC, NCH = -1.93221348, 0.02, 4096          # the owner's Super-X axis (OffsetEnergy -1932.21348 eV, Dispersion 20 eV)
E = OFF + SC*np.arange(NCH)
# independent line energies (keV, X-ray data booklet): Mg Ka 1.2536, Al Ka 1.4865(6), Si Ka 1.7400 ; Kb/Ka
LINES = {"Mg":[(1.2536,1.0),(1.3022,0.02)], "Al":[(1.4865,1.0),(1.5575,0.013)], "Si":[(1.7400,1.0),(1.8359,0.02)]}
def fwhm_fano(E_keV, R_mn):                      # Fano-limited law (physical, not Fiori-Newbury)
    eps, F = 3.76, 0.11
    s2n = (R_mn**2)/5.545 - eps*F*5898.7
    return sqrt(5.545*(s2n + eps*F*E_keV*1000))/1000.0
def binint(c, w):                                # gaussian mass in each channel [E-s/2, E+s/2)
    s = w/2.3548200450309493
    lo = (E-SC/2-c)/(s*sqrt(2)); hi = (E+SC/2-c)/(s*sqrt(2))
    return 0.5*(np.vectorize(erf)(hi)-np.vectorize(erf)(lo))
def planted(NAl, rho_mg, rho_si=0.01, R_mn=130.0, dE=0.0, tail=0.0, cont_frac=0.3, E0=200.0):
    """expected counts per channel; NAl = Al Ka+Kb counts; truth areas known."""
    mu = np.zeros(NCH); truth={}
    for el, N in (("Al",NAl),("Mg",NAl*rho_mg),("Si",NAl*rho_si)):
        tot = sum(w for _,w in LINES[el]); a=0
        for e,w in LINES[el]:
            area = N*w/tot; a+=area
            g = binint(e+dE, fwhm_fano(e,R_mn))
            mu += area*g
            if tail>0 and el=="Al" and w==1.0:   # incomplete-charge tail: exponential shelf below the line, fraction `tail` of the line area
                sh = np.where(E<e+dE, np.exp((E-(e+dE))/0.15), 0.0); sh/=sh.sum()
                mu += area*tail*sh - area*tail*g
        truth[el]=N
    en=np.clip(E,1e-3,None)
    cont=np.where((E>0.15)&(E<E0), (E0-en)/en*(1-np.exp(-(en/0.30)**2.5)), 0.0)
    cont*= (1+0.0*en)
    cont*= cont_frac*NAl/ cont[(E>0.2)&(E<20)].sum()
    mu += cont
    return mu, truth
def make_spec(counts, R_mn=130.0):
    s = EDSTEMSpectrum(counts.astype(float))
    ax=s.axes_manager.signal_axes[0]; ax.offset=OFF; ax.scale=SC; ax.units="keV"; ax.name="Energy"
    s.set_microscope_parameters(beam_energy=200.0, energy_resolution_MnKa=R_mn)
    return s
if __name__=="__main__":
    rng=np.random.default_rng(1)
    mu,_=planted(1e6,0.01)
    print("planted mean total counts (0.2-20 keV)", mu[(E>0.2)&(E<20)].sum())
    s=make_spec(rng.poisson(mu))
    s.set_elements(["Mg","Al","Si"]); s.set_lines(["Mg_Ka","Al_Ka","Si_Ka"])
    bw=s.estimate_background_windows(); print("bw",np.round(bw,4).tolist())
    iw=s.estimate_integration_windows(2.0); print("iw",np.round(np.array(iw),4).tolist())
    I=s.get_lines_intensity(background_windows=bw)
    print([float(i.data[0]) for i in I], "expected windows contain ~Ka share")
    for xl in ("Mg_Ka","Al_Ka","Si_Ka"): print(xl, s._get_line_energy(xl,FWHM_MnKa=130))
    print("FWHM FN vs Fano at Mg,Al,Si", [(round(s._get_line_energy(x,FWHM_MnKa=130)[1]*1000,1), round(fwhm_fano(s._get_line_energy(x),130)*1000,1)) for x in ("Mg_Ka","Al_Ka","Si_Ka")])
