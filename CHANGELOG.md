# Changelog

SpectroKit follows semantic versions (0.x). Each release says what changed, and what a consumer must do (Migration).

## 0.8.2 (2026-10-21) — the pooled fit's k, line energies and take-off angle are public

Additive public API; no number moves. An app can now build a per-pixel `EDXQuantificationSetup` (`quantify`, `quantifyMaps`) from the very k-factors, line energies and detector geometry the pooled fit used, computed k and absorption included.

- `PooledQuantification.kFactors: [PooledKFactor]?` (element, k relative to the fit's reference, relative sigma) in the rows' order, for computed and typed k; nil when no at% was computed. `kFactorSourceDescription` names the source.
- `PooledQuantification.Row.lineEnergyKeV`: the energy of the fitted line, the `EDXAbsorptionSetting.lineEnergiesKeV` entry.
- `EDXQuantification.takeOffDegrees(metadata:)`: the solid-angle-weighted mean take-off angle of the file's detector segments (shadow fractions applied), for `EDXAbsorptionSetting.takeOffDegrees`; throws the pooled fit's own reason (no tilt, a segment without geometry, GMS).
- Deviation to know: the pooled fit averages the transmission over the four segments, the per-pixel call takes one angle, so a map with absorption differs slightly from the pooled number. Both stay `validation: "none"`.
- Tests: `EDXQuantificationInputsTests` (the k reproduces the fit's own wt% through `quantify`, typed and computed; the line energy; the weighted take-off; the refusals).

### Migration
None; nothing is removed or renamed. An app that held the k or the geometry itself can read them from the fit now.

## 0.8.1 (2026-10-21) — quantification pins at exSpy's tolerance

Tests, fixtures and documentation only; no source change and no number moves.

- The absorption runs of `everyRunMatchesExspy` were pinned at 1.0 percentage point; they are now pinned at exSpy's own atol 1e-3 (the per-pixel iteration agrees with
  exSpy's image-wide one to better than 1e-9 on the 36 runs), which makes the 0.8.0 sentence "at exSpy's test tolerances" true. Mass thickness and atoms with
  absorption were rtol 1e-2 and are now rtol 1e-5 (exSpy's cross-section atoms come from the iteration before its last composition update, 4e-6 apart on pixel 0).
- Cross-section mass thickness is now pinned: exSpy returns none, so `tools/edx-quant-maps/pins.py` records exSpy's own `get_abs_corr_cross_section` total-mass
  formula on exSpy's atoms (the fixture gained that field; nothing else in it changed).
- Every quantification result still says `validation: "none"` (no standard of known composition has been measured, `docs/open-items.md` 7); a test asserts it on
  both `quantify` and `quantifyMaps`.
- Added `docs/status.md`.

### Migration
None.

## 0.8.0 (2026-10-21) — public EDX quantification, parity audit, benchmarks

Additive public API; no existing number moves.

- `EDXQuantification.quantify` and `.quantifyMaps` (SpectroEDX): Cliff-Lorimer with typed k-factors, zeta-factor and ionisation cross-section quantification, each with
  or without the absorption iteration, on one spectrum's line intensities or per pixel over a spectrum image: `navigationMask`, weight and atomic percent maps, mass
  thickness, atoms, per-pixel live-time dose, parallel over pixels. Neutral input types (`EDXQuantificationSetup`, `EDXQuantificationMethod`, `EDXAbsorptionSetting`);
  no region name or file path. Also public: `EDXQuantification.takeOffAngle`, `.weightToAtomic`, `.atomicToWeight`, `.zetaFactors(fromCrossSectionsBarn:)`,
  `.crossSectionsBarn(fromZetaFactors:)`, and `LineConflict.init`. Pinned against 36 runs of exSpy 0.3.2's own `quantification` at exSpy's test tolerances
  (`tools/edx-quant-maps`). Results say `validation: "none"`.
- `SpectrumImageMetadata.sameScanAs4DCube` is renamed `sameScanAsCube`; the old name stays as a deprecated alias. The golden baselines moved with the rename (own commit).
- `docs/parity.md` rewritten from the exSpy 0.3.2 source (state, priority, upstream tolerance per row), `docs/benchmarks.md` and `tools/benchmarks` added, `docs/open-items.md` added.
- Dependency range unchanged (FormatoKit `0.4.0..<1.0.0`); FormatoKit is not bumped by this release.

### Migration
None required. Replace `sameScanAs4DCube` with `sameScanAsCube` to drop the deprecation warning. An app that reached `CliffLorimer`, `ZetaFactor` or `AbsorptionCorrection` by
`@testable import` can move to `EDXQuantification`; those types stay `package`.

## 0.7.1 (2026-10-21) — FormatoKit range widened to 0.4.0 up to 1.0.0

Dependency range only; no source change, and no SpectroKit API or number moves.

- FormatoKit is now `"0.4.0"..<"1.0.0"` (was `"0.4.0"..<"0.6.0"`), so an app can pin FormatoKit 0.6.x or 0.7.0 beside SpectroKit. FormatoKit is the only dependency.
  Tested against FormatoKit 0.7.0.

### Migration
None. An app pinning FormatoKit 0.6.0 or later re-pins SpectroKit to 0.7.1.

## 0.7.0 (2026-10-20) — FormatoKit 0.4.x and 0.5.x

Dependency range only; no source change, and no SpectroKit API or number moves.

- FormatoKit is now `"0.4.0"..<"0.6.0"` (was `"0.3.0"..<"0.5.0"`): 0.3.x is dropped, 0.5.x added. FormatoKit 0.5.0 adds `HDF5Reader`,
  `HDF5AppendWriter`, `TIFFAppImage` and new `HDF5FileError` cases (source-breaking only for an exhaustive switch over `HDF5FileError`;
  SpectroKit has none).
- Test fixture: `velox-tiny.txt` of the golden test regenerated. FormatoKit 0.3.1 and later add four optional `VeloxMetadata` fields (`stageXMeters`,
  `stageYMeters`, `stageZMeters`, `instrumentClass`) that the golden dumps; additive lines only, 251 to 255 lines, no SpectroKit number moves.
  Tested against FormatoKit 0.4.0 and 0.5.0.

### Migration
Consumers on FormatoKit 0.3.x stay on SpectroKit 0.6.0. An app pinning FormatoKit 0.4.0 or 0.5.0 exact uses SpectroKit 0.7.0; re-pin SpectroKit to 0.7.0.

## 0.6.1 (2026-10-20) — FormatoKit range 0.3.x and 0.4.x

Dependency range only; no source change, and no SpectroKit API or number moves.

- FormatoKit is now `"0.3.0"..<"0.5.0"` (was `.upToNextMinor(from: "0.3.0")`). FormatoKit 0.4.0 only repackages libhdf5 as XCFrameworks, so
  an app that embeds FormatoKit 0.4.0 can still resolve SpectroKit.

Tests only: `LineTableParityTests` pins all 947 rows of the X-ray line table against exSpy 7185a4d1's own loader (was about 12 rows); no deviation found.

Correction (found 2026-10-20): the golden test `testOutputsAreByteIdenticalToTheBaseline` (the 0.6.1 fixture) fails against FormatoKit 0.3.1, 0.4.0 and 0.5.0 (measured: it passes against 0.3.0, fails against 0.3.1 and 0.4.0 with "velox-tiny: line count changed from 251 to 255", the new optional Velox metadata fields; 0.5.0 likewise). Fixed at 0.7.0, which needs FormatoKit 0.4.0 or later.

### Migration
None. An app that pins FormatoKit 0.4.0 exact must use SpectroKit 0.6.1 or later; re-pin SpectroKit to 0.6.1.

## 0.6.0 (2026-10-16) — FormatoKit as a minor range

Dependency range only; no source change was needed against FormatoKit 0.3.0, and no SpectroKit API or number moves.

- FormatoKit is now `.upToNextMinor(from: "0.3.0")` (was `exact: "0.2.1"`), the standard SwiftPM practice for a library, so an app
  that pins exact kit tags resolves one FormatoKit without lockstep releases. FormatoKit 0.3.0 is additive, and its
  FormatoTIFF target now depends on FormatoDM.

### Migration
Consumers must use FormatoKit 0.3.x (any 0.3.y satisfies the range); a consumer still on FormatoKit 0.2.x must move to 0.3.x.
Re-pin SpectroKit to 0.6.0.

## 0.5.4 (2026-10-16) — CI fix

0.5.3 was tagged with red CI. The Golden and unit tests passed on both jobs; the failure was the consumer check's negative
controls on the newest-Xcode job (Swift 6.3.3): 96 of the 151 access controls reported "no note ... declared here". The
controls require the compiler's note beside `error: '<member>' is inaccessible due to 'package' protection level`, and
looked for Swift 6.4's module-qualified form (`SpectroCore.<Owner>.<member>:2:13: note:`) only; Swift 6.3 names the edited
file by path. No library or test number moves.

- **Consumer-check controls.** `controls.py` accepts a path-form note (Swift 6.3's format, unverified until the next CI run) as well as
  the module-qualified one (a path ending in the edited file), still requiring the member's own name in the note and the edited file; a note in another file is refused. On a miss it prints up to 5 compiler note lines naming the member.
  `test_judge.py` pins the three cases and runs before the controls in `run.sh --controls`.
- **Migration.** None. Re-pin to 0.5.4 in place of 0.5.3, which was tagged with red CI.

## 0.5.3 (2026-10-16) — CI fixes

0.5.2 was tagged at 9de71e9 with red CI: both jobs (macos-15 and the newest Xcode) failed in
`SpectroGoldenTests.testOutputsAreByteIdenticalToTheBaseline`, 26 and 20 records. This release is the fix, plus an additive API:
no existing number moves.

- **Golden scalar bound.** The runners' CPUs (Accelerate paths) moved small cancellation-conditioned scalars (relative
  atomic/weight counting terms, unlisted-candidate and sum-peak nets) by up to 3.2e-10 relative, past the 1e-12 relative scalar
  bound that was measured on developer machines. The scalar bound is now 1e-9 relative (the stated ceiling for roundoff; a gap
  above it is a defect, not a tolerance). Array elements stay at 1e-12 of the pinned peak; text, integers, structure and hashes
  stay exact. The baselines and companions are unchanged, nothing was regenerated from CI, and the deterministic tie rule is untouched.
- The 0.5.2 type-check fixes (QuantificationPolicyTests, SpectroscopyFitTests) are listed under 0.5.2 below.

- **Registration.** `GridRegistration`, `MaskTransport` (area-overlap label transport from the scan grid to the spectrum grid) and
  `PoolBuilder` (pooled counts and grouping), ported from mac4DSTEM's Registration code. Oracle: a NumPy transcription of the app
  source (`tools/registration/pins.py`, not exSpy); labels, ties and counts exact, overlaps within 2e-12 pixel areas (measured gap 0).
  Additive; pools stay `validation: nil`/unvalidated. Unlike the app, `MaskTransport.region` and `PoolBuilder.pool` throw
  `MaskTransportError` on invalid input instead of trapping. Fixture includes exact, within-1e-6 and beyond-tolerance ties.
- **Migration.** Nothing required: the registration API is additive, and the Golden scalar bound (now 1e-9 relative) is test-side only. Re-pin to 0.5.3 in place of 0.5.2, which was tagged with red CI.


## 0.5.2 (tagged with red CI; fixed in 0.5.3)

- **Golden portability.** Original scalar values and array hashes are retained. CPU-dependent fitted scalars use a stated
  1e-12 relative bound (1e-9 from 0.5.3); each floating-point array element uses 1e-12 of the pinned array peak. Compact companions were
  expanded only after all six developer dumps matched the original baseline byte for byte, and a regression verifies
  their original counts, hashes and sums. Text, integer, structure and CSV hash comparisons remain exact.

- **Portable estimated EELS thresholds.** The Savitzky–Golay solve stays on LAPACK's SVD, as in SciPy's `savgol_coeffs`.
  Automatic SG tolerance treats derivatives within `64 eps * peak cropped input * coefficient L1` as tied and chooses the
  first channel. This intentionally changes 20 of 138 pinned policy pixel answers from raw exSpy, preventing small CPU
  rounding changes from producing large thickness changes. Explicit tolerance and gradient comparisons remain exact.
  The unchanged raw SciPy/exSpy fixtures remain as evidence; a new pinned Python policy fixture records the changed channels.
- **Migration.** Recompute results obtained with `.estimated()` if numerical ties matter to the analysis. Record the library
  version with those results. Fixed thresholds and the zero-loss spectrum route retain their existing values. No API change.

- **CI diagnostics and shell fixes.** The main gate now propagates a failing `swift test` status through `tee`. The consumer
  target inventory tolerates either absent build backend directory under zsh `errexit`. Swift Testing regressions cover
  both failures. The macos-26 numerical audit is in `docs/ci-parity.md`; the original raw reference fixtures are retained.

- **CI: the macos-15 job failed with a type-check timeout.** `QuantificationPolicyTests.swift` had one `#expect` whose
  expression (two closures in a comparison) the Xcode 26.0 compiler could not type-check in reasonable time. The sums and the
  slack are now typed `let`s; the assertion and its tolerance are unchanged. Test code only; no library number moves.
  The planted-spectrum closure in `SpectroscopyFitTests.swift` (the tail-shape test) likewise has an explicit `(i: Int) -> Double` signature and typed lets; same arithmetic, same order, same values.

## 0.5.1 — macOS 15 / iOS 18 floor

- **Platforms.** `Package.swift` declares `.macOS(.v15)` and `.iOS(.v18)` (0.5.0: macOS 27). SpectroKit needed no source
  change for it: there is no availability branch anywhere in `Sources/`.
- **FormatoKit** is pinned `exact: "0.2.1"` (0.5.0: `0.0.3`). FormatoKit 0.2.1 rebuilds its bundled libhdf5 dylibs for macOS 15,
  which is what lets the floor come down. FormatoKit's 0.1.x Velox changes (stored dtype, RosettaSciIO's titles) come in with
  the pin; no SpectroKit number moves (below).
- **No number moves.** The default path on the owner's EDX spectrum image (open, summed spectrum, proposer, pooled
  quantification, 14 043 lines of full-precision dump) is byte-identical to 0.5.0's; the golden CSV hashes and every pinned
  fixture pass unchanged.
- **CI.** A `test-macos15` job (macos-15, Xcode 26.0, Swift 6.2) runs the gate at the new floor. The consumer check no longer
  exits silently when `.build/debug` is absent (a `find` under `pipefail`), which failed the macos-26 job.
- **Tests.** The three `Test.cancel` skips (the public Velox files, absent without `References/`) are a printed note and an
  early return: `Test.cancel` is missing from Xcode 26.0's Swift Testing. The test names are unchanged.
- **Migration.** Consumers may lower their floor to macOS 15 (iOS 18 for the pure-Swift modules) and re-pin to 0.5.1. A
  consumer that pins FormatoKit itself must pin 0.2.1 (it resolves to 0.2.1 through SpectroKit anyway). Nothing else changes.

## 0.5.0 — the generality pass

The suite's policies became public parameters (`WindowRules`, `QuantificationPolicy`, `ProposerPolicy`, `UnlistedLineRules`,
`SmoothingKernel`, the EELS default window offsets), each default 0.4.0's value, the default path bit for bit; a stand-alone
README and `Examples/QuantifyEDX`; a DocC catalogue per module; `docs/parity.md`. One behaviour change:
`SpectroscopyExport.csv`'s default title is "Spectroscopy quantification". Migration: nothing required.

## 0.4.0

The file readers moved to FormatoKit (`FormatoDM`, `FormatoEMD`, `FormatoHDF5`), pinned `exact: "0.0.3"`; libhdf5 ships inside
FormatoHDF5.

## 0.3.0, 0.2.0, 0.1.0

EELS thickness (t/λ) and the C K ratio method; the EDX quantification stage gates; the first extraction from the source
application (`../_archive/SpectroKit/docs/history.md`).

Consumer notes for 0.0.1 to 0.5.0 are archived.
