# Changelog

All notable changes to SpectroKit are listed here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [semantic versioning](https://semver.org) (0.x: a minor
version may break the API). Each release says what a consumer must change under **Migration**. Release headings are bare versions
(`## 0.12.0 - 2026-10-23`) because the release tooling reads them; the compare links are at the end.

Every quantification and thickness result reports `validation: "none"`: agreement with exSpy and HyperSpy is not validation on a
sample of known composition.

## Unreleased

## 0.12.0 - 2026-10-23

### Added
- **Every K, L and M edge exSpy builds with the dft GOS.** `CoreLossEdge.bundled` holds 383 edges of 95 elements (K 17, L 126, M 240),
  with exSpy 7185a4d1's onsets and occupancy ratios; the 20 named edges are among them, unchanged. The 231 tables of Segger, Guzzinati
  and Kohl's GOSH 1.5.0 (DOI 10.5281/zenodo.7645765, CC BY 4.0) ship as float32 in `Resources/GOS/dft-gos-tables.bin` with
  `dft-gos-index.json`, so a sandboxed app works offline. M edges pair as exSpy's twins (M2 with M3, M4 with M5), as L2 with L3 do.
  All 231 tables are bit-exact, and B K, Ti L1 to L3, Zr M2, M3 and Ba M4, M5 match exSpy at two microscope settings each.
- `EdgeIntensityPixel.intensityStd`: the 1σ of each per-edge intensity, the signal window's Poisson noise plus the background power
  law's (A, r) covariance (the error propagation behind Egerton's h factor). Nil on the joint fit, on failed or masked pixels, and for
  every edge after the first with `stripPrecedingEdges`. Statistical only.

### Migration
A consumer that lists `CoreLossEdge.bundled` (a periodic table, a picker) now gets 383 edges, not 20: filter by the energies its
spectrum covers.

## 0.11.0 - 2026-10-23

### Changed
- **Element identification is the published identification loop** (Newbury and Ritchie; AutoEMX documents its defaults; written from
  the method, no code copied). `ElementProposer.propose` keeps its signature: find the strongest residual peak (top-hat filtered,
  5 σ, 7.5 σ below 1 keV), test the elements with a line of weight ≥ 0.1 near it and the pile-up pairs of the modelled elements, add
  the one that explains the peak best when the weighted misfit falls by ≥ 100, repeat (at most 30 peaks, 10 elements), then drop what
  the final fit does not need. A 1 % relative model term replaces the flank-misfit factor. The loop's fit uses the NIST EPQ Kβ
  weights (`EDSLineWeights.epqK`); quantification keeps exSpy's weights, and no quantification number changes.
- An L or M pick needs its K or L alpha line as a 3 σ residual peak (the confirmation-line rule; `ProposerPolicy.familyConsistency`,
  `familyOvervoltage`); where that line is out of range the find stays a candidate (`ElementCandidate.unconfirmable`).
- A find is *proposed* when it is unambiguous, needed by the final fit and sits where the background fits (data over model 0.8 to
  1.25 off the lines; for Si, ≥ 0.2 % of the counts). Every other tested element is a candidate with `ElementCandidate.possibleReason`.
  The thresholds are `IdentificationThresholds` on `ProposerPolicy.thresholds`.
- A weak line beside a very strong one is proposed only when the fit gains 100: a planted 1 % Mg beside Al at 9e5 counts is now a
  possible candidate, not a proposal.
- Sum-peak plausibility (`sumPeakFraction`, default 1): a candidate on a pile-up energy is a sum-peak question only when its net is at
  most that fraction of the smaller parent's net.
- The default element pool stops at Bi (Th and U join `defaultExcluded`).
- The golden baselines were re-recorded for the new proposal fields and notes; every quantification line is byte-identical.

### Added
- **Line shape with a low-energy tail, opt-in.** `LineTail`, `FitSettings.lineTail` and `FitPolicy.lineTail` add PyMca's Hypermet
  short tail to every line, escape and sum-peak column, tied to the line's area (no new free parameter). `TailEstimate.measure` finds
  the fraction and slope that minimise the residual. `EDSFitResult.lineShapeLabel` names the shape. Off by default; no Python
  counterpart.
- **EELS per-edge background and signal windows.** `EdgeWindows` and `EdgeWindows.defaults(onsetEV:family:...)` (public constants),
  and `EELSModelFit.fit(..., edgeWindows:)`: per edge, a power law on its own background window(s) extrapolated under its signal
  window, and the edge's intensity on the background-subtracted window. Overlapping signal windows, too few channels and windows off
  the axis are refused by name. `EELSBackground.preview` is HyperSpy's two-area power law on one spectrum, for a live drag. The
  convention is GMS's and eels.info's; no Python counterpart.
- **Stripping each edge before the next, opt-in** (`EELSModelOptions.stripPrecedingEdges`): each fitted edge is subtracted before the
  next edge's background is fitted. Close edges get a background window by a rule, and `EdgeWindows.note` says which. On a planted
  C K, N K, O K spectrum (100:1:2) the ratio comes back 97.6:1:1.97 with it.

### Removed
- `ProposerPolicy.maxPasses`, `maxForwardRounds`, `flankScaling`, `flank` and `FlankMisfitGeometry`.

### Migration
Set `thresholds: IdentificationThresholds(...)` instead of the removed `ProposerPolicy` fields. `ElementProposer(currie:pool:minimumLineEnergyKeV:)`
loses `maxPasses` and `maxForwardRounds`. `ElementCandidate.misfit` is always 1. `candidates` holds only the elements the loop
tested; `passes` counts fits and `settled` is false only when the loop stopped at its cap. `ProposerError.rankDeficient` is thrown
only when the listed elements' own fit is rank deficient. `possible` no longer lists withheld candidates (they are in `withheld`).
`ProposerPolicy(familyConsistency: false)` with the 0.10.0 pool reproduces the 0.10.0 nets and limits bit for bit.
`EELSModelFit.fit`'s new `edgeWindows` defaults to nil (the joint fit, unchanged); `EELSModelError` gains four cases, so an exhaustive
`switch` needs a `default`.

## 0.10.0 - 2026-10-22

No existing number moves.

### Added
- **Richardson-Lucy:** `EELSDeconvolution.richardsonLucy(_:psf:options:)`, exSpy's `richardson_lucy_deconvolution`, with one shared
  PSF or one per pixel. Matches exSpy to 8e-15 relative. A pixel whose iterate leaves the real line is zeros with a reason.
- **MLLS fit:** `EELSMLLS.fit(coreLoss:edges:microscope:lowLoss:mask:options:)`, HyperSpy's `Model1D.fit(optimizer="lstsq")` on the
  exSpy EELS model with a fixed exponent (given, per pixel, or exSpy's two-area estimate): each edge's intensity and standard error,
  the residual and `modelCurve(pixel:)`. Matches HyperSpy well inside `assert_allclose`'s default. The columns are scaled to unit
  length before the solve, and a singular design is a pixel with `.fitFailed` (HyperSpy raises).
- **Sum and escape peaks in the EDS fit, opt-in:** `EDSSumEscapeFit.run` with `SumEscapeModel` (one pile-up coefficient and one Si
  escape fraction), and `PooledQuantificationInput.sumEscape`. No Python counterpart; checked against planted truth.
- **k-factor import:** `KFactorImport.parse(_:)` reads a Cliff-Lorimer k table as EDS software exports it, and hands it to
  `QuantificationMethod` or `EDXQuantification`. Malformed rows are refused by line.
- **Sigma on wt% and at%:** `EDXQuantification.quantifyWithSigma(...)`, first-order propagation of counting and factor sigma
  (`EDXQuantification.sigmaFormula`), agreeing with Monte Carlo within 1.7 %.
- **Per-region result:** `RegionQuantResult.make(from:regionName:pixelCount:)`, a Codable record with a CSV header and row.
- **Line-profile pooling:** `SpectrumLineProfile.compute` along a polyline of given width (hard membership or bilinear), matching
  scikit-image's `profile_line`.
- **Display smoothing:** `SpectrumSmoothing` (Savitzky-Golay, Gaussian, moving average), matching SciPy and HyperSpy.
- **Sparse regions:** `MaskTransport.regions(...)` and `PoolBuilder.pools(image:transported:...)` for many regions at once.

### Changed
- `MaskTransport.clippedArea` and a few export helpers are `package`, no longer visible to consumers.
- `RegionQuantResult.Line.netCounts` and `netSigma` are `Double?` (nil when not finite).

### Migration
`PooledQuantificationInput.init` gained a trailing defaulted `sumEscape` parameter: existing calls compile. Read
`RegionQuantResult.Line.netCounts` and `netSigma` with `?? 0` or `if let`.

## 0.9.0 - 2026-10-22

The EELS chain beyond thickness, against exSpy 0.3.2 and HyperSpy 2.4.0 (`docs/parity.md`).

### Added
- **Zero-loss alignment:** `EELSAlignment.alignZeroLossPeak`, `.zeroLossPeakCentre`, `.zeroLossPeakMask`, `.estimateShift`, `.shift`.
- **Spectrum operations:** `EELSSpectrumOps.powerLawExtrapolation` (binned axis) and `.hanningTaper`.
- **Deconvolution:** `EELSDeconvolution.fourierLog`, `.fourierRatio`, `.optimalFFTSize`, `.peakWidth`.
- **Edge model:** `EELSModelFit.fit`, `.fitBackground`, `.twoAreaBackground`, `EELSModelResult.modelCurve(pixel:)`,
  `.quantifyText(pixel:)` and `EELSQuantification.composition` (at% and wt%), within 3e-5 of exSpy's converged fit. It uses an exact
  minimiser (variable projection) instead of Levenberg-Marquardt; no fine structure, no free onset energy.
- **Edges:** 20 bundled edges (K of C, N, O, Mg, Al, Si; L of Mg, Al, Si, Fe, Cu), `CoreLossEdge.bundled(_:_:)` and `family`.
- **EDX:** `EDXQuantification.quantifyMaps(takeOffDegreesPerPixel:)`, and public initialisers for `ResolvedWindow`, `LineWindow`,
  `SpectrumDetectorSegment`, `ElementCandidate`, `SumPeakFinding`, `ProposalResult` and the `PooledQuantificationInput` fields.
- `sum(mask:)` on `LowLossSpectrumImage` and `CoreLossSpectrumImage`.
- Dependency on ImagoKit `"0.6.1"..<"1.0.0"` for its exact-length FFT.

### Migration
`CoreLossEdge.bundled` holds 20 edges, not 3 (the first three are unchanged). A consumer's build now also resolves ImagoKit.

## 0.8.2 - 2026-10-21

### Added
- `PooledQuantification.kFactors` and `kFactorSourceDescription`: the k-factors the pooled fit used.
- `PooledQuantification.Row.lineEnergyKeV`: the energy of the fitted line.
- `EDXQuantification.takeOffDegrees(metadata:)`: the solid-angle-weighted mean take-off angle of the file's detector segments.

With these an app builds a per-pixel `EDXQuantificationSetup` from the pooled fit's own inputs. The pooled fit averages the
transmission over the four segments while the per-pixel call takes one angle, so a map with absorption differs slightly from the
pooled number.

## 0.8.1 - 2026-10-21

### Changed
- Tests only: the absorption runs of the quantification pins are held at exSpy's own tolerance (atol 1e-3 on percent; rtol 1e-5 on
  mass thickness and atoms), and the cross-section mass thickness is now pinned. No number moves.

## 0.8.0 - 2026-10-21

### Added
- `EDXQuantification.quantify` and `.quantifyMaps`: Cliff-Lorimer, zeta-factor and cross-section quantification, with or without
  the absorption iteration, on one spectrum or per pixel (weight and atomic percent maps, mass thickness, atoms, live-time dose).
  Also `takeOffAngle`, `weightToAtomic`, `atomicToWeight`, `zetaFactors(fromCrossSectionsBarn:)`, `crossSectionsBarn(fromZetaFactors:)`
  and `LineConflict.init`. Pinned against 36 runs of exSpy 0.3.2's `quantification`.
- `docs/parity.md` (rewritten from the exSpy 0.3.2 source), `docs/benchmarks.md` with `tools/benchmarks`, and `docs/open-items.md`.

### Changed
- `SpectrumImageMetadata.sameScanAs4DCube` is renamed `sameScanAsCube`; the old name stays as a deprecated alias.

### Migration
Replace `sameScanAs4DCube` with `sameScanAsCube`.

## 0.7.1 - 2026-10-21

### Changed
- FormatoKit range `"0.4.0"..<"1.0.0"` (was `..<"0.6.0"`).

## 0.7.0 - 2026-10-20

### Changed
- FormatoKit range `"0.4.0"..<"0.6.0"` (was `"0.3.0"..<"0.5.0"`).

### Fixed
- The golden test failed against FormatoKit 0.3.1 and later, which add four optional Velox metadata fields; its fixture now has them.

### Migration
A consumer on FormatoKit 0.3.x stays on SpectroKit 0.6.x.

## 0.6.1 - 2026-10-20

### Changed
- FormatoKit range `"0.3.0"..<"0.5.0"`, so an app on FormatoKit 0.4.0 resolves SpectroKit.
- The X-ray line table is pinned on all 947 rows against exSpy's own loader.

## 0.6.0 - 2026-10-16

### Changed
- FormatoKit as a minor range, `.upToNextMinor(from: "0.3.0")` (was `exact: "0.2.1"`).

### Migration
Use FormatoKit 0.3.x.

## 0.5.4 - 2026-10-16

### Fixed
- The consumer check accepts Swift 6.3's path-form compiler notes. No library change.

## 0.5.3 - 2026-10-16

### Added
- `GridRegistration`, `MaskTransport` (area-overlap label transport from the scan grid to the spectrum grid) and `PoolBuilder`.
  They throw `MaskTransportError` on invalid input.

### Fixed
- The golden test's scalar bound is 1e-9 relative, which CI runners' CPUs need; arrays stay at 1e-12 of their peak.

## 0.5.2 - 2026-10-16

### Changed
- `.estimated()` EELS thresholds treat Savitzky-Golay derivatives within a stated rounding bound as tied and choose the first
  channel, so CPU rounding cannot move a threshold far. This changes 20 of 138 pinned policy pixels from raw exSpy.

### Migration
Recompute results obtained with `.estimated()` if numerical ties matter. Fixed thresholds and the zero-loss route are unchanged.

## 0.5.1

### Changed
- Platforms: macOS 15 and iOS 18 (was macOS 27). FormatoKit pinned `exact: "0.2.1"`. No number moves.

## 0.5.0

### Changed
- The analysis policies are public parameters (`WindowRules`, `QuantificationPolicy`, `ProposerPolicy`, `UnlistedLineRules`,
  `SmoothingKernel`, the EELS default window offsets), each defaulting to the previous behaviour.
- `SpectroscopyExport.csv`'s default title is "Spectroscopy quantification".

### Added
- A stand-alone README, `Examples/QuantifyEDX`, a DocC catalogue per module and `docs/parity.md`.

## 0.4.0

### Changed
- The file readers moved to FormatoKit (`FormatoDM`, `FormatoEMD`, `FormatoHDF5`).

## 0.3.0, 0.2.0, 0.1.0

EELS thickness (t/λ) and the C K ratio method; the EDX quantification stages; the first extraction from the mac4DSTEM application.

[Unreleased]: https://github.com/mac4DSTEM/SpectroKit/compare/0.12.0...HEAD
[0.12.0]: https://github.com/mac4DSTEM/SpectroKit/compare/0.11.0...0.12.0
[0.11.0]: https://github.com/mac4DSTEM/SpectroKit/compare/0.10.0...0.11.0
[0.10.0]: https://github.com/mac4DSTEM/SpectroKit/compare/0.9.0...0.10.0
[0.9.0]: https://github.com/mac4DSTEM/SpectroKit/compare/0.8.2...0.9.0
[0.8.2]: https://github.com/mac4DSTEM/SpectroKit/compare/0.8.1...0.8.2
[0.8.1]: https://github.com/mac4DSTEM/SpectroKit/compare/0.8.0...0.8.1
[0.8.0]: https://github.com/mac4DSTEM/SpectroKit/compare/0.7.1...0.8.0
[0.7.1]: https://github.com/mac4DSTEM/SpectroKit/compare/0.7.0...0.7.1
[0.7.0]: https://github.com/mac4DSTEM/SpectroKit/compare/0.6.1...0.7.0
[0.6.1]: https://github.com/mac4DSTEM/SpectroKit/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/mac4DSTEM/SpectroKit/compare/0.5.4...0.6.0
[0.5.4]: https://github.com/mac4DSTEM/SpectroKit/compare/0.5.3...0.5.4
[0.5.3]: https://github.com/mac4DSTEM/SpectroKit/compare/0.5.2...0.5.3
[0.5.2]: https://github.com/mac4DSTEM/SpectroKit/compare/0.5.1...0.5.2
