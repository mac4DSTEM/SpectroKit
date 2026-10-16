# Changelog

SpectroKit follows semantic versions (0.x). Each release says what changed, and what a consumer must do (Migration).

## Unreleased (0.5.2)

- **Portable estimated EELS thresholds.** Scalar QR replaces Accelerate-dependent Savitzky–Golay coefficients and edge fits.
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
`SpectroscopyExport.csv`'s default title is "Spectroscopy quantification". Migration: nothing required
(`docs/consumers-0.5.0.md`).

## 0.4.0

The file readers moved to FormatoKit (`FormatoDM`, `FormatoEMD`, `FormatoHDF5`), pinned `exact: "0.0.3"`; libhdf5 ships inside
FormatoHDF5 (`docs/consumers-0.4.0.md`).

## 0.3.0, 0.2.0, 0.1.0

EELS thickness (t/λ) and the C K ratio method; the EDX quantification stage gates; the first extraction from the source
application (`docs/consumers-0.3.0.md`, `../_archive/SpectroKit/docs/history.md`).
