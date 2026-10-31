"""tools/edx-sim/forward.py: the physical EDX forward model behind the synthetic EDX fixtures. numpy only.

Per pixel p (thickness t_p nm along the foil normal, density rho_p, live fraction lam_p):

  line component:  a = lam * Gp * N_el * s_family * w_line * eps(E_line) * T_eff(E_line, p)
                   N_el = atoms/nm^2 of the element = x_el * rho t N_A 1e-21 / Mbar
                   T_eff = sum_j W_j f_j(x_j),  x_j = mu_mix(E)/rho * rho_p * 1e-7 * t / |c_j|,  c_j = d_j . n_top
                   f = NUMERICAL integral over generation depth s in (0,1) of g(s) exp(-x * exit_path(s)), g = 1 + beta (s - 1/2)
                   (a depth-weighted, per-segment path integral; NOT the closed form (1-e^-x)/x)
  continuum:       Kc * sum_el N_el Z_el * (E0-E)/E * eps(E) * T_eff(E, p) * dE * lam
  detector dead layer (optional, `dead_layer_um`, default 0 = none): eps(E) of lines and continuum times exp(-mu_Si(E) rho_Si t_dead),
                   mu_Si from the FFAST table, rho_Si 2.33 g/cm^3; a step down at the Si K edge (1.839 keV)
  escape (E_line > Si K edge): fraction f_esc = 0.02 (1.839/E)^1.5 of a moves to E - 1.7397 keV
  Al Ka tail: 1.5 % of the Al Ka counts in an exponential shelf (lambda 0.12 keV) below the peak
  sum peaks (pairs of Al Ka, Mg Ka, Si Ka): s_ab = kappa a_a a_b (a != b), kappa a_a^2 / 2 (a == b); parents lose the photons
  Si internal fluorescence: 0.4 % of all mean counts above 1.839 keV appear as a Si Ka peak (stray Cu K included)
  stray: Cu Ka/Kb 0.05 counts/px x lam, not absorbed, not thickness dependent
  Ga L lines: N_Ga = N_Ga0 exp(-d_edge/lambda) planted in a FIB-damaged edge region (medium absorption ignores Ga)

Geometry convention (stored in truth; eXSpy's, `exspy/utils/eds/_geometry.py` take_off_angle with beta tilt 0): the azimuth of segment j is
measured from the direction PERPENDICULAR to the alpha-tilt axis (0 = in the plane containing the beam and the tilt-perpendicular), a
POSITIVE alpha-tilt turns the sample's gun-side face toward that direction, elevation theta is above the sample plane at alpha = 0. The sine of
the take-off angle, which is the exit cosine to the gun-side normal, is c_j = sin(theta) cos(alpha) + cos(theta) cos(phi_j) sin(alpha).
c_j > 0: X-rays leave through the gun-side face (exit path ~ s t / c); c_j < 0: through the far face (~ (1 - s) t / |c|).
With alpha = -16.87, theta = 22: c = (0.169, 0.549, 0.549, 0.169) for phi = (45, 135, 225, 315).
"""
import hashlib
import math

import numpy as np

import xray_model as xm

NA = 6.02214076e23
ATOMIC_MASS = {"Al": 26.9815, "Mg": 24.305, "Si": 28.0855, "Cu": 63.546, "O": 15.999, "Ga": 69.723}
PHASE_DENSITY = {"Al": 2.70, "beta": 2.00, "Q": 2.80}            # g/cm^3 (model values)
THICKNESS_BASE_NM = 80.0
WEDGE = (0.85, 0.30)                                               # t = 80 nm * (0.85 + 0.30 (x+0.5)/nx)
PRECIP_T = 1.3
DEPTH_BETA = 0.2
SEG_AZ = (45.0, 135.0, 225.0, 315.0)
SEG_ELEV = 22.0
SEG_WEIGHT = (0.4, 0.2, 0.1, 0.3)                                  # relative solid angle (sums to 1); UNEQUAL so a wrong convention shows (round 3)
TILT_ALPHA = -16.87
KC_TOTAL_REF = 8.0                                                 # continuum counts/px of the reference pixel (no absorption)
G_AL_KA_REF = 32.4                                                 # Al Ka counts/px of the reference pixel (no absorption)
SI_K_EDGE = 1.839
SI_KA = 1.7397
SI_DENSITY = 2.33                                                  # g/cm^3, the detector dead layer (SpectroEDX QuantElementData)
ESC0 = 0.02
PILE_KAPPA = 2.0e-3
STRAY = 0.05
VACUUM_CONT = 0.4
GA_LAMBDA_PX = 2.0
GA_LA_EDGE_COUNTS = 1.2
GA_COLUMNS = 4                                                     # edge region: the last 4 scan columns (decay length 2 px)
SI_INT = xm.SI_INTERNAL_FRACTION
TAIL_FRAC, TAIL_LAMBDA = xm.AL_KA_TAIL_FRACTION, xm.AL_KA_TAIL_LAMBDA_KEV


def load_mac(path):
    rows = [l.rstrip("\n").split(",") for l in open(path)]
    width = max(len(r) for r in rows)
    curves = {}
    for z in range(1, width // 2 + 1):
        e, m = [], []
        for r in rows:
            if len(r) >= 2 * z:
                a, b = r[2 * (z - 1)].strip(), r[2 * (z - 1) + 1].strip()
                if a and b:
                    ev, mv = float(a), float(b)
                    if ev == 0 and mv == 0:
                        continue
                    e.append(ev); m.append(mv)
        if e:
            curves[z] = (np.array(e), np.array(m))
    return curves


def mac(curves, el, energy):
    """mu/rho (cm^2/g), log-log interpolation (as eXSpy)."""
    e, m = curves[xm.ATOMIC_NUMBER[el]]
    en = np.asarray(energy, dtype=np.float64)
    out = np.exp(np.interp(np.log(np.maximum(en, 1e-9)), np.log(e), np.log(m)))
    return out


def sha_file(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


class DepthTables:
    """f(x) = int_0^1 g(s) exp(-x * exit(s)) ds by midpoint quadrature (N=4096) on a fine x grid, linear interpolation."""

    def __init__(self, beta=DEPTH_BETA, n=4096, xmax=80.0, m=6000):
        self.xs = np.concatenate([[0.0], np.geomspace(1e-5, xmax, m)])
        s = (np.arange(n) + 0.5) / n
        g = 1.0 + beta * (s - 0.5)
        self.pos = (g[None, :] * np.exp(-self.xs[:, None] * s[None, :])).mean(axis=1)           # exit through the gun-side face
        self.neg = (g[None, :] * np.exp(-self.xs[:, None] * (1 - s)[None, :])).mean(axis=1)     # through the far face

    def f(self, x, sign):
        tab = self.pos if sign > 0 else self.neg
        y = np.interp(x, self.xs, tab)
        return np.where(x > self.xs[-1], tab[-1] * self.xs[-1] / np.maximum(x, 1e-12), y)      # ~1/x beyond the table


def segment_cosines(az=SEG_AZ, elev=SEG_ELEV, alpha=TILT_ALPHA):
    th, a = math.radians(elev), math.radians(alpha)
    return np.array([math.sin(th) * math.cos(a) + math.cos(th) * math.cos(math.radians(p)) * math.sin(a) for p in az])


class Component:
    def __init__(self, name, kind, energy, element=None, line=None, parent=None):
        self.name, self.kind, self.energy, self.element, self.line, self.parent = name, kind, energy, element, line, parent


def build_components():
    comps = []
    for el, ls in xm.LINES.items():
        for ln, (e, w) in ls.items():
            comps.append(Component(f"{el}_{ln}", "line", e, el, ln))
    for ln in ("Ka", "Kb"):
        comps.append(Component(f"Cu_{ln}_stray", "stray", xm.LINES["Cu"][ln][0], "Cu", ln))
    base = list(comps)
    for c in base:
        if c.kind in ("line", "stray") and c.energy > SI_K_EDGE:
            comps.append(Component(c.name + "_escape", "escape", c.energy - SI_KA, parent=c.name))
    comps.append(Component("Al_Ka_tail", "tail", xm.LINES["Al"]["Ka"][0], parent="Al_Ka"))
    trio = ["Al_Ka", "Mg_Ka", "Si_Ka"]
    for i, a in enumerate(trio):
        for b in trio[i:]:
            ea = xm.LINES[a[:2]]["Ka"][0]; eb = xm.LINES[b[:2]]["Ka"][0]
            comps.append(Component(f"sum_{a}+{b}", "sum", ea + eb, parent=(a, b)))
    comps.append(Component("Si_Ka_internal", "internal", SI_KA))
    return comps


class Forward:
    def __init__(self, axis, mac_path, beam_kev=200.0, fwhm_mnka_ev=130.0, dead_layer_um=0.0):
        self.axis, self.beam, self.fwhm_ev = axis, beam_kev, fwhm_mnka_ev
        self.mac_path = mac_path
        self.curves = load_mac(mac_path)
        self.tables = DepthTables()
        self.cos = segment_cosines()
        self.comps = build_components()
        self.cidx = {c.name: i for i, c in enumerate(self.comps)}
        e = axis.centre
        self.eps_ch = xm.detector_efficiency(e)
        self.gen = np.zeros_like(e)
        ok = (e > 0.05) & (e < beam_kev)
        self.gen[ok] = (beam_kev - e[ok]) / e[ok]
        self.shape = np.zeros((len(self.comps), axis.n))
        for i, c in enumerate(self.comps):
            if c.kind == "tail":
                sig = xm.fwhm_kev(c.energy, fwhm_mnka_ev) / 2.3548200450309493
                near = e < c.energy + 0.5
                x = np.where(near, e - c.energy, 0.0)
                sh = np.where(near, np.exp(x / TAIL_LAMBDA) * 0.5 * (1 - xm.erf(x / (sig * math.sqrt(2)))), 0.0)
                self.shape[i] = sh / sh.sum()
            else:
                self.shape[i] = axis.gaussian(c.energy, xm.fwhm_kev(c.energy, fwhm_mnka_ev))
        self.above = (e > SI_K_EDGE)
        self.line_comps = [i for i, c in enumerate(self.comps) if c.kind == "line"]
        # reference normalisation (a pure matrix pixel at 80 nm, rho 2.70, no absorption, lam 1)
        n_tot_ref = PHASE_DENSITY["Al"] * THICKNESS_BASE_NM * NA * 1e-21 / ATOMIC_MASS["Al"]
        self.gp = G_AL_KA_REF / (n_tot_ref * 0.988 * float(xm.detector_efficiency(np.array([1.4865]))[0]) * xm.SENSITIVITY["Al_K"])
        s_ref = float((self.gen * self.eps_ch).sum() * axis.disp_kev)
        nz_ref = n_tot_ref * (0.988 * 13 + 0.006 * 12 + 0.006 * 14)
        self.kc = KC_TOTAL_REF / (nz_ref * s_ref)
        self.n_tot_ref = n_tot_ref
        # Detector Si dead layer (after the normalisation above, so G and Kc keep their meaning: the reference pixel's counts in
        # front of the dead layer). 0 leaves every array bit-identical to the model without it.
        self.dead_layer_um = float(dead_layer_um)
        if self.dead_layer_um > 0:
            self.eps_ch = self.eps_ch * self.dead_layer_T(e)

    def dead_layer_T(self, energy):
        """Transmission of the detector Si dead layer, exp(-mu_Si(E) rho_Si t) (Beer-Lambert), mu/rho from the FFAST table above,
        rho_Si = SI_DENSITY, t = dead_layer_um. The same factor as the dead-layer term of SpectroEDX SDDEfficiency (EPQ SiLiCalibration)."""
        en = np.maximum(np.asarray(energy, dtype=np.float64), 0.05)
        return np.exp(-mac(self.curves, "Si", en) * SI_DENSITY * self.dead_layer_um * 1e-4)

    def line_eps(self, energy):
        """eps(E_line) of a line: the detector efficiency, times the dead-layer transmission when there is a dead layer."""
        eps = float(xm.detector_efficiency(np.array([energy]))[0])
        if self.dead_layer_um > 0:
            eps *= float(self.dead_layer_T(np.array([energy]))[0])
        return eps

    # ---- per-recipe medium ------------------------------------------------------------------------------------
    def medium(self, spec):
        """atom fractions (incl. O), mean atomic mass, weight fractions."""
        n = dict(spec.n)
        metals = sum(n.values())
        if metals > 0:
            n["O"] = spec.oxide * metals
        tot = sum(n.values())
        x = {k: v / tot for k, v in n.items()} if tot > 0 else {}
        mbar = sum(x[k] * ATOMIC_MASS[k] for k in x) if x else 1.0
        wf = {k: x[k] * ATOMIC_MASS[k] / mbar for k in x}
        return x, mbar, wf

    def mu_rho(self, wf, energy):
        return sum(w * mac(self.curves, el, energy) for el, w in wf.items())

    def effective_T(self, kappa_per_nm, t_nm):
        """kappa (1/nm, scalar or array) x thickness (nm) -> (T_eff, T_by_segment (4, ...))."""
        ts = []
        for j, c in enumerate(self.cos):
            x = np.asarray(kappa_per_nm) * np.asarray(t_nm) / max(abs(c), 1e-9)
            ts.append(self.tables.f(x, 1 if c > 0 else -1) if abs(c) > 1e-9 else np.zeros_like(x, dtype=float))
        ts = np.array(ts)
        return np.tensordot(np.array(SEG_WEIGHT), ts, axes=1), ts

    # ---- the pixel loop -------------------------------------------------------------------------------------------
    def run(self, specs, rid, t_nm, rho, lam, ga, groups, n_groups, rng=None, footprint=1, keep_pixel_arrays=True, chunk=256, pile=None):
        """specs: list of RecipeSpec indexed by rid. All per-pixel arrays are flat (npix_sub). With footprint k, every k consecutive
        sub-pixels are summed into one output pixel (means add; Poisson of a sum). `groups` assigns an output pixel to a group
        (for the expected-spectrum sums). Returns dict(counts|None, truth...)."""
        npix = len(rid)
        pile = np.ones(npix) if pile is None else pile        # per-pixel multiplier of the sum-peak kappa (dwell-time dosing)
        nout = npix // footprint
        nch, nc = self.axis.n, len(self.comps)
        med = [self.medium(s) for s in specs]
        kappa_ch = []     # per recipe: mu/rho(E) * 1e-7 (cm -> nm), per channel (1/nm per g/cm^3)
        for (x, mbar, wf), s in zip(med, specs):
            if s.vacuum:
                kappa_ch.append(np.zeros(nch)); continue
            e = np.maximum(self.axis.centre, 0.05)
            kappa_ch.append(self.mu_rho(wf, e) * 1e-7)
        # per recipe per line-component kappa at the line energy
        line_kappa = np.zeros((len(specs), nc))
        for ri, (x, mbar, wf) in enumerate(med):
            if specs[ri].vacuum:
                continue
            for i, c in enumerate(self.comps):
                if c.kind == "line":
                    line_kappa[ri, i] = self.mu_rho(wf, c.energy) * 1e-7
        Z = np.array([[xm.ATOMIC_NUMBER[el] * med[ri][0].get(el, 0.0) for el in ("Al", "Mg", "Si", "Cu", "O")] for ri in range(len(specs))]).sum(1)
        amp = np.zeros((nc, nout)) if keep_pixel_arrays else None
        a_free = np.zeros((len(self.line_comps), nout)) if keep_pixel_arrays and footprint == 1 else None
        t_eff = np.zeros((len(self.line_comps), nout)) if keep_pixel_arrays and footprint == 1 else None
        t_seg = np.zeros((4, len(self.line_comps), nout)) if keep_pixel_arrays and footprint == 1 else None
        exp_sum = np.zeros((n_groups, nch))
        pix_total = np.zeros(nout)
        counts = np.zeros((nout, nch), dtype=np.uint32) if rng is not None else None
        stray_idx = [self.cidx["Cu_Ka_stray"], self.cidx["Cu_Kb_stray"]]
        for s0 in range(0, npix, chunk * footprint):
            sl = slice(s0, min(npix, s0 + chunk * footprint))
            r_, t_, rho_, lam_, ga_, pile_ = rid[sl], t_nm[sl], rho[sl], lam[sl], ga[sl], pile[sl]
            m = len(r_)
            A = np.zeros((m, nc))
            ntot = np.array([0.0 if specs[r].vacuum else 1.0 for r in r_])
            mbar_p = np.array([med[r][1] for r in r_])
            n_tot = rho_ * t_ * NA * 1e-21 / mbar_p * ntot
            cont = np.zeros((m, nch))
            for r in np.unique(r_):
                if specs[r].vacuum:
                    continue
                pm = r_ == r
                x_el = med[r][0]
                tt, rr = t_[pm], rho_[pm]
                nt = n_tot[pm]
                for i in self.line_comps:
                    c = self.comps[i]
                    if c.element == "Ga":
                        continue
                    n_el = nt * x_el.get(c.element, 0.0)
                    fam = xm.family(c.element, c.line)
                    w = xm.LINES[c.element][c.line][1]
                    a0 = lam_[pm] * self.gp * n_el * xm.SENSITIVITY[fam] * w * self.line_eps(c.energy)
                    teff, tseg = self.effective_T(line_kappa[r, i] * rr, tt)
                    A[np.where(pm)[0], i] = a0 * teff
                    if a_free is not None:
                        li = self.line_comps.index(i)
                        a_free[li, (sl.start + np.where(pm)[0]) // footprint] = a0
                        t_eff[li, (sl.start + np.where(pm)[0]) // footprint] = teff
                        t_seg[:, li, (sl.start + np.where(pm)[0]) // footprint] = tseg
                # Ga L (planted FIB damage): medium absorption of the host
                for i in self.line_comps:
                    c = self.comps[i]
                    if c.element != "Ga":
                        continue
                    w = xm.LINES["Ga"][c.line][1]
                    n_ga = ga_[pm]
                    a0 = lam_[pm] * self.gp * n_ga * (xm.SENSITIVITY["Ga_L"]) * w * self.line_eps(c.energy)
                    kap = self.mu_rho(med[r][2], c.energy) * 1e-7
                    teff, tseg = self.effective_T(kap * rr, tt)
                    A[np.where(pm)[0], i] = a0 * teff
                    if a_free is not None:
                        li = self.line_comps.index(i)
                        a_free[li, (sl.start + np.where(pm)[0]) // footprint] = a0
                        t_eff[li, (sl.start + np.where(pm)[0]) // footprint] = teff
                        t_seg[:, li, (sl.start + np.where(pm)[0]) // footprint] = tseg
                # continuum with per-channel absorption
                gen_amp = self.kc * nt * Z[r]
                x = kappa_ch[r][None, :] * (rr * tt)[:, None]
                T = np.zeros_like(x)
                for j, cj in enumerate(self.cos):
                    T += SEG_WEIGHT[j] * self.tables.f(x / abs(cj), 1 if cj > 0 else -1)
                cont[pm] = (lam_[pm] * gen_amp)[:, None] * (self.gen * self.eps_ch * self.axis.disp_kev)[None, :] * T
            # vacuum continuum
            vm = np.array([specs[r].vacuum for r in r_])
            if vm.any():
                sh = self.gen * self.eps_ch
                cont[vm] = (lam_[vm] * VACUUM_CONT)[:, None] * (sh / sh.sum())[None, :]
            # stray
            for i, ln in zip(stray_idx, ("Ka", "Kb")):
                A[:, i] = lam_ * STRAY * xm.LINES["Cu"][ln][1]
            # pile-up among Al Ka, Mg Ka, Si Ka (before the tail is split off): amplitudes are the TOTAL line counts
            ia, ib, ic = self.cidx["Al_Ka"], self.cidx["Mg_Ka"], self.cidx["Si_Ka"]
            trio = [ia, ib, ic]
            tot = {k: A[:, k].copy() for k in trio}
            for c in self.comps:
                if c.kind == "sum":
                    a, b = (self.cidx[p] for p in c.parent)
                    s_ = PILE_KAPPA * pile_ * tot[a] * tot[b] * (0.5 if a == b else 1.0)
                    A[:, self.cidx[c.name]] = s_
                    A[:, a] -= s_
                    A[:, b] -= s_
            # tail split, escapes
            tail = TAIL_FRAC * A[:, ia]
            A[:, self.cidx["Al_Ka_tail"]] = tail
            A[:, ia] -= tail
            for c in self.comps:
                if c.kind == "escape":
                    p = self.cidx[c.parent]
                    f = ESC0 * (SI_K_EDGE / self.comps[p].energy) ** 1.5
                    A[:, self.cidx[c.name]] = f * A[:, p]
                    A[:, p] *= (1 - f)
            if (A < 0).any():
                raise ValueError('negative component amplitude: pile-up depletion exceeds the parent counts (rate too high for the model)')
            spec = A @ self.shape + cont
            internal = SI_INT * spec[:, self.above].sum(1)
            A[:, self.cidx["Si_Ka_internal"]] = internal
            spec += internal[:, None] * self.shape[self.cidx["Si_Ka_internal"]][None, :]
            # Ga: a_free/t_eff of Ga are filled above only for non-vacuum pixels; fine (vacuum has no Ga)
            if footprint > 1:
                spec = spec.reshape(-1, footprint, nch).sum(1)
                A = A.reshape(-1, footprint, nc).sum(1)
            o0 = s0 // footprint
            o1 = o0 + spec.shape[0]
            if amp is not None:
                amp[:, o0:o1] = A.T
            pix_total[o0:o1] = spec.sum(1)
            g = groups[o0:o1]
            for gi in np.unique(g):
                exp_sum[gi] += spec[g == gi].sum(0)
            if rng is not None:
                counts[o0:o1] = rng.poisson(spec).astype(np.uint32)
        return {"counts": counts, "amp": amp, "a_free": a_free, "t_eff": t_eff, "t_seg": t_seg, "exp_sum": exp_sum, "pix_total": pix_total,
                "line_names": [self.comps[i].name for i in self.line_comps], "med": med}
