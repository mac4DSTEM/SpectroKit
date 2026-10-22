# SpectroKit 0.10.0, EDS and results slice: notes for the merge

Branch `worktree-agent-a8cea44853ef54bfa`. Four commits: sum/escape model, k-factor import, sigma on wt% and at%, per-region result. Every file the slice adds is new; the
shared files touched are listed at the end. This file is for the session that merges `CHANGELOG.md`, `docs/parity.md`, `docs/status.md`, `docs/open-items.md` and `README.md`.

## CHANGELOG bullets (under 0.10.0, "EDS and results")

- **Sum and escape peaks in the EDS fit (optional, off by default).** `EDSSumEscapeFit.run(counts:axis:settings:model:)` with `SumEscapeModel`: pile-up (sum) peaks of the strongest alpha lines, area `c m A_i A_j` at `E_i + E_j` (c = tau/T, one coefficient, estimated or fixed), and one common Si-escape fraction `f` of each parent group in place of the default fit's free escape area per group. `PooledQuantificationInput.sumEscape` (nil = the fit runs exactly as before) switches it on in the Quantify run and names the parameters in the footer. No Python reference exists (exSpy's `EDSModel` has neither): planted truth only, `validation: "none"`. Every existing result is unchanged bit for bit.
- **k-factor import.** `KFactorImport.parse(_:)` reads a Cliff-Lorimer k table as Velox and other EDS software export it (element, line, k, optional sigma; tab, semicolon or comma separated, decimal comma tolerated, header optional, units and comment lines ignored); `typedK(from:elements:line:reference:)`, `apply(_:to:source:date:...)` and `cliffLorimerFactors(from:...)` hand it to `QuantificationMethod` (`.typed`) or `EDXQuantification`. Malformed rows are refused by name and line (`KFactorImportError`).
- **Sigma on wt% and at%.** `EDXQuantification.quantifyWithSigma(intensities:...)` propagates the counting sigma of the net counts (or a fit's covariance) and the factors' relative sigma (typed k, zeta, cross section) to wt%, at% and the mass thickness for every method, with or without absorption; counting and factor shares are returned apart. First order, formula stated in `EDXQuantification.sigmaFormula`. No Python counterpart; Monte Carlo over Poisson realisations agrees within 1.7 % (bound 5 %). `validation: "none"`.
- **Per-region quantification result.** `RegionQuantResult.make(from:regionName:pixelCount:)` builds, from a finished `PooledQuantification`, a Codable, Sendable record with everything a report row needs (region and pixel count, elements, k source and values, net counts and sigma per line, wt% and at% with sigma, absorption note, method hash, unlisted-line check, validation), with a CSV header and row (wide and long) and `reportRow(elements:)`.

Migration: none. All additions are new public names; no existing signature changed (`PooledQuantificationInput.init` gained a trailing `sumEscape: SumEscapeModel? = nil`).

## docs/parity.md rows (same columns as the file: reference | Swift | state | tag | priority | upstream test | evidence)

Add (no Python counterpart, planted truth; tag NOPIN as the file uses it for rows without a pin, priority `study`):

| (none: eXSpy's `EDSModel` has `add_family_lines` and no sum or escape model) sum and Si-escape peaks | `EDSSumEscapeFit.run`, `SumEscapeModel`, `SumEscapeResult`; `PooledQuantificationInput.sumEscape` (public, 0.10.0) | present | NOPIN | study | none: no reference exists | SpectroEDXTests/SumEscapeFitTests: noise-free planted c = 1e-8 and f = 0.01 recovered to 0.04 % and 0.04 %, the Ag area biased by the Al+Al sum (2750 against 2000 planted) back to 2000.9; 20 seeded Poisson draws all improve the Ag net, mean c 1.013e-8 (planted 1e-8), sigma_c within 25 % of the spread (measured 4.9e-10 against 5.2e-10); off is bit-for-bit the default fit. `validation: "none"` |
| (none) k-factor table import | `KFactorImport.parse`, `typedK`, `apply`, `cliffLorimerFactors` (public, 0.10.0) | present | PART | study | none for the table; the convention is `quantification_cliff_lorimer`, tests atol 1e-3 on percent | SpectroEDXTests/KFactorImportTests (layouts, refusals by line); SpectroKitParityTests/KFactorImportPinsTests: the planted text in 4 layouts x 2 sets parses to exSpy's documented list `[1, 1.47, 1.72]` and to a second list, and drives the kit's Cliff-Lorimer to exSpy's own weight fractions (32 runs, difference 0.0; `tools/edx-0100/pins.py`). exSpy has no k table, so the parser itself is planted-text only |
| (none: neither HyperSpy nor eXSpy reports a sigma on a composition) sigma on wt% and at% | `EDXQuantification.quantifyWithSigma` (public, 0.10.0), `EDXQuantificationSigma` | present | NOPIN | study | none | SpectroEDXTests/QuantificationSigmaTests: Monte Carlo over seeded Poisson draws of a planted 3-element case, propagated against standard deviation within 5 % (measured worst: CL 1.0 %, CL with typed-k sigma 0.6 %, CL with absorption 1.7 %, zeta 1.2 %, cross section 1.5 %); two-element CL against the hand-derived sigma to 1e-6. First order; thickness, dose and detector exact |
| (none) per-region quant result and report row | `RegionQuantResult.make`, `.csvHeader`, `.csvRow`, `.reportRow`, `.csvLongRows` (public, 0.10.0) | present | NOPIN | useful | none | SpectroEDXTests/RegionQuantResultTests: every number equals the pooled row; k, hash, absorption note, unlisted-line outcome, validation carried; Codable round trip; CSV rows line up with the headers |

No existing row changes. (The `quantification` rows' evidence is unchanged: the code behind them did not move.)

## docs/open-items.md text

- Sum/escape model: the pile-up coefficient is one number for the whole spectrum and the parents are the alpha lines of the strongest groups; family lines (Kb) are not parents. A real detector's escape fraction depends on energy; the common fraction is a first model. Not tested on real data, no standard: needs one measured spectrum with a known sum peak (a thick pure Cu or Fe sample at a high rate) before the badge can change.
- Sum/escape model: `PooledQuantification.plotModel` includes the peaks; the proposer and the unlisted-line check still use their own pile-up columns and do not know the model's.
- Sigma on wt% and at%: the thickness sigma, the dose and the detector are not in the per-spectrum `quantifyWithSigma` (the pooled quantification has the thickness term); a per-pixel sigma map is not provided.
- k import: the table is taken in exSpy's convention (C_A/C_B = k_A/k_B I_A/I_B); a vendor table in the inverse convention is the caller's to invert. A real Velox export has not been read (none in the data folder); the layouts are the ones the task named.

## Deviations (stated where they live)

- Sum/escape: the sum term uses the alpha line of a group only; degrees of freedom do not count the one or two extra coefficients; `fit.escapeLabel` is replaced by the model's parameter text; with `commonEscapeFraction` the default fit's free escape columns are removed (`escapeValues` is nil, the escapes are in `SumEscapeResult.escapePeaks`). The solver is an alternation (Gauss-Newton on the areas, one-dimensional least squares on c and f), not a joint nonlinear solve; c's sigma ignores the dependence of the sum shape on the areas.
- Sigma: derivatives are central finite differences of the kit's own quantification; the absorption loop is run to 1e-10 for them, whatever the caller's criterion.
- k import: with a `reference`, the factors are renormalised so the reference is 1 (only ratios enter) and carry relative sigma 0; a row without a sigma takes the method's default 0.20 (`TypedK.relativeSigma == nil`).

## Measured agreement

- k import against exSpy `quantification_cliff_lorimer`: 32 runs, worst weight-percent difference 0.0 (tolerance used 1e-3, exSpy's atol on percent).
- Sigma against Monte Carlo (20 000 draws for Cliff-Lorimer, 8 000 with absorption, 15 000 zeta and cross section): worst relative difference 1.7 %.
- Sum/escape: noise-free c and f within 0.04 % of planted; Poisson mean c 1.013e-8 (1.3 % high), SD 5.2e-10 over 20 draws.
- Full suite on this branch: fast target 9 + 99 + 85 (2 known issues, not new) + 185 tests green; parity target 70 tests green (114 s). No existing pin moved.

## New public names

`SumEscapeModel`, `SumEscapeError`, `SumPeakComponent`, `EscapeComponent`, `SumEscapeResult`, `EDSSumEscapeFit`, `PooledQuantificationInput.sumEscape` (and the init parameter); `ImportedKFactor`, `KFactorTable`, `KFactorImportError`, `KFactorImport`; `EDXQuantificationSigma`, `EDXQuantification.quantifyWithSigma`, `EDXQuantification.sigmaFormula`; `RegionQuantResult` (and `.Line`).

## Shared files touched (minimal)

- `Sources/SpectroEDX/Spectroscopy/Fit/EDSModel.swift`: a `package init` on `FitLine` (4 lines).
- `Sources/SpectroEDX/Spectroscopy/Quant/PooledQuantification.swift`: `sumEscape` on `PooledQuantificationInput` (field, init parameter), the fit call chooses `EDSSumEscapeFit` when it is set, the parameter lines join the footer.
- `Sources/SpectroEDX/Spectroscopy/SpectroscopyExport.swift`: `num` and `field` from `private` to `package`.
