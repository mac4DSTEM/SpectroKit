# consumer-check

A separate SwiftPM package that depends on SpectroKit **by path** (`.package(path: "../..")`) and uses, from outside the
package, every symbol macTEM reads across the package boundary for SpectroKit 0.2.0. `package` access does not cross a
package boundary, so the target compiles only while each of these symbols is `public`.

| macTEM's ask | symbols | where checked |
|---|---|---|
| 1. the DM4 API public (macTEM ADR 019) | `DM4Experiment.readImage(path:index:)`, `readImage(data:index:)`, `tagTree(data:)`; `DM4Image` (the struct) `.object .width .height .pixels .xAxis .yAxis`; `DM4Axis` (the struct) `.origin .scale .units`; `DM4ImageObject` `.name .dimensions .axes .metaDataFormat .imageTagNumbers .imageTagStrings` (these six, with `DM4Image`, `DM4Axis`, `readImage` and `tagTree`, are what 0.2.0 changed from `package`). Also read, public since 0.1.0: `DM4Experiment.list(path:)`, `list(data:)`; `DM4ImageObject` `.index .role .voltage`; the six `DM4Error` cases | `DM4DemoChecks`, `DM4ErrorChecks`, `TagTreeChecks` |
| 2. the Velox metadata fields (five from macTEM's ask of 2026-10-13, `stemMagnification` the owner's of 2026-10-14) | `VeloxMetadata` `.nominalMagnification .stemMagnification .cameraLengthMeters .operatingMode .projectorMode .exposureTimeSeconds`; `VeloxDetectorInfo.exposureTimeSeconds`; with `VeloxMetadata.parse(jsonData:)`, `VeloxEMDReader(path:).images()`, `VeloxImageInfo.metadata` | `VeloxChecks` |
| 3. the bounded quit barrier (macTEM ADR 021) | `HDF5Serial.exitBarrierBound` (read-only, 10 s) | `BarrierChecks`, and the process's own `exit` |

## What it proves

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

## Negative controls (`run.sh --controls`)

For each of the 28 symbols 0.2.0 made public (ask 1's 20: three `DM4Experiment` methods, `DM4Image` and its six members,
`DM4Axis` and its three, six `DM4ImageObject` fields; the seven Velox ones; and `HDF5Serial.exitBarrierBound`),
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
- **type** (`DM4Image`, `DM4Axis`, the structs): the library itself no longer compiles, since public members are typed with a
  `package` struct (`property cannot be declared public because its type uses a package type`, at a line naming the struct).
  Reverting a struct cannot reach the consumer, so each struct's fields are controlled on their own as well.

It prints `consumer-check: negative controls: N of N caught` and exits non-zero unless all are caught. The build logs of the
last run are in `<root>/.build/consumer-check/mutants/logs/`.

## What it cannot prove

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
