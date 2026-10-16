# SpectroKit: status

Updated 2026-10-16 for the 0.5.2 CI portability fix; the 0.5.0 gate below is historical. The source of truth for the state of the repo; the suite board shows it.

## Version and modules

**0.5.1**, ready for the owner's tag (0.5.0 is the last tag). Swift 6.2 tools, macOS 15 / iOS 18 floor, FormatoKit `exact: "0.2.1"`.

| Module | What it does |
|---|---|
| `SpectroCore` | The spectrum image (dense, sparse), its opening through FormatoKit's readers, `EnergyAxis`, counting statistics, least-squares solvers (C target `CSpectroLAPACK`), `SmoothingKernel`. |
| `SpectroEDX` | X-ray quantification: the line table, windows, the EDS model and fit, the element proposer, Cliff-Lorimer with computed k-factors, the absorption correction, export, the six EPQ / FFAST / Krause tables. |
| `SpectroEELS` | The t/lambda thickness by the log-ratio method; the C K areal density by the ratio method with the dft GOS tables. |

The file readers are FormatoKit's (a dependency pinned `exact: "0.2.1"` since 0.5.1; 0.0.3 before). 0.5.0 makes the suite's policies public parameters,
each default 0.4.0's value (`docs/generality-0.5.0-registration.md`).

## The gate at 0.5.0

- `tools/test.sh` (release, Swift Testing): **340 test names** (the 302 of 0.4.0, 35 for the policies, 3 for the Gate B fixes), **2 known issues** (the
  `EnergyAxisRefinement` finding, E3), 0 warnings; the golden byte-identical to 0.4.0's but for the 13 CSV-hash lines moved on
  purpose by the export's neutral default title.
- `tools/consumer-check/run.sh`: **189 checks** plus the README consumer (built from the README's code, drift-checked against
  `Examples/QuantifyEDX`), **151 negative controls** all caught.
- The new tests were each broken once: 61 mutants, 61 caught; the Gate B fixes 8 of 9 (the ninth equivalent, replaced and caught).
- Gate B (one refuter on `3bc197c`): no blocker; the default path byte-identical against 0.4.0 over 9 dump files and
  34 891 lines (fixtures, the public Velox files, the owner's 1.7 GB EDX SI, two EELS SIs); 0.4.0 call sites compile
  unchanged. Its two should-fix items (a nil or array policy field not named in the footer; the proposer's notes) are
  fixed (registration section 11).

## Validation

All EDX quantification and EELS thickness / areal density say `validation: "none"`. Agreement with exSpy is not truth; nothing
is validated until it recovers a planted value and a sample of known composition. zeta stays `package`.

## Where things are

- `docs/parity.md`: SpectroKit against exSpy 7185a4d1, row by row (BIT / TOL / DEV / PART / NOPIN / NO / NP), and the claims the
  source makes that the tests do not show.
- Registrations kept here: `docs/eels-slice-1-registration.md`, `docs/eels-slice-2-registration.md`,
  `docs/edx-stage-gates-registration.md`, `docs/generality-0.5.0-registration.md`.
- Consumer notes: `docs/consumers-0.3.0.md`, `docs/consumers-0.4.0.md`, `docs/consumers-0.5.0.md`.
- History, the real-data check and its registration, the 0.2.0 handoff: `../_archive/SpectroKit/docs/history.md` (and its
  neighbours in that folder).
- `References/` is a link to the suite's `../References/SpectroKit` (2026-10-15); gitignored.

## 0.5.2 CI portability fix

The macos-26 run at `0653404` had 120 unexpected issues across eight tests and two registered known issues.
[The audit](ci-parity.md) records measured ULP/relative gaps and missing operands. Commit `3577715` fixes the masked
CI gate status and the consumer target inventory's silent exit on an absent build backend directory.

The estimated-threshold source fix replaces Accelerate's Savitzky–Golay coefficients and edge fits with scalar QR,
then applies the documented automatic SG tie allowance. The pinned Python policy fixture covers 18 routes / 138 pixel
answers; 20 thresholds intentionally differ from raw exSpy. All original raw fixtures remain unchanged. Explicit-tolerance,
gradient, fixed-threshold and zero-loss routes retain their comparison rules. `ThresholdRule` DocC and the changelog explain
that previously computed estimated-threshold results may need recomputation.

The portable Golden comparison verifies each floating-point array element against companions proven to reproduce the
original baseline's hash and sum. Strings, integers, structure and CSV hashes remain exact. CI confirmation requires the
owner's push; this session does not push or dispatch CI.

Local verification: `tools/test.sh` green, 347 test names, zero unexpected issues and the two registered known issues;
`tools/consumer-check/run.sh` green, 189 API checks plus the README consumer. The 151 negative controls remain for CI.

## Open items

**The owner's**
- EDX Q1-Q5 (`docs/edx-stage-gates-registration.md` section 12), and the Mg fix, which waits on them: no EDX fix is registered
  until Q5 is answered.
- Enabling CI (Actions) and the tag for 0.5.0.

**Planned**
- EELS slice 3 (not started; `docs/parity.md` lists what a full EELS model would need).
- 0.5.2: resolve the macos-26 numerical portability failures (the CI investigation above); the API gaps below and the owner's EDX Q1-Q5 follow.

**0.5.1 (2026-10-15, ready for the owner's tag): the macOS 15 / iOS 18 floor.** FormatoKit `exact: "0.2.1"`; no source change
in `Sources/`. Proof: the gate (tools/test.sh) green (337 names, 2 known issues, 0 warnings), consumer-check green with 151 of
151 controls, the owner's EDX SI default path byte-identical to 0.5.0 (14 043 dump lines: open, summed spectrum, proposer,
pooled quantification), iOS 18 simulator builds of SpectroCore, SpectroEDX and SpectroEELS. CI: a `test-macos15` job (Xcode
26.0); the consumer-check silent exit fixed. `Test.cancel` removed from three tests (missing in Xcode 26.0). `CHANGELOG.md`.
Three EDX tests (E1 axis rule, C1 loop, C1 four-detector file) read RosettaSciIO's public Velox files from `References/` and return without
checking when it is absent (CI has none): they pass vacuously there; the gate on this Mac checks them.

**API gaps found by the README lane** (each is a fix that needs its own registration)
- `SpectrumDetectorSegment.init` is `package`.
- `ElementCandidate`'s `lists`, `possible` and `sumPeaks` are `package`.
- `EDSFitResult.degreesOfFreedom`, `PooledQuantification.referenceElement` and `FitSettings`' range fields are `package`.
- There is no `[UInt64]` overload of `ElementProposer.propose`: `counts.map(Double.init)` on a `[UInt64]` silently selects the
  wrong initialiser, so the README writes `counts.map { Double($0) }`.
- There is no `PooledQuantificationInput` builder from a `LoadedSpectrumImage`.

**Where the source claims more than the tests show** (from `docs/parity.md`; reword or add a test)
- `NumpySum.swift` says I_0 and I_t are bit for bit, while `ThicknessPinsTests` bounds them at 1e-12.
- `MassAbsorption.swift` says all 90 FFAST lists equal exSpy's; no test compares them (about 10 coefficients are pinned).
- The 947-row line table is checked on about 12 rows and the row count.
- The slice-2 registration's "bit-identical (0.0)" for n and the background, against tests bounding them at 1e-12 / 1e-10.
- `ElementWindows`' default line choice differs from exSpy's `add_lines` (`XRayLines.defaultLines` equals exSpy's and is
  `package`).
- The cross-section route of `ZetaFactor` has hand-recorded pins only.

**DocC**: two parameters undocumented: `axis` in `ElementProposer.swift`, `cancelled` in `EdgeQuantification.swift`.

**Wording left from the generality pass**: `SDDEfficiency.sourceName` says "not the owner's Super-X calibration" (pinned by
`SpectroscopyComputedKTests`; neutral wording needs that test's string changed too); suite-internal ADR numbers (054, 064) and
"the owner" remain in comments of `PooledQuantification`, `Continuum`, `SpectrumQuantities`, `FitRange`, `WindowIntensity`.
WindowRules, UnlistedLineRules and SmoothingKernel produce no notes or footer: a caller records a non-default value itself.
