# consumer-check

A separate SwiftPM package that depends on SpectroKit **by path** (`.package(path: "../..")`) and uses, from outside the
package, the public surface a consumer reads: the whole `SpectroEELS` product (the t/λ thickness map and the areal density by
the ratio method, with its GOS resource bundle) and, since 0.4.0, `SpectroCore`'s spectrum-image opening, which reads files
through FormatoKit. `package` access does not cross a package boundary, so the target compiles only while each of these symbols
is `public`. (The tests in `Tests/` are in-package and CAN use `package` symbols; this package is what enforces "public API
only".)

## What moved to FormatoKit (0.4.0)

The file readers (`DM4Experiment`, `DM4Error`, the DM4 EELS spectrum-image reader, `VeloxEMDReader` and its metadata types,
`HDF5Serial` and its quit barrier) are FormatoKit 0.0.2's now, a package dependency of SpectroKit pinned `exact: "0.0.2"`.
Their checks (the DM4 and Velox fields against truth files, the tag tree, the EELS reader against RosettaSciIO, the barrier's
bound) left this package with them: FormatoKit carries its own consumer check and tests. This package no longer names a
FormatoKit type and declares no FormatoKit product; FormatoKit is resolved through SpectroKit only.

## What it proves

- **SpectroCore through FormatoKit (new section, 41 checks).** Through SpectroCore's public API only, on the committed fixtures
  `Tests/SpectroCoreTests/Fixtures/velox-tiny.emd` and `demo-edx-tiny.dm4`, against what SpectroKit's own tests assert for
  them (`SpectrumImageOpeningTests.swift`; `spectro-golden/velox-tiny.txt`, `demo-edx-tiny-dm4.txt`; the truth file's
  `totals_written.eds_counts`):
  - `SpectrumImageOpener.kind(ofFileAt:)`: the Velox file is `.veloxSpectrumImage`, the DM4 is `.other` (it has a diffraction
    object), a path that is neither is `.other`.
  - Velox, `open(path:kind:)`: 3 rows x 2 columns x 8 channels, 11 counts, the summed spectrum and the spectrum of five pixels
    (through `sum(mask:)`), the energy axis (offset -0.25 keV, 0.01 keV per channel, 8 channels), the metadata (scan size,
    `.veloxEMD`, 2 frames, 200 keV, 1 nm pixel, detectors `SuperXG21` and `SuperXG22`, solid angle) and the scan image
    `[11, 22, 33, 44, 55, 66]`.
  - GMS DM4, `openGMSEDS(path:)`: 6 x 4 x 512, 706 counts, the file's energy axis (offset -0.488955998 keV, 0.02004 keV per
    channel), `.gmsDM4`, 200 keV, 5 nm pixel, the `EDS` detector, a 24-pixel scan image; `open(path:kind: .gmsEDSOnly)` equals it;
    `open(kind: .other)` throws `SpectrumImageOpenError.notASpectrumImage`.
  - Cancellation: `catch is SpectroCancelled` catches `open(path:kind:cancelled:)` when the closure answers true at once and
    after three questions, for Velox and DM4. The error is FormatoKit's `FormatoCancelled`; `SpectroCancelled` is a typealias of
    it.
  - **No setup.** `run.sh` unsets `MAC4DSTEM_HDF5_PATH`; the Velox open in a Debug consumer finds the libhdf5 FormatoKit ships.
    Some checks are consistency between public paths (`open(kind: .gmsEDSOnly)` equals `openGMSEDS`); the counts, axes and
    pixel spectra carry the values.
- **SpectroEELS (5).** (a) A one-pixel image whose answer is arithmetic: a 1 eV fixed threshold on counts `1 2 4 8 4 2 1 1` from
  -2 eV gives I_0 = 7, I_t = 23, t/λ = ln(23/7), σ = sqrt(1/7 - 1/23). (b) exSpy's line scan (`Tests/SpectroEELSTests/Fixtures`,
  17 spectra x 1024 channels) against `pins.json`, exSpy 7185a4d1's answers (not truth; its tolerances are the pins'): the
  fixed 2.5 eV rule (t/λ, I_0, I_t, the threshold channel), the three absolute-thickness routes (λ given; density; both), the
  zero-loss-spectrum route and the estimated rule (tolerance, channels, t/λ), and Iakoubovskii's λ and the angular correction.
  (c) Every `ThicknessUnavailable` and `SigmaUnavailable` reason produced by an image that causes it, and every
  `EELSThicknessError` case produced by an input that causes it (with its payload where it has one).
  Symbols: `EELSThickness.logRatio`, `.methodName`; `LowLossSpectrumImage` (both initialisers, six fields, `pixelCount`,
  `energy(ofChannel:)`); `ThresholdRule`; `MeanFreePathSource`; `InelasticMeanFreePath.iakoubovskii`, `.angularCorrection`;
  `ThicknessMap` (eleven members and the subscript); `ThicknessPixel` (ten fields); `ZeroLossSource`; `ThicknessUnavailable`;
  `SigmaUnavailable`; `EELSThicknessError`. Section: `SpectroEELSChecks`.
- **SpectroEELS areal density (6).** (a) The cross section: `differentialCrossSection` equals exSpy 7185a4d1's `EELSCLEdge.function` on
  `edge-pins.json`'s grid (C, N, O K; every fourth case, all three scales for those, relative 1e-10; the effective angle 1e-14), and
  `ratioMethod`'s `crossSectionBarn` / `edgeChannels` equal the grid's sigma_k and window for N and O as well as C (a flat image on the
  grid's axis). (b) The planted images (`edge-planted` set and set R: 16 images, noiseless and noisy, three background windows, four
  widths, 15 pixels) against the pins, exSpy/HyperSpy's answers and not truth: `atomsPerNM2` 1e-10 relative, `edgeCounts`,
  `backgroundCounts`, `powerLawR`, `powerLawA` 1e-12, `sigmaCounting` 1e-9, `lowLossIntensity` exactly; and the I_0 route
  (`.zeroLoss(ThicknessMap)`, three fixed thresholds). (c) Set R's single-scattering image in detail: the map's own statements
  (edge, windows, channels, dose, method, `validation` "none", caveats for N K and O K), the dose ratio, `edgeOnsetEV`, a custom
  window and width, a different microscope, a Float-count image, cancellation. (d) Every `EdgeUnavailable` reason produced by an input
  that causes it (an empty window half, a zero and a negative low loss, window sums of 9e301 and 9e-299 whose r and A overflow, a
  thickness map with no I_0) and every `EELSEdgeError` case that can be reached publicly, with its payload.
  Symbols: `EELSEdgeQuantification.ratioMethod` (every parameter; both `LowLossIntensity` routes), `.differentialCrossSection`,
  `.methodName`, `.defaultBackgroundWindow`; `CoreLossSpectrumImage` (both initialisers, six fields, `pixelCount`);
  `EELSMicroscope` (init, three fields); `LowLossIntensity`; `CoreLossEdge` (`.element .subshell .onsetEV`,
  `.carbonK .nitrogenK .oxygenK`, `.bundled`, `description`, `Equatable`); `ArealDensityMap` (fifteen fields);
  `ArealDensityPixel` (eight fields); `EdgeUnavailable` (four cases); `EELSEdgeError`. Section: `EdgeQuantificationChecks`.
- **SpectroEDX policies and SpectroCore kernels (0.5.0, 37 checks).** The 0.5.0 policy parameters used
  from outside the package, each with its default (no change against the call that names none) and one non-default value that
  moves the result as predicted: `WindowRules` through `ElementWindows.build(rules:)` and `defaultFamily(of:rules:)` (9, section
  `windowRulesChecks`); `QuantificationPolicy` (`FitPolicy`, `AbundancePolicy`, `DetectorLayers`, `SingleLineRule`, `IRLSSettings`,
  `AxisRefinementSettings`) through `PooledQuantificationInput.policy` and `PooledQuantifier.run`, and
  `FitRangeSensitivityCheck.run(alternativeToKeV:)` (13, `quantificationPolicyChecks`); `ProposerPolicy` (with `Currie.init`,
  `FlankMisfitGeometry`, `ElementContext`), `ElementProposer(policy:)`, the public `ProposalRules` fields and `UnlistedLineRules`
  with `UnlistedLineChecker.neighbour` (10, `proposerPolicyChecks`); `SmoothingKernel` with `MapSmoothing.apply(kernel:)` and
  `defaultBackgroundWindow(onsetEV:belowOnsetEV:gapEV:)` (5, `kernelAndWindowChecks`). The consumer now depends on the
  `SpectroEDX` product too.
- **Public.** The target compiles only while each symbol above is `public`: a symbol made `package` stops the build.
- **Debug, no unsafe flags, no setup.** `run.sh` builds in Debug, as a consumer's Debug build does, with zero warnings except the
  Swift Build's prints for FormatoKit's signed xcframeworks (`not stripping binary because it is signed`: `FormatoLibHDF5`,
  `FormatoLibSZ`, `FormatoLibAEC`, only those three names, possibly repeated or absent on a warm build; colour codes stripped, the log split on `warning:` because the lines can
  arrive glued together). It fails if a test-only target (`ExitProbe`, `SpectroKitTests`, `SpectroCoreTests`,
  `SpectroGoldenTests`, `SpectroEDXTests`, `SpectroEELSTests`, any FormatoKit `Formato*Tests`) was built; `.build/checkouts`,
  which holds FormatoKit's sources, is not searched.
- **The barrier does not fire when nothing is stuck.** The process ends through `exit` with FormatoKit's quit barrier installed
  (the Velox open installs it); `run.sh` requires exit status 0 and no "quit barrier passed its bound" line. That the bound
  works is FormatoKit's test.
- **The resource bundles.** The GOS tables are SpectroEELS's `Bundle.module` resources: `run.sh` fails unless
  `SpectroKit_SpectroEELS.bundle` sits next to the consumer binary with `dft-C-K1.json`, `dft-N-K1.json` and `dft-O-K1.json`
  inside. libhdf5 is FormatoKit's: `run.sh` fails unless the binary loads `@rpath/FormatoLibHDF5.framework` (`otool -L`) and the
  `FormatoLibHDF5`, `FormatoLibSZ` and `FormatoLibAEC` frameworks sit next to it.

## What it cannot prove

- `EELSEdgeError.noBundledCrossSection`: no public way reaches it. `CoreLossEdge`'s initialiser is internal, so a consumer holds only
  C K, N K and O K, all bundled.
- `.crossSectionFailed`: reached by a microscope outside the cross section's domain (E0 of about 2 keV and below, a convergence
  semi-angle of 1e6 mrad). Found here as a trap inside the library (`Index out of range`); fixed in SpectroEELS (a NaN q limit
  is refused) and tested there (`EdgeEdgeCaseTests.testCrossSectionOutsideItsDomainThrows`), not repeated here.
- `LoadedSpectrumImage.sum(mask:)` and `windowSums(_:)` are used but a `package` revert would not show: each has a second public overload (with
  `cancelled:` and `progress:`), so reverting one makes the call resolve to the other and the build still succeeds.
- That the readers are right: that is FormatoKit's. The values here show that SpectroCore reaches them through the shipped
  libhdf5 and the DM4 reader and gets the numbers its own tests assert.
- That a consumer's Release build or a machine with a different libhdf5 behaves the same; version resolution (a path dependency
  has no version; that a tag resolves, from a clone, in a Debug build with no unsafe-flags refusal is shown by a throwaway
  package outside the repository, not by this one).

## Run

```
tools/consumer-check/run.sh              # build (Debug), run the checks
```

Prints one `PASS`/`FAIL` line per check, then `consumer-check: all passed — N checks ...` and exits 0 only if everything
held. The binary reads the fixtures from the repository's `Tests/SpectroCoreTests/Fixtures` and `Tests/SpectroEELSTests/Fixtures`
(pass another `Tests` directory as its first argument). No libhdf5 is searched for or supplied: FormatoKit ships it, and
`MAC4DSTEM_HDF5_PATH` is unset before the run so that nothing can hide a missing one. The first build resolves FormatoKit
0.0.2 through SpectroKit (network or the SwiftPM cache).
