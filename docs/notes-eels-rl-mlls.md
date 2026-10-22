# Notes for the merge: SpectroKit 0.10.0, EELS slice (Richardson-Lucy and MLLS)

For the session that merges the 0.10.0 pieces (this file is not part of the release; delete it after the merge). Branch `worktree-agent-abc992e7299a07f73`, two commits on top of `a44759b`.
Nothing under CHANGELOG, parity, status, open-items, README or Package.swift was touched.

## CHANGELOG bullets (0.10.0, under the EELS heading)

- **Deconvolution:** `EELSDeconvolution.richardsonLucy(_:psf:options:)` (`RichardsonLucyOptions.iterations`, default 15): exSpy's `richardson_lucy_deconvolution` on a core-loss or low-loss spectrum image, a shared one-pixel PSF or one PSF per pixel, per pixel on all cores. Equals exSpy to 8e-15 relative (worst of 10 pinned cases, 7.7e-8 of the `assert_allclose` allowance). A pixel whose iterate leaves the real line (exSpy: NaN) is zeros with `unavailable` `.divisionByZero` / `.nonFiniteResult`.
- **MLLS fit:** `EELSMLLS.fit(coreLoss:edges:microscope:lowLoss:mask:options:)`: the multiple linear least squares fit of an EELS spectrum image (HyperSpy `Model1D.fit(optimizer="lstsq")` on the exSpy EELS model with the power-law exponent fixed). One least-squares solve per pixel gives the power law's A, each master edge's intensity and any given reference shapes, each with its standard error, plus the residual and `EELSMLLSResult.modelCurve(pixel:)`. The exponent is `.given`, `.perPixel` or exSpy's `.twoArea` estimate; the window is `set_signal_range(start, end)`. Equals HyperSpy to 1.1e-4 of the `assert_allclose` default allowance (rtol 1e-7) on 14 pinned runs (amplitudes, `p_std`, residual, degrees of freedom, curve). `validation: "none"`. `EELSQuantification.composition(_:symbols:)` also takes an `EELSMLLSResult`.
- Deviations to know: the MLLS columns are scaled to unit length before the solve (numpy's `lstsq(rcond=None)` silently drops the power law when the edge columns are 1e13 times larger, for example with a low loss of area 1e6); a singular design is a pixel with `.fitFailed` (HyperSpy raises `LinAlgError`); Richardson-Lucy needs a PSF with the spectrum's channel count (exSpy fails with a broadcast error on any other length).
- Tests: `RichardsonLucyTests`, `EELSMLLSTests` (fast); `RichardsonLucyPinsTests`, `MLLSPinsTests`, `RLMLLSSpeedTests` (parity target); `tools/eels-rl-mlls/pins.py` writes `Tests/SpectroEELSTests/Fixtures/eelsrm-*` (50 arrays + `eelsrm-pins.json`, 1.1 MB, byte-identical on a second run).

Migration: none. New public names only: `EELSDeconvolution.richardsonLucy`, `RichardsonLucyOptions`, `EELSMLLS`, `EELSMLLSOptions`, `EELSBackgroundExponent`, `EELSAmplitude`, `EELSMLLSPixel`, `EELSMLLSResult`, `EELSMLLSError`, `EELSQuantification.composition(_: EELSMLLSResult, symbols:)`. No existing name changed; no existing enum gained a case (the existing `EELSDeconvolutionError.invalidIterations` / `.kernelSizeMismatch` / `.shapeMismatch` and `EELSUnavailable.divisionByZero` / `.nonFiniteResult` / `.fitFailed` were already there).

## docs/parity.md

Replace the row (line 191) `richardson_lucy_deconvolution | none | missing | NO | study | no numeric test upstream |` with:

| `richardson_lucy_deconvolution` (psf, iterations) | `EELSDeconvolution.richardsonLucy` | present | TOL | study | none upstream (`exspy/tests` only checks that it is refused on a non-uniform axis); `assert_allclose` defaults for float64: rtol 1e-7, atol 0, per channel | RichardsonLucyPinsTests `testRichardsonLucyEqualsExSpy` (10 cases: shared and per-pixel PSF, noise-free and Poisson, 0 / 5 / 15 / 40 iterations, flat-topped PSF (first argmax), PSF centre at channel 3, zeros giving NaN; worst 7.7e-8 of the allowance); RichardsonLucyTests (blurred peaks recovered, one iteration by hand, delta PSF and 0 iterations are the identity, refusals). Direct convolutions as numpy (no FFT, no wrap). Needs the PSF to have the spectrum's channel count (exSpy: broadcast error otherwise). A pixel exSpy returns NaN for is zeros with a reason |

Add after the `EELSModel.two_area_background_estimation, fit_background, quantify` row (line 204):

| `Model1D.fit(optimizer="lstsq")` on the EELS model with the power-law exponent fixed (the multiple linear least squares; `p_std` from `_calculate_covariance`; `set_signal_range`) | `EELSMLLS.fit`, `EELSMLLSResult.modelCurve(pixel:)`, `EELSQuantification.composition(_: EELSMLLSResult, ...)` | present | TOL | study | `exspy/tests/models/test_linear_model.py::test_convolved_and_std_error` (lstsq against LM, `assert_allclose` defaults on values and `p_std`); the same defaults here, rtol 1e-7 | MLLSPinsTests `testMLLSEqualsHyperSpyLstsq` (14 runs: Fe L twin, C N O K, Fe + Cu two masters, Fe L with the low-loss convolution; whole axis and an explicit window; exponent planted or from the two-area estimate; A, intensities, `p_std`, RSS, dof, window indices, curve: worst 1.1e-4 of the allowance; the noise-free planted-exponent run, whose residual is rounding noise, compared at the noise floor: RSS < 1e-20 of the data's sum of squares, standard error < 1e-9 of the amplitude); EELSMLLSTests (planted recovery, errors against the scatter of 300 Gaussian-noise realisations within 12 %, badly scaled columns, references, window, refusals, masks, composition). DEVIATIONS: columns scaled to unit length (numpy's `lstsq(rcond=None)` drops the power law for a low loss of area 1e6); a singular design is `.fitFailed` (HyperSpy: `LinAlgError`); the unconstrained fit can return a negative intensity (as `lstsq`). The standard errors assume constant variance (HyperSpy's too): on Poisson data they overstate the background's amplitude error (7x on the pinned Fe L spectrum). Reference shapes (`references`) have no HyperSpy counterpart pinned (planted truth only). Not offered: weights, `ols` / `nnls` / `ridge`, a free exponent (that is `EELSModelFit.fit`) |

Summary table (EELS present 8 -> 10, missing 16 -> 15, rows 31 -> 32; all: present 39 -> 41, missing 30 -> 29, rows 88 -> 89; TOL 22 -> 24; study 57 -> 58 rows, 35 -> 37 present, 22 -> 21 partial or missing). The sentence on line 74 loses `richardson_lucy_deconvolution`.

## docs/open-items.md, item 4

Replace the Richardson-Lucy clause ("Richardson-Lucy deconvolution (design section 5, not started); ") with nothing, and append: "Richardson-Lucy and the MLLS fit landed in 0.10.0; still open there: a Metal or FFT path for Richardson-Lucy at 64 x 64 x 2048 and more (the direct convolutions take 1.1 s for 32 x 32 x 2048 at 15 iterations on the Mac, about 4.4 s for 64 x 64), weighted MLLS (Poisson weights; the unweighted standard errors overstate the background's by 7x on the pinned spectrum), MLLS with a free onset or fine structure (shares the fine-structure item), and the MLLS and Richardson-Lucy on real data (badge `validation: "none"`)."

## Deviations, in one place

1. **Richardson-Lucy:** none in the arithmetic. NaN pixels become zeros plus a reason (the kit rule). PSF and spectrum must have equal channel counts (exSpy raises a broadcast error for any other length; `kernelSizeMismatch` up front). `fftSize` and `taperedChannels` of the returned `DeconvolvedSpectrumImage` are 0.
2. **MLLS, columns scaled:** numpy `lstsq(rcond=None)` truncates singular values below eps x max(M, N) of the largest. The pins first used a low loss of area 1e6 (the old `eels16-model` convention) and HyperSpy returned A = 8.6e-16 instead of 2e11 (the power law dropped, residual 2x the smart fit's); the pins script therefore uses a unit-area low loss, where HyperSpy is sound. The kit scales every column to unit length, so it answers both; tested by `testBadlyScaledColumnsKeepThePowerLaw`.
3. **MLLS, singular designs** are `.fitFailed` pixels; HyperSpy raises. Two equal references, a zero column, or a QR whose smallest diagonal falls below 1e-10 of the largest.
4. **MLLS, the window** is `set_signal_range`: both ends included and `endEnergyEV == nil` keeps the last channel. The smart fit of `EELSModelFit` leaves the last channel out (exSpy's `smart_fit` stage); not changed. An edge onset outside the window is refused (`noEdgeInRange`), and the pre-edge window must be at least 4 channels (the shared `prepare` rule) even with a given exponent.
5. **MLLS, the two-area exponent** reuses `EELSModelFit.twoAreaBackground` (already pinned to 1e-7); a pixel it cannot estimate is `.fitFailed`.
6. **MLLS standard errors:** HyperSpy's, ordinary least squares, `s sqrt(diag((X^T X)^-1))` with `s^2 = RSS / (n - k)`. HyperSpy computes them from columns multiplied by their coefficients, which gives the same number (the coefficients cancel); a coefficient of exactly zero breaks HyperSpy's route, not this one. They assume constant variance. `standardError` is nil only when the window has no degrees of freedom (refused earlier, so in practice never).

## Measured agreement

- Richardson-Lucy, 10 cases, 6 pixels each, 240 channels: worst error 7.7e-8 of the rtol 1e-7 allowance (40 noisy iterations); the others 1e-8 to 4e-8. Zeros case: the 3 even pixels are NaN in exSpy and unavailable here, the 3 odd ones equal.
- MLLS, 14 runs, 6 pixels each: A 1.1e-4, A std 0.016 (the noise-free run with a wrong two-area exponent; 7.9e-7 on the others), RSS 0.011 (same run; 2e-6 on the others), curve 1.1e-4, exponent 0, intensity 9.3e-8, intensity std 0.016 (same). All as fractions of the rtol 1e-7 allowance. The noise-free planted-exponent run, compared at the noise floor: A std 1.4e-4 and intensity std 4.8e-8 of the 1e-9-of-amplitude bound, RSS 9e-11 of the 1e-20-of-data bound.
- Timings (Mac, release, the two speed tests alone): Richardson-Lucy 32 x 32 x 2048, 15 iterations, shared PSF: 1.10 s; MLLS 64 x 64 x 600, one twin pair, two-area exponent: 0.14 s. Not compared with Python (no oracle run for timing).
- Fast target and parity target both green: `swift test -c release --parallel` 437 tests; zero warnings (no `warning:` line other than the xcframework "not stripping" notes).

## Not done

- Richardson-Lucy on the GPU or by FFT (open item above), 64 x 64 x 2048 takes about 4.4 s.
- Weighted MLLS; MLLS with fine structure or a free onset.
- The macTEM design (`rooms-2026-10-21.md` section 5) was read for the ask only; no app code touched.
- No `docs/design` note, no DocC page for the new types (the DocC catalogue is outside this slice).
