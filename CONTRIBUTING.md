# Contributing to SpectroKit

Thanks for your interest. SpectroKit is a Swift library for EDS and EELS spectroscopy, ported from
[exSpy](https://github.com/hyperspy/exspy) and [HyperSpy](https://hyperspy.org). Bug reports, questions, and pull requests
are welcome.

## Build and test

You need a Mac with Xcode 26 (Swift 6.2) or newer. The package supports macOS 15 and iOS 18 or later.

```sh
swift test -c release
```

Use the release configuration: the numerical code is 20 to 50 times slower unoptimised, and the full suite is impractically
slow in Debug. `tools/test.sh` runs the same command with extra warning checks. `tools/consumer-check/run.sh` builds two small
packages that depend on SpectroKit the way an outside project would, which confirms the public API is usable.

Tests use [Swift Testing](https://github.com/swiftlang/swift-testing) (`import Testing`, `@Test`, `#expect`), not XCTest.

## How the numbers are checked

SpectroKit's results are compared with the Python libraries it is ported from, using fixtures generated from pinned versions
of exSpy and HyperSpy. A test's tolerance is the one the Python package's own tests use for that function; a result outside it is a bug. A change
that moves a fixture says why in the pull request and in the CHANGELOG. If you believe the Python reference itself is wrong, open an issue and show the evidence.

Where a result must differ from the reference, mark it in the code with a `DEVIATION` comment and say why.

Results are labelled `validation: "none"` (see "Validation" in the [README](README.md)). Agreement with exSpy and recovery of
planted values in synthetic spectra are not validation against samples of known composition or thickness. Please do not
describe results as validated in code, documentation, or issues until they have been checked on standards.

## Pull requests

- Keep each pull request focused on one change.
- Add or update tests that fail without your change and pass with it.
- Update the documentation and the supported-features table in [`docs/parity.md`](docs/parity.md) when behaviour changes.
- Keep the public API free of application-specific types.
- By contributing you agree that your work is licensed under GPL-3.0-or-later, the licence of this project.

## Reporting issues

Use the issue templates. For a wrong number, include the spectrum (or a minimal synthetic one), the call you made, the result
you got, and the result you expected, with the exSpy or HyperSpy version if you compared against it. For a security problem,
see [SECURITY.md](SECURITY.md) instead.
