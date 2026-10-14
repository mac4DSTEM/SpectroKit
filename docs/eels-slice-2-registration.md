# EELS slice 2: power-law background and the C K edge quantified (registration)

Registered 2026-10-14, before any code, by SpectroKit's session (the owner's order, suite `ROADMAP.md`, "Cross-repo
order" 5: "EELS slice 2: power-law background and one edge quantified … Cross sections: exSpy's open dft/Dirac GOS
(CC-BY-4.0), never Gatan's Hartree-Slater tables. Second oracle: pyEELSMODEL"). Tier 1: it makes a number a scientist
reads (an areal density of atoms). What is written here is fixed before the code; a change after code starts is an
amendment, dated, with its reason. Before this registration the only runs were the cross-section comparison of section
4.3 (exSpy against pyEELSMODEL, no SpectroKit code) and reading the GOS files' structure.

## 1. What slice 2 makes, and the edge

In `SpectroEELS`, from a core-loss EELS spectrum image (counts per pixel per channel, uniform energy axis in eV, axis
binned) and the same pixels' low-loss spectrum image (Dual EELS), per pixel:

- the power-law background A·E^−r fitted by the two-area method in a pre-edge window [E_a, E_b];
- I_k(Δ): the background-subtracted counts summed over the edge window [E_k, E_k + Δ);
- σ_k(β, Δ): the partial cross section of the edge in barns, from exSpy's GOS, summed over the same channels;
- the areal density by Egerton's ratio method, n = I_k(Δ) / (I_low · σ_k(β, Δ)), in atoms per nm²
  (1 barn = 1e−10 nm²), with I_low either I_0 (the zero-loss sum of slice 1; single scattering) or I_low(Δ), the
  low-loss sum from the spectrum's start to Δ (Egerton, *EELS in the Electron Microscope*, 3rd ed., eq. 4.66, the
  standard correction for plural scattering; the default);
- σ_n, the counting-statistics standard deviation of n (section 6), and the inputs (A, r, I_k, I_b, σ_k, I_low).

**The edge: C K** (onset 284 eV, exSpy's `eels_binding_energies.json`). The owner's `EELS_2` high-loss SI starts at 150
eV and holds C K, N K and O K, with GMS's own C, N and O maps beside it. C K is the one edge of the three whose pre-edge
window holds no other edge: N K (401 eV) and O K (532 eV) sit on C K's extended tail (and O K on N K's), where a power
law fitted below the edge is known to misjudge the background; that needs several edges modelled together, a later
slice. So the gates (section 7) are on C K. The code is generic over K shells, and the N K and O K tables ship too,
pinned against exSpy as C K is (agreement only, no planted gate); on the owner's data they are diagnostics.

Every result carries how it was made: "power law (two-area, HyperSpy 2.4.0) + ratio method (Egerton eq. 4.65/4.66),
cross section exSpy 7185a4d1 dft GOS (Segger, Guzzinati and Kohl 1.5.0)", the windows, E0, α, β, the I_low choice, and
`validation: "none"` (section 8). A pixel the method cannot answer is `nil` with a reason (the two-area estimate fails:
a window sum ≤ 0 or equal sums; I_low ≤ 0; σ_k = 0; the window outside the axis). A negative I_k is reported, not clipped.

Not in slice 2: a fitted model (least squares over several components, the fine structure, exSpy's `EELSModel`),
several edges together, Fourier-ratio deconvolution, L/M edges, the Hartree–Slater or hydrogenic GOS, Dirac GOS
(section 4.4), zero-loss alignment, non-uniform axes, energy-axis calibration, a reader of the exposure times.

## 2. The reference

exSpy `7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e` with HyperSpy 2.4.0, NumPy 2.5.4, SciPy 1.18.1 (`References/exspy-venv`,
Python 3.14.7), as slice 1. The GOS: exSpy's default `GOS="dft"`, the GOSH file exSpy fetches,
`Segger_Guzzinati_Kohl_1.5.0.gosh` (md5 `7fee8891c147a4f769668403b54c529b`, exSpy's own pin; DOI 10.5281/zenodo.7645765,
CC-BY-4.0), copied to `References/gos-dft-1.5.0.gosh`. Second oracle: pyEELSMODEL `eed9f0721d5b`
(`References/pyEELSMODEL-pin`, GPL-3.0), its `KohlLossEdge` reading the same file. Never Gatan's Hartree–Slater tables.

## 3. The method, pinned (file:line at the pins)

### 3.1 The background (HyperSpy 2.4.0 `_components/power_law.py:100-187`, `_signals/signal1d.py:1102-1152`)

`PowerLaw.estimate_parameters(signal, x1, x2)`: `i1, i2 = axis.value_range_to_indices(x1, x2)`; if `i1 + i2` is odd,
`i2 −= 1`; if `i2 == i1`, `i2 += 2`; `i3 = (i1 + i2) // 2`; `x1, x2, x3` = the axis values of `i1, i2, i3`; I1 = the
binned sum over `[i1, i3)`, I2 over `[i3, i2)` (`integrate1D`, binned: a sum, by NumPy's pairwise sum as slice 1);
r = 2 (ln I1 − ln I2) / (ln x2 − ln x1); k = 1 − r; A = k · I2 / (x2^k − x3^k); NaN and ±inf replaced by
`np.nan_to_num` (0 and ±1.797e308), and a divide-by-zero makes the whole estimate fail (exSpy returns False): ported as a
`nil` pixel with the reason. The background in channel c is the model's value on a binned axis: A · (E_c − origin)^−r ·
scale with origin 0 and left_cutoff 0 (0 for E_c ≤ 0), `remove_background(fast=True)` = `self − model.as_signal()`; how
`as_signal` applies the scale is read from `models/model1d.py` and pinned.

### 3.2 The edge window

[E_k, E_k + Δ) in channels: `isig[E_k : E_k + Δ]`, HyperSpy's value slicing (the same value-to-index rule as slice 1's
`EnergyAxis.index(of:)`, ported and pinned there). E_k is the edge's onset from exSpy's table unless the caller gives
one. Default Δ = 50 eV; the pins also hold 30, 100 and 150 eV. I_k = Σ (counts − background) over the window; I_b = Σ
background over it.

### 3.3 The cross section (exSpy `components/_eels_cl_edge.py:409-494`, `_misc/eels/base_gos.py`, `gosh_gos.py`,
`utils/eels/effective_angle.py`)

`EELSCLEdge("C_K", GOS="dft")`, `set_microscope_parameters(E0, alpha, beta, energy_scale)`: the effective collection
angle by `effective_angle(E0, onset, alpha, beta)` (Egerton 2nd ed. p. 420; α = 0 gives β); `_integrate_GOS`:
`TabulatedGOS.integrateq(onset, angle, E0)` — per tabulated energy, the q limits from E, γ = 1 + E0/511.06,
T = 511060 (1 − 1/γ²)/2, the GOS linearly interpolated to q_min and q_max (`get_qaxis_and_gos`, clipped at 0), Simpson's
rule (`scipy.integrate.simpson`, SciPy 1.18.1, on the non-uniform ln((a0 q)²) grid), times 4π a0² R² / (E T) ·
occupancy · 1e28 (barn/eV); then `scipy.interpolate.make_interp_spline(E, qint, k=3)` (not-a-knot cubic) for
E_onset ≤ E < E_max, and beyond E_max the power law through the last two tabulated points. CODATA constants as SciPy
1.18.1 holds them (a0, Rydberg in eV), copied with their source. `function(E)` × scale summed over the edge window's
channels is σ_k(β, Δ), what exSpy's model predicts for the window with intensity 1. The GOSH reading: the `K1` table,
`free_energies − min(free_energies)` + onset, the `q` axis, `occupancy_ratio`.

The tables SpectroKit ships: the dft `C/K1`, `N/K1`, `O/K1` groups (data, q, free_energies, occupancy ratio), extracted
by a committed script (`tools/eels-edge/extract_gos.py`, h5py) into `Bundle.module` resources in `SpectroEELS`, with the
source file's md5 and DOI in each resource and CC-BY-4.0 attribution (Segger, Guzzinati and Kohl) in NOTICE; the
extraction is byte-reproducible and the values bit-identical to the GOSH file's.

### 3.4 The ratio

n = I_k / (I_low · σ_k) · 1e10 atoms/nm² (σ in barns). I_low = I_0 from `EELSThickness` (slice 1, any threshold rule),
or I_low(Δ) = the low-loss counts from the first channel to the channel of energy Δ (value slicing, end exclusive).
When the low-loss and core-loss spectra were recorded with different exposures (Dual EELS), the caller gives the ratio
`coreLossToLowLossDose` (exposure_HL / exposure_LL, default 1), and I_low is multiplied by it. This is the caller's
number: the reader does not read exposures (section 1).

## 4. Pins

### 4.1 exSpy (`tools/eels-edge/pins.py`, written before the Swift code)

For every planted image (section 5) and the grid below: the background estimate (i1, i2, i3, x1..x3, I1, I2, r, A, the
background per channel), I_k, I_b, and exSpy's `function(E)` per channel and σ_k for each Δ; the effective angle;
`qint` at every tabulated energy and the spline's knots and coefficients for one setting. Grid: E0 60, 80, 200, 300 keV;
α 0, 1, 10, 30 mrad; β 5, 20, 50, 100 mrad; scale 0.1, 0.25, 1.0 eV; C, N and O K.

Agreement required: the background indices equal; I1, I2, I_k, I_b relative ≤ 1e-12; r, A relative ≤ 1e-12; the
effective angle relative ≤ 1e-14; `qint` relative ≤ 1e-12 (Simpson ported); `function(E)` and σ_k relative ≤ 1e-10 (the
spline is a banded solve, ported; the bound allows the solve's own rounding and nothing else; tightened if the port
meets more); n relative ≤ 1e-10. A difference beyond these is a port failure, never a tolerance to widen.

### 4.2 Reproducibility

The pins file records the script's sha256, the GOS file's md5, and the environment; regenerating it gives the same bytes.

### 4.3 pyEELSMODEL, the second oracle (measured 2026-10-14, before code)

pyEELSMODEL's `KohlLossEdge` integrates the same GOS by its own code (a uniform 100-point ln q² grid, Kohl's angular
correction factor instead of the effective angle, onset excluded). One reading had to be made: its loader keeps the GOS
as (192, 97, 1) and NumPy 2.5 refuses its scalar assignment; the trailing axis is squeezed before the call (shape only).
Measured on 1 eV channels from 150 eV, σ_k for C, N, O K, Δ 50, 100, 150 eV, (E0, α, β) = (200, 0, 20), (200, 10, 20),
(300, 0, 50), (80, 0, 10): pyEELSMODEL against exSpy from −2.5 % (N K, Δ 50, α 10) to +1.1 % (O K, Δ 150, 80 keV); C K
within −1.1 % to +0.6 %. Gate: the port's σ_k within 3 % of pyEELSMODEL's on that grid (scale 1.0 eV and 0.25 eV). It
is a check that both codes read the tables the same way, not a pin: the port follows exSpy.

### 4.4 Dirac

The Dirac GOS (`Dirac_GOS_compact.gosh`, md5 `01a855d3750d2c063955248358dbee8d`, DOI 10.5281/zenodo.12800856) is not
shipped in slice 2. Its σ_k against the dft one for C K on the grid is reported by the pins script as a diagnostic.

## 5. Truth (independent of exSpy's quantification; `tools/eels-edge/make_planted.py`, NumPy only, committed with its
fixture before the code)

A core-loss axis from 150 eV, 0.25 eV per channel, 2000 channels (to 650 eV), and the low-loss axis of slice 1's
planted image (−10 eV to 160 eV, 0.05 eV). Per pixel, a planted areal density n_true in {2, 5, 10, 20, 50} atoms/nm²
of carbon and a planted background B(E) = A E^−r with (A, r) in {(1e9, 3.0), (5e8, 2.5), (2e10, 3.5)}. The edge's
single-scattering shape is n_true · I_low · σ(E) · scale with σ(E) from the exSpy pins (the cross section is then the
same on both sides by construction: this truth tests the background, the windows and the ratio, not the GOS).

1. **Single scattering, noiseless**: background integrated exactly over each channel from the analytic power law, plus
   the edge; I_low = I_0 = 1e7. The generator writes, per pixel and Δ, the bias the method itself makes (the two-area
   estimate's error from channel sums standing in for integrals, extrapolated under the window, computed from the
   components, not by the method).
2. **Plural scattering, noiseless**: the edge convolved with the planted low-loss spectrum of slice 1 at τ = 0.3, 0.7,
   1.3 (Poisson plural scattering, the low-loss normalised to its own total); I_low(Δ) from the same low-loss. The
   generator writes the ratio method's own bias for each τ and Δ (from the convolution, exactly).
3. **Noisy**: a Poisson copy of 1 and 2 (seed 20261015).

## 6. Uncertainty

Counting statistics only: the window sums are Poisson. I_k + I_b is the window's total; I_b comes from (A, r), which
come from I1 and I2. σ_n² is the first-order propagation: Var(I_k) = (I_k + I_b) + (∂I_b/∂I1)² I1 + (∂I_b/∂I2)² I2,
the derivatives taken analytically through the two-area formulas, and σ_n = n · sqrt(Var(I_k)/I_k² + 1/I_low) (I_low's
own Poisson term; σ_k has none). Its limits, stated with it: the stored counts are not electron counts unless the
detector's conversion is applied; the power law's model error, the cross section's accuracy (section 4.3 shows two
codes differ by up to 2.5 %), E0, α, β, the dose ratio and the onset are not in it.

## 7. Gates and predicted outcomes (registered now)

1. Pins (4.1): all within the stated bounds, every image and grid point. Predicted: met.
2. pyEELSMODEL (4.3): within 3 %. Predicted: met (measured −2.5 % to +1.1 % before code).
3. Planted single scattering, noiseless: |n − n_true| ≤ the generator's predicted bias + 1e−9 relative, every pixel and
   Δ; and |n − n_true| / n_true ≤ 2 % for Δ = 50 eV with the default window [E_k − 50, E_k − 5] eV. Predicted: the bias
   is below 1 % (the generator's numbers, committed first, are the prediction).
4. Planted plural scattering, noiseless, I_low(Δ): |n − n_true| ≤ the predicted bias + 1e−9 relative; the I_0 route is
   reported beside it (its bias grows with τ, Egerton's reason for eq. 4.66).
5. Planted noisy: per pixel |n_noisy − n_noiseless| ≤ 4 σ_n; over 200 realisations (seeds 1 to 200, in the test) the
   standard deviation of n is within 15 % of σ_n for every n_true ≥ 5 atoms/nm² at Δ = 50 eV. Below that the spread is
   reported without a bound.
6. Every new test broken once by a mutant aimed at its rule (planned: the two-area parity rule dropped; i3 rounding; r's
   sign; k = r − 1; background without scale; the edge window end inclusive; the onset from the wrong subshell; the
   effective angle skipped with α > 0; γ's 511.06 → 511; Simpson replaced by the trapezoid; the spline's not-a-knot
   replaced by natural; the extrapolation power law through the wrong points; the occupancy ratio dropped; 1e10 → 1e9;
   the dose ratio inverted; I_low(Δ) end inclusive; σ_n without the background terms).
7. One Gate B refuter on the frozen commit (a second only on a named doubt); Gate D only if a discrepancy's cause is
   unproven.

## 8. Real data (diagnostics, never a gate)

On the owner's `EELS_2` (`$MACEM_DATA/eels/EELS_2/SI data (2)(2)/143_STEM SI.dm4`, the sha256 of the slice-1 real-data
registration), after R1 of that registration has read it: the C K areal-density map with the default windows and both
I_low routes, with the dose ratio from the file's exposure tags read by RosettaSciIO (logged), E0, α and β from the
owner or the file (logged; when absent, the run says so and reports n for stated assumed values, labelled assumed); and
its comparison with GMS's own C map in `EELS Map (1)/` (correlation, ratio median and spread), reported, never judged.
N K and O K maps the same way, labelled "background under a preceding edge's tail". The numbers-only log goes under
`docs/eels-real-data/`.

## 9. What is not claimed

Agreement with exSpy and recovery of planted n do not make an areal density right on a real specimen: the cross section
itself (dft GOS, no solid-state effects near the onset), the power-law background and the ratio method's approximations
are what a standard of known composition and thickness tests. `validation: "none"` until that check, registered later
with the owner.

## 10. Amendments

(none yet)
