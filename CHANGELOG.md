# Changelog

SpectroKit follows semantic versions (0.x). Each release says what changed, and what a consumer must do (Migration).

## Unreleased (0.13.0), removals: the deprecated scan alias, an unused export helper, the duplicate GOS JSON

- **Removed** `SpectrumImageMetadata.sameScanAs4DCube`, deprecated since 0.8.0: use `sameScanAsCube`.
- **Removed** `SpectroscopyExport.elementsLine(_:)`, unused: join `PooledQuantification.rows.map(\.element)` yourself.
- **Smaller bundle.** The 16 per-table GOS JSON files (`Resources/GOS/dft-*-*.json`, about 6.8 MB) are gone: every edge now reads the
  float32 pack, which held the same tables bit for bit (`GOSPackTests` checked the energy axis, q, gos and occupancy ratio of every edge
  against them before the removal). No number changes. `CoreLossEdge.bundled` is empty, not the 20 named edges, if the pack cannot be read.
- **Migration.** Replace `sameScanAs4DCube` with `sameScanAsCube`, and `elementsLine(q)` with `q.rows.map(\.element).joined(separator: ", ")`.

## 0.12.0 (2026-10-23), EELS per-edge windows report a 1σ on each edge intensity; every K, L and M edge of the dft GOS

- **Every edge exSpy builds with the dft GOS** (additive). `CoreLossEdge.bundled` holds 383 edges of 95 elements (K 17, L 126, M 240): each K, L and M
  subshell of exSpy 7185a4d1's eels_binding_energies.json whose GOSH table the file holds, with exSpy's onsets and occupancy ratios; the 20 named
  edges are among them, unchanged. The tables are Segger, Guzzinati and Kohl's dft GOS, GOSH 1.5.0 (DOI 10.5281/zenodo.7645765, CC BY 4.0, md5
  7fee8891c147a4f769668403b54c529b, the file exSpy fetches with pooch), bundled, not fetched: 231 tables as float32 in `Resources/GOS/dft-gos-tables.bin`
  (17.5 MB, the stored values exactly) with `dft-gos-index.json`, so a sandboxed app works offline on first use and every number is the pinned file's
  (tools/eels-edge/extract_gos.py --all). M edges pair as exSpy's twins (M2 with M3, M4 with M5) by element and family, as L2 with L3 already did.
  Parity: all 231 tables bit-exact, and B K, Ti L1, L2, L3, Zr M2, M3, Ba M4, M5 against exSpy at two microscope settings each (EdgePackPinsTests:
  angle 0, qint 3e-16, function 6e-16 against 1e-14, 1e-12, 1e-10). `validation: "none"` as before.
- **Migration.** A consumer that lists `CoreLossEdge.bundled` (a periodic table, a picker) now gets 383 edges, not 20: filter by the energies its
  spectrum covers. Nothing else changes; the JSON tables of the 20 named edges stay and are read first.

- `EdgeIntensityPixel.intensityStd` (additive; nil on the joint fit, on failed or masked pixels, and for every edge after the first with `stripPrecedingEdges`): the signal window's Poisson counting noise plus the background power law's (A, r) sandwich covariance, the error propagation behind Egerton's h factor. Statistical only, of the unclamped estimator, for raw detected counts; areal density's σ is `intensityStd` × 1e10 on a convolved fit. `validation: "none"`. No intensity changes.

## 0.11.0 (2026-10-23), Auto ID is the identification loop of the published method; EELS per-edge windows

- **Auto ID rebuilt** (docs/design/auto-id-tem.md). `ElementProposer.propose` keeps its signature and `ProposalResult`, and its search is now the
  identification loop Newbury and Ritchie published and AutoEMX documents (written from the method and its published defaults, no code copied):
  the strongest top-hat-filtered residual peak at 5 σ (7.5 σ below 1 keV), the elements with a line of weight ≥ 0.1 within 2.5 σ + 25 eV of it
  and the pile-up pairs of the modelled elements as candidates, the one that explains that peak best joins when Σ(y − μ)²/(μ + (0.01 μ)²)
  falls by ≥ 100, ≥ 20 % of it at its own lines, its area ≥ Currie L_D and no line of it worsens its window by 9 and 5 % of the gain;
  repeat (30 peaks, 10 elements), then the final fit drops what it does not need (< 100). The 1 % relative model term replaces the
  flank-misfit factor (gone), which had scaled Mg's σ₀ ×33 by Al's misfit on the owner's file 1339. The fit inside the loop is weighted by
  the statistic's own variance and uses the NIST EPQ Kβ weights (`EDSLineWeights.epqK`: Al Kβ/Kα 0.0315 against eXSpy's 0.0132; the owner's
  1339 and 1840 sums read 0.031 and 0.034 with Kβ free); the quantification fit keeps eXSpy's weights and every Quantify number is unchanged.
  The confirmation rule (R4) runs at nomination: an L or M pick needs its K or L alpha line as a residual peak of 3 σ within one σ of the
  line; where that line is out of range the find stays possible. Tiers: a find is proposed when it is unambiguous, needed by the final fit,
  its peak lies where the background is healthy (data over model 0.8 to 1.25 off the lines) and, for Si, it holds ≥ 0.2 % of the counts;
  every other find or tested element is a candidate with `ElementCandidate.possibleReason` (and `unconfirmable` true for a find whose confirmation line is out of range). Thresholds are `IdentificationThresholds`
  on `ProposerPolicy.thresholds`. On the owner's three whole-map sums, on the refined axis: 1339 and 1840 propose O, Mg, Al, Si, Cu (and Zr,
  Mn, Fe), 1456 proposes O, Si, Ni, Ge, Pt (and Cu, Zr, Ga); `RealFileAutoIDTests` (opt-in) holds that, `IdentificationLoopTests` the planted
  Mg at 2 % beside a 5 %-misfit Al (found at 121 509 of 120 000) and its Al-only guard. Not yet: the method's overlap check (open item).
  `validation: "none"`. Moved bar (review before tag): a weak line beside a very strong one is proposed only when the fit gains 100; a planted
  1 % Mg beside Al at 9e5 counts gains 44 to 71 at 3.7 L_D and is now a possible candidate in every draw, not a proposal
  (`testKramersContinuumNoFalseMgAndTheDetectionRate`). The weighted fit decides; the found elements' reported numbers (net, σ, L_D, the
  pile-up parents, the hole-region note, χ²ᵣ) come from one standard unweighted fit of the final model, as Quantify's. Parity P2 restated
  (review before tag): a cell is detectable when its noise-free net is ≥ 3 L_D and the bias is against that net, because the planted
  generator integrates lines over the channel while the model samples the centre (eXSpy's convention), which reads Mg 0.3 % of N_Al low
  beside Al at 1e6 to 1e7 counts (Gate D4 measures it); the flank factor used to widen σ around that offset. M.s.N4.rho0p05 (461 Mg counts)
  is found in 77 to 80 % against the 90 % bar: the published 5 σ residual-peak bar, a registered known issue.
- Golden baseline re-recorded on purpose for the identification loop (four scenarios and their array companions): only the proposal,
  unlisted-line and withholding lines move; every Quantify line and array is byte-identical (checked key by key before the re-record).

The rules below landed first in 0.11.0 and are kept in the loop's terms (the joint all-candidate fit they were written for is gone):
- **Family consistency, R4** (`ProposerPolicy.familyConsistency`, default true; `familyOvervoltage`, default 2): an element nominated by an L or M line is withheld when its K (or L) alpha line, in the fitted range and with the beam at least `familyOvervoltage` times its energy, shows no residual peak of 3 σ (the field's confirmation-line rule: Goldstein ch. 18, Newbury 2005, AutoEMX, NIST EPQ's overvoltage rule); no Python counterpart; `validation: "none"`. A withheld candidate is in `candidates` and `withheld` with `ElementCandidate.familyNote` saying why, and never enters the model.
- **Sum-peak plausibility** (`sumPeakFraction`, default 1): a candidate on a pile-up energy is a sum-peak question only when its net is at most that fraction of the smaller parent's group net (a pile-up peak cannot exceed the parent it is made of; a self-pair's is in truth at most half, a tightening left for a registration with the planted sum fixtures; a smaller fraction would be a measured dead-time fraction); a Si K line twenty times the Mg line is no longer held as the Mg+O sum. R4 also withholds a FIB-implanted Ga seen by its L line alone: at the overvoltages where the rule runs its K line is excited too, which is what the Ga conflict's remedy asks to check.
- The default pool stops at Bi: Th and U join `defaultExcluded` (the field's auto IDs propose Z 5 to 83).
- Golden baseline (`Tests/SpectroCoreTests/Fixtures/spectro-golden`, five of six scenarios and their array companions) re-recorded on purpose for the fields and notes this version adds (`familyNote`, `lineTail`, `lineShapeLabel`, the R4 and settle-again notes) and the pool and sum-peak changes in the candidate lists; every quantification number is byte-identical to the previous baseline (checked line by line before the re-record).
- Measured, not shipped: refining the energy axis and width on the proposer's own strong picks before a second proposal. On the three files the file's 130 eV width against the fit's refined 133 to 135 eV was most of the misfit beside the strong K lines (reduced chi-square 635 to 30 on the refined axis of the labelled fit), but a refinement on the proposer's own picks drifted on one file (one Cu line: +46 eV, −0.4 % gain) and lost Al, Mg and Si. The proposal therefore keeps the axis and width it is given; a consumer that has a refinement from the pooled fit passes its refined axis and `resolutionMnKaEV` in the settings.
- **Line shape with a low-energy tail, opt-in.** `LineTail` (fraction, slope in keV, source), `FitSettings.lineTail` and `FitPolicy.lineTail` (threaded through `FitSettings.standard`) add PyMca's Hypermet short tail to every line, escape and sum-peak column: the column is `(G + T) / (1 + f)`, tied to the line's area, so no new free parameter and the fitted area stays the line's total (for a line within about five slopes of the fit's start the part of the tail below the first channel is cut, and the area reads low by up to f/(1+f)). `TailEstimate.measure(counts:axis:settings:elements:)` finds the fraction and slope that minimise the fit's residual (a grid, then two halvings) and reports the residual with and without. `EDSFitResult.lineShapeLabel` ("line shape: Gaussian" or "Gaussian + tail (f, β, source)") is in the pooled footer when a tail is on. The step (shelf) term of Hypermet is not included. No Python counterpart; `validation: "none"`. Off by default: every number unchanged.

- **EELS: per-edge background and signal windows.** `EdgeWindows` (background, signal, optional second background, in eV) and `EdgeWindows.defaults(onsetEV:family:precedingSignalEndEV:nextOnsetEV:axis:)` (the background ends 5 eV below the onset and is 20 % of it wide, clamped to 20 to 100 eV, kept 5 eV above the preceding edge's signal end; the signal starts at the onset for K, 20 eV above for L, M and later, is 10 % of the onset wide, clamped to 30 to 150 eV, ends 5 eV below the next onset; clipped to the axis; the constants are public). `EELSModelFit.fit(..., edgeWindows:)` then runs a per-edge sequence in place of the joint model: a power law (non-negative least squares, exponent by Brent) on each edge's own background window(s), extrapolated under its signal window, and the edge's intensity as the cross-section amplitude on the background-subtracted signal window. One window set per fitted edge (the result's `edges`, twins as one) in onset order; signal windows that share energies are refused (`overlappingSignalWindows`), as are a wrong count, a window outside the axis, below 4 background or 2 signal channels, or at non-positive energy. The result reports `edgeWindows`, `fitRangeEV` (the signal windows), `edgeBackgrounds` and `exponent(pixel:edge:)`; the same call is the per-pixel map. `EELSBackground.preview(counts:axis:window:extrapolateTo:)` is the one-spectrum two-area power law (HyperSpy's estimate) with its curve, for a live drag. The convention is GMS's and eels.info's, no Python counterpart; on a planted C K, N K, O K spectrum (3:1:2) on a tail with two components the windows return 2.88:1:1.96, the one-range fit 2.09:1:2.56; `validation: "none"`.

- **EELS windowed fit: stripping each edge before the next, opt-in; close edges get a window by a rule.** With `EELSModelOptions.stripPrecedingEdges` (default false; the result's `strippedPrecedingEdges` and `methodName` say so) in `EELSModelFit.fit(..., edgeWindows:)` the edges are fitted in onset order and each fitted contribution (amplitude times its cross section on every channel to the end of the range) is subtracted from a working copy of the spectrum before the next edge's power law and amplitude are fitted; the reported intensities are the amplitudes, `modelCurve` adds the earlier edges' tails under each window. Without it the N K background window (319 to 396 eV) lies in the tail of C K, its fresh power law runs above the data under N and the non-negative amplitude clamps to 0 (all three real GMS maps). `EdgeWindows.defaults` has the defaulted parameters `precedingOnsetEV`, `precedingBackgroundEV`, `precedingName`: when the preceding edge leaves a background window under 20 eV, the window becomes the stretch from the preceding onset to this onset minus 5 eV when that holds 20 eV, else the preceding edge's own window, and the new `EdgeWindows.note` says which ("background shares C K's window: edges 85 eV apart"); `note` is nil for the ordinary rule and with no fallback given the window stays empty and the fit refuses it by name. Planted: with C K 65 times the N signal under N's window, N K reads 0.097 without stripping against 0.38 with it, and the C:N:O ratio comes back to 97.6:1:1.97 (planted 100:1:2) with it; two edges 85 eV apart (Fe L1, Cu L3) recover the 0.6 ratio. The fit without windows is untouched bit for bit. Off by default because on the owner's three real GMS maps (a-C films, convolved with the low loss) the C K model fitted on its 30 eV signal window overshoots the data from 450 eV up, so O K comes out 0 and N K stays 0 either way; without stripping C K and O K read as before (142: C 93, O 7 at%). Stripping uses the cross-section table's own shape beyond the signal window; the a-C fine structure is not that shape. No Python counterpart; `validation: "none"`.

### Migration
Auto ID: `ProposerPolicy` loses `maxPasses`, `maxForwardRounds`, `flankScaling` and `flank`, and `FlankMisfitGeometry` is removed; set
`thresholds: IdentificationThresholds(...)` instead. `ElementProposer(currie:pool:minimumLineEnergyKeV:)` loses `maxPasses` and
`maxForwardRounds`. `ElementCandidate.misfit` is always 1 and goes in 0.12.0; the new `possibleReason` (a defaulted trailing init parameter) is
part of `isProposed`. `candidates` holds only the elements the loop tested, not one per pool element: an absent element was never a candidate.
`passes` counts fits and `settled` is false only when the loop stopped at its 30-peak cap. `ProposerPolicy.init` takes `minimumLineEnergyKeV`
before the new `thresholds` (labelled calls compile unchanged). `ProposerError.rankDeficient` is thrown only when the listed elements' own
fit is rank deficient. A consumer that showed "possible" from `aboveCriticalLevel` keeps working; one that reads `possibleReason` can say why.
A minor bump: the default run's picks move on real spectra (withheld phantoms, released sum questions). A consumer that builds `ElementCandidate` by hand compiles unchanged (`familyNote: String? = nil` is a defaulted trailing parameter). `ProposerPolicy(familyConsistency: false)` with `pool` set to the 0.10.0 default list in line-table order (Th and U in their old places) reproduces the 0.10.0 nets and limits bit for bit (no rerun happens with the rule off); the notes then name the non-default policy, and a candidate whose net exceeds `sumPeakFraction` of its parents no longer carries the sum-peak question; `possible` no longer lists withheld candidates (they are in `withheld`). `EELSModelFit.fit` has a new defaulted parameter `edgeWindows` (nil: the joint fit runs exactly as before, bit for bit); `EELSModelError` gains four cases, so an exhaustive `switch` over it needs a `default`.

## 0.10.0 (2026-10-22), the EDS and EELS rooms' asks

New public API for the rooms' asks: Richardson-Lucy and the MLLS fit in EELS, sum and escape peaks, k-factor import, sigma on wt% and at% and the per-region result in EDS, and line-profile pooling, smoothing and sparse regions in SpectroCore. No existing number moves.

EELS
- **Richardson-Lucy:** `EELSDeconvolution.richardsonLucy(_:psf:options:)` (`RichardsonLucyOptions.iterations`, default 15): exSpy's `richardson_lucy_deconvolution` on a core-loss or low-loss spectrum image, a shared one-pixel PSF or one PSF per pixel, per pixel on all cores. Equals exSpy to 8e-15 relative (worst of 10 pinned cases, 7.7e-8 of the `assert_allclose` allowance). A pixel whose iterate leaves the real line (exSpy: NaN) is zeros with `unavailable` `.divisionByZero` / `.nonFiniteResult`. The PSF must have the spectrum's channel count (exSpy fails with a broadcast error on any other length).
- **MLLS fit:** `EELSMLLS.fit(coreLoss:edges:microscope:lowLoss:mask:options:)`: the multiple linear least squares fit of an EELS spectrum image (HyperSpy `Model1D.fit(optimizer="lstsq")` on the exSpy EELS model with the power-law exponent fixed). One least-squares solve per pixel gives the power law's A, each master edge's intensity and any given reference shapes, each with its standard error, plus the residual and `EELSMLLSResult.modelCurve(pixel:)`. The exponent is `.given`, `.perPixel` or exSpy's `.twoArea` estimate; the window is `set_signal_range(start, end)`. Equals HyperSpy to 1.1e-4 of the `assert_allclose` default allowance (rtol 1e-7) on 14 pinned runs (amplitudes, `p_std`, residual, degrees of freedom, curve). `validation: "none"`. `EELSQuantification.composition(_:symbols:)` also takes an `EELSMLLSResult`.
- Deviations to know: the MLLS columns are scaled to unit length before the solve (numpy's `lstsq(rcond=None)` silently drops the power law when the edge columns are 1e13 times larger, for example with a low loss of area 1e6); a singular design is a pixel with `.fitFailed` (HyperSpy raises `LinAlgError`).
- Tests: `RichardsonLucyTests`, `EELSMLLSTests` (fast); `RichardsonLucyPinsTests`, `MLLSPinsTests`, `RLMLLSSpeedTests` (parity target); `tools/eels-rl-mlls/pins.py` writes `Tests/SpectroEELSTests/Fixtures/eelsrm-*` (50 arrays + `eelsrm-pins.json`, 1.1 MB, byte-identical on a second run).

EDS and results
- **Sum and escape peaks in the EDS fit (optional, off by default).** `EDSSumEscapeFit.run(counts:axis:settings:model:)` with `SumEscapeModel`: pile-up (sum) peaks of the strongest alpha lines, area `c m A_i A_j` at `E_i + E_j` (c = tau/T, one coefficient, estimated or fixed), and one common Si-escape fraction `f` of each parent group in place of the default fit's free escape area per group. `PooledQuantificationInput.sumEscape` (nil = the fit runs exactly as before) switches it on in the Quantify run and names the parameters in the footer. No Python reference exists (exSpy's `EDSModel` has neither): planted truth only, `validation: "none"`. Every existing result is unchanged bit for bit.
- **k-factor import.** `KFactorImport.parse(_:)` reads a Cliff-Lorimer k table as Velox and other EDS software export it (element, line, k, optional sigma; tab, semicolon or comma separated, decimal comma tolerated, header optional, units and comment lines ignored); `typedK(from:elements:line:reference:)`, `apply(_:to:source:date:...)` and `cliffLorimerFactors(from:...)` hand it to `QuantificationMethod` (`.typed`) or `EDXQuantification`. Malformed rows are refused by name and line (`KFactorImportError`). Against exSpy `quantification_cliff_lorimer`: 32 runs, worst weight-percent difference 0.0 (tolerance used 1e-3, exSpy's atol on percent).
- **Sigma on wt% and at%.** `EDXQuantification.quantifyWithSigma(intensities:...)` propagates the counting sigma of the net counts (or a fit's covariance) and the factors' relative sigma (typed k, zeta, cross section) to wt%, at% and the mass thickness for every method, with or without absorption; counting and factor shares are returned apart. First order, formula stated in `EDXQuantification.sigmaFormula`. No Python counterpart; Monte Carlo over Poisson realisations agrees within 1.7 % (bound 5 %). `validation: "none"`.
- **Per-region quantification result.** `RegionQuantResult.make(from:regionName:pixelCount:)` builds, from a finished `PooledQuantification`, a Codable, Sendable record with everything a report row needs (region and pixel count, elements, k source and values, net counts and sigma per line, wt% and at% with sigma, absorption note, method hash, unlisted-line check, validation), with a CSV header and row (wide and long) and `reportRow(elements:)`.

Spectrum tools (SpectroCore)
- **Line-profile pooling:** `SpectrumLineProfile.compute` pools a spectrum image along a polyline of given width, one spectrum per step of arc length (hard pixel membership by default, `.bilinear` as scikit-image `profile_line(order=1)`), with per-step pixel counts, weights, arc length and sum or mean. Hard membership equals `profile_line(order=0)` exactly where the geometries coincide; bilinear equals `profile_line(order=1)` to 2.4e-15.
- **Smoothing:** `SpectrumSmoothing`, for display only (never for a fit): Savitzky-Golay (SciPy `savgol_filter` and HyperSpy `smooth_savitzky_golay`, all edge modes), Gaussian (`gaussian_filter1d`, sigma in channels, truncate 4) and moving average (`uniform_filter1d`), on one spectrum, a list, or a whole image in one parallel call. Agreement 5.8e-13 (Savitzky-Golay), 3e-15 (others).
- **Sparse regions:** `MaskTransport.regions(...)`, the sparse transport for many regions (scan-pixel indices or runs per region), equal to the dense transport of each region (overlap and footprints bit for bit), with `PoolBuilder.pools(image:transported:...)`. 300 regions on a 512 x 512 grid: 0.11 s and 5 MB against 0.70 s and 600 MB for the dense `transport(labels:)`.

### Migration
No existing number moves and no existing name is removed or renamed; everything is new public names. `PooledQuantificationInput.init` gained a trailing defaulted parameter (`sumEscape: SumEscapeModel? = nil`), so existing calls compile unchanged. `MaskTransport.clippedArea` and a few helpers (the export `num` and `field`, a `FitLine` initialiser) are now `package`, not visible to consumers. Every new quantification output is badged `validation: "none"`: the sum/escape model, sigma on wt% and at%, and the MLLS fit; none of them has a standard of known composition, and none is pinned to a Python result as a quantification (what is pinned: Richardson-Lucy against exSpy, the MLLS fit against HyperSpy's `lstsq` fit, the k-factor table's effect on Cliff-Lorimer against exSpy, line profiles against scikit-image, smoothing against SciPy and HyperSpy; the sum/escape model and sigma are checked against planted truth and Monte Carlo only). `RegionQuantResult.Line.netCounts` and `netSigma` are `Double?` (nil when not finite, so a plain `JSONEncoder` no longer throws); read them with `?? 0` or `if let`.

## 0.9.0 (2026-10-22) — EELS task 16: alignment, deconvolution and the edge model

SpectroEELS grows from the t/lambda map and one K edge to the study's EELS chain, all against exSpy 0.3.2 / HyperSpy 2.4.0 (`docs/parity.md`, `docs/design/eels-task-16.md`).

- **Zero-loss alignment:** `EELSAlignment.alignZeroLossPeak`, `.zeroLossPeakCentre`, `.zeroLossPeakMask`, `.estimateShift`, `.shift` (calibrate, subpixel, crop, mask, signal range, also-align).
- **Spectrum operations:** `EELSSpectrumOps.powerLawExtrapolation` (binned axis) and `.hanningTaper`.
- **Deconvolution:** `EELSDeconvolution.fourierLog`, `.fourierRatio`, `.optimalFFTSize`, `.peakWidth`, with their option and result types; quirks of exSpy kept and pinned. Richardson-Lucy is not in this release.
- **Edge model:** `EELSModelFit.fit`, `.fitBackground`, `.twoAreaBackground` on the new K and L edges, `EELSModelResult.modelCurve(pixel:)` and `.quantifyText(pixel:)`; `EELSQuantification.composition` (at% and wt%); `sum(mask:)` on `LowLossSpectrumImage` and `CoreLossSpectrumImage`. Intensities within 3e-5 of exSpy's converged fit. Deviation: an exact minimiser (variable projection) instead of Levenberg-Marquardt; no fine structure, no free onset energy.
- **Edges:** `CoreLossEdge` now carries 20 bundled edges: K of C, N, O, Mg, Al, Si and the L edges of Mg, Al, Si, Fe, Cu (`CoreLossEdge.bundled(_:_:)`, public initialiser, `family`). The tables are the same dft GOSH file, bit-exact.
- **EDX (the 0.8.3 asks):** `EDXQuantification.quantifyMaps(takeOffDegreesPerPixel:)`; public initialisers and readbacks for tests and replay: `ResolvedWindow`, `ResolvedWindow.Background`, `LineWindow`, `SpectrumDetectorSegment`, `ElementCandidate`, `SumPeakFinding`, `ProposalResult`, and the `PooledQuantificationInput` fields.
- **Dependency:** SpectroKit now depends on ImagoKit `"0.6.1"..<"1.0.0"` (ImagoCore's exact-length FFT, used by the deconvolutions).

### Migration
`CoreLossEdge.bundled` is no longer `[C K, N K, O K]` but 20 edges (the first three are unchanged); code that compared the whole list or assumed K1 only must be adjusted. `EELSUnavailable`, `EELSDeconvolutionError` and `EELSModelError` are new enums; nothing was removed or renamed. A consumer's `swift build` now also resolves ImagoKit.

## 0.8.2 (2026-10-21) — the pooled fit's k, line energies and take-off angle are public

Additive public API; no number moves. An app can now build a per-pixel `EDXQuantificationSetup` (`quantify`, `quantifyMaps`) from the very k-factors, line energies and detector geometry the pooled fit used, computed k and absorption included.

- `PooledQuantification.kFactors: [PooledKFactor]?` (element, k relative to the fit's reference, relative sigma) in the rows' order, for computed and typed k; nil when no at% was computed. `kFactorSourceDescription` names the source.
- `PooledQuantification.Row.lineEnergyKeV`: the energy of the fitted line, the `EDXAbsorptionSetting.lineEnergiesKeV` entry.
- `EDXQuantification.takeOffDegrees(metadata:)`: the solid-angle-weighted mean take-off angle of the file's detector segments (shadow fractions applied), for `EDXAbsorptionSetting.takeOffDegrees`; throws the pooled fit's own reason (no tilt, a segment without geometry, GMS).
- Deviation to know: the pooled fit averages the transmission over the four segments, the per-pixel call takes one angle, so a map with absorption differs slightly from the pooled number. Both stay `validation: "none"`.
- Tests: `EDXQuantificationInputsTests` (the k reproduces the fit's own wt% through `quantify`, typed and computed; the line energy; the weighted take-off; the refusals).

### Migration
None; nothing is removed or renamed. An app that held the k or the geometry itself can read them from the fit now.

## 0.8.1 (2026-10-21) — quantification pins at exSpy's tolerance

Tests, fixtures and documentation only; no source change and no number moves.

- The absorption runs of `everyRunMatchesExspy` were pinned at 1.0 percentage point; they are now pinned at exSpy's own atol 1e-3 (the per-pixel iteration agrees with
  exSpy's image-wide one to better than 1e-9 on the 36 runs), which makes the 0.8.0 sentence "at exSpy's test tolerances" true. Mass thickness and atoms with
  absorption were rtol 1e-2 and are now rtol 1e-5 (exSpy's cross-section atoms come from the iteration before its last composition update, 4e-6 apart on pixel 0).
- Cross-section mass thickness is now pinned: exSpy returns none, so `tools/edx-quant-maps/pins.py` records exSpy's own `get_abs_corr_cross_section` total-mass
  formula on exSpy's atoms (the fixture gained that field; nothing else in it changed).
- Every quantification result still says `validation: "none"` (no standard of known composition has been measured, `docs/open-items.md` 7); a test asserts it on
  both `quantify` and `quantifyMaps`.
- Added `docs/status.md`.

### Migration
None.

## 0.8.0 (2026-10-21) — public EDX quantification, parity audit, benchmarks

Additive public API; no existing number moves.

- `EDXQuantification.quantify` and `.quantifyMaps` (SpectroEDX): Cliff-Lorimer with typed k-factors, zeta-factor and ionisation cross-section quantification, each with
  or without the absorption iteration, on one spectrum's line intensities or per pixel over a spectrum image: `navigationMask`, weight and atomic percent maps, mass
  thickness, atoms, per-pixel live-time dose, parallel over pixels. Neutral input types (`EDXQuantificationSetup`, `EDXQuantificationMethod`, `EDXAbsorptionSetting`);
  no region name or file path. Also public: `EDXQuantification.takeOffAngle`, `.weightToAtomic`, `.atomicToWeight`, `.zetaFactors(fromCrossSectionsBarn:)`,
  `.crossSectionsBarn(fromZetaFactors:)`, and `LineConflict.init`. Pinned against 36 runs of exSpy 0.3.2's own `quantification` at exSpy's test tolerances
  (`tools/edx-quant-maps`). Results say `validation: "none"`.
- `SpectrumImageMetadata.sameScanAs4DCube` is renamed `sameScanAsCube`; the old name stays as a deprecated alias. The golden baselines moved with the rename (own commit).
- `docs/parity.md` rewritten from the exSpy 0.3.2 source (state, priority, upstream tolerance per row), `docs/benchmarks.md` and `tools/benchmarks` added, `docs/open-items.md` added.
- Dependency range unchanged (FormatoKit `0.4.0..<1.0.0`); FormatoKit is not bumped by this release.

### Migration
None required. Replace `sameScanAs4DCube` with `sameScanAsCube` to drop the deprecation warning. An app that reached `CliffLorimer`, `ZetaFactor` or `AbsorptionCorrection` by
`@testable import` can move to `EDXQuantification`; those types stay `package`.

## 0.7.1 (2026-10-21) — FormatoKit range widened to 0.4.0 up to 1.0.0

Dependency range only; no source change, and no SpectroKit API or number moves.

- FormatoKit is now `"0.4.0"..<"1.0.0"` (was `"0.4.0"..<"0.6.0"`), so an app can pin FormatoKit 0.6.x or 0.7.0 beside SpectroKit. FormatoKit is the only dependency.
  Tested against FormatoKit 0.7.0.

### Migration
None. An app pinning FormatoKit 0.6.0 or later re-pins SpectroKit to 0.7.1.

## 0.7.0 (2026-10-20) — FormatoKit 0.4.x and 0.5.x

Dependency range only; no source change, and no SpectroKit API or number moves.

- FormatoKit is now `"0.4.0"..<"0.6.0"` (was `"0.3.0"..<"0.5.0"`): 0.3.x is dropped, 0.5.x added. FormatoKit 0.5.0 adds `HDF5Reader`,
  `HDF5AppendWriter`, `TIFFAppImage` and new `HDF5FileError` cases (source-breaking only for an exhaustive switch over `HDF5FileError`;
  SpectroKit has none).
- Test fixture: `velox-tiny.txt` of the golden test regenerated. FormatoKit 0.3.1 and later add four optional `VeloxMetadata` fields (`stageXMeters`,
  `stageYMeters`, `stageZMeters`, `instrumentClass`) that the golden dumps; additive lines only, 251 to 255 lines, no SpectroKit number moves.
  Tested against FormatoKit 0.4.0 and 0.5.0.

### Migration
Consumers on FormatoKit 0.3.x stay on SpectroKit 0.6.0. An app pinning FormatoKit 0.4.0 or 0.5.0 exact uses SpectroKit 0.7.0; re-pin SpectroKit to 0.7.0.

## 0.6.1 (2026-10-20) — FormatoKit range 0.3.x and 0.4.x

Dependency range only; no source change, and no SpectroKit API or number moves.

- FormatoKit is now `"0.3.0"..<"0.5.0"` (was `.upToNextMinor(from: "0.3.0")`). FormatoKit 0.4.0 only repackages libhdf5 as XCFrameworks, so
  an app that embeds FormatoKit 0.4.0 can still resolve SpectroKit.

Tests only: `LineTableParityTests` pins all 947 rows of the X-ray line table against exSpy 7185a4d1's own loader (was about 12 rows); no deviation found.

Correction (found 2026-10-20): the golden test `testOutputsAreByteIdenticalToTheBaseline` (the 0.6.1 fixture) fails against FormatoKit 0.3.1, 0.4.0 and 0.5.0 (measured: it passes against 0.3.0, fails against 0.3.1 and 0.4.0 with "velox-tiny: line count changed from 251 to 255", the new optional Velox metadata fields; 0.5.0 likewise). Fixed at 0.7.0, which needs FormatoKit 0.4.0 or later.

### Migration
None. An app that pins FormatoKit 0.4.0 exact must use SpectroKit 0.6.1 or later; re-pin SpectroKit to 0.6.1.

## 0.6.0 (2026-10-16) — FormatoKit as a minor range

Dependency range only; no source change was needed against FormatoKit 0.3.0, and no SpectroKit API or number moves.

- FormatoKit is now `.upToNextMinor(from: "0.3.0")` (was `exact: "0.2.1"`), the standard SwiftPM practice for a library, so an app
  that pins exact kit tags resolves one FormatoKit without lockstep releases. FormatoKit 0.3.0 is additive, and its
  FormatoTIFF target now depends on FormatoDM.

### Migration
Consumers must use FormatoKit 0.3.x (any 0.3.y satisfies the range); a consumer still on FormatoKit 0.2.x must move to 0.3.x.
Re-pin SpectroKit to 0.6.0.

## 0.5.4 (2026-10-16) — CI fix

0.5.3 was tagged with red CI. The Golden and unit tests passed on both jobs; the failure was the consumer check's negative
controls on the newest-Xcode job (Swift 6.3.3): 96 of the 151 access controls reported "no note ... declared here". The
controls require the compiler's note beside `error: '<member>' is inaccessible due to 'package' protection level`, and
looked for Swift 6.4's module-qualified form (`SpectroCore.<Owner>.<member>:2:13: note:`) only; Swift 6.3 names the edited
file by path. No library or test number moves.

- **Consumer-check controls.** `controls.py` accepts a path-form note (Swift 6.3's format, unverified until the next CI run) as well as
  the module-qualified one (a path ending in the edited file), still requiring the member's own name in the note and the edited file; a note in another file is refused. On a miss it prints up to 5 compiler note lines naming the member.
  `test_judge.py` pins the three cases and runs before the controls in `run.sh --controls`.
- **Migration.** None. Re-pin to 0.5.4 in place of 0.5.3, which was tagged with red CI.

## 0.5.3 (2026-10-16) — CI fixes

0.5.2 was tagged at 9de71e9 with red CI: both jobs (macos-15 and the newest Xcode) failed in
`SpectroGoldenTests.testOutputsAreByteIdenticalToTheBaseline`, 26 and 20 records. This release is the fix, plus an additive API:
no existing number moves.

- **Golden scalar bound.** The runners' CPUs (Accelerate paths) moved small cancellation-conditioned scalars (relative
  atomic/weight counting terms, unlisted-candidate and sum-peak nets) by up to 3.2e-10 relative, past the 1e-12 relative scalar
  bound that was measured on developer machines. The scalar bound is now 1e-9 relative (the stated ceiling for roundoff; a gap
  above it is a defect, not a tolerance). Array elements stay at 1e-12 of the pinned peak; text, integers, structure and hashes
  stay exact. The baselines and companions are unchanged, nothing was regenerated from CI, and the deterministic tie rule is untouched.
- The 0.5.2 type-check fixes (QuantificationPolicyTests, SpectroscopyFitTests) are listed under 0.5.2 below.

- **Registration.** `GridRegistration`, `MaskTransport` (area-overlap label transport from the scan grid to the spectrum grid) and
  `PoolBuilder` (pooled counts and grouping), ported from mac4DSTEM's Registration code. Oracle: a NumPy transcription of the app
  source (`tools/registration/pins.py`, not exSpy); labels, ties and counts exact, overlaps within 2e-12 pixel areas (measured gap 0).
  Additive; pools stay `validation: nil`/unvalidated. Unlike the app, `MaskTransport.region` and `PoolBuilder.pool` throw
  `MaskTransportError` on invalid input instead of trapping. Fixture includes exact, within-1e-6 and beyond-tolerance ties.
- **Migration.** Nothing required: the registration API is additive, and the Golden scalar bound (now 1e-9 relative) is test-side only. Re-pin to 0.5.3 in place of 0.5.2, which was tagged with red CI.


## 0.5.2 (tagged with red CI; fixed in 0.5.3)

- **Golden portability.** Original scalar values and array hashes are retained. CPU-dependent fitted scalars use a stated
  1e-12 relative bound (1e-9 from 0.5.3); each floating-point array element uses 1e-12 of the pinned array peak. Compact companions were
  expanded only after all six developer dumps matched the original baseline byte for byte, and a regression verifies
  their original counts, hashes and sums. Text, integer, structure and CSV hash comparisons remain exact.

- **Portable estimated EELS thresholds.** The Savitzky–Golay solve stays on LAPACK's SVD, as in SciPy's `savgol_coeffs`.
  Automatic SG tolerance treats derivatives within `64 eps * peak cropped input * coefficient L1` as tied and chooses the
  first channel. This intentionally changes 20 of 138 pinned policy pixel answers from raw exSpy, preventing small CPU
  rounding changes from producing large thickness changes. Explicit tolerance and gradient comparisons remain exact.
  The unchanged raw SciPy/exSpy fixtures remain as evidence; a new pinned Python policy fixture records the changed channels.
- **Migration.** Recompute results obtained with `.estimated()` if numerical ties matter to the analysis. Record the library
  version with those results. Fixed thresholds and the zero-loss spectrum route retain their existing values. No API change.

- **CI diagnostics and shell fixes.** The main gate now propagates a failing `swift test` status through `tee`. The consumer
  target inventory tolerates either absent build backend directory under zsh `errexit`. Swift Testing regressions cover
  both failures. The macos-26 numerical audit is in `docs/ci-parity.md`; the original raw reference fixtures are retained.

- **CI: the macos-15 job failed with a type-check timeout.** `QuantificationPolicyTests.swift` had one `#expect` whose
  expression (two closures in a comparison) the Xcode 26.0 compiler could not type-check in reasonable time. The sums and the
  slack are now typed `let`s; the assertion and its tolerance are unchanged. Test code only; no library number moves.
  The planted-spectrum closure in `SpectroscopyFitTests.swift` (the tail-shape test) likewise has an explicit `(i: Int) -> Double` signature and typed lets; same arithmetic, same order, same values.

## 0.5.1 — macOS 15 / iOS 18 floor

- **Platforms.** `Package.swift` declares `.macOS(.v15)` and `.iOS(.v18)` (0.5.0: macOS 27). SpectroKit needed no source
  change for it: there is no availability branch anywhere in `Sources/`.
- **FormatoKit** is pinned `exact: "0.2.1"` (0.5.0: `0.0.3`). FormatoKit 0.2.1 rebuilds its bundled libhdf5 dylibs for macOS 15,
  which is what lets the floor come down. FormatoKit's 0.1.x Velox changes (stored dtype, RosettaSciIO's titles) come in with
  the pin; no SpectroKit number moves (below).
- **No number moves.** The default path on the owner's EDX spectrum image (open, summed spectrum, proposer, pooled
  quantification, 14 043 lines of full-precision dump) is byte-identical to 0.5.0's; the golden CSV hashes and every pinned
  fixture pass unchanged.
- **CI.** A `test-macos15` job (macos-15, Xcode 26.0, Swift 6.2) runs the gate at the new floor. The consumer check no longer
  exits silently when `.build/debug` is absent (a `find` under `pipefail`), which failed the macos-26 job.
- **Tests.** The three `Test.cancel` skips (the public Velox files, absent without `References/`) are a printed note and an
  early return: `Test.cancel` is missing from Xcode 26.0's Swift Testing. The test names are unchanged.
- **Migration.** Consumers may lower their floor to macOS 15 (iOS 18 for the pure-Swift modules) and re-pin to 0.5.1. A
  consumer that pins FormatoKit itself must pin 0.2.1 (it resolves to 0.2.1 through SpectroKit anyway). Nothing else changes.

## 0.5.0 — the generality pass

The suite's policies became public parameters (`WindowRules`, `QuantificationPolicy`, `ProposerPolicy`, `UnlistedLineRules`,
`SmoothingKernel`, the EELS default window offsets), each default 0.4.0's value, the default path bit for bit; a stand-alone
README and `Examples/QuantifyEDX`; a DocC catalogue per module; `docs/parity.md`. One behaviour change:
`SpectroscopyExport.csv`'s default title is "Spectroscopy quantification". Migration: nothing required.

## 0.4.0

The file readers moved to FormatoKit (`FormatoDM`, `FormatoEMD`, `FormatoHDF5`), pinned `exact: "0.0.3"`; libhdf5 ships inside
FormatoHDF5.

## 0.3.0, 0.2.0, 0.1.0

EELS thickness (t/λ) and the C K ratio method; the EDX quantification stage gates; the first extraction from the source
application (`../_archive/SpectroKit/docs/history.md`).

Consumer notes for 0.0.1 to 0.5.0 are archived.
