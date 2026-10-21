# Parity checklist: SpectroKit against exSpy

What SpectroKit has of exSpy's documented API, row by row, and what shows it. Written 2026-10-15 for 0.5.0 (docs only; no
test was run for this file).

**Reference.** exSpy `7185a4d1` (checkout `References/exspy-7185a4d1`) with HyperSpy 2.4.0, RosettaSciIO 0.14.0, NumPy 2.5.4,
SciPy 1.18.1. The list is the pinned `doc/reference/*.rst` (signals, models, components, material, utils, data) and
`doc/user_guide/{eds,eels,dielectric_function}.rst`, with the public methods read from the modules.

**Validation: none.** Agreement with exSpy is agreement, not truth. Every EDX quantification and every EELS thickness or areal
density SpectroKit returns says `validation: "none"`; nothing here is validated on a sample of known composition or
thickness. A BIT or TOL row below means "reproduces what exSpy returned", never "is right". Where a row is also checked
against planted truth, the evidence column says so.

## Status codes

| code | meaning |
|---|---|
| BIT | ported, bit-identical to the pin (or equal in every case compared); a measured fact, not a requirement: numerics are held to the tolerance the Python package's own tests use; readers, I/O, indices and metadata are exact (D17) |
| TOL | ported within a registered tolerance (the bound is stated; the measured value is often far smaller) |
| DEV | ported with a registered deviation (named in the code or in an archived design note; the evidence says where) |
| PART | partial: part of the item exists, part does not |
| NOPIN | ported, but no exSpy output is compared (truth, constants or source reading only) |
| NO | not ported |
| NP | not planned (interactive or plotting, Gatan-licensed tables, bundled datasets) |

"package" in the SpectroKit column means the code exists and is tested but is not public API: a consumer cannot call it.

## CI portability

The macos-26 runner at `0653404` refuted cross-CPU bit parity for the Savitzky–Golay coefficients and edge fits.
0.5.2 keeps the LAPACK SVD solve (as SciPy) and adds a documented automatic-tolerance tie rule. The raw SciPy and exSpy fixtures are retained;
`portable-thresholds.json` adds the pinned Python policy oracle. [The CI audit](ci-parity.md) records the original gaps.

| Check | Status | Evidence |
|---|---|---|
| CI gate exit and consumer target inventory | regression tested | `CIScriptTests`: propagate a failing test through `tee`; tolerate absent build backend directories; gap-audit controls |
| Scan-to-spectrum mask transport and pooling (`MaskTransport`, `PoolBuilder`) | regression tested | no exSpy counterpart; pinned to a NumPy transcription of the app source: `RegistrationTests.numpyTranscriptionPins`, 2e-12 bound, measured gap 0 |

## Summary

| status | EDS | EELS | shared (axes, SciPy, NumPy) | all |
|---|---|---|---|---|
| BIT | 4 | 0 | 4 | 8 |
| TOL | 9 | 7 | 5 | 21 |
| DEV | 6 | 1 | 0 | 7 |
| PART | 7 | 3 | 0 | 10 |
| NOPIN | 1 | 0 | 1 | 2 |
| NO | 15 | 16 | 1 | 32 |
| NP | 4 | 4 | 0 | 8 |
| rows | 46 | 31 | 11 | 88 |

Where SpectroKit's strength is. EDS: the line table, X-ray windows and net counts, Cliff-Lorimer, the absorption iteration and
the line model's columns reproduce exSpy to 1e-9 or better on pinned cases. EELS: fixed-threshold, gradient and zero-loss log-ratio routes agree with the raw pins at the bounds below; automatic SG thresholds follow the documented policy oracle and deliberately differ at numerical ties. The C, N, O K cross section from exSpy's dft GOS reproduces it to 1e-10 or better (measured 7e-16 for the cross section).

### The largest gaps, in the order an outside user would ask

1. **A full EELS model fit.** `EELSModel` with `EELSCLEdge` components (several edges together, power-law background fitted
   with the edges, fine structure, low-loss convolution, `quantify`) is not ported. What exists is one K edge (C, N or O) quantified
   by the ratio method after a two-area power-law background: a single-edge estimate, not exSpy's model. No L or M edges, no
   hydrogenic or Dirac GOS, no edges database beyond three onsets.
2. **Deconvolution and dielectric function.** `fourier_log_deconvolution`, `fourier_ratio_deconvolution`,
   `richardson_lucy_deconvolution`, `power_law_extrapolation`, `kramers_kronig_analysis` and `DielectricFunction` are not ported
   (the maintainers' roadmap lists deconvolution as later work).
3. **Zero-loss peak handling.** `align_zero_loss_peak`, `get_zero_loss_peak_mask` and a masked `estimate_zero_loss_peak_centre`
   are not ported: the thickness code assumes the peak sits at 0 eV and only reports the energy of the first maximum.
4. **EDS quantification as an API.** Zeta and cross-section quantification, the absorption iteration, take-off angle, mass
   absorption and composition conversion are ported and pinned but are `package`, not public; only Cliff-Lorimer reaches a
   consumer, through `PooledQuantifier` on one pooled spectrum. No per-pixel quantification maps, `vacuum_mask`,
   `get_probe_area`, `density_of_mixture`.
5. **EDS model operations and calibration.** `EDSModel.fit_background`, `calibrate_xray_lines`, the free/fix line parameters,
   `get_calibration_from`, `get_xray_lines_near_energy`, and public control of the background-window parameters
   (`line_width`, `windows_width`, `integration_window_factor`) are missing. The energy-axis refinement that exists is
   SpectroKit's own method, not `calibrate_energy_axis`, and it has a registered finding (offset and gain trade off on lines
   that span little of the axis).

## EDS

### Elements, lines, line table

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `EDSSpectrum.set_elements`, `add_elements` | element lists are plain input (`FitSettings.elements`, `QuantificationMethod.elements`, `ElementWindows.Pick`); no metadata tree | PART | H and He are dropped where exSpy keeps them: SpectroCoreTests/SpectroscopyCoreTests `testHeliumAndHydrogenAreDroppedWhereExspyKeepsThem`; the bookkeeping itself is not compared |
| `EDSSpectrum.set_lines`, `add_lines` (`only_one`, `only_lines`) | `XRayLines.defaultLines` (package); the public `ElementWindows.build(picks:)` defaults to a different rule (`ElementWindows.defaultFamily`: K up to 20 keV, else L) | DEV | `testDefaultLineChoiceMatchesExspy` (lists equal on 2 axes x 4 beam energies, for `defaultLines`); the deviation of the public default is named in `ElementWindows` |
| `utils.eds.get_xray_lines` (`weight_threshold`, `energy_range`, `only_lines`) | `XRayLines.lines(of:)`, `.all`, `.linesInRange` | PART | `testDefaultLineChoiceMatchesExspy`, `testEmptyOnlyLinesIsNoFilter`; the weight and energy filters are not exposed |
| `utils.eds.get_xray_lines_near_energy`, `print_lines_near_energy`, `print_lines`, `EDSSpectrum.print_lines*` | not in Sources: the rule is re-implemented inside the test over `XRayLines.all` | NO | SpectroEDXTests/PeakGateTests `testP1LineLookupEqualsExSpy` (360 lookups equal) checks the table through that rule |
| `material.elements` X-ray lines (Chantler energies, EPQ weights) | `XRayLines.all` (947 rows, Z 1...92), `XRayLines.line(_:)` | BIT | SpectroEDXTests/LineTableParityTests `testEveryLineOfTheTableEqualsExSpy`: all 947 rows (Z, line, energy, weight, order) `==` exSpy's own loader (`tools/edx-lines/pins.py`); also SpectroCoreTests/SpectroscopyCoreTests `testLineTableIsExspyVerbatim` and SpectroEDXTests/PeakGateTests `testP1LineEnergyAndWidthEqualExSpy` |
| `material.elements` general and physical properties (Z, atomic weight, density) | `QuantElementData` (package, Z 1...95) | PART | used inside the pins (`testCuSnWeightToAtomic`, `testCliffLorimerAlZnAndFePt`); not exposed |
| `material.elements` binding energies, EELS `threshold` and `edge` fields | none (EELS has three onsets, see below) | NO | |
| `material.atomic_number_to_name` | none | NO | |
| `utils.eds.get_FWHM_at_Energy` | `XRayLines.fwhm(resolutionMnKaEV:atEnergy:)` | TOL | `testFWHMLawMatchesExspy` (about 20 values, 1e-15 absolute), `testP1LineEnergyAndWidthEqualExSpy` (1e-14 relative) |

### Windows and line intensities

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `get_lines_intensity` (net counts of integration windows less background windows) | `ElementWindows.build(picks:...)`, `ElementWindows.netCounts`, `.maps`, `.integratedMaps` (public); sigma added | BIT | FePt and TM002 net counts equal (`testFePtPins`, `testTM002Pins`, `==` on integer sums); WindowGateTests `testLineIntensitiesEqualExSpyOnEveryPlantedSpectrum` (26 280 values, 4e-16 relative). Two checked lines of one element closer than a window are clipped (`clipOverlaps`), which exSpy does not do |
| `estimate_integration_windows` | `WindowIntensity.integrationWindows` (package), used by `ElementWindows.build` at width 2.0 | BIT | `testFePtPins`, `testTM002Pins` (windows `==`), WindowGateTests `testWindowsEqualExSpy` |
| `estimate_background_windows` (with the merge of overlapping windows) | `BackgroundWindows.estimate`, `.merge` (package), used at `line_width` [2,2], `windows_width` 1 | BIT | `testFePtPins`, `testTM002Pins` (merged windows at [2,2] and [5,2]), `testMgAlSiMergedBackgroundSitsOnSiliconsFlank`, `testWindowsEqualExSpy` |
| the window parameters of the three rows above (`integration_window_factor`, `line_width`, `windows_width`, `xray_lines`) | not settable from the public API | PART | the package functions take them and are tested at [5,2] and at 2.1 FWHM (`testTM002Pins`) |
| `EDSSpectrum.sum` | `SpectrumImage.sum(mask:)`, `windowSums` (dense and sparse); exact UInt64; live time is passed through, not summed | NOPIN | CountsGateTests `testC1*`, `testC2*`, `testC3NoWrapAndNoLiveTimeProduct`: equal to a NumPy decode and planted draws; exSpy's `sum` was only probed (design note edx-stage-gates, archived in the suite's private folder, section 3, G-C) |
| `EDSSpectrum.rebin` | none | NO | |
| `LazyEDS*Spectrum` | none (a sparse store exists instead) | NP | |
| `EDSSpectrum.plot`, `add_xray_lines_markers`, `remove_xray_lines_markers` | none (headless) | NP | |

### Geometry and microscope

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `get_take_off_angle`, `utils.eds.take_off_angle` | `TakeOff.angle` (package) | DEV | `testTakeOffPins` (6 cases, 1e-9 relative); a missing tilt, azimuth or elevation is refused where exSpy fills 0, 0, 35 deg |
| `set_microscope_parameters` (beam energy, tilt, live time, azimuth, elevation, Mn Ka resolution, beam current) | `SpectrumImageMetadata` read from the file, `BeamEnergy.resolve`; no mutable metadata tree | PART | `testTheDM4EnergyAxisAndMetadataAreTheFiles`, `testTheVeloxOpenerCarriesTheFilesAxisAndMetadata` |
| `get_calibration_from` (TEM and SEM) | none | NO | |
| `EDSTEMSpectrum.get_probe_area` | none (the probe area is an input of `ZetaFactor.doseCrossSection`, package) | NO | |
| `EDSTEMSpectrum.vacuum_mask` | none | NO | |
| `EDSTEMSpectrum.decomposition` | none | NO | |

### Quantification

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `quantification(method="CL")` | `CliffLorimer.weightFractions` (package); public only through `PooledQuantifier.run` on one pooled spectrum, computed or typed k | DEV | EDSQuantPinsTests `testCliffLorimerWithoutAbsorption` (at least 10 cases, 1e-9), SpectroscopyQuantTests `testCliffLorimerAlZnAndFePt`, `testCliffLorimerZeroHandlingTable`; fewer than two lines above the 0.1 floor is refused where exSpy reports 100 % (`.exspyHundredPercent` reproduces it for the pins) |
| `quantification(method="zeta")` | `ZetaFactor.quantify`, `.dose` (package; outside the method menu, unused by the pooled path) | TOL | `testZetaWithoutAbsorption` (1e-9; dose 1e-12) |
| `quantification(method="cross_section")` | `ZetaFactor.crossSection`, `.doseCrossSection` (package) | TOL | SpectroscopyQuantTests `testZetaAndCrossSectionPins` (exSpy values recorded by hand, 1e-9; no fixture-driven set as for CL and zeta) |
| `absorption_correction=True`, `get_abs_corr_zeta`, `get_abs_corr_cross_section` (iteration to convergence) | `AbsorptionCorrection` (package), `SingleDetectorGeometry`; the four-detector geometry is SpectroKit's own | DEV | `testCliffLorimerAbsorptionMatchesEXSpyIterationForIteration`, `testZetaAbsorptionMatchesEXSpyIterationForIteration` (same iteration count, 1e-9, with `.exspySigned`); the default `.absolute` rule runs on where exSpy's signed maximum stops (`testAbsoluteCriterionRunsOnWhereEXSpyStopsEarly`, within 1.0 percentage point); zero thickness is the limit T = 1, exSpy gives nan |
| `CL_get_mass_thickness` | mass thickness from `CliffLorimer` / `AbsorptionCorrection` (package) | TOL | `testMassThicknessCL`; pinned mass thickness 1e-9 in EDSQuantPinsTests |
| `cross_section_to_zeta`, `zeta_to_cross_section` | `ZetaFactor.zetaFromCrossSection`, `.crossSectionFromZeta` (package) | TOL | `testZetaAndCrossSectionPins` (1e-9; round trip 1e-12) |
| `quantification` over a spectrum image (per-pixel maps, `navigation_mask`, `closing`, `plot_result`) | none: one pooled spectrum per call | NO | |
| `material.weight_to_atomic`, `atomic_to_weight` | `CompositionConversion` (package) | TOL | `testCuSnWeightToAtomic` (1e-9), and inside every quantification pin |
| `material.mass_absorption_coefficient`, `mass_absorption_mixture` | `MassAbsorptionTable.mac`, `.mixture` (package) | DEV | `testMassAbsorptionPins` (about 10 values, 1e-9); the table's trailing (0, 0) sentinel is stripped and an energy outside the table is refused (`testSentinelIsStrippedAndOutsideTableRefuses`) where exSpy runs off the array |
| `material.density_of_mixture` | none | NO | |
| `utils.eds.electron_range`, `xray_range` | none | NO | |

### Model

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `create_model` (TEM, SEM), `EDSModel`, `EDSTEMModel`, `EDSSEMModel` objects | `EDSLineModel.build`, `FitSettings`, `EDSFitResult` (public); `EDSFit.run` is package, reached through `PooledQuantifier.run` and `ElementProposer.propose` | PART | no model object, no component handling |
| `EDSModel.add_family_lines` (tied line energies, widths, weights) | `EDSLineModel.build`; Si-escape columns are an option (on by default, off is the parity setting) | TOL | SpectroscopyFitTests `testDesignColumnsMatchHyperspy` (columns 1e-9 of the peak; centres, FWHM, weights 1e-12) |
| `EDSModel.add_polynomial_background(order=6)` | `FitBackground.polynomial(order:)` (the parity path; the default is SpectroKit's own continuum) | TOL | `testPoly6PathEqualsHyperspyModel` (model equals `as_signal()` to 1e-7 counts) |
| `EDSModel.fit` (`lm`) | `EDSFit.run` (package): a non-negative linear least-squares solve, not an iterative `lm`; Poisson maximum likelihood is an option | TOL | `testClosedLoopRecoversWeightFractions` (1e-4 of truth, 1e-6 of exSpy's fit), `testFePtLeastSquaresPins` (2e-4 of the pin: HyperSpy's `lm` stops short of the minimum; 1e-6 of the exact minimiser) |
| `EDSModel.fit_background` | none (the background is fitted with the lines) | NO | |
| `EDSModel.calibrate_energy_axis` (offset, scale or resolution, one at a time) | `EnergyAxisRefinement.refine` (package; `AxisRefinementResult` public): all three jointly, a different method | DEV | SpectroKit's own method, not a port: `testAxisRefinementRecoversPlantedOffsetAndGain`; SpectroEDXTests/AxisGateTests `testE3RefinementRecoversPlantedOffsetAndGain` (registered finding: 349 of 384 fits outside 1 eV offset, `withKnownIssue`), `testE3ExSpyCalibrationPinsAreTheRecordedSecondEstimate` (exSpy as second estimate) |
| `EDSModel.calibrate_xray_lines` | none | NO | |
| `EDSModel.free_`/`fix_` `sub_xray_lines_weight`, `xray_lines_energy`, `xray_lines_width`, `free_background`, `fix_background` | none: line energies, widths and weights are fixed by the table and the width law | NO | |
| `EDSModel.get_lines_intensity` (fitted areas) | `EDSFitResult.values`, `.sigma(at:)`; `PooledQuantification.Row.net`, `.sigma` | PART | the fit pins above; per-line sigma is not compared with exSpy |
| `EDSModel.enable_xray_lines`, `disable_xray_lines`, `remove`, `as_dictionary`, `plot` | none | NP | |
| `utils.eds.xray_lines_model` (simulated spectrum from lines) | none; `EDSLineModel` builds the same Gaussian columns for fitting | NO | |
| `exspy.data.EDS_TEM_FePt_nanoparticles`, `EDS_SEM_TM002` | used as test fixtures only | NP | |

## EELS

### Edges, elements, microscope

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `EELSSpectrum.add_elements`, `generate_subshells`, `edges_at_energy`, `print_edges_near_energy`; `utils.eels.get_edges_near_energy`, `get_info_from_edges` | none | NO | |
| the edges database (`eels_binding_energies.json`: onsets, major and minor edges) | `CoreLossEdge.bundled`: C K, N K, O K onsets 284, 401, 532 eV | PART | `EdgePinsTests` use the three edges |
| `EELSSpectrum.set_microscope_parameters` (E0, alpha, beta, ...) | `EELSMicroscope` (E0, convergence, collection) | PART | `EdgeEdgeCaseTests` `testRefusals`; no metadata tree |

### Zero-loss peak, elastic intensity, thickness

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `estimate_zero_loss_peak_centre` (with `mask`) | `ThicknessPixel.zlpCentre`: the energy of the first maximum, no mask, a diagnostic only | PART | SpectroEELSTests/ThicknessEdgeCaseTests `testZeroLossCentreIsTheEnergyOfTheFirstMaximum`; no exSpy output compared |
| `align_zero_loss_peak`, `get_zero_loss_peak_mask` | none (nothing is shifted) | NO | |
| `estimate_elastic_scattering_threshold` | `ThresholdRule.estimated` over `ElasticThreshold.estimate` (package) | DEV | The SG solve stays on LAPACK's SVD as in SciPy; automatic SG ties use `64 eps * peak cropped input * coefficient L1`, first channel wins. `portable-thresholds.json` pins 18 routes / 138 pixel answers; 20 differ deliberately from raw exSpy. ThicknessPinsTests / RefuterRegressionTests hold channels exactly and I0/It to 1e-12 relative, t/lambda to 1e-12 absolute. Explicit tolerance and gradient retain exact comparisons. Even/short windows and unsupported orders are refused. |
| `estimate_elastic_scattering_intensity` (threshold as float, signal or estimated; zero-loss sum) | `ThresholdRule` (`.fixed`, `.estimated`, `.perPixel`) giving `ThicknessPixel.i0`; summed in NumPy's order | TOL | `testFixedThresholdPins`, `testEstimatedThresholdPins` (I_0 1e-12 relative; automatic SG uses the policy deviation above). Binned axes only (the Simpson path for unbinned axes is not ported); a Python `int` threshold (a channel index) cannot be expressed; `.perPixel` out of the axis gives a nil pixel where exSpy raises (design note eels-slice-1, archived in the suite's private folder, sections 1 and 3) |
| `estimate_thickness` (log ratio, `threshold` or `zlp`) | `EELSThickness.logRatio` -> `ThicknessMap` | TOL | `testEstimatedThresholdPins`, `testFixedThresholdPins`, `testZeroLossSpectrumRoutePins` (t/lambda 1e-12 absolute, 3 images; automatic SG uses the policy oracle above); truth: PlantedTruthTests, LineScanTruthTests. Registration: design note eels-slice-1, archived in the suite's private folder |
| `estimate_thickness` with `density` and `lambda` (absolute nm) | `MeanFreePathSource` (`.given`, `.iakoubovskii`, `.givenWithAngularCorrection`) | TOL | `testAbsoluteThicknessPins` (3 routes x 3 lambda sources, 1e-12 times lambda x correction) |
| `utils.eels.iMFP_Iakoubovskii` | `InelasticMeanFreePath.iakoubovskii` | TOL | `testMeanFreePathAndAngularCorrectionPins` (20 values, 1e-13 relative) |
| `utils.eels.iMFP_angular_correction` | `InelasticMeanFreePath.angularCorrection` | TOL | same test (180 values, 1e-13) |
| `utils.eels.iMFP_TPP2M` | none | NO | |
| `utils.eels.effective_angle` | `EdgeCrossSection.effectiveAngleMrad` (package) | TOL | EdgePinsTests `testCrossSectionEqualsExSpyOnTheGrid` (1e-14) |

### Deconvolution, extrapolation, dielectric function

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `fourier_log_deconvolution` | none | NO | |
| `fourier_ratio_deconvolution` | none | NO | |
| `richardson_lucy_deconvolution` | none | NO | |
| `power_law_extrapolation` | none (the pre-edge power law below is a different function) | NO | |
| `kramers_kronig_analysis`; `DielectricFunction.get_number_of_effective_electrons`, `get_electron_energy_loss_spectrum`; `utils.eels.eels_constant_dielectric` | none | NO | |
| `spikes_diagnosis`, `spikes_removal_tool`, `EELSSpectrum.plot`, `LazyEELSSpectrum` | none | NP | |
| `EELSSpectrum.rebin`, `vacuum_mask` | none | NO | |
| `estimate_single_scattering` | not in exSpy at the pin (`grep` finds nothing); Fourier-log is the pinned single-scattering route | NO | |

### Model, edge component, GOS

| exSpy / HyperSpy | SpectroKit | status | evidence |
|---|---|---|---|
| `create_model`, `EELSModel` (`fit`, `smart_fit`, `fit_background`, `quantify`, convolution with the low loss, `append`, `remove`, `enable_`/`disable_edges`, `fix_`/`free_edges`, onset-energy freedom) | none | NO | |
| `EELSModel.two_area_background_estimation`, `resolve_fine_structure`, `remove_fine_structure_data`, fine-structure enable/disable/fix/free | none | NO | |
| `EELSCLEdge.function` (energy-differential cross section, dft GOS, K shell) | `EELSEdgeQuantification.differentialCrossSection` (public), `EdgeCrossSection` (package) | TOL | EdgePinsTests `testCrossSectionEqualsExSpyOnTheGrid` (192 cases x 3 scales x 4 widths: cross section 1e-10 bound, 7e-16 measured), `testSplineAndQLimitsEqualExSpy`; second oracle `testCrossSectionWithinThreePercentOfPyEELSMODEL` (72 cases). C K, N K, O K only. Registration: design note eels-slice-2, archived in the suite's private folder |
| `EELSCLEdge` with `GOS="Hartree-Slater"` | none | NP | Gatan's tables are never shipped (design note eels-slice-2, section 1, archived in the suite's private folder) |
| `EELSCLEdge` with `GOS="hydrogenic"` | none | NO | |
| `EELSCLEdge` with the Dirac GOS (`Dirac_GOS_compact.gosh`) | none; its C K cross section is a pins-script diagnostic | NO | design note eels-slice-2, section 4.4, archived in the suite's private folder |
| `EELSCLEdge` L, M and other K edges; fine structure (spline, Gaussians); `fine_structure_*` | none | NO | |
| `EELSArctan`, `DoublePowerLaw`, `Vignetting`, `VolumePlasmonDrude` | none | NO | |
| `SEE`, `PESCoreLineShape`, `PESVoigt` | none | NP | |
| `exspy.data` EELS datasets, `eelsdb` | none | NP | |

## Shared numerics (HyperSpy, SciPy, NumPy) that the rows above stand on

| reference | SpectroKit | status | evidence |
|---|---|---|---|
| HyperSpy `value2index` (half-towards-zero rounding after a 1e-12 truncation) | `EnergyAxis.index(of:)` | BIT | AxisGateTests `testE2ValueToIndexEqualsHyperSpyOnTheWholeGrid` (12 573 cases, 3 that raise), `testValue2IndexMatchesHyperspy` (544) |
| HyperSpy axis slices (`isig[a:b]`) | `EnergyAxis.channelRange` | BIT | `testE2SlicesEqualHyperSpyArraySlices` (52), `testSliceSemanticsMatchHyperspy` |
| HyperSpy `value_range_to_indices` | `EELSAxis.valueRangeToIndices` | NOPIN | AxisRulesTests `testValueRangeToIndicesFollowsHyperSpysFourConditions`: hand-derived from the source, no HyperSpy run compared |
| `scipy.signal.savgol_filter(deriv=1, mode="interp")` as `smooth_savitzky_golay(differential_order=1)` | `SavitzkyGolay` (package) | TOL | LAPACK SVD coefficients and edge fits, as SciPy. Unchanged SciPy fixture: coefficients within 1e-13 times coefficient L1; derivatives within 1e-12 times input peak times coefficient L1 (cancellation-scaled absolute error). Supplied-coefficient interior/convolution tests remain bit exact. Edge values alone and in an image agree within the same bound (dgelsd's bits depend on the number of right-hand sides). Legacy test names containing “BitIdentical” are retained for continuity; their comments state the current bounds. |
| `numpy.gradient` | `NumpyGradient` | BIT | SavitzkyGolayPortTests `testGradientIsBitExact` |
| NumPy pairwise sum | `NumpySum` | BIT | AxisRulesTests `testPairwiseSumEqualsNumpysSum` (bit patterns, 11 lengths) |
| `scipy.interpolate.make_interp_spline(k=3)` | `InterpolatingSpline` | TOL | `testSplineAndQLimitsEqualExSpy` (knots equal, coefficients 1e-10) |
| `scipy.integrate.simpson` | `ScipySimpson` | TOL | `testCrossSectionEqualsExSpyOnTheGrid` (q integral 1e-12) |
| HyperSpy `PowerLaw.estimate_parameters` (two-area) and `remove_background(fast=True)` | `PowerLawWindow`, `PowerLawFit` | TOL | `testRatioMethodEqualsExSpyOnThePlantedImages` (window indices and energies equal; I1, I2, r, A, background 1e-12). A pixel whose window sum is not positive is nil with a reason where HyperSpy gives `nan_to_num`; a window not inside the axis is refused where HyperSpy clamps (design note eels-slice-2, archived in the suite's private folder, amendments) |
| `scipy.optimize.nnls` | `LeastSquaresFit.solve(nonNegative:)` | TOL | `testNNLSMatchesScipyAndDiffersFromUnbounded` (1e-8) |
| HyperSpy `find_peaks1D_ohaver` | none (pins used as an independent check of the proposer) | NO | PeakGateTests `testP3PeakFinderIsTheRegisteredIndependentEye` |

## Readers

Opening a file is not SpectroKit's job. The readers, and parity with RosettaSciIO, live in FormatoKit (`FormatoDM` for Gatan
`.dm3` / `.dm4`, `FormatoEMD` for Velox `.emd`); SpectroKit depends on it at an exact tag. `SpectrumImageOpener` in
`SpectroCore` calls them for a Velox EDS stream and a GMS `.dm4` EDS spectrum image. What SpectroKit still tests at that seam,
with RosettaSciIO's rules as the reference: counts (CountsGateTests, 8 public files and planted streams equal an independent
decode), the energy axis (AxisGateTests `testE1*`, exactly equal to RosettaSciIO's rule on 8 public files and the planted
headers), and the opener (SpectrumImageOpeningTests `testTheDM4EDSDecodeMatchesTheTruthPerRecipe`). RosettaSciIO's own Velox EDS
loader was never run as an oracle (its `sparse` dependency is not installed in the reference environment).

## In SpectroKit with no exSpy counterpart

Not parity items, listed so nobody looks for a pin: the element proposer (Currie detection limit, joint non-negative fit),
Currie and Garwood counting statistics and sigma propagation, pooled quantification with computed k-factors (Bote-Salvat
cross sections, Krause fluorescence yields, an EPQ detector efficiency), the four-detector absorption geometry, the empirical
continuum with an Al K-edge step, Poisson maximum-likelihood and reference shapes in the fit, the unlisted-line check, the
fit-range sensitivity check, and, in EELS, the ratio-method areal density (`EELSEdgeQuantification.ratioMethod`, Egerton's
ratio method on exSpy's GOS), which exSpy does not have as a function.

## Where the source claims more than the tests show

- `NumpySum.swift` header: I_0 and I_t "bit for bit" against exSpy, citing `ThicknessPinsTests`. Those tests hold I_0 and I_t to
  1e-12 relative, which the written tolerance allows; the header should say so. The summation order itself is bit-tested (`testPairwiseSumEqualsNumpysSum`).
- `MassAbsorption.swift` header: all 90 FFAST lists "equal exSpy `ffast_mac.py` value for value", measured 2026-10-05. No test
  compares the table with exSpy's; the tests pin about 10 coefficients and mixtures.
- `XRayLineData.swift` / `XRayLines.swift`: the 947-row table is "verbatim" (a source hash is recorded). The tests assert about
  12 lines and the row count, not every row.
- design note eels-slice-2, archived in the suite's private folder (amendment of 2026-10-14): background fit, window sums and n "bit-identical to HyperSpy's
  (0.0)". The tests bound these at 1e-12 and 1e-10 relative, which the written tolerance allows; only window indices, energies and the low-loss
  intensity are asserted equal. The measured zero is true of the run, not of the test.
- `ElementWindows` (public) picks the default line by a Velox-style family rule; `XRayLines.defaultLines`, which equals exSpy's
  choice, is package. The public window path therefore does not reproduce `add_lines()` for heavy elements (Hf at 200 kV on an 80 keV axis picks
  L, exSpy picks K).
- `FitRange.swift` / `QuantificationMethod`: "eXSpy parity" for the whole-range polynomial. It is pinned on one synthetic
  closed loop (model to 1e-7 counts) and FePt (2e-4 of the pin, since HyperSpy's `lm` stops short), not on a general case.
- The cross-section route of `ZetaFactor` has hand-recorded exSpy values (`testZetaAndCrossSectionPins`) but no fixture-driven
  iteration-for-iteration set like Cliff-Lorimer and zeta.
