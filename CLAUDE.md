# CLAUDE.md — start here

SpectroKit: the macEM suite's spectroscopy library, a Swift port of exSpy (EDS now, EELS later), imported by tagged
version by mac4DSTEM and macTEM. GPL-3.0, crediting exSpy. **Extraction in progress (S2).** This file is a pointer until
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

## The slots

- **S2 (this repo, now)**: `git filter-repo` extraction from `5ba712a0`, merge into `main`. `Package.swift`: one
  `SpectroCore` target for now, Swift 6 language mode, nonisolated default; the old `-DACCELERATE_NEW_LAPACK`
  `unsafeFlags` still present, only until S3. `Bundle.module` for the six CSVs; `#filePath` fixture paths. `swift test`
  passes exactly the 258 names. The golden baseline (mac4DSTEM's `SpectroGoldenTests`, recorded at `71929a01`) matches
  byte for byte for the scenarios the library can reach.
- **S3 (this repo)**: LAPACK C shim, no `unsafeFlags`; the Debug `-O` decision; a throwaway remote consumer resolves;
  ζ stays `package` (not public in 0.1.0); tag `0.1.0` locally.
- **S4 (mac4DSTEM)**: the switch to the tag.
- **Then**: the per-stage exSpy gates (counts, energy axis, background, peak ID, Cliff–Lorimer, ζ, absorption), which
  are also the diagnosis of why Auto ID misses Mg in 37 of 38 Al-Mg-Si files. Backlog item: `VeloxEMDReader` reads a
  plain Velox `Data/Image` dataset (macTEM ADR 004 D1).
