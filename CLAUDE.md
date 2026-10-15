# CLAUDE.md — start here

SpectroKit: the macEM suite's spectroscopy library, a Swift port of exSpy (EDS and EELS), imported by tagged version by
mac4DSTEM and macTEM. GPL-3.0, crediting exSpy. Modules: `SpectroCore` (spectrum image and its opening, `EnergyAxis`, statistics,
least-squares solvers; C target `CSpectroLAPACK`), `SpectroEDX` (X-ray quantification, the six tables), `SpectroEELS`
(thickness t/λ, the C K areal density). Since 0.4.0 the file readers are FormatoKit's (`FormatoDM`, `FormatoEMD`,
`FormatoHDF5`; `../FormatoKit`), a package dependency pinned `exact: "0.0.3"`. The slot narrative, 0.2.0 details, measurements and the post-0.2.0 work are in `../_archive/SpectroKit/docs/history.md` (archived).

## State (2026-10-15)

- 0.1.0, 0.2.0 (`edb6ba8`) and 0.3.0 (`6ab9ec2`) tagged and pushed. The apps skip 0.3.0 and bump once to 0.4.0.
- **0.4.0 is ready for the owner's tag** (2026-10-15; the commit named on the board row, after `c914b03`'s candidate and its
  Gate B; the tag is the signal for macTEM's EDX room and both apps' bumps):
  - SpectroKit depends on FormatoKit **0.0.3** by tag (`8d647bd`, public); `DM4Experiment`, `VeloxEMDReader`, `HDF5Serial`
    and their 121 tests left SpectroCore; `SpectroCancelled = FormatoCancelled` (typealias), `SpectroCancellation` stays
    SpectroCore's own enum; no re-export of the Formato modules. libhdf5 is FormatoKit's shipped 2.1.1 (sha256 equal to
    mac4DSTEM `5ba712a0`'s).
  - The 302 staying tests are Swift Testing (Apple's modernize-tests mapping; same names, same outcomes, `isEqual(accuracy:)`
    is XCTest's rule). FormatoKit 0.0.3 made public the five Velox members SpectroEDXTests read (the 0.0.2 stand-ins are
    gone) and takes the Velox detectors in written order (the detector-order test passes without its `withKnownIssue`).
  - Gate on 0.0.3: 190 + 76 + 32 (2 known issues: the `EnergyAxisRefinement` finding) + 2 golden (recorder skipped) + 2, 0
    warnings except FormatoKit's three signed-dylib notices; consumer-check and a cold build as the history records. Gate B
    (on the 0.0.2 candidate `c914b03`): no blocker, no should-fix; 45 runs of one consumer source against `301f1eb` (and
    0.3.0 on its API) byte-identical, the owner's 1.7 GB Velox EDX SI and all 14 EELS DM4s included (`../_archive/SpectroKit/docs/history.md` (archived)).
  - What each app changes: `docs/consumers-0.4.0.md` (imports, products, scripts, one HDF5 lock per process, the three
    libhdf5 options until the owner decides).
- Open, the owner's: EDX Q1–Q5 (`docs/edx-stage-gates-registration.md` section 12); no EDX fix is registered until Q5. The
  Velox detector-order finding is fixed in FormatoKit 0.0.3.
- Earlier on `main`: EELS slice 2 (C K by the ratio method, refuted and fixed), the real-data check of the owner's EELS scans
  (R1, R2 bit for bit; C K vs GMS Pearson 0.985), the EDX stage gates and the Mg Gate D, CI (enabling Actions is the
  owner's), the rank test, the proposer about 7x faster.
- Registrations: `docs/eels-slice-1-registration.md`, `docs/eels-slice-2-registration.md`,
  `docs/edx-stage-gates-registration.md`.

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
  explicit paths. The public DM4 API is access only; the moved test names (190 since 0.4.0) and the golden files change only on purpose.
- **Suite board**: this repo's row is `lanes/spectrokit`; how a session opens and closes it is in `../CLAUDE.md`.
