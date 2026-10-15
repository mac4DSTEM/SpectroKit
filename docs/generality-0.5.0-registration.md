# Generality pass 0.5.0, item b: every suite policy a parameter, today's value the default (registration)

Registered 2026-10-15, before any code, by SpectroKit's session (lane B of the 0.5.0 generality pass; main at `9b93fb4`, the
0.4.0 tag). Tier 1: a parameter that replaces a constant sits on the path of numbers a scientist reads (net counts, areas,
at%, L_D, areal densities). What is written here is fixed before the code; a change after code starts is an amendment, dated,
with its reason. Before this registration the only work was reading `Sources/` and the earlier registrations (this file's
inventory); no code, test or fixture changed. Phase 1 (this document) is inventory and registration; the code follows only
after the session reviews it.

## 1. Scope: what becomes a parameter, what does not

**The rule.** A *policy* is a constant, a switch or a rule that the suite chose, or tuned on one lab's data, rather than took
from the reference (exSpy `7185a4d1`, HyperSpy 2.4.0) or from physics, and that a different lab could reasonably want
differently. Each policy gets one of four statuses:

| status | meaning | work |
|---|---|---|
| A | already a **public** parameter with a default | document the default and where it came from; no code |
| B | a parameter exists but is `package`-only, or is not reachable from the public entry point that runs the number | make it public / thread it through; default unchanged |
| C | a literal in the code | new parameter; default is today's literal |
| N | not parameterised | reason in the table |

**What does not become a parameter, and why (status N).** (1) Values that *are* the reference's and define the method being
ported (the overlapping-window merge `_eds.py:833-843`, Cliff-Lorimer's `min_intensity` 0.1, the Iakoubovskii θ_C = 20 mrad,
exSpy's 10-channel minimum for the threshold search, the GOS tables and CODATA constants): changing one stops it being that
method, and the pins would no longer mean anything. (2) Detector physics (Si escape energies) and data sources (EPQ/FFAST/
Krause tables, the GOS): replacing one is a new feature with its own registration, not a constant. (3) Numerical guards
(rank and conditioning thresholds 1e-12 / 1e-10 / 1e-8, series tolerances, the 38 σ reach): they bound arithmetic, not a
scientific choice. (4) Refusals that protect against a silent wrong number (a pre-edge window outside the axis, an even
Savitzky–Golay window, σ_k = 0). (5) Definitions (the proposal bar is Currie's L_D; "possible" is above L_C), report-only
thresholds in `notes`, wording, and the algorithm's internals (Nelder–Mead's initial simplex, the refinement's
accept-if-the-residual-falls rule).

**Pooling.** The brief expected pooling rules (which pixels pool, floors). There are none in the kit: a pool is a mask the
caller passes to `SpectrumImage.sum(mask:)`, and `PooledQuantificationInput.counts` arrives already summed (`pixelCount` is a
label). Nothing to parameterise. Likewise the ratio method has no minimum-counts rule (a window sum ≤ 0 is a nil pixel, a
fact, not a threshold).

**Where a parameter lives.** One small public options struct per call family, each with a `static let default` whose fields
equal today's literals. Existing signatures keep working: the new argument is trailing with `= .default`, and where an
overload would be ambiguous (`ElementProposer.init`) the new initialiser has a required label. No struct, field or
doc comment names an app or the suite ("the suite's value" is for this registration only). A policy is **not** part of
`QuantificationMethod` (its canonical JSON and SHA-256 must not move for any method recorded before); it is a separate
`Codable` value with sorted-key `canonicalJSON` and `isDefault`, and a **non-default policy is named in the result's footer
lines** (a default policy adds no line, so every default-path footer is byte-identical).

## 2. Inventory

Origin: **ref** = exSpy/HyperSpy default, **syn** = measured on a synthetic generator (cited in the code), **own** = tuned or
read off the owner's files, **conv** = a convention (Currie, geometry), **suite** = a suite choice with no measurement.
Lines are at `9b93fb4`.

### 2.1 SpectroEDX, windows (`WindowRules`)

| id | policy | file:line | value | origin | st | proposed |
|---|---|---|---|---|---|---|
| W1 | integration window width, E ± W·F/2 | WindowIntensity.swift:137 (called unthreaded at SpectrumQuantities.swift:229) | W = 2.0 FWHM | ref (`estimate_integration_windows`) | B | `WindowRules.integrationWindowsWidth` |
| W2 | background gap `line_width` left, right | WindowIntensity.swift:51 | [2, 2] FWHM | ref (`estimate_background_windows`) | B | `WindowRules.backgroundLineWidth` |
| W3 | background `windows_width` | WindowIntensity.swift:51 | 1 FWHM | ref | B | `WindowRules.backgroundWindowsWidth` |
| W4 | conflict report: weakest table line considered | WindowIntensity.swift:240 | weight ≥ 0.01 | suite | B | `WindowRules.conflictMinimumWeight` |
| W5 | conflict report: flank of the other line | WindowIntensity.swift:263 | max(2 FWHM, half integration window) | conv | C | `WindowRules.conflictFlankFWHM` = 2 |
| W6 | default family: K while Kα ≤ limit, else L | SpectrumQuantities.swift:165 | 20 keV | own (one instrument's 200 kV file; vendor-software rule) | C | `WindowRules.kFamilyLimitKeV`; `ElementWindows.defaultFamily(of:rules:)` |
| W7 | two lines of one element: later window clipped | SpectrumQuantities.swift:259 | on | suite | C | `WindowRules.clipOverlappingWindows` |
| W8 | stand-in Mn Kα resolution when a file states none | SpectrumQuantities.swift:155 | 130 eV | suite (a Super-X-class detector) | A | document (public `defaultResolutionMnKaEV`, `resolutionMnKaEV:` argument) |
| W9 | overlapping windows of different lines merged | WindowIntensity.swift:70 | on | ref (`_eds.py:833-843`) | N | the reference's rule; windows widths (W1-W3) are the lever |

### 2.2 SpectroEDX, fit (`FitPolicy`)

| id | policy | file:line | value | origin | st | proposed |
|---|---|---|---|---|---|---|
| F1 | fit start | EDSFit.swift:61, PooledQuantification.swift:201 and 214, FitRange.swift:38 | 0.2 keV (keeps the zero-energy noise peak out) | suite ("a stated choice, not a measurement") | C | `FitPolicy.fitFromKeV` (one source for the four literals) |
| F2 | default upper limit | EDSFit.swift:43 | min(axis end, beam, 20 keV) | syn (WP3c E1: unbiased 11-60 keV, biased at 80) | C | `FitPolicy.defaultUpperLimitKeV` |
| F3 | continuum orders per segment | Continuum.swift:80 (not passed at EDSFit.swift:62) | (9, 5) | syn (one generator; "not a property of the method") | B | `FitPolicy.continuumOrders` |
| F4 | continuum split edges | Continuum.swift:78, 80 | [1.5596] keV (Al K) | tabulated | B | `FitPolicy.continuumEdges` |
| F5 | Bernstein basis, non-negative coefficients | Continuum.swift:80 | on | suite design | B | `FitPolicy.continuumNonNegative` |
| F6 | detector efficiency inside the continuum | EDSFit.swift:56 (`standard(efficiency:)` public, unreachable from `PooledQuantifier`) | none (Kramers only) | registered selection, tie unresolved | B | `FitPolicy.continuumEfficiency` (sources: nil or SDD layers, Q4) |
| F7 | Si-escape columns in the fit | EDSFit.swift:25 (public var; `PooledQuantifier` never sets it) | on | suite deviation from exSpy | B | `FitPolicy.escapePeaks` |
| F8 | polynomial background order bound | PooledQuantification.swift:212 (order itself is `method.polynomialOrder`, default 6 = exSpy, public) | clamp 0...8 | suite | C | `FitPolicy.maximumPolynomialOrder` |
| F9 | Poisson ML iteration (cap, tolerance, μ floor) | PoissonMLFit.swift:26-32; PooledQuantification.swift:216 | 200, 1e-9, 1e-6 | suite ("decides alone, recorded") | B | `FitPolicy.irls` (make `IRLSSettings` public) |
| F10 | Si-escape / parent flag | EDSFit.swift:307 | 0.05 | suite ("a sanity bound") | C | `FitPolicy.escapeRatioWarning` |
| F11 | axis refinement: which of offset, gain, width; cap; tolerance | EnergyAxisRefinement.swift:24-29 (`package`; `refine` called without options at PooledQuantification.swift:230) | all on; 600; 1e-12 | suite | B | `FitPolicy.axisRefinement` (make `AxisRefinementSettings` public) |
| F12 | refinement keeps the width in (lo, hi) | EnergyAxisRefinement.swift:76 | 20 < R < 500 eV | suite guard | C | `AxisRefinementSettings.resolutionBoundsEV` |
| F13 | range-sensitivity statement: the one alternative fit | FitRange.swift:158-160 | the axis reach | suite | C | `FitRangeSensitivityCheck.run(..., alternativeToKeV:)` (nil = reach) |
| F14 | standardised-residual floor | EDSFit.swift:88 | 1.0 | conv (HyperSpy-style) | N | definition of the reported residual |
| F15 | refinement accepted only if RSS falls | PooledQuantification.swift:238 | rule | suite logic | N | algorithm, not a constant |
| F16 | Nelder–Mead initial steps and coefficients | EnergyAxisRefinement.swift:94 | (5, 10, 5) units; 1, 2, ½, ½ | standard | N | internals |
| F17 | Si K edge 1.839 keV, Si Kα (escape energy) | EDSModel.swift:47 | Si | physics | N | another detector is a new model |
| F18 | numerical guards (rcond, rank, support, 38 σ reach) | FitLinearAlgebra.swift:103, 153; LinearDesign.swift:77; EDSModel.swift:110 | 1e-12, 1e-10, 1e-8, 38 | numerics | N | not scientific choices |

### 2.3 SpectroEDX, quantification (`AbundancePolicy`)

| id | policy | file:line | value | origin | st | proposed |
|---|---|---|---|---|---|---|
| Q1 | default relative σ_k | QuantificationMethod.swift:111 (duplicate `defaultRelativeSigma`, KFactorSource.swift:32, `package`) | 0.20 | own/vendor rule (20 %, flat) | A | document; make the duplicate read the same source |
| Q2 | absorption correction on | QuantificationMethod.swift:114 | on | suite | A | document |
| Q3 | reference element when none is typed | PooledQuantification.swift:303-309 | Al if quantified and measured, else largest net | suite | C | `AbundancePolicy.fallbackReference` (nil = largest net) |
| Q4 | computed-k detector layers (Au, Al, dead Si, Si) | SDDEfficiency.swift:24-27; used at PooledQuantification.swift:505 | 0 nm, 10 nm, 0 µm, 450 µm | ref (EPQ `getDefaultSDDProperties`) | B | `AbundancePolicy.detector` (`DetectorLayers`, public) |
| Q5 | absorption iteration: convergence (%), cap | PooledQuantification.swift:536 | 1e-7, 200 | suite deviation (exSpy 0.5, 30) | B | `AbundancePolicy.absorptionConvergencePercent`, `.absorptionMaxIterations` |
| Q6 | counting-term central-difference step | PooledQuantification.swift:571 | 1 % of the area (floor 1e-9) | suite | C | `AbundancePolicy.derivativeRelativeStep` |
| Q7 | fewer than two lines above `min_intensity` | CliffLorimer.swift:35 | refuse | suite deviation (exSpy: 100 %) | B | `AbundancePolicy.singleLine` (make `SingleLinePolicy` public) |
| Q8 | `min_intensity` | CliffLorimer.swift:27 | 0.1 | ref | N | the reference's number |
| Q9 | k-term: each k moved ±σ_k, quadrature; guard 1e-6 | PooledQuantification.swift:586-595 | method | suite method | N | method definition |
| Q10 | k-factor inputs: Bote-Salvat σ, Krause ω, EPQ weights, FFAST MACs | BoteSalvatCrossSection.swift, KrauseFluorescenceYield.swift | tables | data | N | data sources |

### 2.4 SpectroEDX, element proposer (`ProposerPolicy`) and unlisted-line check (`UnlistedLineRules`)

| id | policy | file:line | value | origin | st | proposed |
|---|---|---|---|---|---|---|
| E1 | Currie α, β | Currie.swift:25, 27 (`init` is `package`: the public `ElementProposer(currie:)` cannot be given another) | 0.05, 0.05 | conv (Currie 1968) | B | make `Currie.init(alpha:beta:)` public |
| E2 | candidate pool; default exclusion list | ElementProposer.swift:148-158 (`package`) | all table elements minus H, He, Li, Be and 15 radioactive or inert | suite | B | `ProposerPolicy.pool`, `.excluded`; `defaultPool`, `defaultExcluded` public |
| E3 | `maxPasses` | ElementProposer.swift:160 | 5 | suite | A | document |
| E4 | `maxForwardRounds` | ElementProposer.swift:160 | 24 | suite | A | document |
| E5 | `minimumLineEnergyKeV` | ElementProposer.swift:160 | 0.45 keV | syn (lane P: C K, N K, Ca L, Sc L false at ×100) | A | document |
| E6 | flank-misfit scaling of σ₀ | ElementProposer.swift:143 (`package var`) | on | suite | B | `ProposerPolicy.flankScaling` |
| E7 | flank-misfit geometry: flanks 1.5-6.5 FWHM from the line, 5 bins a side, bin 1 FWHM, ≥ 3 channels a bin, ≥ 3 bins | ElementProposer.swift:268-284 | as stated | suite | C | `ProposerPolicy.flank` (`FlankMisfitGeometry`) |
| E8 | a candidate's alpha line must lie ½ FWHM inside the fitted range | ElementProposer.swift:236-237 | 0.5 FWHM | suite | C | `ProposerPolicy.rangeMarginFWHM` |
| E9 | alpha line "on" a sum-peak energy within | LineConflicts.swift:46 (`package static let`) | 0.06 keV | own (half Mn Kα FWHM of one detector) | C | `ProposerPolicy.sumPeakToleranceKeV`; `LineConflicts.conflicts(..., toleranceKeV:)` |
| E10 | element context: Cu quantified by default, Cu hole-region check, Ga FIB conflict | ElementProposer.swift:438-451; LineConflicts.swift:71-78 | Cu, Cu, Ga | own (the owner's samples) | C | `ProposerPolicy.context` (`ElementContext`: `quantifyByDefault`, `gridElements`, `implantedElements`; the questions' wording stays generic) |
| E11 | R1-R3 cuts: Z ≥ 89, beside-K 1.5 FWHM, L/M corroboration 3 L_D, release 10 L_D; the four switches | ProposalRules.swift:47-60 (`package` fields) | `shipped`: R1 actinide half only | own (78 files of one operator; R2, R3, beside-K refuted or held) | B | make the fields public; document `shipped`, `registered`, `none` |
| E12 | refused elements H, He, Li, Be | LineConflicts.swift:89-98 | 4 | physics/window | N | no characteristic line or below any window |
| E13 | proposal bar is net ≥ L_D; "possible" above L_C | ElementCandidate | definition | conv | N | a definition |
| E14 | notes only: near-miss 0.5, inflation 1.005, weak-line note conditions | ElementProposer.swift:467-468; PooledQuantification.swift:406 | | wording | N | report-only |
| E15 | single-candidate fits per concurrent chunk | ElementProposer.swift:397 | 2 × cores | performance | N | no effect on numbers |
| U1 | candidate "beside a listed line" if within | UnlistedLineCheck.swift:211 | ±2 FWHM | conv (not a measured bar) | C | `UnlistedLineRules.besideLineFWHM` |
| U2 | candidate "beside a split edge" if within | UnlistedLineCheck.swift:214 | ±1 FWHM | conv | C | `UnlistedLineRules.besideEdgeFWHM` |
| U3 | a quantified net "moved" if abs(Δnet) exceeds | UnlistedLineCheck.swift:281 | 1 σ | conv | C | `UnlistedLineRules.moveSigmaFactor` |
| U4 | which edge belongs to which element (1 eV match) | UnlistedLineCheck.swift:223 | 0.001 keV | identity | N | not a choice |

### 2.5 SpectroCore

| id | policy | file:line | value | origin | st | proposed |
|---|---|---|---|---|---|---|
| M1 | map smoothing kernels and truncation | MapSmoothing.swift:19, 51 | box 3, box 5, Gaussian σ 1, σ 2 px; ±⌈2σ⌉ taps | suite (a menu) | C | `SmoothingKernel` (`.box(width:)`, `.gaussian(sigma:, truncation:)`), `MapSmoothing.apply(_:width:height:kernel:)`; the enum stays |
| M2 | Garwood confidence (`package` type, no public path) | CountingInterval.swift:32 | 0.95 | conv | N | nothing is reachable by a consumer |
| M3 | border renormalisation of the smoothing | MapSmoothing.swift:75 | on | design, documented | N | |

### 2.6 SpectroEELS

| id | policy | file:line | value | origin | st | proposed |
|---|---|---|---|---|---|---|
| L1 | thickness zero-loss threshold search (window, start, S-G window length, order, tolerance) | ThresholdRule.swift:33 | 10 eV, 1 eV, 5, 3, nil | ref (`estimate_elastic_scattering_threshold`, `_eels.py:641-643`) | A | document |
| L2 | ratio method: default pre-edge window relative to the onset | EdgeQuantification.swift:154 | [E_k − 50, E_k − 5] eV | suite (registration 2026-10-14; exSpy has none) | C | `defaultBackgroundWindow(onsetEV:belowOnsetEV:gapEV:)` with the two as defaulted arguments |
| L3 | edge window width Δ | EdgeQuantification.swift:183 | 50 eV | suite (pins also hold 30, 100, 150) | A | document |
| L4 | `coreLossToLowLossDose` | EdgeQuantification.swift:184 | 1 | neutral | A | document |
| L5 | default edge | EdgeQuantification.swift:178 | C K | suite | A | document |
| L6 | edge onset | EdgeQuantification.swift:179 | exSpy's table | ref | A | document |
| L7 | I_low route | EdgeQuantification.swift:177 | required, no default | | A | document |
| L8 | minimum threshold-search channels | ElasticThreshold.swift:36 | 10 | ref (`_eels.py:713`) | N | the reference's |
| L9 | θ_C of the mean free path | MeanFreePath.swift:48, 58 | 20 mrad | ref (Iakoubovskii) | N | model constant |
| L10 | GOS table, CODATA constants, γ = 1 + E0/511.06 | EdgeCrossSection.swift:19-21, 68 | | ref | N | data/reference |
| L11 | N K, O K carry a caveat | EdgeQuantification.swift:242 | | wording | N | |
| L12 | pre-edge window outside the axis refused; even S-G window refused | PowerLawBackground.swift:23; SavitzkyGolay.swift:142 | | safety | N | |

**Tally** is in section 10 (computed from this table when the registration was committed).

## 3. The API, per family (additive; every default is today's value)

All types are `public nonisolated struct ...: Sendable, Equatable, Codable` with memberwise public initialisers whose
arguments default to the default value, and `public static let default`. Doc comments state the default, its origin in the
words of the table's "origin" column (no app or suite names), and the direction each field pushes the result.

```
// SpectroEDX
WindowRules(integrationWindowsWidth: 2.0, backgroundLineWidth: [2, 2], backgroundWindowsWidth: 1.0,
            conflictMinimumWeight: 0.01, conflictFlankFWHM: 2.0, kFamilyLimitKeV: 20.0, clipOverlappingWindows: true)
  ElementWindows.build(..., rules: WindowRules = .default)           // both overloads
  ElementWindows.defaultFamily(of:rules:)                            // new overload; the old one calls it with .default
FitPolicy(fitFromKeV: 0.2, defaultUpperLimitKeV: 20, continuumOrders: [9, 5], continuumEdges: [1.5596],
          continuumNonNegative: true, continuumEfficiency: nil, escapePeaks: true, maximumPolynomialOrder: 8,
          irls: IRLSSettings(), escapeRatioWarning: 0.05, axisRefinement: AxisRefinementSettings())
AbundancePolicy(fallbackReference: "Al", detector: DetectorLayers(goldNm: 0, aluminiumNm: 10, deadLayerMicrons: 0, siliconMicrons: 450),
                absorptionConvergencePercent: 1e-7, absorptionMaxIterations: 200, derivativeRelativeStep: 0.01,
                singleLine: .refuse)
QuantificationPolicy(fit: FitPolicy, abundance: AbundancePolicy)     // Codable, canonicalJSON, isDefault
  PooledQuantificationInput.init(..., policy: QuantificationPolicy = .default)
  FitSettings.standard(..., policy: FitPolicy = .default)
  FitRangeSensitivityCheck.run(..., alternativeToKeV: Double? = nil)
ProposerPolicy(currie: .standard, pool: nil, excluded: <defaultExcluded>, maxPasses: 5, maxForwardRounds: 24,
               minimumLineEnergyKeV: 0.45, flankScaling: true, flank: FlankMisfitGeometry(innerFWHM: 1.5, binWidthFWHM: 1,
               binsPerSide: 5, minimumChannelsPerBin: 3, minimumBins: 3), rangeMarginFWHM: 0.5, sumPeakToleranceKeV: 0.06,
               context: ElementContext(quantifyByDefault: ["Cu"], gridElements: ["Cu"], implantedElements: ["Ga"]))
  ElementProposer.init(policy:)                                      // required label; the existing init is unchanged
UnlistedLineRules(besideLineFWHM: 2, besideEdgeFWHM: 1, moveSigmaFactor: 1)
  UnlistedLineChecker.neighbour(..., rules:), .check(..., rules: UnlistedLineRules = .default)
// public from package: Currie.init(alpha:beta:), ProposalRules fields, IRLSSettings, AxisRefinementSettings (+ resolutionBoundsEV),
//   DetectorLayers (SDDEfficiency's four layers), SingleLinePolicy, ElementProposer.defaultPool / defaultExcluded
// SpectroCore
SmoothingKernel.box(width: 3) / .gaussian(sigma: 1, truncation: 2);  MapSmoothing.kernel -> SmoothingKernel (box3 = .box(width: 3) ...)
// SpectroEELS
EELSEdgeQuantification.defaultBackgroundWindow(onsetEV:belowOnsetEV: = 50, gapEV: = 5)
```

Notes on the shape. (1) `QuantificationMethod` gains nothing. (2) `Currie.init` keeps its `precondition` (α, β in (0, 0.5)); its
doc comment says so. (3) The numbers behind `fitFromKeV` are today four literals; after the change one field feeds
`FitSettings.standard`, the polynomial path, `FitRangeChoice.fromKeV` and the refusal message (the refusal bound is
`fitFromKeV`, not 0.2). (4) `FlankMisfitGeometry` is written so that at the default every bin edge is computed by the same
floating-point expressions as today (a bin's low edge `inner + Double(b) * binWidth` equals `1.5 + Double(b)` exactly for the
integers involved; this is a claim of G1, not an assumption). (5) A non-default `QuantificationPolicy` adds one footer line,
`policy (non-default): <field = value, ...>`, to `PooledQuantification.footerLines`; the default adds none.

## 4. Claims and gates

**(G1) The default path changes nothing, bit for bit.** With every new argument absent or `.default`:
`tools/test.sh` passes with the same 302 test names (the new tests are additional names; no existing name removed or renamed),
the golden files are **byte-identical** (`SpectroGoldenTests`, no regeneration), every pin and fixture reproduces to its
registered tolerance (the `SpectroEDXTests` and `SpectroEELSTests` gates unchanged), and `tools/consumer-check` is green on
its existing 152 checks / 136 negative controls (0.4.0, `62466ad`; its call sites compile unchanged: source compatibility is checked by compiling
them) plus the checks added for the new API. In addition, for each family a new test calls the new entry point with an
explicit `.default` and compares with the old call: equal arrays (bitwise on `Double`), equal footers, equal
`PooledQuantification` rows. `QuantificationMethod.canonicalJSON` and `.hash` of a set of recorded methods are unchanged.
*Refuted if* any of these differs by one bit.

**(G2) Each new parameter moves the number the way the prediction below says.** Section 5 states, before code, for each
parameter whose status is B or C (and for A items that gain a new default function) the direction or exact value of the
change when a non-default value is given. Each is one tier-2 test (planted or constructed input, noise-free where an exact
prediction is made). **Each new test is broken once** by a mutation that makes it fail (the parameter ignored: the literal
put back; and, where the parameter feeds several places, one site reverted), recorded in an amendment. A prediction that
does not hold is recorded as refuted, with the number, and the parameter's doc comment says what it does instead.

**(G3) One Gate B refuter** on the frozen commit (a second only on a named doubt): a session that did not write the code,
given the code and this registration, hunts for (a) any default path that is not bit-identical (arithmetic reordered when a
literal became a field), (b) a literal left behind (a second copy of a constant that the policy no longer reaches), (c) a
parameter that is accepted and silently ignored, (d) a non-default policy that is not named in the footer, (e) API that breaks
a 0.4.0 call site.

**(G4) Documentation.** Every status A parameter and every field of the new structs carries a doc comment with its default
and where the default came from (table "origin"). Checked by reading, listed in the refuter's brief.

**Gate D** only if a discrepancy's cause is unproven. No fixture is regenerated.

## 5. Predictions (stated before any code)

Noise-free planted spectra unless said. "Exact" means equality to rounding.

| id | non-default value | predicted outcome |
|---|---|---|
| W1 | 2 → 1 | isolated Gaussian line on a flat continuum: signal channels shrink; the Gaussian fraction inside ±F/2 over that inside ±F, erf(1.177/√2) / erf(2.355/√2) = 0.7612 / 0.9817, so net / net(default) = **0.775 ± 0.01**; background windows unchanged (they are anchored to W2, W3) |
| W2 | [2,2] → [3,3] | the four background edges move outward by exactly F each (exact, `estimate`); on a convex decreasing continuum the net **falls** (the symmetric mean of two points overestimates the centre more the farther out) |
| W3 | 1 → 2 | windows twice as wide (channel counts ×2, scale ×½, exact); flat continuum: net unchanged to 1e-9 relative; a peak planted 3F above the line enters the wider right window and the net **falls** by that peak's counts × scale |
| W4 | 0.01 → 0.5 | `candidateLines` count **drops** and is monotone in the threshold; no candidate with weight < 0.5 remains (exact) |
| W5 | 2 → 1 | a candidate line 1.5 FWHM from a background window is reported at 2 and **not** at 1 (exact); overlap intervals shrink |
| W6 | 20 → 10 keV and → 25 keV | Zr (Kα 15.77 keV) defaults to L at 10, K at 25; Rh (Kα 20.22 keV) K at 25 (exact) |
| W7 | on → off | two checked lines of one element with overlapping signal windows: the later window is **not** clipped; the sum of the nets **exceeds** the clipped sum by the shared channels' net (exact) |
| F1 | 0.2 → 1.0 keV | fit channels start at the channel of 1.0 keV (count falls by 0.8 keV / scale, exact); footer reads "fit range 1–20 keV"; the refusal bound moves to 1.0 |
| F2 | 20 → 40 keV, 80 keV axis | `FitRangeChoice.toKeV` = 40, source `defaultLimit`; at 20 → 20 (exact) |
| F3 | (9,5) → (5,4) | on the planted roll-off spectrum the continuum has 11 coefficients not 16 and Pearson χ²_red **rises** (the WP3 selection found (5,4) leaves a misfit of up to 10 σ) |
| F4 | [1.5596] → [] (orders [9]) | no step at Al K: coefficient count 10; on a planted spectrum with a step at 1.56 keV χ²_red **rises** |
| F5 | true → false | RSS of the fit **does not exceed** the non-negative fit's (free-sign monomials span the same space as the Bernstein basis, a superset of the constraint set); label changes to "poly" |
| F6 | nil → SDD layers | continuum label gains "×ε(...)"; on a planted detector-rolled-off continuum χ²_red **falls** |
| F7 | true → false | on a planted spectrum with a Cu Kα escape peak, `escapeValues` all nil, Cu net shifts, χ²_red **rises**; at true the escape ratio recovers the planted fraction (existing behaviour) |
| F8 | bound 8 → 4, order 6 | the order used is 4 and the label says so (exact) |
| F9 | tolerance 1e-9 → 1e-3; cap 200 → 2 | iterations **do not exceed** the default's; with cap 2, `converged` false and `exit` "cap reached" (exact) |
| F10 | 0.05 → 0.001 | the escape-ratio warning appears on a spectrum whose planted ratio is 0.01 (and not at the default) (exact) |
| F11 | gain off; cap 600 → 3; tolerance 1e-12 → 1e-3 | gain shift is exactly 0; cap 3: `converged` false and `rssRefined` **not below** the default's; tolerance 1e-3: iterations **do not exceed** the default's |
| F12 | (20,500) → (120,140) | the refined width lies in (120,140) on a spectrum planted at 130 eV with a 5 eV shifted axis (exact); with (20,500) it is free |
| F13 | alternative 40 keV | the sensitivity statement reads "if fitted to 40 keV" and its fit used 40 keV (exact) |
| Q3 | "Al" → nil | the reference becomes the largest net; every k-free ratio is multiplied by net(Al)/net(largest) (exact) |
| Q4 | Al layer 10 → 1000 nm | k_Mg / k_Si **rises** (the efficiency at Mg Kα falls faster than at Si Kα, k ∝ 1/ε); the at% of Mg from fixed nets **rises**; `sourceName` carries the new thickness |
| Q5 | 1e-7 → 0.5 %; cap 200 → 1 | at% differs from the default by **more than 0 and less than 0.5 %** relative (the loop stops earlier); cap 1: `abundanceRefusal` set (did not converge) (exact) |
| Q6 | 0.01 → 0.1 | the counting σ of at% changes by a **nonzero amount below 5 %** relative (Cliff-Lorimer is nonlinear; the central difference error is O(h²)); at% itself unchanged (exact) |
| Q7 | refuse → exSpy 100 % | with one row's net ≤ 0.1: default sets `abundanceRefusal` (needTwoLines); parity gives 100 % / 0 % (exact) |
| E1 | α = β 0.05 → 0.01 | L_D for the same σ₀ **rises** (z 1.645 → 2.326); the number of proposed candidates **does not increase**; the notes name α = 0.01 |
| E2 | pool restricted; excluded [] | every candidate's element is in the pool (exact); with excluded [] the table elements Tc ... Xe join the pool when their lines lie in range |
| E6 | on → off | every candidate's `misfit` is exactly 1 and L_D **does not exceed** the default's |
| E7 | minimumBins 11 (> 10 available) | the guard fails everywhere, misfit exactly 1 (equals E6 off); innerFWHM 1.5 → 20: flanks outside the range, misfit 1 (exact); binsPerSide 5 → 3: misfit changes on a planted Al-tail spectrum |
| E8 | 0.5 → 0 | a group whose alpha line lies between 0 and ½ FWHM inside the range is **added** to the pool (group count +1, exact) |
| E9 | 0.06 → 0.005 keV | Ar at 15 eV from the Al+Al sum: the default names the "Al+Al sum or Ar?" conflict; at 0.005 no conflict is attached and the sum energy gets its own column (exact) |
| E10 | context emptied | Cu `suggestedRole` is `fitOnly`; no `holeRegionNote`; no `ga-fib` conflict on Ga (exact) |
| E11 | (fields now public) | a consumer-check call sets every field and the picks change as `ProposalRules` documents (existing tests already cover the logic) |
| U1 | 2 → 0.5 FWHM | a candidate 1 FWHM from a listed Al Kα, "unexplained excess beside Al Kα" at 2, an **element** candidate at 0.5 (exact) |
| U2 | 1 → 0.25 FWHM | a candidate 0.5 FWHM from a split edge: "excess beside the split" at 1, an element at 0.25 (exact) |
| U3 | 1 → 3 σ | the `moves` list is a **subset** of the default's; `largest` unchanged (exact) |
| M1 | box width 7; Gaussian σ 1.5, truncation 3 | a unit impulse in the interior becomes a 7 × 7 block of 1/49 (exact); the Gaussian kernel has 2⌈4.5⌉ + 1 = 11 taps and the interior total is conserved to 1e-12; `.box(width: 3)` equals `MapSmoothing.box3` bit for bit |
| L2 | (50, 5) → (80, 10) | `defaultBackgroundWindow(onsetEV: 284)` = 204 ... 274 (exact); the areal density from it differs from the default's on a planted image (the two-area estimate's own bias moves) |

## 6. Mutants planned (G2's "broken once")

For each new test one mutant, recorded in an amendment with the test that went red: the parameter's literal restored at its
use (the parameter ignored); and the second site of each literal that appears in more than one place (F1's four sites: the
refusal message, `FitSettings.standard`, the polynomial path, `FitRangeChoice.fromKeV`; W6's `defaultFamily` and the
`lineID` caller; E7's two flanks; Q6's lower and upper difference points). A mutant that stays green is reported and the test
is strengthened or the mutant shown equivalent, as in the slice-2 registration.

## 7. Order of work (after the session reviews this)

1. Windows (W1-W7), then FitPolicy (F1-F13), then AbundancePolicy (Q3-Q7), then proposer and unlisted-line rules (E1-E11,
   U1-U3), then SmoothingKernel (M1) and the EELS default (L2). One commit per family, each at a green gate; commit
   messages name tier 1.
2. Per family: failing tests from section 5 first (they fail to compile or fail because the parameter is absent), the
   code, the default-equivalence test, `tools/test.sh`, `tools/consumer-check`.
3. Then the status A documentation pass (W8, Q1, Q2, E3-E5, L1, L3-L7), the amendment with the mutants, the freeze, the
   refuter, `docs/consumers-0.5.0.md` additions (what a consumer may now pass; nothing it must change).

## 8. What is not claimed

Making a policy a parameter does not validate it: every EDX quantification and EELS thickness and areal density stays
`validation: "none"`, and the defaults keep the provenance printed in section 2 (several are tuned on one lab's data or one
synthetic generator and say so). A non-default value is the caller's responsibility and is named in the footer, not
checked. The pins prove the default path equals the reference; they say nothing about any other setting except the
predictions of section 5, which are about direction and structure, not accuracy. No new default is proposed in this pass,
and no value is changed. Parameters that the owner's data were used to choose (W6, E9, E10, E11, Q1) are not re-measured.

## 9. Items proposed not to be parameterised, for the session's decision

Rows marked N above, in particular: W9 (merge), Q8 (`min_intensity`), L8-L10, F14-F18, E12-E15, U4, M2, M3. If the
session wants Q8 or W9 exposed, the default is the reference's value and the cost is one more G2 test each.

## 10. Tally at registration

Counted from the tables of section 2 (one row = one policy):

71 policies found: **12** already public parameters with a default (A: document only), **18** parameters that exist but are
`package`-only or not threaded to the public entry (B: expose, default unchanged), **20** literals to become parameters (C),
**21** not parameterised (N). So 38 policies change code (B + C), each with one prediction in section 5 and one tier-2 test
(the 38 prediction rows), the 12 A items get documentation only, and the 21 N items get a reason. The brief's expected
pooling rules and the ratio method's minimum counts do not exist in the kit (section 1).
