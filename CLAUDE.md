# CLAUDE.md — start here

SpectroKit: the macEM suite's spectroscopy library, a Swift port of exSpy (EDS now, EELS later), imported by tagged
version by mac4DSTEM and macTEM. GPL-3.0, crediting exSpy. **0.1.0 tagged and public; 0.2.0 (macTEM's three asks) is
`edb6ba8`, ready for the owner's tag (push that commit, not `main`'s tip). `main` goes on toward 0.3.0: three modules,
`SpectroCore` / `SpectroEDX` / `SpectroEELS`, and EELS slice 1 (t/λ).** This file is a pointer until the library's own
full rules replace it.

## Read first

1. macTEM's ADR 003, the plan: `../macTEM/docs/decisions/003-spectrokit.md` (`github.com/mac4DSTEM/macTEM`).
2. mac4DSTEM's ADR 064 with both 2026-10-13 amendments, and ADR 066 (v5.0 has no microscope validation):
   `docs/decisions/064-spectrokit-v5-ships-on-it.md`, `docs/decisions/066-v5-no-microscope-validation-b-star-after.md`.
3. In mac4DSTEM `docs/archive/v5/` (read at `5ba712a0`): `spectrokit-slot-plan-2026-10-13.md` (§8 mechanics, §9 slots),
   `spectrokit-test-partition-2026-10-13.md` (the 258 names), `spectrokit-gateB-2026-10-13.md` (non-blocking items for S2).
4. The survey of what moves: `../macTEM/docs/archive/mac4dstem-edx-survey-2026-10-12.md`.

## Hard rules

- **mac4DSTEM and macTEM are read-only from here**: `git -C ../<repo> --no-optional-locks show <commit>:<path>`.
  Never build, test or write in them. The extraction runs on a scratch clone (`git filter-repo`), never their working trees.
- **The freeze happened**: freeze commit `5311bc43`, Gate B passed at `5ba712a0`. **The extraction source is `5ba712a0`.**
  Moving set (ADR 064 amendment 2): `Core/Spectroscopy/` minus `Registration/`;
  `Core/Data/{VeloxEMDReader,HDF5Types,DM4Experiment,DM4Error}.swift` (`SessionSidecarFormat` stayed in mac4DSTEM);
  the six CSVs of `Resources/Spectroscopy` as `Bundle.module` resources; the 28 test files and their fixtures.
- **258 moving tests, by name** (28 files: 18 whole + 10 `+Spectro` halves; the partition doc), not 560.
- **History is merged into the existing `main`** (`--allow-unrelated-histories`); no force-push, no rewrite. The tracked
  `.DS_Store` is deleted in a normal commit and added to `.gitignore`.
- **v5.0 ships on the SpectroKit tag with no microscope validation (ADR 066).** All EDX quantification stays badged
  unvalidated (`validation:"none"`); nothing is called validated. Validation on real data is re-registered after v5.0,
  against the SpectroKit tag.
- **A reference for every number**: exSpy `7185a4d1`, HyperSpy 2.4.0, NIST EPQ `249dd3f8`, rsciio `049e7d70`
  (mac4DSTEM's pins), fetched into the gitignored `References/` (exSpy as `References/exspy-7185a4d1`, one commit, with
  `References/exspy-venv`: HyperSpy 2.4.0, RosettaSciIO 0.14.0, Python 3.14.7; the owner's approval, 2026-10-14; exSpy is
  not installed there, so build its signal classes directly, as `tools/eels-thickness/pins.py` does). An unpinned copy
  is never a reference (the old `exspy-main` and `hyperspy-RELEASE_next_minor` snapshots went to the Trash, 2026-10-14).
  Agreement with exSpy is not truth: an at% is called validated only after it recovers a planted composition and a
  sample of known composition. Until then it self-reports `validation:"none"`.
- **The owner's data** lives in the suite's `data/` folder, read as `$MACEM_DATA` (default `../data`): never copied or
  committed here; numbers measured on it are cited with their log; a manifest line in `data/README.md` per file used;
  using it as a gate or truth is a registration change first (suite CLAUDE.md, 2026-10-14).
- **Names** (the suite's standard): apps are `mac` + technique, libraries are domain + `Kit`, modules carry the
  library's prefix: `SpectroCore` (shared spectrum machinery), `SpectroEDX`, `SpectroEELS` (later).
- **Public at the first tag** (`0.1.0`), the owner's decision of 2026-10-12. Pushing and making it public are the owner's.
- One session per repo. `main` only, commit by explicit paths.
- **Suite board**: this repo's row is `lanes/spectrokit`; how a session opens it, closes it and writes the next pickup
  prompt is `../CLAUDE.md`, "The suite board is the workflow".

## The slots

- **S2 (this repo, done)**: `git filter-repo` extraction from `5ba712a0`, merge into `main`. `Package.swift`: one
  `SpectroCore` target for now, Swift 6 language mode, nonisolated default; the old `-DACCELERATE_NEW_LAPACK`
  `unsafeFlags` still present, only until S3 (gone in S3). `Bundle.module` for the six CSVs; `#filePath` fixture paths. `swift test`
  passes exactly the 258 names. The golden baseline (mac4DSTEM's `SpectroGoldenTests`, recorded at `71929a01`) matches
  byte for byte for the scenarios the library can reach.
  **Done 2026-10-13**: `tools/test.sh` (= `swift test` with mac4DSTEM's vendored libhdf5/libsz/libaec, taken by
  `git show` at `5ba712a0` into `.build/hdf5`; the library has no libhdf5 of its own, the host supplies it): 258 / 0
  failed / 0 skipped, names equal to the partition's list; `SpectroGoldenTests` 6 of mac4DSTEM's 7 scenarios
  byte-identical (`demo-spectrum-fixture` is the app's demo source and stays there), red on a one-character baseline
  mutation. Zero warnings in Swift 6. Open for S3: where the library's own tests and CI get libhdf5.
- **S3 (this repo, done 2026-10-13)**: tag `0.1.0` (local; pushing it, `main`, and making the repo public are the owner's).
  - **LAPACK**: C target `CSpectroLAPACK` (`sk_dgelsy`, `sk_dgeqrf`, `sk_dorgqr`, `sk_dtrtri`: values in, `info` out; the
    public header includes no Accelerate). `ACCELERATE_NEW_LAPACK` comes from its `cSettings`, not a `#define` in the .c:
    Accelerate is a precompiled clang module and does not see an in-source define (tried: `__LAPACK_int` undeclared). The
    objects call the same `_dgelsy$NEWLAPACK`… symbols as S2's Swift did. Golden byte-identical after; 258 names identical.
    Mutations: rcond = 0.9 → 18 fit tests + golden red; dtrtri diag 'U' → 2 covariance tests + golden red; **rcond ×1e9
    (1e-12 → 1e-3) stays green**: no fixture's design is near rank-deficient, so dgelsy's rank threshold is untested (gap).
    Gate B (Sonnet, did not write it): PASS, every argument checked against the old calls.
  - **Debug `-O` dropped** (a versioned dependency cannot carry unsafe flags). Measured (Mac17,9; median s; Debug -Onone /
    Debug -O / Release): Velox 483 MB 16.1 / 0.86 / 0.80; 936 MB 24.5 / 1.05 / 0.96; 1745 MB 82.4 / 3.87 / 3.79; velox-tiny
    ~0.001 all; ElementProposer (eds-proposer-sim) 956 / 19.8 / 19.9; PooledQuantifier sim 31.6 / 0.75 / 0.67, DM4 4.88 /
    0.10 / 0.096; SpectroGoldenTests 1349 / 26.5. `@_optimize(speed)` does not help at -Onone (28.8 vs 31.6; disassembly
    unoptimised). So optimisation is the consumer's: **S4 must decide how mac4DSTEM's Debug builds SpectroKit optimised**
    (else EDX in Debug is 20–50× slower). The proposer's ~20 s even optimised is its own performance item.
  - **Tests**: `tools/test.sh` = `swift test -c release` (`-Xswiftc -O` on Debug crashes swift-frontend on a test file,
    `swifterror`). libhdf5, in order: `MAC4DSTEM_HDF5_PATH`; mac4DSTEM's vendored 2.1.1 by `git show` at `5ba712a0` (the exact
    binaries the app ships); Homebrew `hdf5` (soname 320) for CI and machines without mac4DSTEM. Not vendored: SwiftPM clones
    the whole repo into every consumer, and the library deliberately ships no libhdf5 (the host does).
    Both sources run the 258 + golden green and byte-identical (Homebrew 2.2.0 checked in S3); no CI exists yet.
  - **Consumer**: a throwaway package resolved `exact: "0.1.0"` from a `file://` clone, built in Debug with no unsafe-flag
    refusal, and called `QuantificationTables.bundled()` and `SpectrumImageOpener.open(path:kind:)` on velox-tiny
    (`openVelox` itself is `package`; `open(…, .veloxSpectrumImage)` is its public door).
    Result at `d26baf0`: `Package.resolved` 0.1.0; velox-tiny 2 x 3 x 8, 11 counts, 200 keV. The consumer must supply
    libhdf5 (here `MAC4DSTEM_HDF5_PATH`), as any host does.
  - ζ stays `package` (`ZetaFactor`, `AbsorptionCorrection.zeta`); the only validation value is
    `PooledQuantification.abundanceValidation = "none"`; S3 changed no validation line. LICENSE (GPL-3.0) and NOTICE (exSpy,
    HyperSpy, rsciio, EPQ, FFAST, Krause, HDF5) added; `Licenses/` holds HDF5's and libaec's texts.
- **S4 (mac4DSTEM, done)**: mac4DSTEM builds on SpectroKit 0.1.0 and its in-tree EDX copy is deleted (`2cbb216a`).
- **0.2.0 (this repo, 2026-10-14; ready for the owner's review and tag)**: macTEM's three asks
  (`../macTEM/docs/archive/spectrokit-asks-2026-10-13.md`) and the owner's sixth field. Hand-off for macTEM's session,
  with the steps rehearsed twice in scratch clones: `docs/macTEM-handoff-0.2.0.md`.
  - **DM4 API public** (access only): `DM4Experiment.readImage(path:index:)`, `readImage(data:index:)`, `tagTree(data:)`;
    `DM4Image`, `DM4Axis` and their fields; `DM4ImageObject`'s `name`, `dimensions`, `axes`, `metaDataFormat`,
    `imageTagNumbers`, `imageTagStrings`. With `public` read as `package` the file equals 0.1.0's and macTEM's copy apart
    from a 3-line header. The initializers, `readEDSSpectrumImage`, `spectroDisplayFileName` and the other object fields
    stay non-public.
  - **Six Velox fields** on `VeloxMetadata`, column 0, as stored (no unit conversion, no decoding, nil when absent or not a
    number by Swift's `Double(_:)`): `nominalMagnification`, `stemMagnification` (`CustomProperties.StemMagnification.value`,
    what RosettaSciIO maps as the magnification; the owner's, 2026-10-14; its `type` is not consulted, so the camera
    images' bool-typed "0", Velox's unset value, reads 0), `cameraLengthMeters` (metres), `operatingMode`, `projectorMode`
    (codes "1"/"2" in an `.emd`, not names), `exposureTimeSeconds`; and `VeloxDetectorInfo.exposureTimeSeconds`. The
    exposure is macTEM's rule (first entry by `Detector-<n>` index whose `DetectorName` equals `BinaryResult.Detector`;
    `DetectorIndex` never decides) applied with RosettaSciIO's matcher; it is not RosettaSciIO's `DetectorMetadata`.
  - **Bounded quit barrier** (macTEM ADR 021): the atexit handler waits `HDF5Serial.exitBarrierBound` (10 s, public
    read-only; `setExitBarrierBound` is `package`, for the tests) for the lock, then writes one stderr line and calls
    `_exit(70)`. It must be installed right after the first successful `H5open` (before it, a quit during an HDF5 call
    crashes: measured). A healthy operation longer than 10 s is cut too: a host's temp-file-and-rename write keeps its
    destination and leaves the temporary file. mac4DSTEM's longest holds (a tile read of up to physicalMemory/24 bytes,
    a sidecar rebuild) can pass 10 s on a slow volume; for mac4DSTEM's bump. `HDF5Types.swift` imports `Synchronization`.
  - **Golden**: `velox-tiny.txt` re-recorded on purpose, +13 nil lines (the per-detector exposure on 5 detectors and 2
    stream segments, the six metadata fields), 0 removed or changed; the other five files byte-identical. mac4DSTEM's
    `velox-tiny.txt` is the same blob as 0.1.0's and gains the same 13 lines on its bump (and its pins are three:
    `Package.swift`, `Package.resolved`, and the Xcode project's own requirement and `Package.resolved`).
  - **SpectroKitTests** (SpectroKit's own, apart from the 258 moved names): `HDF5ExitBarrierTests` (6: through the child
    process `SpectroHDF5ExitProbe`, an executable target that is not a product; the wait is measured from the child's own
    CLOCK_UPTIME_RAW stamp; the lock is checked held at the teardown; `velox-order` checks the real loader's order with
    libhdf5's `H5atclose`) and `VeloxMetadataFieldsTests` (26, public API only; inline JSON and
    `Fixtures/velox-metadata-planted.emd`, 12 images with a decoy column, regenerated byte-for-byte by
    `References/python-venv/bin/python -I tools/velox-metadata-parity/make_fixture.py` with h5py 3.16.0 / HDF5 2.0.0).
    Mutation controls: barrier 16 of 16, fields 35 of 35.
  - **Tools**: `tools/velox-metadata-parity/run.sh [--controls]` (the six fields against h5py and rsciio 049e7d70's pinned
    matcher on its public files, bit for bit: 1614 public values; six doc-comment claims; one documented deviation, on the
    planted file only; 11 of 11 controls; needs `References/`). `tools/consumer-check/run.sh [--controls]` (a separate
    package using every symbol 0.2.0 made public, Debug: 110 checks; 28 of 28 controls).
  - **Gates**: `tools/test.sh` at `5f0c707`, vendored libhdf5 2.1.1 and Homebrew 2.2.0: 258 / 0 (same names), golden
    byte-identical, SpectroKitTests 32 / 0, 0 warnings (cold build). 0.2.0 resolves by version from a `file://` scratch
    tag; a consumer builds no test target or probe. mac4DSTEM (sources `02437c27`) builds on it with 0 warnings and no
    collisions. macTEM rehearsed twice (unit 761 -> 740, exactly the 21 tests now here; every no-host gate green). Gate B:
    three Sonnet refuters, one per ask, all "pass with required fixes"; the fixes (three tests closing surviving
    mutants, doc corrections) are in.
  - **Build note**: `swift build --build-tests -c release` fails ("module built without -enable-testing") at `2ac3606`
    too, on this toolchain's Swift Build backend; `tools/test.sh` (`swift test -c release`) is the gate.
  - **Open**: the owner's tag and push; macTEM's bump (its session, from the hand-off); mac4DSTEM's bump (re-record its
    `velox-tiny.txt`, three pin places). Comment-only follow-ups Gate B noted: a few public DM4 doc comments still name
    mac4DSTEM internals (`gms.md`, `DM4Reader`); `DM4ImageObject`'s public `Equatable` compares package-only fields too.
- **Then**: the per-stage exSpy gates (counts, energy axis, background, peak ID, Cliff–Lorimer, ζ, absorption), which
  are also the diagnosis of why Auto ID misses Mg in 37 of 38 Al-Mg-Si files. Backlog item: `VeloxEMDReader` reads a
  plain Velox `Data/Image` dataset (macTEM ADR 004 D1).
- **After 0.2.0 (`main`, toward 0.3.0; 2026-10-14, the owner's order in the suite `ROADMAP.md`)**. What each consumer
  changes on its bump: `docs/consumers-0.3.0.md`.
  - **The split** (tier 3, byte-identical output): `SpectroCore` keeps the readers, the spectrum image and its opening,
    `EnergyAxis`, `MapSmoothing`, the statistics and the least-squares solvers (19 files); `SpectroEDX` (product and
    target, on `SpectroCore` only) takes the 35 X-ray files and the six tables (`SpectroKit_SpectroEDX.bundle`). No public
    declaration added, removed or re-signed (symbol graphs equal but for the module), four memberwise inits written out
    as `package` for the tests; the 258 names, the golden and instructions retired (±0.1 %) unchanged; one reviewer, pass.
    Shared things left in `SpectroEDX` for later: `PixelRect` / `PixelPoint` / `SpectrumRegionShape` (an EELS region mean
    will want them in Core) and `EnergyAxis.fitChannels`; Core's `EnergyAxis` is documented in keV but unit-free.
  - **EELS slice 1** (tier 1): `docs/eels-slice-1-registration.md` (registered before code, two dated amendments: the noise
    gate holds for fixed thresholds only, exSpy's estimated threshold being unstable on noisy data; the tie rule).
    `SpectroEELS`: `EELSThickness.logRatio` over a `LowLossSpectrumImage`, exSpy's log-ratio route ported exactly
    (SciPy's Savitzky-Golay in interp mode, NumPy's gradient and pairwise sum, HyperSpy's rounding, Iakoubovskii's λ and
    the angular correction), σ_counting with its limits, `validation: "none"`. Truth and pins: `tools/eels-thickness`
    (planted Poisson plural scattering with the method's own bias; exSpy's simulated line scan), fixtures in
    `Tests/SpectroEELSTests/Fixtures`. 55 tests; 79 of 83 mutants red, 4 equivalent. Open: 3 of 7 noisy tie pixels take
    another tie channel than exSpy (SpectroCore's `dgelsy` against SciPy's `dgelsd`, 1.3e-15; a `dgelsd` route is an
    option); the owner's EELS scans (`$MACEM_DATA/eels`) are diagnostics, never a gate.
  - **EELS slice 1b** (tier 2): `DM4Experiment.readEELSSpectrumImage` (public) and `DM4EELSSpectrumImage`, every count
    equal to RosettaSciIO's reading of its public `EELS_SI.dm4` and of a planted non-square file; 16 tests, 14 sampled
    mutants red. `tools/consumer-check` does not cover it yet.
  - **Still owed before 0.3.0 is ready for the tag**: one tier-2 refuter on the EELS reader and one Gate B refuter on
    SpectroEELS, side by side on the frozen commit (the split's tier-3 review is done); then the owner's tag.
