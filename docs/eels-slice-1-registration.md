# EELS slice 1: the t/λ thickness map (registration)

Registered 2026-10-14, before any code, by SpectroKit's session (the owner's order, suite `ROADMAP.md`: "split the
shared core from EDX, then EELS slice 1: a t/λ thickness map with exSpy pins"). Tier 1: it makes a number a scientist
reads (thickness, which feeds mac4DSTEM's precipitate number density). What is written here is fixed before the code; a
change after code starts is an amendment, dated, with its reason.

## 1. What slice 1 makes

A new module and product, `SpectroEELS`, depending on `SpectroCore` only. From a low-loss EELS spectrum image (counts
per pixel per channel on a uniform energy axis in eV, the zero-loss peak at 0 eV), per pixel:

- `tOverLambda`: t/λ by the log-ratio method, ln(I_t / I_0).
- `i0`, `iTotal`: the two sums it comes from; `threshold`: the energy the zero-loss sum stops at.
- `sigmaCounting`: sqrt(1/I_0 − 1/I_t), the counting-statistics standard deviation of t/λ when the stored counts are
  Poisson counts (section 6).
- `zlpCentre`: the energy of the spectrum's maximum, a diagnostic of alignment (exSpy's `estimate_zero_loss_peak_centre`
  without its masking); nothing is shifted.
- Optional absolute thickness `thicknessNM` = (t/λ) · λ, with λ either given (nm) or from the material's density by
  Iakoubovskii et al. 2008 eq. 9 with the angular correction, exactly as exSpy applies them (section 3.4).

Every result says how it was made: the method ("log-ratio, exSpy 7185a4d1"), the threshold rule, the λ source, and
`validation: "none"` until a real-truth check (section 8). A pixel the method cannot answer is `nil` with a reason
(threshold not found; I_0 ≤ 0; I_t ≤ I_0 is allowed and gives t/λ ≤ 0, reported, not clipped).

Not in slice 1: zero-loss alignment, a fitted zero-loss model, Fourier-log or Fourier-ratio deconvolution,
Kramers–Kronig, TPP-2M, non-uniform axes, unbinned (Simpson) integration, any file reader. Slice 1b (registered here,
Tier 2): `DM4Experiment.readEELSSpectrumImage`, tested on RosettaSciIO 049e7d70's public
`digitalmicrograph/3D/EELS_SI.dm4` (a 2 × 2 × 2048 core-loss SI) against RosettaSciIO's own reading; the owner's
low-loss files are diagnostics, never a gate.

## 2. The reference

exSpy `7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e` (fetched 2026-10-14 into the gitignored `References/exspy-7185a4d1`,
one commit) run with HyperSpy 2.4.0, RosettaSciIO 0.14.0, NumPy 2.5.4, SciPy 1.18.1 in `References/exspy-venv` (Python
3.14.7). Agreement with exSpy is agreement, not truth (CLAUDE.md); truth is section 5.

## 3. The method, pinned (file:line at the pin)

### 3.1 The threshold (`exspy/signals/_eels.py:641-753`, `estimate_elastic_scattering_threshold`)

Defaults `window = 10.0`, `tol = None`, `window_length = 5`, `polynomial_order = 3`, `start = 1.0`. Indices
`[min, max) = value_range_to_indices(start, start + window)` of the energy axis; at least 10 channels or an error. On
that sub-range, the first derivative by Savitzky–Golay: HyperSpy 2.4.0 `smooth_savitzky_golay` calls
`scipy.signal.savgol_filter(window_length, polynomial_order, deriv = 1, delta = axis.scale)` with SciPy's default
`mode = "interp"` (polynomial fits at the two edges), on the CROPPED sub-range. With `window_length = 0` the derivative
is HyperSpy's `derivative` instead (registered as an option, pinned the same way). `tol`, when not given, is ONE number
for the whole image: the maximum over pixels of each pixel's minimum |derivative| in the sub-range. Per pixel the
threshold is the energy of the first sub-range channel where |derivative| ≤ tol; a first index of 0 gives NaN (exSpy's
rule: no inflexion found). So one pixel's threshold depends on every other pixel through `tol`: ported as is.

### 3.2 The zero-loss sum (`_eels.py:566-639`, `estimate_elastic_scattering_intensity`)

A per-pixel threshold θ: `ind = axis.value2index(θ)` (HyperSpy's rounding, to be read and ported exactly), I_0 = the sum
of channels `[0, ind)`. A single number θ: `isig[:θ]`, HyperSpy's value slicing (end exclusive), then the sum.
SpectroKit sums: the energy axis is binned (detector counts per channel). exSpy integrates with Simpson's rule when the
axis is not binned; that path is not ported. Measured on exSpy's own line scan (below): with the axis marked unbinned,
exSpy's fixed-threshold route is off from the truth by 0.6975 (about ln 2), its estimated-threshold route by 0.0037;
with the axis binned both are near 0.004. Recorded as a difference, not ported, not reported upstream by this session.

### 3.3 The ratio (`_eels.py:755-868`, `estimate_thickness`)

I_t = the sum over every channel of the spectrum (`integrate1D`, binned). I_0 from 3.2, or, when a zero-loss spectrum is
supplied (exSpy's `zlp =`), the sum of that spectrum (ported: it is a sum). t/λ = ln(I_t / I_0).

### 3.4 λ and the angular correction (`exspy/utils/eels/electron_inelastic_mean_free_path.py`)

- `iMFP_Iakoubovskii(density, electron_energy)` (`:32-68`): 1/λ = 11 ρ^0.3 / (200 F E0) · ln(θ_C² / θ_E²), θ_C = 20
  mrad, θ_E = 5.5 ρ^0.3 / (F E0), F = (1 + E0/1022) / (1 + E0/511)², E0 in keV, ρ in g/cm³, λ in nm.
- `iMFP_angular_correction(density, beam_energy, alpha, beta)` (`:121-161`; `_F` and `_theta_E` at `:24-29`):
  ln(θ_C²/θ_E²) / ln(A θ_C² / (B θ_E²)), A = α² + β² + 2θ_E² + |α² − β²|, B = α² + β² + 2θ_C² + |α² − β²| (mrad).
- `estimate_thickness` with a density: t/λ is MULTIPLIED by the angular correction (it needs E0, α, β), and λ is
  Iakoubovskii's unless a mean free path is given; then t = (t/λ)·λ. With a mean free path and no density, t = (t/λ)·λ
  with no correction. Ported as exSpy does it, including that a given λ is still multiplied by the correction when a
  density is given.

## 4. Pins (agreement with exSpy)

A generator, `tools/eels-thickness/pins.py` (run in `References/exspy-venv`, exSpy constructed directly from the pinned
checkout), writes the pins into a fixture before the Swift code exists: for every truth case in section 5 and exSpy's
own line scan, exSpy's estimated thresholds, I_0, I_t, t/λ (estimated threshold; fixed thresholds 2.5, 4.5 and 6.0 eV;
the zero-loss route where a zero-loss spectrum exists), absolute thickness for (ρ 2.70 g/cm³, E0 200 keV, α 10, β 20
mrad) with and without λ = 120 nm given, and `iMFP_Iakoubovskii` / `iMFP_angular_correction` on a grid of ρ (1, 2.7,
7.9, 19.3), E0 (60, 80, 120, 200, 300 keV), α (1, 10, 30), β (5, 20, 100).

Agreement required: the same threshold channel for every pixel; I_0 and I_t relative difference ≤ 1e-12; t/λ absolute ≤
1e-12; λ and the correction relative ≤ 1e-13. A difference is a failure of the port, never a tolerance to widen.

## 5. Truth (independent of exSpy)

### 5.1 Planted spectra (`tools/eels-thickness/make_planted.py`, NumPy only, committed with its fixture before the code)

Energy axis −10 to 160 eV, 0.05 eV per channel (3400 channels), zero-loss peak a Gaussian at 0 eV with σ = 0.25 eV. A
single-scattering distribution S(E): the Drude loss function E Γ E_p² / ((E² − E_p²)² + (E Γ)²) for E > 0, E_p = 15.0
eV, Γ = 0.8 eV (aluminium-like), normalised to unit sum over the axis. Plural scattering by Poisson statistics: I(E) = N
Σ_n e^(−τ) τ^n / n! · (Z ⊛ S^⊛n)(E), the convolutions on the channel grid, n up to the first term below 1e-14 of the
total. τ (the planted t/λ) in {0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0, 1.3, 1.6, 2.0}, as a 2 × 5 image; N = 1e6 (noiseless)
and a Poisson-noised copy (seed 20261014). The generator also writes, per τ and per threshold, the log-ratio value the
planted components imply (the inelastic intensity below θ and the zero-loss intensity above θ and beyond the axis,
computed from the components, not by the method): the method's own bias, so that the gate below separates the method's
bias from a port's error.

### 5.2 exSpy's simulated line scan

`exspy/tests/signals/data/EELS_LL_linescan_simulated_thickness_variation.hspy` and its zero-loss twin (17 spectra, axis
−100 eV + 0.5 eV × 1024, binned, E0 200 keV, α 10, β 20 mrad; GPL-3.0 test data of exSpy, copied with attribution as a
fixture), planted t/λ = 0.3, 0.4, ..., 1.9.

## 6. Uncertainty

With I_0 and I_t Poisson counts and I_0 a subset of I_t, Var(ln I_t − ln I_0) ≈ 1/I_0 − 1/I_t. Reported as
`sigmaCounting`. Its limits, stated with it: the stored counts of a spectrometer are not electron counts unless the
detector's conversion is applied; the threshold's own variability, the λ model's accuracy and the angular correction's
inputs are not in it. mac4DSTEM must carry the λ source and its own uncertainty separately.

## 7. Gates and predicted outcomes (registered now)

1. Pins (section 4): all equal within the stated bounds.
2. Planted, noiseless: |t/λ − τ| ≤ the bias the generator predicts for that τ and threshold + 1e-9, for every pixel and
   route; and |t/λ − τ| ≤ 0.02 for every τ ≤ 2.0 with the estimated threshold (predicted: the bias grows with τ through
   the plasmon intensity below the threshold; the generator's numbers are the prediction and are committed first).
3. Planted, noisy: per pixel |t/λ_noisy − t/λ_noiseless| ≤ 4 σ_counting; over 200 noise realisations (seeds 1 to 200,
   generated in the test, not stored) the standard deviation of t/λ is within 15 % of σ_counting for every τ.
4. exSpy's line scan (predicted by running exSpy at the pin on 2026-10-14, axis binned): estimated thresholds 4.0 and
   4.5 eV, max |t/λ − truth| 0.004117; fixed 4.5 eV, 0.004402; zero-loss route, 0.003760. The port reproduces exSpy's
   values (gate 1), so the same errors.
5. Every new test broken once by a mutant aimed at its rule (planned: threshold index ± 1; I_0 including the threshold
   channel; `tol` per pixel instead of global; Savitzky–Golay without `delta`, or `mode` other than interp, or window 7;
   ratio inverted; angular correction applied without a density or skipped with one; θ_C 20 → 25; F's 1022/511 swapped;
   σ from 1/I_0 + 1/I_t).
6. One Gate B refuter on the frozen commit (a second only on a named doubt); Gate D only if a discrepancy's cause is
   unproven.

## 8. What is not claimed

Agreement with exSpy and recovery of planted τ do not make the thickness right on a real specimen. `validation: "none"`
until a sample of known thickness is measured (for example a wedge or a FIB lamella measured another way); that check is
registered later, with the owner.
