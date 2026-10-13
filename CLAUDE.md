# CLAUDE.md — start here

SpectroKit: the macEM suite's spectroscopy library, a Swift port of exSpy (EDS now, EELS later), imported by tagged
version by mac4DSTEM and macTEM. GPL-3.0, crediting exSpy. **0.1.0 tagged locally (S3 done); S4 (mac4DSTEM) next.** This file is a pointer until
the library's own full rules replace it.

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
  (mac4DSTEM's pins), fetched into the gitignored `References/`. The `exspy-main` there is unpinned and is never a
  reference. Agreement with exSpy is not truth: an at% is called validated only after it recovers a planted composition
  and a sample of known composition. Until then it self-reports `validation:"none"`.
- **Names** (the suite's standard): apps are `mac` + technique, libraries are domain + `Kit`, modules carry the
  library's prefix: `SpectroCore` (shared spectrum machinery), `SpectroEDX`, `SpectroEELS` (later).
- **Public at the first tag** (`0.1.0`), the owner's decision of 2026-10-12. Pushing and making it public are the owner's.
- One session per repo. `main` only, commit by explicit paths.
- **Suite board** (`https://claude.ai/artifact/EdMG2EVb6t9ah3SmbrVykv`): at closeout, update only this repo's row, document
  `lanes/spectrokit`, with `ArtifactData` `update` pinned to the version just read: `step` {label, status
  done|running|next|blocked|waiting, detail}, `now`, `next`, `waitsOn`, `session` (open|idle), `head`, `unpushed`, `tests`,
  `waiting` (the owner's to-dos), `done` (newest first, {date, text, ref}), `open`, `updatedAt` (UTC ISO), `updatedBy`.
  A cloud routine refreshes every row from GitHub at 07:00 Berlin; it never touches `session` or `unpushed`.

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
- **S4 (mac4DSTEM)**: the switch to the tag.
- **Then**: the per-stage exSpy gates (counts, energy axis, background, peak ID, Cliff–Lorimer, ζ, absorption), which
  are also the diagnosis of why Auto ID misses Mg in 37 of 38 Al-Mg-Si files. Backlog item: `VeloxEMDReader` reads a
  plain Velox `Data/Image` dataset (macTEM ADR 004 D1).
