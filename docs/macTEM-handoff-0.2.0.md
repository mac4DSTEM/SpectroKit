# SpectroKit 0.2.0: hand-off to macTEM

Written 2026-10-14 by SpectroKit's 0.2.0 session, for macTEM's next session. Read it from the tag:
`git -C ../SpectroKit --no-optional-locks show 0.2.0:docs/macTEM-handoff-0.2.0.md`.

0.2.0 answers macTEM's three asks (`docs/archive/spectrokit-asks-2026-10-13.md` in macTEM, items 1 to 3) and adds one
field the owner chose on 2026-10-14 (`stemMagnification`, section 4). SpectroKit changed nothing in macTEM: every step
below is macTEM's session's, once the owner has tagged and pushed 0.2.0.

Two rehearsals in scratch clones of macTEM back the steps, each against a scratch-only 0.2.0 tag (macTEM's own working
tree was never built or written). The first, at macTEM `3dbeb3f` against the sources without `stemMagnification`, ran
the unit tests. The second, at `3412d4a` against SpectroKit `ad53ddf` (the 0.2.0 sources as reviewed), followed sections
1 to 3 of this document literally and ran every gate that needs no test host; its corrections are in the text below.
Line numbers are at `3412d4a`'s committed tree. macTEM moved on during the session (`5c1ca88` at the end of it:
`ROADMAP.md`, `docs/open-items.md` and `docs/status.md` shifted; the files below given with two numbers moved), and its
working tree carries another session's uncommitted edits (`tools/lib/sources.manifest` gains an `indexing` group,
`tools/run-tests.sh`). So locate every cited line by its text; the numbers are there to check against. Every commit hash
and `originHash` written into macTEM must come from the owner's real tag
(`git -C ../SpectroKit rev-parse '0.2.0^{commit}'`), not from the rehearsal.

## 1. The bump

- Three files pin SpectroKit. `Package.swift`:
  `.package(url: "https://github.com/mac4DSTEM/SpectroKit", exact: "0.2.0")`, then `swift package resolve` rewrites
  `Package.resolved`. `macTEM.xcodeproj` takes the package through a local reference to `.`, but Xcode keeps its own
  tracked pin, `macTEM.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (originHash line 2,
  revision line 9, version line 10); `xcodebuild -resolvePackageDependencies -project macTEM.xcodeproj -scheme macTEM`
  rewrites it and builds and launches nothing.
- `NOTICE` lines 27 to 29 (26 is blank): the tag `0.1.0` (end of line 27) and the commit `f7a40fc…` (start of line 28)
  become `0.2.0` and its commit; "for its Velox EMD reader" (end of line 28) / "and HDF5 layer" (start of line 29)
  becomes "for its Velox EMD reader, DM3/DM4 reader and HDF5 layer".
- `ROADMAP.md`: every line containing `0.1.0` (11; at `3412d4a` lines 14, 26, 27, 73, 81, 282, 284, 286, 293, 1205,
  1537, at `5c1ca88` 14, 26, 27, 73, 81, 307, 309, 311, 318, 1230, 1562), and the commit `f7a40fc` one line after the
  second of the block (283 / 308). The rehearsal updated the V1-E1 row (27: 0.2.0 imported for Velox and the DM3/DM4
  reader), the V1-E1 entry (81), and the sentence "The DM4 copies stay: their API is `package` in 0.1.0" (286 / 311),
  which the bump falsifies (amended in place). The others are history.
- `tools/velox-image-parity`: the check at `main.swift:317-319` (the four fields macTEM does not read are `unread`) is
  unchanged by the bump and passes on 0.2.0; it flips only once macTEM reads them. Its wording is what becomes false:
  "the four fields SpectroKit 0.1.0 does not expose" at `:22`, `:319` and `README.md:61` becomes "the four fields macTEM
  does not read yet (SpectroKit 0.2.0 exposes them)"; `README.md:3` and `:64` change only the version.
- `tools/lib/fetch-spectrokit.sh` follows `Package.resolved`, so the harnesses take 0.2.0's sources by themselves. An
  existing `References/SpectroKit` at 0.1.0's commit (macTEM's is) is refused, with the fix printed (fetch the tags,
  check out the pin); the fix works. Its header comment (line 4) says `exact 0.1.0`.
- Other live text that says 0.1.0, that the DM4 copies stay, or that the asks are still to be taken: `README.md:26-27`;
  `docs/architecture.md:16-17`, `:45`, `:115`, `:117-119`; `docs/open-items.md`, the entry "SpectroKit's next tag: the
  DM4 API public, five Velox fields" (95-100 / 91-96: the copies half becomes false, the field-reading half stays open);
  `docs/status.md:9`, `:15`, the Owner row "Optional: `docs/archive/spectrokit-asks-2026-10-13.md` into a SpectroKit
  session (not taken yet; SpectroKit is at 0.1.0)" (63 / 65) and the bullet "For SpectroKit, if you want it" (71 / 73);
  `docs/decisions.md:28` (row 019); and ADR 019 itself (`:51`, "Owed to SpectroKit, through the owner"), which needs an
  amendment.

## 2. The DM4 API (ask 1)

Public in 0.2.0, as asked: `DM4Experiment.readImage(path:index:)`, `readImage(data:index:)`, `tagTree(data:)`;
`DM4Image` (`object`, `width`, `height`, `pixels`, `xAxis`, `yAxis`); `DM4Axis` (`origin`, `scale`, `units`);
`DM4ImageObject`'s `name`, `dimensions`, `axes`, `metaDataFormat`, `imageTagNumbers`, `imageTagStrings`.
`DM4Experiment.list(path:)` and `list(data:)`, `DM4ImageObject`'s `index`, `role`, `voltage` and `experimentID`, and
`DM4Error` were public at 0.1.0. The change is access only: with `public` read back as `package`, SpectroKit's
`DM4Experiment.swift` is macTEM's copy apart from the headers, and `DM4Error.swift` and `SpectroFileName.swift` are
identical apart from macTEM's provenance header.

Still `package` (not asked; macTEM's sources and tests build without them): `readEDSSpectrumImage`, the initializers
(`DM4Axis.init` is `package`, `DM4Image`'s is the implicit internal one), `DM4ImageObject`'s `label`, `roleSource`,
`dataType`, `dataTypeName`, `eds`, `dataOffset`, `dataByteCount`, `metaDataSignal`, and `spectroDisplayFileName`.
macTEM's harnesses compile sources into one module, where access does not matter.

The steps:

- Delete `Sources/TEMCore/Data/DM4Experiment.swift`, `DM4Error.swift`, `SpectroFileName.swift` and
  `macTEMTests/DM4ExperimentTests+Spectro.swift`.
- `MemberImportVisibility` then needs SpectroCore imported where DM4 is used, and only there (necessary and sufficient:
  without these lines the build fails in exactly these six files, with them it has 0 warnings). After
  `import Foundation` in `Sources/TEMCore/Data/AcquisitionMetadata+Read.swift`, `AcquisitionMetadata+TIFF.swift` and
  `ImageOpening.swift`: `#if canImport(SpectroCore)` / `import SpectroCore` / `#endif` (the pattern of
  `VeloxImageReader.swift`, which the one-module harnesses need). A plain `import SpectroCore` in
  `macTEMTests/AcquisitionMetadataReadTests.swift`, `FixtureReadTests.swift` and `ImageOpeningTests.swift`.
- Before the deletion TEMCore declares 11 namesakes of SpectroCore's: `DM4Axis`, `DM4EDSDetectorTags`,
  `DM4EDSSpectrumImage`, `DM4Error`, `DM4Experiment`, `DM4Image`, `DM4ImageObject`, `DM4ImageRole`, `DM4RoleSource`,
  `DM4SpectrumImageRect`, `spectroDisplayFileName`; after it, none (TEMCore's top-level names 101 to 90).

Unit tests: in the first rehearsal 761 passed before and 740 after, 0 failed, 0 skipped, each run matched by
`Class.method` to the declared list. The 21 that go are exactly `DM4ExperimentSpectro`'s; they live in SpectroKit
(`Tests/SpectroCoreTests/DM4ExperimentTests+Spectro.swift`: the same 21 plus one that reads SpectroKit's own
`demo-edx-tiny.dm4`). The second rehearsal ran no test host: the declared names are again 761 and 740 with the same 21
removed, and `xcodebuild build-for-testing` of the whole test bundle succeeded on the final candidate. A unit run on the
real tag is still the proof.

## 3. The harnesses

- `tools/lib/copies.manifest`: delete the four lines of the copies (21, 25, 28 and 54).
- `tools/lib/sources.manifest`: delete `"$core/Data/DM4Error.swift"`, `"$core/Data/SpectroFileName.swift"` and
  `"$core/Data/DM4Experiment.swift"` from the five group lists that hold them (dm, tiff, mrc, metadata, velox: 15
  lines), and add SpectroKit's three to the `want+=(` list of `mactem_spectrokit_velox`, which exactly those five groups
  call, after its `VeloxEMDReader.swift` line:

  ```
      "$sk/Sources/SpectroCore/Data/DM4Error.swift"
      "$sk/Sources/SpectroCore/Spectroscopy/SpectroFileName.swift"
      "$sk/Sources/SpectroCore/Data/DM4Experiment.swift"
  ```

  (Replacing the entries inside the group lists does not work: `$sk` is local to `mactem_spectrokit_velox`, and the
  groups fail with `mactem_sources:8: sk: parameter not set`.) Update that function's header comment.
- `tools/metadata-parity/run.sh`: the eight walker source mutations copy `DM4Experiment.swift` from `$DATA`
  (`Sources/TEMCore/Data`), where it no longer is. In `source_mutant`, delete the `DATA=` line (104) and replace
  `cp "$DATA/$file" "$copy"` by a lookup among the harness's sources:

  ```
    local -a found=(${(M)MACTEM_SOURCES:#*/$file})
    if (( ${#found} != 1 )); then
      echo "  FAIL  source mutation '$name': $file is among the harness's sources ${#found} times, not once"
      return
    fi
    ...
    cp "${found[1]}" "$copy"
  ```

  and correct the comment above it ("The walker (DM4Experiment.swift) is mac4DSTEM's file, copied verbatim"). The eight
  `source_mutant_run walker-*` calls need no change: their 12 edit targets each match exactly once in SpectroKit's file,
  and in the rehearsal `metadata-parity` caught 33 of 33 controls, the 8 walker mutants among them.
- Gates in the rehearsal, base (0.1.0) against switch (0.2.0), same commands: `tools/run-tests.sh core` 0 warnings in
  both; typecheck of the groups dm, tiff, mrc, velox, metadata and sidecar clean in both; the harness mains of
  dm4-reader-parity, tiff-reader-parity, mrc-reader-parity, metadata-parity, velox-image-parity, export-parity,
  histogram-parity, sidecar-parity and ring-fit-parity built with 0 warnings; the eight scientific harnesses that
  compile DM4 or SpectroKit sources (metadata, dm4-reader, velox-image, tiff-reader, mrc-reader, histogram, export,
  sidecar) passed with the same check counts in both. `MAC4DSTEM_REPO=../mac4DSTEM tools/check-shared-drift.sh` (the
  pre-push hook's) goes from "copies 57" with the four rows "matches GONE" to "copies 53", green both times.
- `tools/run-tests.sh inventory`: without the manifest edits it fails with the four files MISSING. With them it reports
  what it reports before the bump: at `3412d4a` a clean clone is already red with two DEAD PATH
  (`Sources/TEMCore/Data/SessionMarks.swift` and `docs/archive/v12-session-ui-design-2026-10-14.md`, which `ROADMAP.md`
  cites and which exist only in macTEM's working tree); with those present it is clean before and after.
- `HDF5Types.swift` now imports `Synchronization` (the bound is an `Atomic<Int>`): a harness that compiles it needs a
  deployment target of macOS 15 or later (the sidecar typecheck passed).

## 4. The Velox metadata fields (ask 2, and a sixth)

All read from column 0 of an image's `Metadata`, like the fields 0.1.0 has. As stored: no unit conversion, no decoding,
`nil` when absent or not a number (a string is parsed with Swift's `Double(_:)`, a JSON number taken as is).

| field | stored at | type | note |
|---|---|---|---|
| `VeloxMetadata.nominalMagnification` | `Optics.NominalMagnification` | `Double?` | absent on every public STEM image |
| `VeloxMetadata.stemMagnification` | `CustomProperties.StemMagnification.value` | `Double?` | the owner's sixth field; see below |
| `VeloxMetadata.cameraLengthMeters` | `Optics.CameraLength` | `Double?` | metres, as stored |
| `VeloxMetadata.operatingMode` | `Optics.OperatingMode` | `String?` | a code in an `.emd` ("1", "2"), not a name |
| `VeloxMetadata.projectorMode` | `Optics.ProjectorMode` | `String?` | a code as well |
| `VeloxMetadata.exposureTimeSeconds` | `ExposureTime` of a `Detectors` entry | `Double?` | the rule below |
| `VeloxDetectorInfo.exposureTimeSeconds` | that entry's own `ExposureTime` | `Double?` | every entry |

Exposure is macTEM's rule from the ask: the `ExposureTime` of the first `Detectors` entry, in `Detector-<n>` index
order, whose `DetectorName` EQUALS `BinaryResult.Detector`; `nil` when that entry has none, when no entry matches, or
when `BinaryResult.Detector` is absent or empty. It matches as RosettaSciIO 049e7d70's `_get_detector_metadata_dict`
does (`_emd_velox.py:51-57`: `==`, first as stored), but it is not RosettaSciIO's `DetectorMetadata`: RosettaSciIO feeds
that function a name taken from `Operations` or from `Detector-<DetectorIndex>`, not `BinaryResult.Detector` (macTEM's
`AcquisitionMetadata+TIFF.swift:56-58` already records this). The two agree on every public file because only camera
entries carry an `ExposureTime`. Stored order and index order can only give different answers when two entries share a
`DetectorName`; in the public files none does and every file stores the keys in index order (the parity harness's one
documented deviation is a planted case built to break both). Not by `DetectorIndex`: on 1 of the 42 public image entries
`Detector-<DetectorIndex>` is another entry than the named one (`1854 Camera Ceta.emd`: `DetectorIndex` 0 is `BF`, the
`BM-Ceta` entry is `Detector-8`; by name the exposure is 1.0 s, by index there is none), and 14 store no
`DetectorIndex`.

Two differences from macTEM's own Velox-TIFF rule (`AcquisitionMetadata+TIFF.swift:204-210`), which takes the first
named entry with a POSITIVE `ExposureTime` and keeps scanning past one without: SpectroKit stops at the first named
entry, and it returns 0 or a negative number as stored. They agree on every public file (no duplicate names, no zero
exposures); keep macTEM's positive() gate when switching to the SpectroKit value.

What SpectroKit checked: `Tests/SpectroKitTests/VeloxMetadataFieldsTests.swift` (26 tests, public API only) on inline
JSON and on a planted file (`Fixtures/velox-metadata-planted.emd`, each case with a decoy in column 1), among them that
`DetectorIndex` never decides the exposure; each of 35 mutants of the reader turns at least one test red. And
`tools/velox-metadata-parity`, which reads RosettaSciIO 049e7d70's public Velox files with h5py and its pinned
`_get_detector_metadata_dict` and compares every value bit for bit: on the public files alone 31 files (18 Velox, 13
refused as not Velox), 42 image entries, 440 detector records, 1614 values bit-identical; with the planted file as well
54 entries, 1763 values, and the one planted deviation. Six doc-comment claims of the reader hold on the public files
(the sixth: every entry stores its `Detectors` keys in index order with no duplicate `DetectorName`), and 11 of 11
negative controls are caught. Agreement with RosettaSciIO and h5py is agreement, not truth. In the rehearsal, TEMCore
built with reads of all six fields and the per-detector exposure (and failed on 0.1.0, naming all six).

## 5. Corrections to the asks document, and what macTEM still has to decide

- **Magnification.** RosettaSciIO 049e7d70 does not map `Optics.NominalMagnification`. It maps `Optics.CameraLength`
  (×1e3 to mm, in every mode, `_emd_velox.py:942-945`) and `CustomProperties.StemMagnification.value` (`float`, as the
  magnification, `:946-949`). `NominalMagnification` is absent on every public STEM image and present on the camera
  (Ceta) images. `StemMagnification` is an entry `{"type": …, "value": …}`: typed "double" with the magnification on the
  STEM images, and typed "bool" with the value "0" on three of the four public camera images (macTEM's
  `AcquisitionMetadata+TIFF.swift:56` calls it "a boolean StemMagnification", which is true of those three only). The
  fourth camera image, `1854 Camera Ceta.emd`, stores "115000" typed "double" beside a `NominalMagnification` of
  8609.428. RosettaSciIO maps the value with `float` whatever the type, and so does SpectroKit: those three read
  `stemMagnification == 0`. So it is not a STEM marker, the EELS spectrometer entries carry none, and which field is
  "the magnification" depends on the image kind: that rule is macTEM's to register (a 0 is no magnification).
- **Modes are codes.** In an `.emd`, `OperatingMode` and `ProjectorMode` are codes, not the names a Velox TIFF's XML
  holds. The only code-to-name pairs seen are "1" = "TEM" (OperatingMode) and "2" = "Imaging" (ProjectorMode), on the
  owner's paired Ceta `.emd`/`.tif` files; the public STEM images also carry OperatingMode "2" and ProjectorMode "1",
  which no published reader maps. SpectroKit decodes none. macTEM's camera-length gate (rule c: ProjectorMode
  "Diffraction" or OperatingMode "STEM") cannot be applied to `.emd` codes until macTEM registers a mapping.
- **Camera length** is metres as stored; RosettaSciIO converts it to mm in every mode, macTEM's TIFF rule only where the
  mode makes it real.

## 6. The quit barrier (ask 3, macTEM ADR 021)

Nothing new for macTEM to call: SpectroKit's Velox loader and macTEM's own `SidecarHDF5.swift:246` already install the
barrier right after `H5open`, as before. A quit now waits at most `HDF5Serial.exitBarrierBound` (10 s, public,
read-only) for the HDF5 lock. Past it the handler writes one line to stderr,
`SpectroKit: HDF5Serial's quit barrier passed its bound with the HDF5 lock still held; _exit(70) without HDF5's shutdown`,
and calls `_exit(70)`: the atexit handlers registered before the barrier (HDF5's `H5_term_library` among them), static
destructors and runtime teardown do not run, stdio buffers are not flushed, and no `defer` of the cut thread runs. Gate
B measured it with real libhdf5 and macTEM's `hangcase-flip.mactem.h5` (a thread spinning inside `H5Aread`): the quit
left after 10.2 s with status 70 and that one line, where 0.1.0 waited for Force Quit.

What it costs, and what to keep in mind:

- A file a stuck thread was writing is not closed: HDF5's cached metadata is never flushed. The unbounded wait never
  improved on that.
- A healthy operation longer than 10 s is cut too, where 0.1.0 finished it. A write that publishes by temporary file and
  rename (macTEM's `SessionSidecarFile`, mac4DSTEM's `BraggVectorEMDWriter`) keeps its destination unchanged but leaves
  the unfinished temporary file behind (its `defer` cleanup does not run).
- The order matters. The barrier must be installed after the first successful `H5open`, so that it runs before HDF5's
  teardown. Installed before, it runs after `H5_term_library`, and the teardown races the stuck thread: Gate B measured
  a SIGSEGV (status 139). `SidecarHDF5.swift:246` is in the right place; do not move it. A second, different libhdf5
  image loaded later would register its own teardown after the barrier and run unguarded.
- Two threads calling `exit()` at once bypass the barrier in progress (libc runs the remaining handlers on the second
  call); 0.1.0 had the same hole. `fork` without `exec` is unsupported.

For macTEM, checked by Gate B at `5c1ca88`: its longest hold is `SessionSidecarFile.withLibrary`
(`SessionSidecarFile.swift:318`), a whole sidecar read or write under the lock, but of four strings of at most 4 MiB:
milliseconds, nowhere near 10 s. Exit status: `tools/sidecar-parity/fuzz.swift:175-200`,
`tools/metadata-parity/main.swift:476-503` and `tools/velox-image-parity/main.swift:210-262` treat any non-zero status
as a failure, but their children read, print and `exit(0)` from one thread, so the barrier cannot fire there, and a hung
read never reaches `exit()` and is still reported as timed out. In the rehearsal `sidecar-parity` passed 122 cases and
41 of 41 controls on 0.2.0. Status 70 replaces a hang, not a success.

## 7. What 0.2.0 was gated on

- `tools/test.sh` at `5f0c707` (the last commit touching code or tests), with mac4DSTEM's vendored libhdf5 2.1.1 and
  with Homebrew's 2.2.0: SpectroCoreTests 258 passed, 0 failed (the same 258 names as 0.1.0); SpectroGoldenTests
  byte-identical on the re-recorded `velox-tiny.txt`; SpectroKitTests 32 passed, 0 failed (26 field tests, 6 barrier
  tests). A cold build of every target: 0 warnings.
- Mutation controls: the barrier tests 16 of 16 mutants red, the field tests 35 of 35; every test red under at least
  one.
- `tools/velox-metadata-parity`: section 4. `tools/consumer-check`: 110 checks through the public API in a Debug build,
  and 28 of 28 negative controls (each symbol 0.2.0 made public, reverted to `package`, fails the build naming it).
  0.2.0 resolves by version (`exact: "0.2.0"` from a `file://` clone carrying a scratch tag) and a consumer builds
  neither the test targets nor the barrier's probe.
- mac4DSTEM, sources at `02437c27`: `DSTEMCore`, `DSTEMSession` and `DSTEMTraining` build on 0.2.0 with 0 errors and 0
  warnings, as on 0.1.0; no name collides with a newly public one; its `tools/hdf5-exit-race-test` passed 200 of 200 on
  0.2.0; its golden `velox-tiny.txt` is SpectroKit 0.1.0's and gains the same 13 nil lines on its bump.
- macTEM: the two rehearsals described at the top.
- Gate B: three Sonnet reviewers that had not written the change, one per ask, briefed to refute. All three passed it
  with required fixes, and the fixes are in. Two mutants had passed all five barrier tests (the lock given back before
  HDF5's teardown; the Velox loader installing the barrier before `H5open`, which with real libhdf5 crashes a quit): the
  tests now check that the lock is held at the teardown and, with real libhdf5's `H5atclose`, that the loader's order is
  right. One mutant had passed all 22 field tests (exposure by `DetectorIndex` when present): three tests now pin that
  `DetectorIndex` never decides (a fourth, that a JSON bool reads 1/0). The doc comments and this document were
  corrected where they overstated: the exposure is macTEM's rule with RosettaSciIO's matcher, what `_exit(70)` costs,
  the line numbers and live text in macTEM.
- Not proven here: macTEM's unit run on the real tag (no test host in this session), mac4DSTEM's app target and its
  XCTest suites on 0.2.0, and any Velox file beyond RosettaSciIO's public set and the owner's three paired Ceta files.
