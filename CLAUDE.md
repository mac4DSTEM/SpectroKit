# CLAUDE.md — start here

SpectroKit: the macEM suite's spectroscopy library, a Swift port of exSpy (EDS and EELS), imported by tagged version by
mac4DSTEM and macTEM. GPL-3.0, crediting exSpy. Modules: `SpectroCore` (readers, spectrum image, `EnergyAxis`, statistics,
least-squares solvers; C target `CSpectroLAPACK`), `SpectroEDX` (X-ray quantification, the six tables), `SpectroEELS`
(thickness t/λ so far). The slot narrative, 0.2.0 details, measurements and the post-0.2.0 work are in `docs/history.md`.

## State (2026-10-14)

- 0.1.0 tagged and public. 0.2.0 (macTEM's three asks) is tagged at `edb6ba8`.
- `main` goes toward 0.3.0: the split into the three modules, EELS slice 1 (`EELSThickness.logRatio`) and 1b
  (`DM4Experiment.readEELSSpectrumImage`). What each consumer changes on its bump: `docs/consumers-0.3.0.md`.
- 0.3.0 still owes: one tier-2 refuter on the EELS reader and one Gate B refuter on SpectroEELS, side by side on the frozen
  commit; then the owner's tag. The owner's EELS scans (`$MACEM_DATA/eels`) are diagnostics, never a gate.
- Registrations: `docs/eels-slice-1-registration.md`, `docs/eels-real-data-check-registration.md`.

## Read first

1. macTEM's ADR 003, the plan: `../macTEM/docs/decisions/003-spectrokit.md` (`github.com/mac4DSTEM/macTEM`).
2. mac4DSTEM's ADR 064 with both 2026-10-13 amendments, and ADR 066 (v5.0 has no microscope validation):
   `docs/decisions/064-spectrokit-v5-ships-on-it.md`, `docs/decisions/066-v5-no-microscope-validation-b-star-after.md`.
3. The suite's `../CLAUDE.md` (board, tiers, how we work) and `../ROADMAP.md`.

## Hard rules

- **mac4DSTEM and macTEM are read-only from here**: `git -C ../<repo> --no-optional-locks show <commit>:<path>`.
  Never build, test or write in them.
- **The gate is `tools/test.sh`** (`swift test -c release "$@"`). Never run `swift build --build-tests -c release` (fails on
  this toolchain). Debug is -Onone and 20-50x slower on hot paths and the manifest carries no Debug `-O` (a versioned
  dependency cannot carry unsafe flags), so a consumer builds SpectroKit optimised itself.
- **libhdf5**: the library ships none; a consumer must supply it. `tools/test.sh` takes, in order, `MAC4DSTEM_HDF5_PATH`;
  mac4DSTEM's vendored 2.1.1 by `git show` at `5ba712a0` into `.build/hdf5`; Homebrew `hdf5` (soname 320).
- **Green stamp**: a full, passing `tools/test.sh` run on a clean tracked tree writes `.build/last-green` (commit, UTC time,
  libhdf5); `tools/last-green.sh` prints it and says whether HEAD equals it.
- **Hook**: `.claude/settings.json` runs `tools/hooks/no-sleep-poll.sh` before every Bash call; it refuses a sleep of 30 s or
  more and any `while`/`until` loop with a sleep in it. Wait on background-task notifications or Monitor. Proof:
  `tools/hooks/test-no-sleep-poll.sh`.
- **A reference for every number.** Pins: exSpy `7185a4d1`, HyperSpy 2.4.0, NIST EPQ `249dd3f8`, rsciio `049e7d70`, all in the
  gitignored `References/` (`exspy-7185a4d1`, `rosettasciio`, `pyEELSMODEL-pin` at `eed9f0721d5b`). An unpinned copy is never
  a reference. Oracles run as `References/exspy-venv/bin/python -I -B` (HyperSpy 2.4.0, RosettaSciIO 0.14.0, Python 3.14.7).
  exSpy is not installed there: build its signal classes directly, as `tools/eels-thickness/pins.py` does. exSpy's GOS tables
  are in `~/Library/Caches/pooch`, by md5: `7fee8891c147a4f769668403b54c529b` (dft, `Segger_Guzzinati_Kohl_1.5.0.gosh`) and
  `01a855d3750d2c063955248358dbee8d` (`Dirac_GOS_compact.gosh`).
- **Validation.** Agreement with exSpy is not truth. All EDX quantification and EELS thickness stay `validation:"none"`;
  nothing is called validated until it recovers a planted value and a sample of known composition. Validation on real data is
  re-registered against a SpectroKit tag. ζ stays `package` (`ZetaFactor`, `AbsorptionCorrection.zeta`).
- **The owner's data** lives in the suite's `data/` folder, read as `$MACEM_DATA` (default `../data`): never copied or
  committed here; numbers measured on it are cited with their log; a manifest line in `data/README.md` per file used; using it
  as a gate or truth is a registration change first.
- **Names** (the suite's standard): apps are `mac` + technique, libraries are domain + `Kit`, modules carry the library's
  prefix: `SpectroCore`, `SpectroEDX`, `SpectroEELS`.
- **Public since 0.1.0.** Pushing, tagging and making things public are the owner's. One session per repo; `main` only; commit by
  explicit paths. The public DM4 API is access only; the 258 moved test names and the golden files change only on purpose.
- **Suite board**: this repo's row is `lanes/spectrokit`; how a session opens and closes it is in `../CLAUDE.md`.
