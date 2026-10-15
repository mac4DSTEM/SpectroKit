# SpectroKit 0.5.0: what the consumers change

> Update: the macOS 15 floor and the FormatoKit 0.2.1 pin described below as pending shipped in 0.5.1 (`CHANGELOG.md`).

Written 2026-10-15 by SpectroKit's 0.5.0 session, for mac4DSTEM's and macTEM's sessions. Both apps are on **0.4.0** (this
file is the record, so the apps are named). Nothing here was done in their repositories.

**0.5.0 is source-compatible with 0.4.0: every 0.4.0 call compiles unchanged, and with every new argument absent the numbers
are bit for bit 0.4.0's** (the 302 original test names unchanged, the golden byte-identical but for the one line family named
in section 3, `tools/consumer-check`'s 152 original checks compiling as before). For the apps nothing is required: the new
arguments are optional, and each default is the value 0.4.0 used. The version is a generality pass: the suite's policies
(constants a different lab could reasonably want differently) became public parameters, and the documentation was rebuilt so
a stranger can use the library from the README alone. The registration is `docs/generality-0.5.0-registration.md` (section 11
records what the code did to it).

## 1. New public API, per family (every default is 0.4.0's value)

Each type is `public`, `Sendable`, with a memberwise initialiser whose arguments default to the default value and a
`static let default`; its doc comments state each default, where it came from and the direction it pushes the result.
`WindowRules`, `QuantificationPolicy` (and `FitPolicy`, `AbundancePolicy`), `FlankMisfitGeometry`, `ElementContext` and
`UnlistedLineRules` are `Codable`; `ProposerPolicy` is `Equatable` only (`Currie` is not `Codable`: a decoder would bypass its
precondition).

| Family | Module | New public API | Where it is passed |
|---|---|---|---|
| `WindowRules` | SpectroEDX | integration and background window widths, the two background gaps, the conflict report's weight and flank, the K-family limit, clipping of overlapping windows | `ElementWindows.build(..., rules:)` (both overloads); `ElementWindows.defaultFamily(of:rules:)` (the old call forwards with `.default`) |
| `QuantificationPolicy` = `FitPolicy` + `AbundancePolicy` | SpectroEDX | fit range, continuum orders and edges, escape peaks, polynomial order, IRLS and axis-refinement options, escape-ratio warning; fallback reference, detector layers, absorption convergence, derivative step, single-line policy. `canonicalJSON`, `isDefault` | `PooledQuantificationInput.init(..., policy:)`; `FitSettings.standard(..., policy:)`; `FitRangeSensitivityCheck.run(..., alternativeToKeV:)` |
| `ProposerPolicy` | SpectroEDX | Currie rates, the candidate pool and exclusions, passes and rounds, minimum line energy, flank scaling and `FlankMisfitGeometry`, range margin, sum-peak tolerance, `ElementContext` | `ElementProposer.init(policy:)` (required label; the existing initialiser is unchanged) |
| `UnlistedLineRules` | SpectroEDX | distances beside a line and an edge, the move factor | `UnlistedLineChecker.neighbour(..., rules:)`, `.check(..., rules:)` |
| `SmoothingKernel` | SpectroCore | `.box(width:)`, `.gaussian(sigma:truncation:)`, `taps`, `isValid` | `MapSmoothing.apply(_:width:height:kernel:)`, `MapSmoothing.smoothingKernel` |
| EELS default window | SpectroEELS | the two offsets of the background window | `EELSEdgeQuantification.defaultBackgroundWindow(onsetEV:belowOnsetEV: = 50, gapEV: = 5)` |

**Package members made public** (they existed, tested, but a consumer could not reach them): `Currie.init(alpha:beta:)` (it
keeps its precondition, alpha and beta in (0, 0.5)), the `ProposalRules` fields, `IRLSSettings`, `AxisRefinementSettings` (with
`resolutionBoundsEV`), `DetectorLayers` (the four layers of the detector efficiency), `SingleLinePolicy`,
`ElementProposer.defaultPool` and `.defaultExcluded`.

**A non-default policy is named in the output.** A `QuantificationPolicy` that is not `.default` adds one line to
`PooledQuantification.footerLines`: `policy (non-default): path = value, ...`; a default adds none, so a default-path footer is
byte-identical to 0.4.0's. The policy is not stored on `PooledQuantification` (the golden walks every stored field, and the
registration keeps it unmoved): it reaches the code by argument. `QuantificationMethod` gained nothing, and its
`canonicalJSON` and hash are unchanged for every method recorded before.

## 2. Where defaults and shapes differ from the registration's first draft

Names and shapes only, none changes a default (section 11 of the registration has all eight): `WindowRules` holds the background
gaps as `backgroundGapLeft` and `backgroundGapRight`; `SmoothingKernel` is an enum; `ElementContext` words a grid or implanted
element other than Cu and Ga generically (Cu and Ga keep their exact sentences); `FitPolicy.continuumEfficiency` is realised
from the library's own FFAST table when no `QuantificationTables` is given. Four predictions were refuted and are recorded
where their tests sit: the 0.775 Gaussian fraction of a narrower window holds on 1 eV channels only (0.764 on 5 eV ones), a thicker Al layer lowers k_Mg / k_Si (the Al K edge lies between Mg Ka and Si Ka), the detector
efficiency in the continuum does not lower chi-squared at the default polynomial orders, and flank scaling off does not give a
smaller L_D.

## 3. The one behaviour change: the export's default title

`SpectroscopyExport.csv`'s default `title` was the app's name followed by "Spectroscopy quantification"; it is now the neutral
**"Spectroscopy quantification"**. A consumer that wants the old title passes it. A consumer that pins the CSV's hash moves: the
golden's 13 lines ending in `csv-fnv` (10) or `csv-withholding-fnv` (3) were re-recorded on purpose (before and after in the
commit message of `25a7bf5`) and nothing else in the golden moved. Nothing else in 0.5.0 changes a byte of output.

## 4. Documentation and examples

- `README.md` stands alone: installation, a quick start that quantifies an EDX spectrum (planted, or a Velox `.emd` / GMS
  `.dm4` EDS spectrum image given as an argument) and an EELS thickness quick start, with the output printed.
- `Examples/QuantifyEDX` is the first quick start as a package (`cd Examples/QuantifyEDX && swift run -c release`).
  `tools/consumer-check/run.sh` builds the README's code blocks as a second consumer, in Debug, and fails if the README and the
  example differ.
- A DocC catalogue per module (`SpectroCore`, `SpectroEDX`, `SpectroEELS`), each with one article.
- `docs/parity.md`: SpectroKit against exSpy's documented API, row by row, with the claims the source makes that the tests do not
  show.
- No source, test comment, tool or manifest names an app or the suite any more.

## 5. Tests

Swift Testing, **337 names**: the 302 of 0.4.0, unchanged, plus 35 for the four families (7 + 13 + 9 + 6). Two known issues,
the `EnergyAxisRefinement` finding (E3) as before. The golden is byte-identical but for section 3's 13 lines.
`tools/consumer-check`: 189 checks plus the README consumer, and 151 negative controls (the 136 of 0.4.0 plus 15 for the new
symbols). The new tests were each broken once: 61 mutants, 61 caught (the registration's G2 amendment, which also records the
four mutants that survived the first version of the proposer tests and the sharpening that followed).

## 6. The platform floor: still macOS 27, lowered at 0.5.1

0.5.0 keeps `platforms: [.macOS("27.0")]`. The reason is FormatoKit, not SpectroKit: FormatoKit's bundled libhdf5 dylibs are
built for macOS 26, so FormatoKit cannot declare 15 yet, and SpectroKit cannot declare a lower floor than its dependency's.
The chain:

1. **FormatoKit 0.2.1** rebuilds the dylibs for macOS 15 and declares `.macOS(.v15)`, `.iOS(.v18)`. The HDF5 and Velox readers
   are macOS-only at run time (iOS cannot `dlopen` bundled dylibs).
2. **SpectroKit 0.5.1** re-pins to it and lowers its own floor.

SpectroKit itself was measured to need no source change at 15: a release build and the 302 tests green against a 15 floor, no
availability branch; the iOS 18 simulator builds the three modules. An app that is on macOS 27 today changes nothing; an app
that wants to deploy lower waits for 0.5.1.

**Registered for 0.5.1:** FormatoKit's 0.1.x Velox dtype / title change comes in with the re-pin. It is a registered re-pin
at 0.5.1 (registered before the re-pin, with its own numbers), not part of this version.

## 7. What each app does

- **mac4DSTEM and macTEM (on 0.4.0): nothing required.** Bump to 0.5.0 when convenient; the pins are
  `.package(url: "https://github.com/mac4DSTEM/SpectroKit", exact: "0.5.0")` with FormatoKit still `exact: "0.0.3"` (0.5.0
  re-pins nothing). Optional: pass a policy where the app wants a value other than the default.
- An app that pins the export CSV's hash, or compares its text, moves (section 3), or passes the old `title`.
- An app that exposes a policy to its user should show `QuantificationPolicy.isDefault` and the footer line, so the user can
  see that a result used a non-default value.

## 8. Checks behind this note

Read from the 0.5.0 registration's amendments (the 2026-10-15 phase-2 and G2 entries and the coordinator's items), not re-run
for this note: `tools/test.sh` 337 names, 0 warnings; the golden byte-identical but for section 3; `tools/consumer-check` 189
checks, 151 of 151 controls.
