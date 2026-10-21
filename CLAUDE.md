# SpectroKit

Spectroscopy: EDX (lines, peak ID, Cliff-Lorimer and zeta quantification, absorption) and EELS (thickness, background, edges). Pure Swift, no UI, standalone; the suite's rules are in `../CLAUDE.md`. Start with `README.md`,
`docs/parity.md` and the task.

## Reference
HyperSpy and exSpy at the versions pinned in `tools/*/pins.py` (`References/`); cross sections from the dft GOS tables (Segger, Guzzinati, Kohl v1.5.0, CC BY 4.0) as exSpy uses them, never Gatan's Hartree-Slater tables. Readers come from FormatoKit `"0.4.0"..<"1.0.0"`. Fixtures are generated from it (`tools/*/pins.py`) and committed under `Tests/*/Fixtures/`; a difference inside
the reference's own tolerance is agreement, outside it a bug. Readers, I/O, indices and metadata exact.

## Build and test
```sh
swift build
swift test -c release          # the gate; Debug is many times slower on the numeric loops
tools/consumer-check/run.sh    # a separate package that compiles against the public API
```
Never `swift build --build-tests -c release` (fails on this toolchain). Real-data tests skip when the data is absent.

## Modules
`SpectroCore` (spectra, axes, lines, fits), `SpectroEDX` (ID, quantification, maps), `SpectroEELS` (thickness, background, edges).

## Rules of the kit
- Public API only; nothing names an app or an app type; error messages never say "mac4DSTEM" or "macTEM".
- Rows and columns, not x and y. Every accelerated path keeps the CPU float64 path as its reference (D16).
- A new or changed number gets a test against the reference at its upstream tolerance, and a row in `docs/parity.md`.
- Bump together with FormatoKit in the apps. Quantification without a validated standard ships badged `validation: "none"`.

## Closeout
`swift test -c release` green; `CHANGELOG.md` entry with a Migration paragraph where a consumer must change something;
version bumped in the entry; one commit on `main` whose last paragraph is the hand-off. Paul tags with
`../macEM-suite/tools/ship.sh` (tag = CHANGELOG top version).
