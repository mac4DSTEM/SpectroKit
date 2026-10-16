# CLAUDE.md — start here

SpectroKit: the macEM suite's spectroscopy library, a Swift port of exSpy (EDS and EELS), imported by tagged version by
mac4DSTEM and macTEM. GPL-3.0, crediting exSpy. Modules: `SpectroCore` (spectrum image and its opening, `EnergyAxis`, statistics,
least-squares solvers; C target `CSpectroLAPACK`), `SpectroEDX` (X-ray quantification, the six tables), `SpectroEELS`
(thickness t/λ, the C K areal density). Since 0.4.0 the file readers are FormatoKit's (`FormatoDM`, `FormatoEMD`,
`FormatoHDF5`; `../FormatoKit`), a package dependency on `.upToNextMinor(from: "0.3.0")` (0.6.0; `exact: "0.2.1"` at 0.5.1; 0.0.3 before). The slot narrative, 0.2.0 details, measurements and the post-0.2.0 work are in `../_archive/SpectroKit/docs/history.md`.

## State (2026-10-15)

- 0.1.0, 0.2.0 (`edb6ba8`), 0.3.0 (`6ab9ec2`) and 0.4.0 tagged and pushed (0.4.0: the readers are FormatoKit's; the
  302 staying tests are Swift Testing).
- 0.5.0 (`c953e64`) tagged and pushed (the generality pass: the suite's policies are public parameters, defaults 0.4.0's;
  `docs/consumers-0.5.0.md`).
- **0.5.1 is ready for the owner's tag** (2026-10-15; the commit is named on the board row): macOS 15 / iOS 18 floor, FormatoKit
  `exact: "0.2.1"`, a `test-macos15` CI job (Xcode 26.0; no `Test.cancel`), the consumer-check fix; no number moves (the owner's
  EDX SI default path byte-identical to 0.5.0). `CHANGELOG.md`.
- Status, the gate's counts and the open items (EDX Q1-Q5 and the Mg fix, EELS slice 3, the README lane's API gaps, the
  parity lane's claims-versus-tests notes): `docs/status.md`.
- Earlier on `main`: EELS slice 2 (C K by the ratio method, refuted and fixed), the real-data check of the owner's EELS scans
  (R1, R2 bit for bit; C K vs GMS Pearson 0.985), the EDX stage gates and the Mg Gate D, CI (enabling Actions is the
  owner's), the rank test, the proposer about 7x faster.
- Registrations: `docs/eels-slice-1-registration.md`, `docs/eels-slice-2-registration.md`,
  `docs/edx-stage-gates-registration.md`, `docs/generality-0.5.0-registration.md`; the real-data check's is
  `../_archive/SpectroKit/docs/eels-real-data-check-registration.md`.

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
- **libhdf5** (0.4.0 on): FormatoKit ships 2.1.1 inside FormatoHDF5; the gate sets nothing (`MAC4DSTEM_HDF5_PATH`, when set,
  still overrides). Swift Build's three "not stripping binary because it is signed" lines are the only warnings allowed.
- **Green stamp**: a full, passing `tools/test.sh` run on a clean tree (no untracked file under Sources or Tests either) writes
  `.build/last-green` (commit, UTC time, libhdf5); `tools/last-green.sh` prints it and says whether HEAD equals it.
  `tools/test-names.py <log> .build/test-results/xunit-swift-testing.xml` lists the names a run passed or skipped.
- **Tests are Swift Testing** (`@Test func testX()`: the names stay the contract). A mutation campaign reuses one warm
  `.build` (never a cold build per mutant).
- **Hook**: `.claude/settings.json` runs `tools/hooks/no-sleep-poll.sh` before every Bash call; it refuses a sleep of 30 s or
  more, any `while`/`until` loop with a sleep in it, `killall`, and `pkill` without `-P <pid>` or a session-specific pattern
  (it matches text: write a commit message that names them to a file). Wait on background-task notifications or Monitor. Proof:
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
  explicit paths. The public DM4 API is access only; the 302 original test names (337 with 0.5.0's) and the golden files change only on purpose.
- **Suite board**: this repo's row is `lanes/spectrokit`; how a session opens and closes it is in `../CLAUDE.md`.
