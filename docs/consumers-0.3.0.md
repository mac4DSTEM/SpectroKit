# SpectroKit after 0.2.0: what the consumers change on their next bump

Written 2026-10-14 by SpectroKit's session, for mac4DSTEM's and macTEM's sessions. `main` after `edb6ba8` (0.2.0) carries
three changes for the next tag, which is 0.3.0 (the module split is source-breaking for EDX users, and 0.1.0 and 0.2.0
exist):

1. **SpectroCore is split.** `SpectroCore` keeps what EDS and EELS share: the readers (`DM4Experiment`, `VeloxEMDReader`,
   `HDF5Serial`), the spectrum image and its opening (`SpectrumImage`, `SpectrumImageOpener`), `EnergyAxis`,
   `MapSmoothing`, the statistics and the least-squares solvers. Everything X-ray moved to a new module and product,
   `SpectroEDX`: the line table, windows, the EDS model and fit, the proposer, quantification, export, and the six
   EPQ / FFAST / Krause tables (now in `SpectroKit_SpectroEDX.bundle`; the bytes are unchanged). No public declaration
   was added, removed or re-signed; 411 public symbols changed module (the 42 top-level ones below). Output is
   byte-identical (the 258 moved tests and the golden baseline).
2. **SpectroEELS**, a new module and product: the t/λ thickness map by the log-ratio method, ported from exSpy 7185a4d1
   (`docs/eels-slice-1-registration.md`). Optional; nothing changes for an app that does not import it.
3. **`DM4Experiment.readEELSSpectrumImage`** in `SpectroCore` (public, additive): a DM4 EELS spectrum image with E0 and
   the convergence and collection semi-angles.

## mac4DSTEM

Found read-only at mac4DSTEM's HEAD by the split's reviewer; recheck at the bump.

- `Package.swift` (the targets that list `SpectroCore` today, lines 29 and 66): add
  `.product(name: "SpectroEDX", package: "SpectroKit")`, and bump the exact pin. `mac4DSTEM.xcodeproj` needs a matching
  `SpectroEDX` product dependency and build file for every target that links `SpectroCore` today, and its own pin
  (`project.pbxproj` requirement and the workspace `Package.resolved`).
- `import SpectroEDX` in every file that uses an EDX type (below); files that use both modules' types import both
  (`MemberImportVisibility` is on).
- Every target that calls `QuantificationTables.bundled()` (e.g. `SpectroscopyRoomController.swift:101`) must link the
  `SpectroEDX` product: with only `SpectroCore` linked, `Bundle.module` traps at run time (reproduced by the reviewer).
- `tools/lib/sources.manifest`, `spectrokit_module` (lines 119-127): build `--target SpectroEDX` as well, change the
  `-f $prod/SpectroCore.o` freshness test, add `$prod/SpectroEDX.o` to `SPECTROKIT_FLAGS` and point `SPECTROKIT_BUNDLE`
  at `SpectroKit_SpectroEDX.bundle`.
- The resource path moves to `.build/checkouts/SpectroKit/Sources/SpectroEDX/Resources/Spectroscopy`:
  `tools/lib/fetch-epq.sh:15` (`DEST`) fails hard without the change (its comment at :4 is stale);
  `tools/demo-edx/sim_edx.py` `DEFAULT_MAC` (line 48) silently stops finding `FFastMAC.csv`; `tools/demo-edx/run.sh:16`
  has the old path in a comment. The CSVs' sha256 are unchanged.
- `tools/run-tests.sh:79` passes `SWIFT_OPTIMIZATION_LEVEL=-O`, which reaches both package targets: the Debug-speed
  workaround needs no change.
- The golden `velox-tiny.txt` re-record of the 0.2.0 bump (+13 nil lines) is unchanged by these changes.

EDX types now in `SpectroEDX` (top-level public declarations): `ContinuumForm`; `EDSFitError`, `EDSFitResult`,
`FitSettings`; `EDSLineModel`, `FitLineGroup`; `AxisRefinementResult`; `FitBackground`; `QuantificationMethod`;
`ElementCandidate`, `ElementProposer`, `ProposalResult`, `ProposerError`; `LineConflict`, `LineConflicts`;
`ProposalRules`, `RuledProposal`; `DetectorEfficiency`; `FitRangeChoice`, `FitRangeSensitivity`,
`FitRangeSensitivityCheck`; `PooledQuantification`, `PooledQuantificationInput`, `PooledQuantifier`,
`QuantificationTables`; `QuantError`; `UnlistedLineCheck`, `UnlistedLineChecker`; `SpectroscopyExport`; `ElementWindows`,
`LineNetCount`, `LineWindow`, `PixelPoint`, `PixelRect`, `SpectrumRegionShape`; `ResolvedWindow`, `SpectralLineError`,
`WindowConflict`, `WindowIntensityError`; `XRayFamily`, `XRayLine`, `XRayLines`.

## macTEM

Nothing beyond the pin: its files that import `SpectroCore` use none of the EDX type names, and the sources its harness
reads (`HDF5Types`, `SpectroCancellation`, `VeloxEMDReader`, and from 0.2.0 on the three DM4 files) all stay in
`SpectroCore`. Its app no longer receives the six EDX tables (it never read them). EELS (`SpectroEELS`,
`readEELSSpectrumImage`) is there to import when macTEM wants it.
