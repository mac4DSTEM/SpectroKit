# consumer-check

A separate SwiftPM package that depends on SpectroKit **by path** (`.package(path: "../..")`) and uses, from outside the
package, every symbol macTEM reads across the package boundary for SpectroKit 0.2.0, and the public surface added since:
the DM4 EELS spectrum-image reader (`SpectroCore`) and the whole `SpectroEELS` product (the t/λ thickness map and the areal density by the ratio method, with its GOS resource bundle).
`package` access does not cross a package boundary, so the target compiles only while each of these symbols is `public`.
(The tests in `Tests/` are in-package and CAN use `package` symbols; this package is what enforces "public API only".)

| macTEM's ask | symbols | where checked |
|---|---|---|
| 1. the DM4 API public (macTEM ADR 019) | `DM4Experiment.readImage(path:index:)`, `readImage(data:index:)`, `tagTree(data:)`; `DM4Image` (the struct) `.object .width .height .pixels .xAxis .yAxis`; `DM4Axis` (the struct) `.origin .scale .units`; `DM4ImageObject` `.name .dimensions .axes .metaDataFormat .imageTagNumbers .imageTagStrings` (these six, with `DM4Image`, `DM4Axis`, `readImage` and `tagTree`, are what 0.2.0 changed from `package`). Also read, public since 0.1.0: `DM4Experiment.list(path:)`, `list(data:)`; `DM4ImageObject` `.index .role .voltage`; the six `DM4Error` cases | `DM4DemoChecks`, `DM4ErrorChecks`, `TagTreeChecks` |
| 2. the Velox metadata fields (five from macTEM's ask of 2026-10-13, `stemMagnification` the owner's of 2026-10-14) | `VeloxMetadata` `.nominalMagnification .stemMagnification .cameraLengthMeters .operatingMode .projectorMode .exposureTimeSeconds`; `VeloxDetectorInfo.exposureTimeSeconds`; with `VeloxMetadata.parse(jsonData:)`, `VeloxEMDReader(path:).images()`, `VeloxImageInfo.metadata` | `VeloxChecks` |
| 3. the bounded quit barrier (macTEM ADR 021) | `HDF5Serial.exitBarrierBound` (read-only, 10 s) | `BarrierChecks`, and the process's own `exit` |
| 4. the DM4 EELS spectrum-image reader (EELS slice 1b) | `DM4Experiment.readEELSSpectrumImage(path:index:)`, `(data:index:)`; `DM4EELSSpectrumImage` (the struct, its `Equatable`) `.object .nx .ny .channels .counts .energyAxis .beamEnergyKeV .convergenceSemiAngleMrad .collectionSemiAngleMrad`; the `DM4Error` cases it throws | `EELSReaderChecks` |
| 5. SpectroEELS (EELS slice 1) | `EELSThickness.logRatio`, `.methodName`; `LowLossSpectrumImage` (both initialisers, six fields, `pixelCount`, `energy(ofChannel:)`); `ThresholdRule`; `MeanFreePathSource`; `InelasticMeanFreePath.iakoubovskii`, `.angularCorrection`; `ThicknessMap` (eleven members and the subscript); `ThicknessPixel` (ten fields); `ZeroLossSource`; `ThicknessUnavailable`; `SigmaUnavailable`; `EELSThicknessError` | `SpectroEELSChecks` |
| 6. SpectroEELS (EELS slice 2, the areal density) | `EELSEdgeQuantification.ratioMethod` (every parameter; both `LowLossIntensity` routes), `.differentialCrossSection`, `.methodName`, `.defaultBackgroundWindow`; `CoreLossSpectrumImage` (both initialisers, six fields, `pixelCount`); `EELSMicroscope` (init, three fields); `LowLossIntensity`; `CoreLossEdge` (`.element .subshell .onsetEV`, `.carbonK .nitrogenK .oxygenK`, `.bundled`, `description`, `Equatable`); `ArealDensityMap` (fifteen fields); `ArealDensityPixel` (eight fields); `EdgeUnavailable` (four cases); `EELSEdgeError` | `EdgeQuantificationChecks`; the resource bundle also by `run.sh` |

## What it proves

- **EELS reader (4), against RosettaSciIO.** `rsciio-EELS_SI.dm4` (object 2) and the planted objects 2, 3, 4, 6, 10, 11, 18 (EELS by
  `Meta Data.Signal` alone), 20 (a stack-builder group that holds only a string) and 21 (its pixel block ends the file) of
  `eels-planted.dm4`: `nx ny channels`, the SHA-256 of the counts and the sample voxels, the energy axis, E0 and the two angles
  equal the `.truth.json` of `tools/eels-reader/truth.py`; the path and data entry points are equal; a different object is not
  equal. Refusals through the public errors: the keV axis (19), a 2D object, an uncalibrated one, the survey, the EDS object, an
  index the file lacks (`cannotOpen`), the bool type (`unsupportedDataType(14)`), a `[3, 0, 5]` cube, and the three files
  whose Data tag declares 0, 29 or 31 elements for a 30-voxel cube (`truncated`; the truth files record that RosettaSciIO raises).
- **SpectroEELS (5).** (a) A one-pixel image whose answer is arithmetic: a 1 eV fixed threshold on counts `1 2 4 8 4 2 1 1` from
  -2 eV gives I_0 = 7, I_t = 23, t/λ = ln(23/7), σ = sqrt(1/7 - 1/23). (b) exSpy's line scan (`Tests/SpectroEELSTests/Fixtures`,
  17 spectra x 1024 channels) against `pins.json`, exSpy 7185a4d1's answers (not truth; its tolerances are the pins'): the
  fixed 2.5 eV rule (t/λ, I_0, I_t, the threshold channel), the three absolute-thickness routes (λ given; density; both), the
  zero-loss-spectrum route and the estimated rule (tolerance, channels, t/λ), and Iakoubovskii's λ and the angular correction.
  (c) Every `ThicknessUnavailable` and `SigmaUnavailable` reason produced by an image that causes it, and every
  `EELSThicknessError` case produced by an input that causes it (with its payload where it has one).

- **Public.** The target compiles only while each symbol above is `public`. `run.sh --controls` shows it for every one: see
  Negative controls.
- **Right values, through the public surface.** On the committed fixtures, against their `.truth.json`:
  `demo-edx-tiny.dm4` (objects, roles, dimensions, axes, voltage, the tag maps, pixel SHA-256 of the survey and the HAADF
  image, `readImage(path:)` equals `readImage(data:)`); `dm-tag65027-saved-with-DM.dm4` (`tagTree` equals ncempy's tree; the
  stream cut at every 7th byte before its trailer, and at the last one, throws, 1512 cuts as `DM4TagTreeTests` samples);
  `velox-tiny.emd` (the six fields and every detector's exposure are nil on this file); `velox-metadata-planted.emd` (all
  12 images: the six fields and each detector's own exposure equal the planted truth, through `images()`). Some checks are
  consistency between two public paths, not independent values: `list(data:)` equals `list(path:)`, `readImage(path:)`
  equals `readImage(data:)`, `DM4Image.object` is the listed object, width and height match `dimensions`, the axes match
  the object's, `Meta Data.Format` and the voltage tag match the object's fields, and `tagTree` under the object's prefix
  equals its `imageTagNumbers`. They show the surface is reachable and coherent; the truth-file and ncempy checks carry
  the values. The planted Velox truth is what `make_fixture.py` planted; independence from the reader is
  `tools/velox-metadata-parity`'s job.
- **The Velox rules, on metadata JSON through the public `VeloxMetadata.parse(jsonData:)`** (the rules are the doc comments
  on `VeloxMetadata` and RosettaSciIO 049e7d70's `_emd_velox.py`): every number is read as stored (a string, as Velox
  writes it, or a JSON number; `"1.3e+006"`; `"0"` is 0); `cameraLengthMeters` is metres with no conversion; the modes are
  the stored strings (a JSON number is nil; `"TEM"` is kept); `stemMagnification` is `CustomProperties.StemMagnification.value`
  whatever its `"type"`, nil when the entry has no `value`, is a bare string, or `CustomProperties` is itself a string, and
  is never a copy of `nominalMagnification` (nor the reverse); `exposureTimeSeconds` is the `ExposureTime` of the first
  `Detectors` entry in `Detector-<n>` index order (numerically) whose `DetectorName` equals `BinaryResult.Detector`,
  case-sensitively, not the `contains` of the energy axis, and an empty or absent `BinaryResult.Detector` names no entry.
- **Debug, no unsafe flags.** `run.sh` builds in Debug, as a consumer's Debug build does, with zero warnings, and fails if a
  test-only target (`SpectroHDF5ExitProbe`, `SpectroKitTests`, `SpectroCoreTests`, `SpectroGoldenTests`) was built.
- **The barrier does not fire when nothing is stuck.** The process ends through `exit` with the barrier installed (the Velox
  open installs it); `run.sh` requires exit status 0 and no "quit barrier passed its bound" line.

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
- **The GOS resource bundle.** The tables are SpectroEELS's `Bundle.module` resources. The Debug consumer computing a cross section
  for C, N and O K is the proof they load; `run.sh` also fails unless `SpectroKit_SpectroEELS.bundle` sits next to the consumer binary
  with `dft-C-K1.json`, `dft-N-K1.json` and `dft-O-K1.json` inside.

## Negative controls (`run.sh --controls`)

For each of the 28 symbols 0.2.0 made public (ask 1's 20: three `DM4Experiment` methods, `DM4Image` and its six members,
`DM4Axis` and its three, six `DM4ImageObject` fields; the seven Velox ones; and `HDF5Serial.exitBarrierBound`), and for each of
the new ones (the two readers, `DM4EELSSpectrumImage` and its nine members; every public type, field, method and initialiser of
`SpectroEELS` listed above; enum cases are covered by their type's control, a case cannot be made `package` alone),
`controls.py` reverts that one declaration from `public` to `package` in an rsync'd **copy**
of the repository (`<root>/.build/consumer-check/mutants/`, the working tree is never edited; the edit must apply exactly
once, else the control fails loudly), builds the consumer against the copy, and requires the build to fail with the
compiler error that names the symbol. First the unedited copy must build (the baseline), so a failure is the edit's. A
control is caught by one of three diagnostics:

- **access** (most): `error: 'pixels' is inaccessible due to 'package' protection level` at the consumer's use, with the note
  `SpectroCore.DM4Image.pixels:2:13: note: 'pixels' declared here` pointing at the edited declaration (this tells `VeloxMetadata`'s
  and `VeloxDetectorInfo`'s `exposureTimeSeconds` apart);
- **overload** (`readImage(path:index:)`, `readImage(data:index:)`): the compiler falls back on the public sibling and says
  `incorrect argument label in call (have 'path:index:', expected 'data:index:')` at a call of `readImage`;
- **decl** (the SpectroEELS types): the type itself becomes `package`; caught by `cannot find '<Type>' in scope` in the consumer,
  or, when a public signature of the library names the type, by `cannot be declared public because ... uses a package type` with
  the type in the code frame under it;
- **library** (`CoreLossEdge.carbonK`, `CoreLossEdge.description`): the library refuses the edit itself, since `carbonK` is `ratioMethod`'s public default argument and `description` witnesses `CustomStringConvertible`; caught by that error in the edited file;
- **used** (the two `LowLossSpectrumImage` initialisers, the two `CoreLossSpectrumImage` ones with the error required in `EdgeQuantificationChecks.swift`, and `EELSMicroscope.init`): the access error has no stable name, so the consumer's build must fail
  with an error in the consumer's own sources that names the type the other initialiser takes (`cannot convert value of type
  '[Double]' to expected argument type '[Float]'`, and the reverse);
- **type** (`DM4Image`, `DM4Axis`, `DM4EELSSpectrumImage`, the structs): the library itself no longer compiles, since public members are typed with a
  `package` struct (`property cannot be declared public because its type uses a package type`, at a line naming the struct).
  Reverting a struct cannot reach the consumer, so each struct's fields are controlled on their own as well.

It prints `consumer-check: negative controls: N of N caught` (143 of 143: the 28 of 0.2.0, 58 of the reader and slice 1, and 57 of slice 2) and exits non-zero unless all are caught. The build logs of the
last run are in `<root>/.build/consumer-check/mutants/logs/`.

## What it cannot prove

- `EELSEdgeError.noBundledCrossSection` and `.crossSectionFailed`: no public way reaches them. `CoreLossEdge`'s initialiser is internal,
  so a consumer holds only C K, N K and O K, all bundled; and every microscope the checks tried that the validation lets through either
  gave a cross section or `crossSectionZero`. (The declarations are still controlled with the type `EELSEdgeError`.)
- That a microscope outside the physical range is refused: beam energies of about 2 keV and below, or a convergence semi-angle of 1e6
  mrad, pass `invalidMicroscope` and then trap inside the library (`Index out of range`). Found while looking for
  `crossSectionFailed`; not asserted here, since it cannot be a check (the process would die).

- That the 10 s bound works: no thread is stuck in HDF5 here. That is `SpectroKitTests` with the `SpectroHDF5ExitProbe` child
  process (`tools/test.sh`).
- That macTEM compiles: only the symbols it names are touched, not its code. `DM4Axis.init` and the other `DM4ImageObject`
  fields (`dataType`, `eds`, `spectrumImageRect`, ...) stay `package`; this check does not claim them. `experimentID` was
  already public and is not read here.
- That the Velox values agree with an independent reading of the bytes: the planted truth is what `make_fixture.py` plants,
  and the JSON rules are the doc comments'. That comparison, bit for bit against h5py and RosettaSciIO 049e7d70, is
  `tools/velox-metadata-parity`.
- Version resolution: a path dependency has no version. That a tag resolves, from a clone, in a Debug build with no
  unsafe-flags refusal (S3's method for 0.1.0) is shown by a throwaway package outside the repository, not by this one.
- Release builds, or a machine with no libhdf5 (see below).

## Run

```
tools/consumer-check/run.sh              # build (Debug), run the checks
tools/consumer-check/run.sh --controls   # then the negative controls (python3, standard library only)
```

Prints one `PASS`/`FAIL` line per check, then `consumer-check: all passed — N checks ...` and exits 0 only if everything
held. The binary reads the fixtures from the repository's `Tests/SpectroCoreTests/Fixtures` and
`Tests/SpectroKitTests/Fixtures` (pass another `Tests` directory as its first argument).

libhdf5 (the Velox reader dlopens the host's; the library ships none), in the order `tools/test.sh` uses:
`MAC4DSTEM_HDF5_PATH`; `<root>/.build/hdf5/libhdf5.dylib`; mac4DSTEM's vendored copy at `5ba712a0`, taken by `git show` into
`<root>/.build/hdf5` when `../mac4DSTEM` is checked out beside the repository; Homebrew's `hdf5`.
