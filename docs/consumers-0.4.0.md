# SpectroKit 0.4.0: what the consumers change

Written 2026-10-15 by SpectroKit's 0.4.0 session, for mac4DSTEM's and macTEM's sessions. Both apps skip 0.3.0 and bump
once (the suite's cross-repo order, item 7): mac4DSTEM from **0.1.0**, macTEM from **0.2.0**. Nothing here was done in
their repositories; the file lists below were read at their HEADs, mac4DSTEM `29e75c0e` and macTEM `08ebfa0`, read-only,
and are a guide: recheck at the bump (mac4DSTEM's DiffractoKit and CuboKit switch was in progress that day).

## 1. What changed since each app's pin

| Since | Change | Source-breaking? |
|---|---|---|
| 0.2.0 (mac4DSTEM only) | The DM4 API public (`readImage`, `tagTree`, `DM4Image`, `DM4Axis`, six `DM4ImageObject` fields); six Velox metadata fields; the bounded quit barrier (`docs/macTEM-handoff-0.2.0.md`). All of it now lives in FormatoKit (section 2) | no (additive) |
| 0.3.0 | **SpectroCore split**: everything X-ray moved to the new module and product **`SpectroEDX`** (the line table, windows, the EDS model and fit, the proposer, quantification, export, the six EPQ / FFAST / Krause tables in `SpectroKit_SpectroEDX.bundle`). Byte-identical output | **yes** for EDX users |
| 0.3.0 | **`SpectroEELS`**, a new product: the t/λ thickness map (log-ratio, exSpy 7185a4d1) | no (opt-in) |
| 0.3.0 | DM4: a Data tag must declare exactly the image's bytes (else `.truncated`); `Meta Data.Signal == "EELS"` makes an EELS object; `readEELSSpectrumImage`. Now FormatoKit's | behaviour |
| after 0.3.0 | SpectroEELS: the C K areal density by the ratio method (`EELSEdgeQuantification.ratioMethod`, `CoreLossSpectrumImage`, `ArealDensityMap`, ...), with exSpy's dft GOS tables in `SpectroKit_SpectroEELS.bundle` (CC-BY-4.0, NOTICE) | no (additive) |
| after 0.3.0 | The element proposer about 7x faster, output bit for bit unchanged; a `dgelsd` solver (package) | no |
| **0.4.0** | **The readers leave SpectroKit for FormatoKit 0.0.2** (section 2), and SpectroKit depends on it by tag | **yes** for reader users |
| 0.4.0 | The tests are Swift Testing (nothing a consumer sees) | no |

`docs/consumers-0.3.0.md` has the 0.3.0 details; this note repeats what an app needs.

## 2. The readers are FormatoKit's

SpectroKit 0.4.0 declares `.package(url: "https://github.com/mac4DSTEM/FormatoKit", exact: "0.0.2")` and its
`SpectroCore` depends on FormatoKit's `FormatoCore`, `FormatoDM` and `FormatoEMD`. What moved, and the module to import
(FormatoKit's `docs/consumers-0.0.1.md` has the full list and the behaviour notes):

| Type | Was | Now |
|---|---|---|
| `DM4Experiment`, `DM4ImageObject`, `DM4Image`, `DM4Axis`, `DM4ImageRole`, `DM4EELSSpectrumImage`, `DM4EDSSpectrumImage`, `DM4EDSDetectorTags`, `DM4Error` | `SpectroCore` | `import FormatoDM` |
| `VeloxEMDReader`, `VeloxEMDError`, `VeloxMetadata`, `VeloxDetectorInfo`, `VeloxEnergyAxis`, `VeloxImageInfo`, `VeloxImageElementType`, `VeloxSpectrumImage`, `VeloxEventStore`, `VeloxStreamGeometry`, `VeloxFrameSelection`, `VeloxScanImage`, `VeloxStreamInfo`, `VeloxScanTransformation` | `SpectroCore` | `import FormatoEMD` |
| `HDF5Serial` (`run`, `acquire`, `release`, `installExitBarrier`, `exitBarrierBound`), `hid_t`, `herr_t`, `hsize_t` | `SpectroCore` | `import FormatoHDF5` |
| `SpectroCancelled` | a struct in `SpectroCore` | `public typealias SpectroCancelled = FormatoCancelled` in `SpectroCore` |
| `SpectroCancellation` (`task`; `check` stays `package`) | `SpectroCore` | unchanged: SpectroCore's own enum, forwarding to `FormatoCancellation` |

**FormatoKit must be public before 0.4.0 is pushed and tagged.** SpectroKit is public and FormatoKit is private (2026-10-15):
until FormatoKit is public, SpectroKit's CI and every clone without the owner's credentials fail to resolve the dependency.
The owner's machine resolves it, which is how this session built and gated. Never work around it with a path dependency.

**SpectroKit does not re-export the Formato modules** (no `@_exported import`): an app imports the module a type comes
from, as `MemberImportVisibility` requires anyway, and lists the products it imports. The decision keeps each dependency
visible in the app's manifest and avoids an underscored attribute in a public library. `SpectrumImageOpener`,
`LoadedSpectrumImage`, `SpectrumImageSource` and the rest of the spectrum image stay in `SpectroCore` with the same
signatures; they call FormatoKit inside.

Behaviour a consumer can see (all FormatoKit's, registered there): the 51 declarations FormatoKit's dry run needed are
`public` (among them `DM4Experiment.readEDSSpectrumImage`, `VeloxEMDReader.readSpectrumImage(frames:cancelled:progress:)`,
`.isVeloxEMD(path:)`, `.storedElementSelection()`, `VeloxSpectrumImage` and `VeloxEventStore`); the quit barrier's stderr line
starts `FormatoKit:` (was `SpectroKit:`); one `HDF5Serial` per process (section 5). Output is byte-identical: FormatoKit's 121
moved test names and golden, and here the 302 staying test names and the six golden scenarios against the same baseline.

`SpectroCancelled()` constructed in an app's own code is `FormatoCancelled()`'s initialiser: under `MemberImportVisibility`
that file needs `import FormatoCore`. `catch is SpectroCancelled` and `SpectroCancellation.task` need nothing new. One exception, unchanged since 0.3.0 and
documented on `ElementProposer.propose`: the proposer reports cancellation as `ProposerError.cancelled`, not `SpectroCancelled`.

## 3. mac4DSTEM (0.1.0 to 0.4.0)

- **Pins, together** (section 5): `Package.swift:24` `exact: "0.4.0"` and a new
  `.package(url: "https://github.com/mac4DSTEM/FormatoKit", exact: "0.0.2")`; the same in `mac4DSTEM.xcodeproj` (the
  package references, `project.pbxproj` requirements, the workspace `Package.resolved`).
- **Products** for every target that lists `SpectroCore` today (`Package.swift:33` DSTEMCore, `:76`, and the Xcode targets):
  add `.product(name: "SpectroEDX", package: "SpectroKit")`, `.product(name: "FormatoDM", package: "FormatoKit")`,
  `.product(name: "FormatoEMD", package: "FormatoKit")`, `.product(name: "FormatoHDF5", package: "FormatoKit")` (and
  `FormatoCore` if a file constructs `SpectroCancelled()` or uses FormatoCore's types). Every target that calls
  `QuantificationTables.bundled()` (`SpectroscopyRoomController.swift`) must link `SpectroEDX`, or `Bundle.module` traps.
- **Imports** (`MemberImportVisibility` is on). At `29e75c0e`, by what each file names:
  - `import SpectroEDX` (EDX types): `App/SpectroscopyRoomController.swift`, `Core/Spectroscopy/Registration/QuantificationStep.swift`,
    `Session/SpectroscopyQuantification.swift`, `Session/SpectroscopySession.swift`, `Support/FigureRendering.swift`, and in
    `UI/Spectroscopy/`: `AutoIDPresentation`, `MapsGridView`, `PeriodicTableView`, `QuantifyPresentation`,
    `SpectroscopyInspectors`, `SpectroscopyLogic`, `SpectroscopyRoomGeometry`, `SpectroscopyRoomModel`, `SpectrumStripView`;
    about 25 test files (`E1PoolRecording`, `FigureExportTests`, `MethodTests`, `SpectroscopyAutoID`, `DriveL9`, `DriveL12`,
    `FitRange`, `LaneS`, `LaneU`, `PoolsH9`, `Pools`, `Quantify`, `RoomLive`, `Spec2B/D/E/K`, `UnlistedLine`, `VeloxL4`,
    `SpectrumImageOpening`, `SpectroGolden`, `SwiftUIReviewE`); `tools/autoid-velox-check`.
  - `import FormatoDM`: `Core/Data/DM4Reader.swift` (`DM4Error`), `Core/Data/GMSFourDRegistration.swift` (`DM4Experiment.list`),
    `Session/SessionGates.swift` (`DM4Error`); tests `DM4ExperimentTests`, `DemoEDXFixtureTests`, `FinalPolishDTests`,
    `RegistrationTests`, `SpectroscopyLaneUTests`, `SpectrumImageOpeningTests`; `tools/dm4-robustness-test`.
  - `import FormatoEMD`: tests `SpectroGoldenTests`, `SpectrumImageOpeningTests`; `tools/velox-parity`, `tools/autoid-velox-check`.
  - `import FormatoHDF5`: `Core/Data/H5Reader.swift`, `Core/Data/BraggVectorEMDWriter.swift`; tests `ReviewHDF5GuardTests`,
    `SidecarAttributeGuardTests`, `SwiftUIReviewBTests`; `tools/dm4-parity-probe`, `tools/hdf5-exit-race-test`.
- **Scripts.** `tools/lib/sources.manifest` (`spectrokit_module`) builds `--target SpectroCore` from
  `.build/checkouts/SpectroKit`: it must also build `SpectroEDX`, and FormatoKit's `FormatoCore`, `FormatoDM`, `FormatoEMD`,
  `FormatoHDF5` from `.build/checkouts/FormatoKit`, link their objects, and point the resource bundles at
  `SpectroKit_SpectroEDX.bundle` (and `FormatoKit_FormatoHDF5.bundle`, or keep `MAC4DSTEM_HDF5_PATH`). The EDX resource path
  is `.build/checkouts/SpectroKit/Sources/SpectroEDX/Resources/Spectroscopy` (`tools/lib/fetch-epq.sh:15`,
  `tools/demo-edx/sim_edx.py` `DEFAULT_MAC`; the CSVs' sha256 unchanged). `tools/velox-parity`'s `-package-name spectrokit`
  trick is not needed for `readSpectrumImage` (public now); `markersPerFrame` is FormatoKit's and still `package`
  (`-package-name formatokit` reaches it).
- **The app's copies of moved tests** (`DM4ExperimentTests`, `DemoEDXFixtureTests`) are mac4DSTEM's to keep or retire;
  FormatoKit carries the originals.
- The golden `velox-tiny.txt` re-record of the 0.2.0 bump (+13 nil lines: the six Velox fields) applies, since mac4DSTEM
  skips 0.2.0.

## 4. macTEM (0.2.0 to 0.4.0)

- **Pins, together**: `Package.swift:19` `exact: "0.4.0"` plus FormatoKit `exact: "0.0.2"`; the Xcode project's own pin
  (`macTEM.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, `xcodebuild -resolvePackageDependencies`).
- **Products** for TEMCore (`Package.swift:24`): `FormatoDM`, `FormatoEMD`, `FormatoHDF5` (FormatoCore if needed); and
  `SpectroEDX` when the EDX room starts using it (it resumes on 0.4.0); `SpectroEELS` when thickness is wanted.
- **Imports** at `08ebfa0`: `import FormatoDM` in `Sources/TEMCore/Data/ImageOpening.swift`, `AcquisitionMetadata+Read.swift`,
  `AcquisitionMetadata+TIFF.swift`, tests `AcquisitionMetadataReadTests`, `FixtureReadTests`, `ImageOpeningTests`;
  `import FormatoEMD` in `VeloxImageReader.swift`, `AcquisitionMetadata+Velox.swift` (and `FormatoCore` where
  `SpectroCancelled()` is constructed); `import FormatoHDF5` in `SidecarHDF5.swift`, `SessionSidecarFile.swift`. None of
  macTEM's files names an EDX type today.
- **Scripts that name SpectroKit source paths break** (FormatoKit's consumers note, macTEM section):
  `tools/lib/sources.manifest:32-38,45` (`HDF5Types.swift`, `SpectroCancellation.swift`, `VeloxEMDReader.swift`,
  `DM4Error.swift`, `SpectroFileName.swift`, `DM4Experiment.swift` under `$sk/Sources/SpectroCore/...`: now FormatoKit's
  `Sources/Formato*/`, the cancellation and file-name helpers as `FormatoCancellation.swift` and `FormatoFileName.swift`);
  `tools/lib/fetch-spectrokit.sh:16` probes `Sources/SpectroCore/Data/VeloxEMDReader.swift`; `tools/metadata-parity/run.sh`
  mutates `DM4Experiment.swift` by path. `NOTICE` names SpectroKit for the readers: they are FormatoKit's now.
- The 0.3.0 note's "nothing beyond the pin" for macTEM no longer holds: the reader imports and the scripts above are the work.

## 5. One HDF5 lock per process: bump both together

`HDF5Serial` is FormatoKit's. SpectroKit 0.1.0 to 0.3.0 define their own. A process that links FormatoKit's and an older
SpectroKit's has two locks and two quit barriers around one libhdf5 that is not thread-safe, the race the lock exists to
prevent. **Bump SpectroKit to 0.4.0 and add FormatoKit 0.0.2 in the same change; never one without the other.** No other
kit depends on FormatoKit today (DiffractoKit 0.0.3, CuboKit 0.0.3), so the exact pins do not conflict.

## 6. libhdf5: the owner's pending decision

FormatoKit ships libhdf5 2.1.1 with libsz and libaec (the binaries mac4DSTEM vendors at `5ba712a0`; sha256 equal, checked
here) inside FormatoHDF5's resource bundle `FormatoKit_FormatoHDF5.bundle`, three ad-hoc-signed dylibs. The reader looks
for libhdf5 in this order: `MAC4DSTEM_HDF5_PATH`; the host app's `Frameworks/libhdf5.dylib` (two forms); the shipped copy;
the bare name. Both apps embed their own three dylibs, which are found first, so their reading does not change. What
changes is that an app linking FormatoHDF5 now also carries the bundle with three more dylibs in `Resources/`, which
notarisation may refuse as unsigned or ad-hoc-signed code outside `Contents/Frameworks`. The owner has not decided
(FormatoKit's board row); until he does, each app's bump chooses one of these and says which:

1. **Sign them in a build phase.** A Run Script phase after "Copy Bundle Resources" signs the three dylibs inside
   `FormatoKit_FormatoHDF5.bundle/Contents/Resources/hdf5/` with the app's identity and hardened runtime
   (`codesign --force --options runtime --timestamp --sign "$EXPANDED_CODE_SIGN_IDENTITY" <dylib>`), before the app itself
   is signed. Keeps the shipped copy usable as a fallback; costs a build phase per app and two copies of libhdf5 in the app.
2. **Strip the bundle's `hdf5/` folder in a build phase.** A Run Script phase deletes
   `$CODESIGNING_FOLDER_PATH/Contents/Resources/FormatoKit_FormatoHDF5.bundle/Contents/Resources/hdf5` before signing. The app's
   own `Frameworks/libhdf5.dylib` is found first anyway; nothing unsigned ships. Costs a build phase; if the app's own copy
   were ever missing, the reader would fall through to the bare name and fail with FormatoKit's "no libhdf5" error, not a crash.
3. **A FormatoKit product split (FormatoKit's work, a later tag).** The dylibs move into an opt-in product (for example
   `FormatoHDF5Binaries`), so a host that embeds its own never receives them and a package or tool that wants zero setup
   adds the product. No build phase in the apps; needs a FormatoKit tag and a SpectroKit bump to it.

For packages and command-line tools (SpectroKit's own tests, `tools/consumer-check`, the apps' `tools/` harnesses) nothing
is needed: the shipped copy loads with no setup, which SpectroKit's gate now relies on (it no longer sets
`MAC4DSTEM_HDF5_PATH`).

## 7. Deviations in SpectroKit's own tests (FormatoKit 0.0.2's access)

Five members SpectroEDXTests read are still `package` in FormatoKit 0.0.2 (its dry run compiled SpectroCoreTests, the EELS
tests and the golden, not SpectroEDXTests): `VeloxSpectrumImage.streamCount`, `.energyCalibrationAgrees`,
`VeloxStreamInfo.id`, `VeloxEventStore.streamsAgreeOnCoverage`, `.pixelCount`. The tests read public equivalents instead:
`streams.count` and `geometry.pixelsPerFrame` (exact: the reader sets the two from them); stream ids by name order (the
reader sorts the stream names with Swift's `sorted()`, so the pinned ids sorted pair with them); the calibration flag recomputed from
the public segments by the reader's own rule (one distinct dispersion|offset); the coverage flag through its public
consequence (both frames complete, no partial frame) on the 4-detector file, which is weaker: those come from the head
stream only, so a non-head stream that ended early would pass (Gate B note). They go back to the reader's members when
FormatoKit makes them public (asked on its row). Nothing a consumer calls is affected.

## 8. Checks behind this note

- `tools/test.sh` (release, FormatoKit's shipped libhdf5, no setup): the 302 staying test names equal the baseline at
  `301f1eb` minus the 121 moved ones, before and after the Swift Testing migration; the six golden scenarios byte-identical;
  0 warnings except the three Swift Build prints for FormatoKit's signed dylibs.
- `tools/consumer-check` (a separate package, Debug): the SpectroEELS public API and SpectroCore's spectrum-image opening
  through FormatoKit, with `MAC4DSTEM_HDF5_PATH` unset: 152 checks; negative controls 136 of 136 (the reader controls left
  with the readers: FormatoKit's own consumer check carries them).
- The Gate B refuter on the frozen candidate (a separate package reading the owner's files through FormatoKit and the EDX and
  EELS public API, bit for bit against 0.3.0's outputs on the same inputs): `docs/history.md`, 0.4.0.
