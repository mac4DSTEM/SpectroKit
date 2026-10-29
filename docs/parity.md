# Parity checklist: SpectroKit against exSpy and HyperSpy

What SpectroKit has of exSpy's and HyperSpy's EDS and EELS API, row by row, what shows it, and what is next. Audited from the
source on disk on 2026-10-21 for 0.8.0 (the walk of every public method of `exspy/signals/{eds,eds_tem,eds_sem,eels,dielectric_function}.py`,
`exspy/models/*`, `exspy/components/*`, `exspy/utils/*`, `exspy/material.py`, and the tests in `exspy/tests/` for tolerances).

**Reference.** exSpy 0.3.2 and HyperSpy 2.4.0 in `References/python` (gitignored; `tools/reference/setup.sh` builds it from `tools/reference/requirements.txt`);
fixtures stay pinned to exSpy `7185a4d1` (`References/exspy-7185a4d1`) with RosettaSciIO 0.14.0, NumPy 2.5.4, SciPy 1.18.1, except the
0.8.0 maps fixture, which is exSpy 0.3.2's own output (`tools/edx-quant-maps/pins.py`). The public methods were read from the installed
modules; the tolerance column is what exSpy's own test files assert (`assert_allclose` defaults are rtol 1e-7).

**Validation: none.** Agreement with exSpy is agreement, not truth. Every EDX quantification and every EELS thickness or areal
density SpectroKit returns says `validation: "none"`; nothing here is validated on a sample of known composition or
thickness. A BIT or TOL row below means "reproduces what exSpy returned", never "is right". Where a row is also checked
against planted truth, the evidence column says so.

## States, codes and priorities

| state | meaning |
|---|---|
| present | the function exists and is compared with the reference (codes BIT, TOL, DEV, NOPIN) |
| partial | part of the item exists, part does not (code PART) |
| missing | not ported (code NO) |
| not planned | out of scope, with the reason in the priority column (code NP) |

| code | meaning |
|---|---|
| BIT | bit-identical to the pin (a measured fact, not a requirement: numerics are held to the tolerance the Python package's own tests use; readers, I/O, indices and metadata exact, D17) |
| TOL | within a stated tolerance (the measured value is often far smaller) |
| DEV | ported with a stated deviation (named in the code or the evidence) |
| NOPIN | ported, but no exSpy output is compared (truth, constants or source reading only) |
| PART / NO / NP | partial / not ported / not planned |

Priority: **study** = on Paul's path (the TEM study, the two apps' open kit asks: public quantification, the EDX fit accuracy, EDS
calibration and `rebin`, the EELS model fit and what it stands on); **useful** = worth porting soon; **not planned: reason**.
"package" in the SpectroKit column means the code exists and is tested but is not public API: a consumer cannot call it.

## CI portability

The macos-26 runner at `0653404` refuted cross-CPU bit parity for the Savitzky–Golay coefficients and edge fits.
0.5.2 keeps the LAPACK SVD solve (as SciPy) and adds a documented automatic-tolerance tie rule. The raw SciPy and exSpy fixtures are retained;
`portable-thresholds.json` adds the pinned Python policy oracle. [The CI audit](ci-parity.md) records the original gaps.

| Check | Status | Evidence |
|---|---|---|
| CI gate exit and consumer target inventory | regression tested | `CIScriptTests`: propagate a failing test through `tee`; tolerate absent build backend directories; gap-audit controls |
| Scan-to-spectrum mask transport and pooling (`MaskTransport`, `PoolBuilder`) | regression tested | no exSpy counterpart; pinned to a NumPy transcription of the app source: `RegistrationTests.numpyTranscriptionPins`, 2e-12 bound, measured gap 0; sparse form `MaskTransport.regions` equal to the dense transport of each region (overlap, footprints exact; inside-grid area 1e-12), SparseMaskTransportTests |
| Line-profile pooling (`SpectrumLineProfile`, hard) | pinned | scikit-image 0.26.0 `measure.profile_line(order=0, linewidth=w)` on axis-parallel lines, odd width on a pixel line and even width on a half-pixel line: exact (gap 0); oblique, polyline, fractional and off-grid paths pinned to a NumPy transcription of the kit's geometry (gap 0); `SpectrumToolsPinsTests` |
| Line-profile pooling (`.bilinear`) | pinned | `profile_line(order=1, linewidth=w)`, integer width, oblique line inside the image, `spacing = length / (n - 1)`: 2.4e-15 relative (bound 1e-12) |
| Savitzky-Golay smoothing (`SpectrumSmoothing.savitzkyGolay`) | pinned | `scipy.signal.savgol_filter(x, w, p, mode)` for interp, mirror, nearest, constant, wrap and HyperSpy 2.4.0 `smooth_savitzky_golay`: 5.8e-13 relative (bound 1e-9, SciPy `assert_allclose` default rtol is 1e-7); derivatives not offered; not bit for bit (unlike the EELS threshold derivative) |
| EELS per-edge windows (`EdgeWindows`, `EELSModelFit.fit(edgeWindows:)`, `EELSBackground.preview`) | regression tested | the convention is GMS's and eels.info's (a power law on a window below each edge, the edge fitted on a signal window above it); no Python parity for the windowing, planted truth only (`EdgeWindowsTests`: C K, N K, O K 3:1:2 recovered to 4 %, the one-range fit 30 % off; with `stripPrecedingEdges` (off by default: on the real a-C maps the convolved C K model over-strips O K) each fitted edge is stripped before the next, so N K inside the C K tail is recovered to 3 % where an unstripped fit reads 75 % low; two edges 85 eV apart take a fallback background window with a note); each edge also carries `intensityStd`, a statistical 1σ from Poisson counts and the background (A, r) sandwich covariance (the concept of Egerton's h factor; nil with stripping after the first edge), tested against a numerical propagation to 1e-3 and, as a Monte Carlo of one seeded fixture at high counts with stripping off, against the scatter of 300 noisy realizations within 15 %; the power law's two-area estimate in `preview` is HyperSpy's (pinned elsewhere); `validation: "none"` |
| Gaussian smoothing | pinned | `scipy.ndimage.gaussian_filter1d(sigma, truncate=4, mode)` all five modes: 8e-16 relative |
| Moving average | pinned | `scipy.ndimage.uniform_filter1d(size, mode)` all five modes, odd and even sizes: 2.9e-15 relative |
| Sparse region transport (`MaskTransport.regions`) | regression tested | equals the dense `transport(mask:)` of each region: overlap, footprints, reports, pooled spectra exact; also against `registration-pins.json` (2e-12) |


## Summary

| state | EDS | EELS | shared | all |
|---|---|---|---|---|
| present | 24 | 24 | 10 | 58 |
| partial | 9 | 2 | 0 | 11 |
| missing | 13 | 9 | 1 | 23 |
| not planned | 4 | 4 | 0 | 8 |
| rows | 50 | 39 | 11 | 100 |

Recounted from the rows themselves at 0.10.0 (a script over the seven-column tables; it reproduces the 0.8.1 summary of 88 rows exactly). The 0.9.0 summary had not been
recounted after the 0.9.0 EELS rows were added, so the EELS column moves by more than the 0.10.0 changes alone (Richardson-Lucy now present, the MLLS fit added); the EDS column gains
four rows (sum and escape peaks, k-factor import, sigma on wt% and at%, the per-region result). The three-column tables above (CI portability, with the new line-profile,
smoothing and sparse-transport rows) are not part of this count.

Of the present rows: BIT 10, TOL 33, DEV 8, NOPIN 5, and two rows with their own code (EXACT, NP). By priority: study 67 rows
(52 present, 15 partial or missing), useful 25,
not planned 8.

Before this audit (0.7.1): 88 rows, 8 BIT, 21 TOL, 7 DEV, 10 PART, 2 NOPIN, 32 NO, 8 NP. 0.8.0 makes quantification public (7 rows from package or missing to public present or deviating).

Where SpectroKit's strength is. EDS: the line table, X-ray windows and net counts, Cliff-Lorimer, zeta, cross section, the absorption iteration and
the line model's columns reproduce exSpy within exSpy's own test tolerances (most to 1e-9) on pinned cases. EELS: fixed-threshold, gradient and zero-loss
log-ratio routes agree with the raw pins at the bounds below; automatic SG thresholds follow the documented policy oracle and deliberately
differ from raw SciPy where the CPU-dependent tie rule says so.

### The largest gaps, in the order the study needs them

1. **What remains of the EELS chain** (0.9.0 landed alignment, power-law extrapolation, Fourier-log and Fourier-ratio, and the multi-edge model fit on 20 K and L edges):
   fine structure and a free onset energy in the model, `kramers_kronig_analysis`, hydrogenic and Dirac GOS. See `docs/open-items.md`.
2. **The dielectric function** (`kramers_kronig_analysis`) and the EELS model on real data (no validation yet).
3. **EDS calibration and model operations**: `rebin`, `get_calibration_from`, `calibrate_xray_lines`, free/fix of line parameters, the public
   background-window parameters (`line_width`, `windows_width`, `integration_window_factor`), `vacuum_mask` (the mask is an input now).
4. **EDX fit accuracy on real Al alloys** (Mg K alpha about 300 counts low, Si 8.7 % low, sigma 5 to 12 % small; auto ID misses Mg in 37 of 38
   Al-Mg-Si files): the diagnosis needs the pure-Al standard; `docs/open-items.md` carries the cause as far as it is known.
5. **The app-side `@testable` reach**: 0.9.0 opened `PooledQuantificationInput`'s fields and the window, segment and proposal initialisers; the next release opens `UnlistedLineCheck.Candidate` and `.Move` (fields and initialisers) and `UnlistedLineCheck.init` with its stored fields (SpectroKit#13). Nothing the apps reach stays `package`.

## EDS

### Elements, lines, line table

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `EDSSpectrum.set_elements`, `add_elements` | element lists are plain input (`FitSettings.elements`, `QuantificationMethod.elements`, `ElementWindows.Pick`); no metadata tree | partial | PART | useful | no numeric test (`tests/signals/test_eds_sem.py::test_add_elements`, names only) | H and He are dropped where exSpy keeps them: SpectroCoreTests/SpectroscopyCoreTests `testHeliumAndHydrogenAreDroppedWhereExspyKeepsThem`; the bookkeeping itself is not compared |
| `EDSSpectrum.set_lines`, `add_lines` (`only_one`, `only_lines`) | `XRayLines.defaultLines` (package); the public `ElementWindows.build(picks:)` defaults to a different rule (`ElementWindows.defaultFamily`: K up to 20 keV, else L) | present | DEV | study | no numeric test (`test_eds_sem.py::test_add_lines`, names only) | `testDefaultLineChoiceMatchesExspy` (lists equal on 2 axes x 4 beam energies, for `defaultLines`); the deviation of the public default is named in `ElementWindows` |
| `utils.eds.get_xray_lines` (`weight_threshold`, `energy_range`, `only_lines`) | `XRayLines.lines(of:)`, `.all`, `.linesInRange` | partial | PART | useful | `tests/misc/test_eds.py` (names, energies; exact) | `testDefaultLineChoiceMatchesExspy`, `testEmptyOnlyLinesIsNoFilter`; the weight and energy filters are not exposed |
| `utils.eds.get_xray_lines_near_energy`, `print_lines_near_energy`, `print_lines`, `EDSSpectrum.print_lines*` | not in Sources: the rule is re-implemented inside the test over `XRayLines.all` | missing | NO | useful | `tests/misc/test_eds.py::test_xray_lines_near_energy` (exact line lists) | SpectroEDXTests/PeakGateTests `testP1LineLookupEqualsExSpy` (360 lookups equal) checks the table through that rule |
| `material.elements` X-ray lines (Chantler energies, EPQ weights) | `XRayLines.all` (947 rows, Z 1...92), `XRayLines.line(_:)` | present | BIT | study | exact table; no tolerance (`tests/misc/test_eds_utils.py`) | SpectroEDXTests/LineTableParityTests `testEveryLineOfTheTableEqualsExSpy`: all 947 rows (Z, line, energy, weight, order) `==` exSpy's own loader (`tools/edx-lines/pins.py`); also SpectroCoreTests/SpectroscopyCoreTests `testLineTableIsExspyVerbatim` and SpectroEDXTests/PeakGateTests `testP1LineEnergyAndWidthEqualExSpy` |
| `material.elements` general and physical properties (Z, atomic weight, density) | `QuantElementData` (package, Z 1...95) | partial | PART | useful | `tests/misc/test_material.py` (allclose defaults) | used inside the pins (`testCuSnWeightToAtomic`, `testCliffLorimerAlZnAndFePt`); not exposed |
| `material.elements` binding energies, EELS `threshold` and `edge` fields | none (EELS has three onsets, see below) | missing | NO | study | no numeric test; data table |  |
| `material.atomic_number_to_name` | none | missing | NO | useful | none |  |
| `utils.eds.get_FWHM_at_Energy` | `XRayLines.fwhm(resolutionMnKaEV:atEnergy:)` | present | TOL | useful | `test_eds.py` (allclose defaults) | `testFWHMLawMatchesExspy` (about 20 values, 1e-15 absolute), `testP1LineEnergyAndWidthEqualExSpy` (1e-14 relative) |

### Windows and line intensities

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `get_lines_intensity` (net counts of integration windows less background windows) | `ElementWindows.build(picks:...)`, `ElementWindows.netCounts`, `.maps`, `.integratedMaps` (public); sigma added | present | BIT | study | `test_eds_tem.py::test_intensity` atol 1e-1; uint input rtol 0.03; `test_eds_sem.py::test_background_substraction` atol 1e-3 | FePt and TM002 net counts equal (`testFePtPins`, `testTM002Pins`, `==` on integer sums); WindowGateTests `testLineIntensitiesEqualExSpyOnEveryPlantedSpectrum` (26 280 values, 4e-16 relative). Two checked lines of one element closer than a window are clipped (`clipOverlaps`), which exSpy does not do |
| `estimate_integration_windows` | `WindowIntensity.integrationWindows` (package), used by `ElementWindows.build` at width 2.0 | present | BIT | study | `test_eds_sem.py::test_estimate_integration_windows` atol 1e-2 | `testFePtPins`, `testTM002Pins` (windows `==`), WindowGateTests `testWindowsEqualExSpy` |
| `estimate_background_windows` (with the merge of overlapping windows) | `BackgroundWindows.estimate`, `.merge` (package), used at `line_width` [2,2], `windows_width` 1 | present | BIT | study | `test_eds_sem.py::test_background_substraction` atol 1e-3 | `testFePtPins`, `testTM002Pins` (merged windows at [2,2] and [5,2]), `testMgAlSiMergedBackgroundSitsOnSiliconsFlank`, `testWindowsEqualExSpy` |
| the window parameters of the three rows above (`integration_window_factor`, `line_width`, `windows_width`, `xray_lines`) | not settable from the public API | partial | PART | study | as the three rows above | the package functions take them and are tested at [5,2] and at 2.1 FWHM (`testTM002Pins`) |
| `EDSSpectrum.sum` | `SpectrumImage.sum(mask:)`, `windowSums` (dense and sparse); exact UInt64; live time is passed through, not summed | present | NOPIN | study | `test_eds_tem.py::test_sum_live_time*` allclose defaults | CountsGateTests `testC1*`, `testC2*`, `testC3NoWrapAndNoLiveTimeProduct`: equal to a NumPy decode and planted draws; exSpy's `sum` was only probed (design note edx-stage-gates, archived in the suite's private folder, section 3, G-C) |
| `EDSSpectrum.rebin` | none | missing | NO | study | `test_eds_tem.py::test_rebin_live_time`, `test_offset_after_rebin` (allclose defaults) |  |
| `LazyEDS*Spectrum` | none (a sparse store exists instead) | not planned | NP | not planned: lazy dask signals; the kit's sparse store is the lazy form | none |  |
| `EDSSpectrum.plot`, `add_xray_lines_markers`, `remove_xray_lines_markers` | none (headless) | not planned | NP | not planned: plotting; the kit is headless | none |  |

### Geometry and microscope

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `get_take_off_angle`, `utils.eds.take_off_angle` | `EDXQuantification.takeOffAngle` (public, 0.8.0), `TakeOff.angle` (package) | present | DEV | study | `test_eds.py::test_takeoff_angle` and `test_eds_sem.py::test_take_off_angle*` allclose defaults | `testTakeOffPins` (6 cases, 1e-9 relative); a missing tilt, azimuth or elevation is refused where exSpy fills 0, 0, 35 deg |
| `set_microscope_parameters` (beam energy, tilt, live time, azimuth, elevation, Mn Ka resolution, beam current) | `SpectrumImageMetadata` read from the file, `BeamEnergy.resolve`; no mutable metadata tree | partial | PART | study | `test_eds_tem.py::test_metadata` (approx_equal, exact values) | `testTheDM4EnergyAxisAndMetadataAreTheFiles`, `testTheVeloxOpenerCarriesTheFilesAxisAndMetadata` |
| `get_calibration_from` (TEM and SEM) | none | missing | NO | study | `test_eds_tem.py::test_get_calibration_from` (exact metadata) |  |
| `EDSTEMSpectrum.get_probe_area` | `ZetaFactor.doseCrossSection` takes `probeAreaNm2`; `EDXQuantificationMethod.crossSection(…, probeAreaNm2:)` (public, 0.8.0) | partial | PART | useful | `test_eds_tem.py::test_get_probe_area*` atol 1e-3 | the probe area is a typed input; deriving it from the navigation pixel size (and the µm/nm conversion of `test_quant_cross_section_units`) is the caller's. `test_get_probe_area*` not compared |
| `EDSTEMSpectrum.vacuum_mask` | none; `quantifyMaps` takes the mask as input | missing | NO | study | `test_eds_tem.py::test_vacuum_mask*` (mask equality) |  |
| `EDSTEMSpectrum.decomposition` | none | missing | NO | useful | `test_eds_tem.py::test_decomposition` |  |

### Quantification

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `quantification(method="CL")` | `EDXQuantification.quantify`, `.quantifyMaps` with `.cliffLorimer(kFactors:thicknessNm:)` (public, 0.8.0); `CliffLorimer` (package); `PooledQuantifier.run` (pooled spectrum, unchanged) | present | TOL | study | `test_eds_tem.py::test_quant_lorimer*` atol 1e-3 on percent | EDXQuantificationTests `everyRunMatchesExspy`: 36 runs x 12 pixels (tight-convergence runs compared at 1e-5) of exSpy's own `quantification`, atol 1e-3 percent; EDSQuantPinsTests (at least 10 cases, 1e-9). Typed k-factors; a single line above the floor is a refusal unless `singleLine: .exspyHundredPercent` |
| `quantification(method="zeta")` | `EDXQuantification.quantify`, `.quantifyMaps` with `.zeta(zetaFactors:)` (public, 0.8.0); `ZetaFactor` (package) | present | TOL | study | `test_quant_zeta` atol 1e-3 | `everyRunMatchesExspy` (percent atol 1e-3, mass thickness rtol 1e-7, with absorption rtol 1e-5); `testZetaWithoutAbsorption` (1e-9). Dose = live time x beam current / e, per pixel when `liveTimesSeconds` is given |
| `quantification(method="cross_section")` | `EDXQuantification.quantify`, `.quantifyMaps` with `.crossSection(sectionsBarn:probeAreaNm2:)` (public, 0.8.0) | present | TOL | study | `test_quant_cross_section*` atol 1e-3 | `everyRunMatchesExspy` (atomic percent atol 1e-3, atoms rtol 1e-7, with absorption 1e-5: exSpy's atoms lag its last composition update by 4e-6); `testZetaAndCrossSectionPins` (hand-recorded, 1e-9). The fixture-driven set is the gap the old audit listed, now closed |
| `absorption_correction=True`, `get_abs_corr_zeta`, `get_abs_corr_cross_section` (iteration to convergence) | `EDXAbsorptionSetting` on any `EDXQuantificationSetup` (public, 0.8.0); `AbsorptionCorrection` (package); the four-detector geometry stays package | present | DEV | study | `test_quant_lorimer_ac`, `test_quant_zeta`, `test_quant_cross_section_ac` atol 1e-3 (1e-5 between equal routes) | `everyRunMatchesExspy` absorption runs (percent atol 1e-3 as exSpy; the per-pixel iteration agrees with exSpy's image-wide one to better than 1e-9 on the pinned cases); EDSQuantPinsTests iteration-for-iteration on `.exspySigned`. Registered deviation: absolute convergence criterion by default |
| `CL_get_mass_thickness` | `EDXQuantificationPixel.massThickness` and `EDXQuantificationMaps.massThickness` (public, 0.8.0): CL with `thicknessNm`, zeta, cross section | present | TOL | study | `test_CL_get_mass_thickness` allclose default rtol 1e-7 | `clMassThicknessEqualsExspyCLGetMassThickness`, `everyRunMatchesExspy` (CL absorption, zeta, and cross-section mass thickness; exSpy returns none for cross section, so the pin is its own `get_abs_corr_cross_section` total-mass formula on its atoms, `tools/edx-quant-maps`); `testMassThicknessCL` (1e-9) |
| `cross_section_to_zeta`, `zeta_to_cross_section` | `EDXQuantification.zetaFactors(fromCrossSectionsBarn:elements:)`, `.crossSectionsBarn(fromZetaFactors:elements:)` (public, 0.8.0) | present | TOL | study | `test_edx_cross_section_to_zeta`, `test_zeta_to_edx_cross_section` atol 1e-3 | `conversionsAndRefusals` (round trip 1e-9); `testZetaAndCrossSectionPins` (1e-9) |
| `quantification` over a spectrum image (per-pixel maps, `navigation_mask`, `closing`, `plot_result`) | `EDXQuantification.quantifyMaps(intensityMaps:rows:columns:setup:navigationMask:liveTimesSeconds:)` returning `EDXQuantificationMaps` (public, 0.8.0), parallel over pixels | present | DEV | study | `test_quant_lorimer_mask` atol 1e-3 (mask → 0); every method over an image with `test_quant_*` atol 1e-3 | `everyRunMatchesExspy` (mask → 0; exSpy masks CL only, this port every method; exSpy builds a vacuum mask by default, this port takes it as input), `aLargeImageEqualsPixelByPixelAcrossTheChunks`, `liveTimeNormalisedDoseScalesMassThicknessAndNotTheComposition`. Not ported: `vacuum_mask` threshold and `closing` (the caller passes the mask), `plot_result`. Failed pixels are NaN with a reason, not a number |
| `material.weight_to_atomic`, `atomic_to_weight` | `EDXQuantification.weightToAtomic`, `.atomicToWeight` (public, 0.8.0); `CompositionConversion` (package) | present | TOL | study | `tests/misc/test_material.py::test_weight_to_atomic`, `test_atomic_to_weight`, `test_multi_dim` allclose defaults, atol 1e-3 | `conversionsAndRefusals`; `testCuSnWeightToAtomic` (1e-9) and inside every quantification pin |
| `material.mass_absorption_coefficient`, `mass_absorption_mixture` | `MassAbsorptionTable.mac`, `.mixture` (package; not exposed) | present | DEV | useful | `test_material.py::test_mac`, `test_mixture_mac` allclose defaults; `assert_array_almost_equal` 6 decimals | `testMassAbsorptionPins` (about 10 values, 1e-9); the table's trailing (0, 0) sentinel is stripped and an energy outside the table is refused (`testSentinelIsStrippedAndOutsideTableRefuses`) where exSpy runs off the array |
| `material.density_of_mixture` | none | missing | NO | useful | `test_material.py::test_density_of_mixture` allclose defaults |  |
| `utils.eds.electron_range`, `xray_range` | none | missing | NO | useful | `test_eds_sem.py::test_electron_range`, `test_xray_range` allclose defaults |  |
| (none) k-factor table import | `KFactorImport.parse`, `typedK`, `apply`, `cliffLorimerFactors` (public, 0.10.0) | partial | PART | study | none for the table; the convention is `quantification_cliff_lorimer`, tests atol 1e-3 on percent | SpectroEDXTests/KFactorImportTests (layouts, refusals by line); SpectroKitParityTests/KFactorImportPinsTests: the planted text in 4 layouts x 2 sets parses to exSpy's documented list `[1, 1.47, 1.72]` and to a second list, and drives the kit's Cliff-Lorimer to exSpy's own weight fractions (32 runs, difference 0.0; `tools/edx-0100/pins.py`). exSpy has no k table, so the parser itself is planted-text only |
| (none: neither HyperSpy nor eXSpy reports a sigma on a composition) sigma on wt% and at% | `EDXQuantification.quantifyWithSigma` (public, 0.10.0), `EDXQuantificationSigma` | present | NOPIN | study | none | SpectroEDXTests/QuantificationSigmaTests: Monte Carlo over seeded Poisson draws of a planted 3-element case, propagated against standard deviation within 5 % (measured worst: CL 1.0 %, CL with typed-k sigma 0.6 %, CL with absorption 1.7 %, zeta 1.2 %, cross section 1.5 %); two-element CL against the hand-derived sigma to 1e-6. First order; thickness, dose and detector exact |
| (none) per-region quant result and report row | `RegionQuantResult.make`, `.csvHeader`, `.csvRow`, `.reportRow`, `.csvLongRows` (public, 0.10.0) | present | NOPIN | useful | none | SpectroEDXTests/RegionQuantResultTests: every number equals the pooled row; k, hash, absorption note, unlisted-line outcome, validation carried; Codable round trip; CSV rows line up with the headers |

### Model

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `create_model` (TEM, SEM), `EDSModel`, `EDSTEMModel`, `EDSSEMModel` objects | `EDSLineModel.build`, `FitSettings`, `EDSFitResult` (public); `EDSFit.run` is package, reached through `PooledQuantifier.run` and `ElementProposer.propose` | partial | PART | study | `tests/models/test_edsmodel.py::test_model_creation` and `_store` (structure only) | no model object, no component handling |
| `EDSModel.add_family_lines` (tied line energies, widths, weights) | `EDSLineModel.build`; Si-escape columns are an option (on by default, off is the parity setting) | present | TOL | study | `test_edsmodel.py::test_lines_intensity` atol 1e-7 | SpectroscopyFitTests `testDesignColumnsMatchHyperspy` (columns 1e-9 of the peak; centres, FWHM, weights 1e-12) |
| `EDSModel.add_polynomial_background(order=6)` | `FitBackground.polynomial(order:)` (the parity path; the default is SpectroKit's own continuum) | present | TOL | study | `test_edsmodel.py::test_fit` atol 1e-4 on intensities; `test_comparison_quantification` rtol 5e-2 | `testPoly6PathEqualsHyperspyModel` (model equals `as_signal()` to 1e-7 counts) |
| `EDSModel.fit` (`lm`) | `EDSFit.run` (package): a non-negative linear least-squares solve, not an iterative `lm`; Poisson maximum likelihood is an option | present | TOL | study | `test_edsmodel.py::test_fit`, `test_quantification` allclose defaults on [50, 20, 30] | `testClosedLoopRecoversWeightFractions` (1e-4 of truth, 1e-6 of exSpy's fit), `testFePtLeastSquaresPins` (2e-4 of the pin: HyperSpy's `lm` stops short of the minimum; 1e-6 of the exact minimiser) |
| `EDSModel.fit_background` | none (the background is fitted with the lines) | missing | NO | useful | no numeric test upstream (`fit_background` is exercised through `test_fit`) |  |
| `EDSModel.calibrate_energy_axis` (offset, scale or resolution, one at a time) | `EnergyAxisRefinement.refine` (package; `AxisRefinementResult` public): all three jointly, a different method | present | DEV | study | `test_edsmodel.py::test_calibrate_energy_scale` atol 1e-5, `_offset` atol 1e-5, `_resolution` atol 1 | SpectroKit's own method, not a port: `testAxisRefinementRecoversPlantedOffsetAndGain`; SpectroEDXTests/AxisGateTests `testE3RefinementRecoversPlantedOffsetAndGain` (registered finding: 349 of 384 fits outside 1 eV offset, `withKnownIssue`), `testE3ExSpyCalibrationPinsAreTheRecordedSecondEstimate` (exSpy as second estimate) |
| `EDSModel.calibrate_xray_lines` | none | missing | NO | study | `test_edsmodel.py::test_calibrate_xray_energy` atol 1e-6, `_weight` atol 1e-3, `_width` atol 1e-2 |  |
| `EDSModel.free_`/`fix_` `sub_xray_lines_weight`, `xray_lines_energy`, `xray_lines_width`, `free_background`, `fix_background` | none: line energies, widths and weights are fixed by the table and the width law | missing | NO | useful | `test_edsmodel.py::test_calibrate_xray_*`, `test_enable_adjust_position` (state flags and the values above) |  |
| `EDSModel.get_lines_intensity` (fitted areas) | `EDSFitResult.values`, `.sigma(at:)`; `PooledQuantification.Row.net`, `.sigma` | partial | PART | study | `test_edsmodel.py::test_lines_intensity` atol 1e-7 | the fit pins above; per-line sigma is not compared with exSpy |
| `EDSModel.enable_xray_lines`, `disable_xray_lines`, `remove`, `as_dictionary`, `plot` | none | not planned | NP | not planned: model-object bookkeeping and plotting; the kit takes the choice as input | `test_edsmodel.py::test_disable_xray_lines`, `test_edsmodel_store` |  |
| `utils.eds.xray_lines_model` (simulated spectrum from lines) | none; `EDSLineModel` builds the same Gaussian columns for fitting | missing | NO | useful | no numeric test upstream (`test_eds_tem.py::test_with_signals_examples`) |  |
| (none: eXSpy's `EDSModel` has `add_family_lines` and no sum or escape model) sum and Si-escape peaks | `EDSSumEscapeFit.run`, `SumEscapeModel`, `SumEscapeResult`; `PooledQuantificationInput.sumEscape` (public, 0.10.0) | present | NOPIN | study | none: no reference exists | SpectroEDXTests/SumEscapeFitTests: noise-free planted c = 1e-8 and f = 0.01 recovered to 0.04 % and 0.04 %, the Ag area biased by the Al+Al sum (2750 against 2000 planted) back to 2000.9; 20 seeded Poisson draws all improve the Ag net, mean c 1.013e-8 (planted 1e-8), sigma_c within 25 % of the spread (measured 4.9e-10 against 5.2e-10); off is bit-for-bit the default fit. `validation: "none"` |
| `exspy.data.EDS_TEM_FePt_nanoparticles`, `EDS_SEM_TM002` | used as test fixtures only | not planned | NP | not planned: bundled example datasets, used as test fixtures | none |  |

## EELS

### Edges, elements, microscope

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `EELSSpectrum.add_elements`, `generate_subshells`, `edges_at_energy`, `print_edges_near_energy`; `utils.eels.get_edges_near_energy`, `get_info_from_edges` | none | missing | NO | study | `tests/signals/test_eels.py::TestEdges*` (exact printed lists) |  |
| the edges database (`eels_binding_energies.json`: onsets, major and minor edges) | `CoreLossEdge.bundled`: 20 edges (C, N, O K at 284, 401, 532 eV; K of Mg, Al, Si; L1, L2, L3 of Mg, Al, Si, Fe, Cu) | partial | PART | study | `tests/misc/test_gos.py::test_binding_energy_database` (exact) | EdgeTablePinsTests `testNewEdgesEqualExSpy` (onsets, occupancy ratios) |
| `EELSSpectrum.set_microscope_parameters` (E0, alpha, beta, ...) | `EELSMicroscope` (E0, convergence, collection) | partial | PART | study | no numeric test; `tests/signals/test_eels.py` metadata checks | `EdgeEdgeCaseTests` `testRefusals`; no metadata tree |

### Zero-loss peak, elastic intensity, thickness

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `estimate_zero_loss_peak_centre` (with `mask`, `signal_range`) | `EELSAlignment.zeroLossPeakCentre` (and `ThicknessPixel.zlpCentre`, the unmasked diagnostic) | present | TOL | study | `test_eels.py::test_estimate_zero_loss_peak_centre` allclose defaults (kit: the first argmax's grid value, 1e-12 eV) | SpectroKitParityTests/AlignPinsTests `testZeroLossPeakCentrePins` (plain, masked, spike); SpectroEELSTests/EELSAlignmentTests (first maximum, mask, `signal_range`) |
| `align_zero_loss_peak` (calibrate, subpixel, crop, mask, signal_range, also_align) | `EELSAlignment.alignZeroLossPeak` | present | TOL | study | `test_eels.py::TestAlignZLP` mean/std of the re-estimated centre allclose defaults (with mask atol eps), `calibrate=False` std atol 1e-2, `crop=False` keeps size; kit: offset and scale 1e-12, shifts 1e-9 eV, data rtol 1e-7 + atol 1e-9 x max | AlignPinsTests `testAlignZeroLossPeakPins` (11 variants incl. `also_align`, mask, spike with and without `signal_range`, ip 3, no-crop, no-subpixel); planted shifts recovered to a quarter channel (EELSAlignmentTests `testPlantedShiftsAreRecovered`) |
| `get_zero_loss_peak_mask` | `EELSAlignment.zeroLossPeakMask` | present | BIT | study | `test_eels.py::test_get_zero_loss_peak_mask*` exact | AlignPinsTests `testZeroLossPeakMaskPinsAreExact` (widths 5 and 2, with and without `signal_mask`); hand-derived width in EELSAlignmentTests |
| `Signal1D.estimate_shift1D` (`max_shift` is a no-op upstream and not offered) | `EELSAlignment.estimateShift` | present | TOL | study | `test_1D_tools.py::TestAlignTools::test_estimate_shift` atol 1e-3 eV (kit: 1e-9) | AlignPinsTests `testEstimateShiftPins` (windows -3..3 and -4..4, ip 0, 5, 9) |
| `Signal1D.shift1D` (linear; crop; `fill_value`/`expand` not offered) | `EELSAlignment.shift` | present | TOL | study | `test_1D_tools.py::TestAlignTools::test_shift1D` defaults; new offset exact. NOTE exSpy's linear interpolant EXTRAPOLATES beyond the ends (the design note's "NaN" is not what it does; the pins say so) | AlignPinsTests `testShift1DPins` (crop and no-crop, fractional shifts); EELSAlignmentTests (a ramp is exact, crop indices, floor/ceil `value2index`) |
| `estimate_elastic_scattering_threshold` | `ThresholdRule.estimated` over `ElasticThreshold.estimate` (package) | present | DEV | study | `test_eels.py::test_min_in_window_*` atol 1e-2 | The SG solve stays on LAPACK's SVD as in SciPy; automatic SG ties use `64 eps * peak cropped input * coefficient L1`, first channel wins. `portable-thresholds.json` pins 18 routes / 138 pixel answers; 20 differ deliberately from raw exSpy. ThicknessPinsTests / RefuterRegressionTests hold channels exactly and I0/It to 1e-12 relative, t/lambda to 1e-12 absolute. Explicit tolerance and gradient retain exact comparisons. Even/short windows and unsupported orders are refused. |
| `estimate_elastic_scattering_intensity` (threshold as float, signal or estimated; zero-loss sum) | `ThresholdRule` (`.fixed`, `.estimated`, `.perPixel`) giving `ThicknessPixel.i0`; summed in NumPy's order | present | TOL | study | `test_eels.py::test_estimate_elastic_scattering_intensity` 6 decimals | `testFixedThresholdPins`, `testEstimatedThresholdPins` (I_0 1e-12 relative; automatic SG uses the policy deviation above). Binned axes only (the Simpson path for unbinned axes is not ported); a Python `int` threshold (a channel index) cannot be expressed; `.perPixel` out of the axis gives a nil pixel where exSpy raises (design note eels-slice-1, archived in the suite's private folder, sections 1 and 3) |
| `estimate_thickness` (log ratio, `threshold` or `zlp`) | `EELSThickness.logRatio` -> `ThicknessMap` | present | TOL | study | `test_eels.py::test_relative_thickness` atol 4e-3 | `testEstimatedThresholdPins`, `testFixedThresholdPins`, `testZeroLossSpectrumRoutePins` (t/lambda 1e-12 absolute, 3 images; automatic SG uses the policy oracle above); truth: PlantedTruthTests, LineScanTruthTests. Registration: design note eels-slice-1, archived in the suite's private folder |
| `estimate_thickness` with `density` and `lambda` (absolute nm) | `MeanFreePathSource` (`.given`, `.iakoubovskii`, `.givenWithAngularCorrection`) | present | TOL | study | `test_eels.py::test_thickness_mfp`, `_density`, `_density_and_mfp`, `test_threshold*` rtol 3e-3 | `testAbsoluteThicknessPins` (3 routes x 3 lambda sources, 1e-12 times lambda x correction) |
| `utils.eels.iMFP_Iakoubovskii` | `InelasticMeanFreePath.iakoubovskii` | present | TOL | useful | `tests/misc/test_eels.py` (no numeric test of iMFP); the kit pins it itself | `testMeanFreePathAndAngularCorrectionPins` (20 values, 1e-13 relative) |
| `utils.eels.iMFP_angular_correction` | `InelasticMeanFreePath.angularCorrection` | present | TOL | useful | as above | same test (180 values, 1e-13) |
| `utils.eels.iMFP_TPP2M` | none | missing | NO | useful | no numeric test upstream |  |
| `utils.eels.effective_angle` | `EdgeCrossSection.effectiveAngleMrad` (package) | present | TOL | study | no numeric test upstream; `test_gos.py` | EdgePinsTests `testCrossSectionEqualsExSpyOnTheGrid` (1e-14) |

### Deconvolution, extrapolation, dielectric function

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `fourier_log_deconvolution` (add_zlp, crop) | `EELSDeconvolution.fourierLog` | present | TOL | study | none upstream (`test_running` only runs); kit decision: per pixel rtol 1e-7 + atol 1e-7 x max\|pinned\| (`assert_allclose` defaults cannot hold near zero across two FFT libraries); fftSize, tapered channels, channel count exact | DeconvolutionPinsTests `testFourierLogEqualsExSpy` (4 variants, worst 6e-7 of the allowance); EELSDeconvolutionTests `testFourierLogReturnsPlantedSingleScattering` (planted plural scattering returns Z x S / I0 within 0.1 %). Quirk kept: `irfft` returns 2 (m - 1) channels |
| `fourier_ratio_deconvolution` (fwhm, threshold, both extrapolations) | `EELSDeconvolution.fourierRatio` | present | TOL | study | none upstream; kit tolerance as Fourier-log; fftSize, FWHM (1e-9 eV), tapered channels exact | DeconvolutionPinsTests `testFourierRatioEqualsExSpy` (6 variants, worst 0.11 of the allowance); EELSDeconvolutionTests `testFourierRatioReturnsPlantedEdge` (planted edge within 5 %). Quirks kept: the FFT size comes from the ORIGINAL core-loss length while the FFT input is the extrapolated one; an odd complex size gives an `irfft` one channel short. A pixel with no threshold gets zeros and `noThreshold` |
| `optimal_fft_size` (scipy `next_fast_len`, real and complex) | `EELSDeconvolution.optimalFFTSize` | present | EXACT | study | `tests/misc/test_math_tools.py` | DeconvolutionPinsTests `testOptimalFFTSizeEqualsScipy` (217 sizes, both rules) |
| `estimate_peak_width` (factor, FWHM roots of the interpolating cubic spline) | `EELSDeconvolution.peakWidth` | present | TOL | study | `tests/signals/test_signal1d.py` (width allclose) | DeconvolutionPinsTests `testPeakWidthEqualsExSpy` (12 pixels, 1e-9 eV; noise gives nil as exSpy's NaN); EELSDeconvolutionTests `testPeakWidthOfPlantedPeak`. `window` argument not offered |
| `richardson_lucy_deconvolution` (psf, iterations) | `EELSDeconvolution.richardsonLucy` | present | TOL | study | none upstream (`exspy/tests` only checks that it is refused on a non-uniform axis); `assert_allclose` defaults for float64: rtol 1e-7, atol 0, per channel | RichardsonLucyPinsTests `testRichardsonLucyEqualsExSpy` (10 cases: shared and per-pixel PSF, noise-free and Poisson, 0 / 5 / 15 / 40 iterations, flat-topped PSF (first argmax), PSF centre at channel 3, zeros giving NaN; worst 7.7e-8 of the allowance); RichardsonLucyTests (blurred peaks recovered, one iteration by hand, delta PSF and 0 iterations are the identity, refusals). Direct convolutions as numpy (no FFT, no wrap). Needs the PSF to have the spectrum's channel count (exSpy: broadcast error otherwise). A pixel exSpy returns NaN for is zeros with a reason |
| `power_law_extrapolation` (window, size, `fix_neg_r`; BINNED axis only, `add_noise` not offered) | `EELSSpectrumOps.powerLawExtrapolation` | present | TOL | study | `test_eels.py::TestPowerLawExtrapolation` atol 1e-2 against the exact power law; `test_power_law.py` A, r defaults. Kit: A, r rtol 1e-7, the continuation rtol 1e-9 against exSpy. exSpy's two-area estimate is 0.25 % from the exact law on the pinned set (the kit reproduces it); its UNBINNED branch (Simpson, no channel width) is a factor two from the exact law and is not ported | SpectroKitParityTests/SpectrumOpsPinsTests `testPowerLawExtrapolationPins` (4 binned cases incl. `fix_neg_r`); EELSSpectrumOpsTests (a power law continued by itself, `fixNegativeR`, a non-positive window sum is a nil fit) |
| `Signal1D.hanning_taper` (side, channels, offset) | `EELSSpectrumOps.hanningTaper`, `defaultTaperChannels` | present | BIT | useful | no numeric test upstream; exact by construction (`np.hanning`'s own formula) | SpectrumOpsPinsTests `testHanningTaperPins` (6 cases, data 1e-15 relative; default width rule for n = 50 ... 5000); EELSSpectrumOpsTests (window values, slices, offset, Python round) |
| `kramers_kronig_analysis`; `DielectricFunction.get_number_of_effective_electrons`, `get_electron_energy_loss_spectrum`; `utils.eels.eels_constant_dielectric` | none | missing | NO | study | `test_kramers_kronig_transform.py` rtol 0.01 (dielectric function, thickness), rtol 1e-6 (Bethe sum rule) |  |
| `spikes_diagnosis`, `spikes_removal_tool`, `EELSSpectrum.plot`, `LazyEELSSpectrum` | none | not planned | NP | not planned: interactive or plotting; spikes_diagnosis is a histogram of derivatives (not on any path) | `test_eels.py::test_spikes_diagnosis` allclose defaults |  |
| `EELSSpectrum.rebin`, `vacuum_mask` | none | missing | NO | useful | `test_eels.py::test_rebin_*`, `test_vacuum_mask_*` (exact) |  |
| `estimate_single_scattering` | not in exSpy at the pin (`grep` finds nothing); Fourier-log is the pinned single-scattering route | missing | NO | useful | none |  |

### Model, edge component, GOS

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| `create_model`, `EELSModel.fit(kind="smart")` (power-law background + dft edges, twins, low-loss convolution of the edges, `start_energy`) | `EELSModelFit.fit`, `EELSModelResult.modelCurve(pixel:)` | present | DEV | study | none upstream for `fit`; kit decision: intensities within rtol 1e-3 of exSpy's converged values, model curve within 1e-4 of its maximum | ModelPinsTests `testSmartFitEqualsExSpy` (5 images, noise-free and Poisson-noisy, K and L, two masters, convolved: intensities 3e-5, curve 5e-6 of the maximum measured); EELSModelFitTests `testFitRecoversPlantedIntensities` (planted intensities 5e-4, noise-free 1e-9). DEVIATION: variable projection (NNLS for A and the intensities, grid + Brent for r in [0, 10]) instead of exSpy's LM, which stops 1e-4 short; only the last cascade stage is solved (the whole range, last channel left out, as exSpy). Twins by element and family (exSpy: by element). An edge onset outside the fit range is refused (exSpy turns one below the range into background). Not offered: fine structure, free onset energy, `append`/`remove`/`enable`/`disable`/`fix`/`free`, other background components |
| `EELSModel.two_area_background_estimation`, `fit_background`, `quantify` | `EELSModelFit.twoAreaBackground`, `.fitBackground`, `EELSModelResult.quantifyText(pixel:)` | present | TOL | study | `test_eelsmodel.py::test_two_area_powerlaw_estimation_*` allclose defaults; `test_quantify` text | ModelPinsTests `testTwoAreaBackgroundEqualsExSpy` (A, r 1e-7), `testFitBackgroundEqualsExSpy` (noise-free 1e-6; noisy: r 0.02, A 10 %: A and r trade off along a valley exSpy's LM leaves early), the quantify lines in `testSmartFitEqualsExSpy`. `resolve_fine_structure`, `remove_fine_structure_data` and the fine-structure switches: none, missing |
| `Model1D.fit(optimizer="lstsq")` on the EELS model with the power-law exponent fixed (the multiple linear least squares; `p_std` from `_calculate_covariance`; `set_signal_range`) | `EELSMLLS.fit`, `EELSMLLSResult.modelCurve(pixel:)`, `EELSQuantification.composition(_: EELSMLLSResult, ...)` | present | TOL | study | `exspy/tests/models/test_linear_model.py::test_convolved_and_std_error` (lstsq against LM, `assert_allclose` defaults on values and `p_std`); the same defaults here, rtol 1e-7 | MLLSPinsTests `testMLLSEqualsHyperSpyLstsq` (14 runs: Fe L twin, C N O K, Fe + Cu two masters, Fe L with the low-loss convolution; whole axis and an explicit window; exponent planted or from the two-area estimate; A, intensities, `p_std`, RSS, dof, window indices, curve: worst 1.1e-4 of the allowance; the noise-free planted-exponent run, whose residual is rounding noise, compared at the noise floor: RSS < 1e-20 of the data's sum of squares, standard error < 1e-9 of the amplitude); EELSMLLSTests (planted recovery, errors against the scatter of 300 Gaussian-noise realisations within 12 %, badly scaled columns, references, window, refusals, masks, composition). DEVIATIONS: columns scaled to unit length (numpy's `lstsq(rcond=None)` drops the power law for a low loss of area 1e6); a singular design is `.fitFailed` (HyperSpy: `LinAlgError`); the unconstrained fit can return a negative intensity (as `lstsq`). The standard errors assume constant variance (HyperSpy's too): on Poisson data they overstate the background's amplitude error (7x on the pinned Fe L spectrum). Reference shapes (`references`) have no HyperSpy counterpart pinned (planted truth only). Not offered: weights, `ols` / `nnls` / `ridge`, a free exponent (that is `EELSModelFit.fit`) |
| (kit) `EELSQuantification.composition`, `LowLossSpectrumImage.sum(mask:)`, `CoreLossSpectrumImage.sum(mask:)` | same | present | NP | study | not in exSpy (macTEM design 2.3): at% and wt% from the master intensities with the kit's atomic masses; the masked-in spectra added channel by channel | EELSModelFitTests `testCompositionFromFittedIntensities`, `testRegionSumAndItsFit` |
| `EELSCLEdge.function` (energy-differential cross section, dft GOS, K shell) | `EELSEdgeQuantification.differentialCrossSection` (public), `EdgeCrossSection` (package) | present | TOL | study | `tests/components/test_eels_cl_edge.py` rtol 5e-7 (model restore); GOS values exact tables | EdgePinsTests `testCrossSectionEqualsExSpyOnTheGrid` (192 cases x 3 scales x 4 widths: cross section 1e-10 bound, 7e-16 measured), `testSplineAndQLimitsEqualExSpy`; second oracle `testCrossSectionWithinThreePercentOfPyEELSMODEL` (72 cases). The 17 task-16 edges (K of Mg, Al, Si; L1, L2, L3 of Mg, Al, Si, Fe, Cu; Al as the combined L2,3): EdgeTablePinsTests `testBundledTablesAreBitExact` (table sha256, float32 bytes) and `testNewEdgesEqualExSpy` (2 settings each; angle 0, qint 5e-16, function 6e-16 measured against the 1e-14 / 1e-12 / 1e-10 bounds). Every other K, L and M edge exSpy builds with the dft GOS (0.12.0: 383 edges from 231 tables, the pack `dft-gos-tables.bin`): EdgePackPinsTests `testBundledTablesAreBitExact` (all 231 tables, sha256) and `testOneEdgePerShellEqualsExSpy` (B K; Ti L1, L2, L3; Zr M2, M3; Ba M4, M5; 2 settings each: angle 0, qint 3e-16, function 6e-16 measured). Registration: design note eels-slice-2, archived in the suite's private folder |
| `EELSCLEdge` with `GOS="Hartree-Slater"` | none | not planned | NP | not planned: Gatan's Hartree-Slater tables are never shipped | `tests/misc/test_gos.py::test_hartree_slater_gos` | Gatan's tables are never shipped (design note eels-slice-2, section 1, archived in the suite's private folder) |
| `EELSCLEdge` with `GOS="hydrogenic"` | none | missing | NO | useful | `test_eelsmodel.py::test_gos_hydrogenic`, `tests/misc/test_gos.py` (errors for M shells) |  |
| `EELSCLEdge` with the Dirac GOS (`Dirac_GOS_compact.gosh`) | none; its C K cross section is a pins-script diagnostic | missing | NO | useful | `test_eelsmodel.py::test_gos_gosh_dirac`, `test_eels_cl_edge.py` rtol 5e-7 | design note eels-slice-2, section 4.4, archived in the suite's private folder |
| `EELSCLEdge` fine structure (spline, Gaussians); `fine_structure_*` (the M edges and every element's K and L edges are present since 0.12.0, row above) | none | missing | NO | study | `test_eelsmodel.py::test_fine_structure_*` (structure), `test_jacobian_convolved` 6 decimals |  |
| `EELSArctan`, `DoublePowerLaw`, `Vignetting`, `VolumePlasmonDrude` | none | missing | NO | useful | `test_EELSarctan.py`, `test_double_power_law.py` allclose defaults, `test_volume_plasmon_drude.py` rtol 1e-6 |  |
| `SEE`, `PESCoreLineShape`, `PESVoigt` | none | not planned | NP | not planned: photoelectron and secondary-electron components, not EELS | `test_pes_*.py` |  |
| `exspy.data` EELS datasets, `eelsdb` | none | not planned | NP | not planned: network database and bundled datasets | `tests/data/test_eelsdb.py` |  |

## Shared numerics (HyperSpy, SciPy, NumPy) that the rows above stand on

| exSpy / HyperSpy | SpectroKit | state | code | priority | upstream tolerance (test file) | evidence |
|---|---|---|---|---|---|---|
| HyperSpy `value2index` (half-towards-zero rounding after a 1e-12 truncation) | `EnergyAxis.index(of:)` | present | BIT | study | HyperSpy `tests/axes/test_axes_manager.py` value2index (exact indices) | AxisGateTests `testE2ValueToIndexEqualsHyperSpyOnTheWholeGrid` (12 573 cases, 3 that raise), `testValue2IndexMatchesHyperspy` (544) |
| HyperSpy axis slices (`isig[a:b]`) | `EnergyAxis.channelRange` | present | BIT | study | HyperSpy axis-slice tests (exact) | `testE2SlicesEqualHyperSpyArraySlices` (52), `testSliceSemanticsMatchHyperspy` |
| HyperSpy `value_range_to_indices` | `EELSAxis.valueRangeToIndices` | present | NOPIN | study | HyperSpy `value_range_to_indices` tests (exact) | AxisRulesTests `testValueRangeToIndicesFollowsHyperSpysFourConditions`: hand-derived from the source, no HyperSpy run compared |
| `scipy.signal.savgol_filter(deriv=1, mode="interp")` as `smooth_savitzky_golay(differential_order=1)` | `SavitzkyGolay` (package) | present | TOL | study | SciPy `test_savitzky_golay.py` (allclose defaults) | LAPACK SVD coefficients and edge fits, as SciPy. Unchanged SciPy fixture: coefficients within 1e-13 times coefficient L1; derivatives within 1e-12 times input peak times coefficient L1 (cancellation-scaled absolute error). Supplied-coefficient interior/convolution tests remain bit exact. Edge values alone and in an image agree within the same bound (dgelsd's bits depend on the number of right-hand sides). Legacy test names containing “BitIdentical” are retained for continuity; their comments state the current bounds. |
| `numpy.gradient` | `NumpyGradient` | present | BIT | study | NumPy tests (exact) | SavitzkyGolayPortTests `testGradientIsBitExact` |
| NumPy pairwise sum | `NumpySum` | present | BIT | study | NumPy tests (exact) | AxisRulesTests `testPairwiseSumEqualsNumpysSum` (bit patterns, 11 lengths) |
| `scipy.interpolate.make_interp_spline(k=3)` | `InterpolatingSpline` | present | TOL | study | SciPy `test_bsplines.py` (allclose defaults) | `testSplineAndQLimitsEqualExSpy` (knots equal, coefficients 1e-10) |
| `scipy.integrate.simpson` | `ScipySimpson` | present | TOL | study | SciPy `test_quadrature.py` (allclose defaults) | `testCrossSectionEqualsExSpyOnTheGrid` (q integral 1e-12) |
| HyperSpy `PowerLaw.estimate_parameters` (two-area) and `remove_background(fast=True)` | `PowerLawWindow`, `PowerLawFit` | present | TOL | study | HyperSpy `tests/component/test_power_law.py` (allclose defaults) | `testRatioMethodEqualsExSpyOnThePlantedImages` (window indices and energies equal; I1, I2, r, A, background 1e-12). A pixel whose window sum is not positive is nil with a reason where HyperSpy gives `nan_to_num`; a window not inside the axis is refused where HyperSpy clamps (design note eels-slice-2, archived in the suite's private folder, amendments) |
| `scipy.optimize.nnls` | `LeastSquaresFit.solve(nonNegative:)` | present | TOL | study | SciPy `test_nnls.py` (allclose defaults) | `testNNLSMatchesScipyAndDiffersFromUnbounded` (1e-8) |
| HyperSpy `find_peaks1D_ohaver` | none (pins used as an independent check of the proposer) | missing | NO | useful | HyperSpy `tests/signals/test_find_peaks1D_ohaver.py` (exact peak positions) | PeakGateTests `testP3PeakFinderIsTheRegisteredIndependentEye` |
| Line shape with tail: no Python counterpart (exSpy fits Gaussians); the formula is PyMca's Hypermet short tail; validation: none until measured on a standard | `LineTail`, `FitSettings.lineTail`, `FitPolicy.lineTail`, `TailEstimate.measure` | present | NO | useful | none (no reference; planted truth only) | `LineTailTests` (a planted tail: the tail model reads Mg within 1 % and closer than the Gaussian; `measure` finds f and beta; a tiny slope stays finite) |

## Readers

Opening a file is not SpectroKit's job. The readers, and parity with RosettaSciIO, live in FormatoKit (`FormatoDM` for Gatan
`.dm3` / `.dm4`, `FormatoEMD` for Velox `.emd`); SpectroKit depends on it at an exact tag. `SpectrumImageOpener` in
`SpectroCore` calls them for a Velox EDS stream and a GMS `.dm4` EDS spectrum image. What SpectroKit still tests at that seam,
with RosettaSciIO's rules as the reference: counts (CountsGateTests, 8 public files and planted streams equal an independent
decode), the energy axis (AxisGateTests `testE1*`, exactly equal to RosettaSciIO's rule on 8 public files and the planted
headers), and the opener (SpectrumImageOpeningTests `testTheDM4EDSDecodeMatchesTheTruthPerRecipe`). RosettaSciIO's own Velox EDS
loader was never run as an oracle (its `sparse` dependency is not installed in the reference environment).

## In SpectroKit with no exSpy counterpart

Not parity items, listed so nobody looks for a pin: the element proposer (the identification loop of docs/design/auto-id-tem.md, written
from Newbury and Ritchie's published method with AutoEMX's documented defaults: `IdentificationThresholds`, every default as published;
departures stated there: the weighted fit inside the loop, the choice by the gain at the peak, the confirmation line as a residual peak
within one σ, the overlap check not yet; Currie detection limit on the fit's own null variance),
Currie and Garwood counting statistics and sigma propagation, pooled quantification with computed k-factors (Bote-Salvat
cross sections, Krause fluorescence yields, an EPQ detector efficiency), the four-detector absorption geometry, the empirical
continuum with an Al K-edge step, Poisson maximum-likelihood and reference shapes in the fit, the unlisted-line check, the
fit-range sensitivity check, and, in EELS, the ratio-method areal density (`EELSEdgeQuantification.ratioMethod`, Egerton's
ratio method on exSpy's GOS), which exSpy does not have as a function.

The proposer's confirmation-line rule (R4, `ProposerPolicy.familyConsistency`) and its sum-peak plausibility bound
(`sumPeakFraction`): no Python counterpart;
the bounds are physics (`familyOvervoltage` 2, `sumPeakFraction` 1, not measured cuts), `validation: "none"`; tests `FamilyConsistencyTests` and
`IdentificationLoopTests` on planted spectra, `RealFileAutoIDTests` (opt-in) on three measured files. The identification fit's Kβ weights are
NIST EPQ's (`EDSLineWeights.epqK`), not eXSpy's; the quantification fit keeps eXSpy's, so no parity row moves.

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
