# CLAUDE.md — start here

SpectroKit: the macEM suite's spectroscopy library, a Swift port of exSpy (EDS now, EELS later), imported by tagged
version by mac4DSTEM and macTEM. GPL-3.0, crediting exSpy. **Nothing is built yet.** This file is a pointer until the
bootstrap below replaces it with the library's full rules.

## Read first

1. macTEM's ADR 003, the plan: `../macTEM/docs/decisions/003-spectrokit.md` (`github.com/mac4DSTEM/macTEM`).
2. mac4DSTEM's ADR 064, its side: `docs/decisions/064-spectrokit-extraction-after-v5.md` in mac4DSTEM.
3. The survey of what moves: `../macTEM/docs/archive/mac4dstem-edx-survey-2026-10-12.md`.

## Hard rules until the bootstrap

- **No extraction before mac4DSTEM cuts v5.0.** The code comes from the v5.0 tag with its history (`git filter-repo`
  on a scratch clone, never mac4DSTEM's working tree). Until then mac4DSTEM owns the code and keeps changing it.
- **mac4DSTEM and macTEM are read-only from here**: `git -C ../<repo> --no-optional-locks show <commit>:<path>`.
  Never build, test or write in them.
- **Names** (the suite's standard): apps are `mac` + technique, libraries are domain + `Kit`, modules carry the
  library's prefix: `SpectroCore` (shared spectrum machinery), `SpectroEDX`, `SpectroEELS` (later).
- **A reference for every number**: exSpy `7185a4d1`, HyperSpy 2.4.0, NIST EPQ `249dd3f8` (mac4DSTEM's pins),
  fetched into the gitignored `References/`. The `exspy-main` there is unpinned and is never a reference. Agreement
  with exSpy is not truth: an at% is called validated only after it recovers a planted composition and a sample of
  known composition. Until then it self-reports `validation:"none"`.
- **Public at the first tag** (`0.1.0`), the owner's decision of 2026-10-12. Pushing and making it public are the owner's.
- One session per repo. `main` only, commit by explicit paths.

## The bootstrap: the first session after the v5.0 cut

1. Remove the tracked `.DS_Store` and add it to `.gitignore`.
2. Write this library's own `CLAUDE.md`, `run-tests.sh` and reference lock, adapted from macTEM's.
3. Extract `Core/Spectroscopy/` (not `Registration/`), `Core/Data/VeloxEMDReader.swift`, `Core/Data/HDF5Types.swift`,
   their tests and fixtures, from the v5.0 tag with history.
4. Write the `Package.swift`, give the API `public`, and make mac4DSTEM's 560 EDX tests pass here.
5. Tag `0.1.0`.
6. Gate each stage against exSpy: counts, energy axis, background, peak ID, Cliff–Lorimer, ζ, absorption. This is
   also the diagnosis of why Auto ID misses Mg in 37 of 38 Al-Mg-Si files.
7. First backlog item: `VeloxEMDReader` reads a plain Velox `Data/Image` dataset (macTEM ADR 004 D1).
