# SpectroKit

A Swift library for X-ray (EDS) and electron energy-loss (EELS) spectroscopy in the transmission electron microscope: a
port of [exSpy](https://github.com/hyperspy/exspy), the EDS and EELS extension of [HyperSpy](https://hyperspy.org), to
Swift for macOS. It opens a spectrum image, proposes which elements the spectrum supports, quantifies them in atomic percent
with an uncertainty, and maps EELS thickness. No UI; headless; Swift 6.

**Status: pre-1.0, and nothing here is validated on a sample of known composition or thickness.** Every result says so
(`validation: "none"`), see [Validation](#validation).

## What is in it

Three products, each a Swift module:

| Product | What it does |
|---|---|
| `SpectroCore` | What EDS and EELS share: the spectrum image (dense and sparse), `EnergyAxis` (HyperSpy's channel rounding), opening a Velox `.emd` or a Gatan `.dm4` EDS spectrum image, linear least-squares and Poisson maximum-likelihood fits (Accelerate LAPACK), counting statistics and sigma propagation. |
| `SpectroEDX` | The X-ray part: the line table, the EDS line and continuum model and its fit, the element proposer (Currie detection limit), Cliff-Lorimer quantification with computed k-factors, the four-detector absorption correction, export. Depends on `SpectroCore`. |
| `SpectroEELS` | The thickness t/lambda by the log-ratio method (`EELSThickness.logRatio`), and the C K areal density by the ratio method with the dft generalised oscillator strengths. Depends on `SpectroCore`. |

The numerical methods follow exSpy's line by line, with deviations named in the code and compared against exSpy's own
output in the tests. Agreement with exSpy is not the same as being right: see [Validation](#validation).

## Installation

Requirements: macOS 15 (Apple silicon) and Swift 6.2 tools. In your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyTool",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/mac4DSTEM/SpectroKit", from: "0.7.0"),
    ],
    targets: [
        .executableTarget(name: "MyTool", dependencies: [
            .product(name: "SpectroCore", package: "SpectroKit"),
            .product(name: "SpectroEDX", package: "SpectroKit"),    // X-ray quantification
            .product(name: "SpectroEELS", package: "SpectroKit"),   // thickness, core-loss areal density
        ]),
    ],
    swiftLanguageModes: [.v6]
)
```

Add only the products you use; `SpectroEDX` and `SpectroEELS` each need `SpectroCore` and bring it.

**File formats.** The readers are not here: they are [FormatoKit](https://github.com/mac4DSTEM/FormatoKit)'s, a dependency
SpectroKit resolves by itself, with its own libhdf5 inside (nothing to install). `SpectrumImageOpener` in `SpectroCore` calls
them: it opens a Velox `.emd` (Thermo Fisher; FormatoKit's `FormatoEMD`) or a Gatan GMS `.dm4` EDS spectrum image
(`FormatoDM`) and needs no import of yours. Add the Formato products to your own target only to read the file yourself:
`FormatoEMD` for Velox `.emd`, `FormatoDM` for Gatan `.dm3` / `.dm4`.

## Quick start: quantify an EDX spectrum

This program has no input of its own: with no argument it builds a spectrum with Mg, Al and Si K-alpha lines planted on a
continuum (areas 24000, 12000 and 6000 counts, fixed pseudo-noise), proposes the elements it supports, and quantifies them.
With a path it does the same on a Velox `.emd` or GMS `.dm4` EDS spectrum image, all pixels summed. It is the whole of
[`Examples/QuantifyEDX`](Examples/QuantifyEDX) (a separate package: `cd Examples/QuantifyEDX && swift run -c release`).

<!-- readme-consumer -->
```swift
import Foundation
import SpectroCore
import SpectroEDX

// 1. A spectrum: counts per channel on an energy axis (10 eV per channel here), and the beam energy in keV.
var axis = EnergyAxis(offset: 0, scale: 0.01, size: 2048)
var beamKeV = 200.0
var metadata = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1,
                                     channelCount: axis.size, energyOffsetEV: 0, energyDispersionEV: 10)
var counts = [UInt64]()
if let path = CommandLine.arguments.dropFirst().first {
    // From a file: a Velox .emd or a GMS .dm4 spectrum image, every pixel summed into one spectrum.
    let file = try SpectrumImageOpener.open(path: path, kind: SpectrumImageOpener.kind(ofFileAt: path))
    axis = file.energyAxis; metadata = file.metadata; beamKeV = file.metadata.beamEnergyKeV ?? beamKeV
    counts = file.sum(mask: nil)
} else {
    // Or a planted one: Mg, Al and Si K-alpha lines (areas 24000, 12000, 6000 counts) on a smooth continuum, with fixed pseudo-noise.
    let lines = [(keV: 1.2536, area: 24000.0), (keV: 1.4867, area: 12000.0), (keV: 1.7400, area: 6000.0)]
    counts = (0..<axis.size).map { i in
        let e = axis.energy(ofChannel: i)
        var mean = 40 * exp(-e / 4) * (1 - exp(-e / 0.3))
        for line in lines {
            let sigma = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: line.keV)! / 2.3548
            mean += line.area * axis.scale * exp(-0.5 * pow((e - line.keV) / sigma, 2)) / (sigma * (2 * Double.pi).squareRoot())
        }
        let u = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return UInt64(max(0, (mean + (2 * (u - u.rounded(.down)) - 1) * (3 * mean).squareRoot()).rounded()))
    }
}
```

<!-- readme-consumer -->
```swift
// 2. Which elements does the spectrum support? The proposer tests a pool of elements against a detection limit.
let settings = FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: 130, beamEnergy: beamKeV)
let proposal = try ElementProposer().propose(counts: counts.map { Double($0) }, axis: axis, settings: settings)
let found = proposal.proposed.map(\.element)
print("proposed elements:", found.joined(separator: " "))

// 3. Quantify them: a least-squares fit with a computed k-factor, atomic percent with sigma.
var method = QuantificationMethod()
method.elements = found.map { .init(symbol: $0, role: .quantify, isManual: false) }
method.beamEnergyKeV = beamKeV
method.absorptionCorrection = false   // the correction needs the stage tilt, the detector geometry and a thickness
let input = PooledQuantificationInput(counts: counts, axis: axis, method: method, metadata: metadata,
                                      regionName: "sum", pixelCount: metadata.scanWidth * metadata.scanHeight)
let result = try PooledQuantifier.run(input, tables: QuantificationTables.bundled())
for row in result.rows {
    print(row.element, row.atomicPercent.map { String(format: "%.2f at.%% +- %.2f", $0, row.atomicSigma ?? .nan) } ?? "no at.%")
}
if let why = result.abundanceRefusal { print("no at.%:", why) }
print("validation:", PooledQuantification.abundanceValidation, "(agreement with exSpy is not validation)")
```

### Example output

```
proposed elements: Mg Si Al
Mg 58.17 at.% +- 5.21
Si 14.01 at.% +- 2.93
Al 27.82 at.% +- 3.39
validation: none (agreement with exSpy is not validation)
```

The planted line areas are 24000 : 12000 : 6000 counts; the fit recovers 23832 : 11712 : 5972 (`result.rows[].net`). The
atomic percentages are those areas divided by computed k-factors (Bote-Salvat cross sections, Krause fluorescence yields, the
EPQ detector efficiency), which are not validated; the sigma combines the counting statistics with a 20 % uncertainty on each
k-factor. A computed k covers K lines only: for an element whose only line in range is an L or M line the result says so
instead of giving a percentage (`abundanceRefusal`), and you may type a k-factor (`QuantificationMethod.typedK`).

## Quick start: EELS thickness

The t/lambda of a low-loss spectrum image by the log-ratio method of exSpy (`estimate_thickness`). This one-pixel image has a
zero-loss peak at 0 eV and a plasmon at 25 eV holding e^0.5 - 1 of the zero-loss area, so the planted t/lambda is 0.5.

<!-- readme-consumer-eels -->
```swift
import SpectroEELS

let step = 0.1   // eV per channel; the axis starts at -10 eV
let eelsCounts = (0..<1024).map { c -> Double in
    let e = -10 + step * Double(c)
    func peak(_ centre: Double, _ sigma: Double, _ area: Double) -> Double {
        area * step * exp(-0.5 * pow((e - centre) / sigma, 2)) / (sigma * (2 * Double.pi).squareRoot())
    }
    return peak(0, 0.4, 1e6) + peak(25, 5, 1e6 * (exp(0.5) - 1))
}
let lowLoss = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 1024, counts: eelsCounts, energyOffsetEV: -10, energyScaleEV: step)
let thickness = try EELSThickness.logRatio(lowLoss, threshold: .fixed(5))   // I_0 = the counts below 5 eV
let pixel = thickness[0, 0]
print("t/lambda = \(pixel.tOverLambda!) +- \(pixel.sigmaCounting!) (planted 0.5, validation: \(thickness.validation))")
```

`EELSThickness.logRatio` also takes `.estimated()` (exSpy's inflexion rule with SciPy's LAPACK polynomial fit and deterministic first-index ties), a per-pixel threshold, a separate zero-loss
spectrum image and a mean free path (`MeanFreePathSource`) for an absolute thickness in nm; `EELSEdgeQuantification.ratioMethod`
gives the C K areal density. Read the doc comments for what each leaves out.

Example output (the planted 0.5 minus the plasmon tail's few counts below the threshold):

```
t/lambda = 0.49998031099622964 +- 0.0006272556508136116 (planted 0.5, validation: none)
```

## Release builds

Build and test in release: `swift build -c release`, `swift run -c release`, `swift test -c release`. The numerical hot paths
(the least-squares fits and the element proposer above all) run 20 to 50 times slower in Debug, which compiles without
optimisation; the proposer, measured before it was made faster, took 956 s in Debug against 20 s in release. A library cannot
make its dependents optimise: SwiftPM does not allow a versioned dependency's manifest to carry the unsafe `-O` flag for Debug,
so SpectroKit's manifest carries none. Everything compiles and is correct in Debug (the README consumer in
[Tests](#tests) builds the code above in Debug with no warning); it is only slow, and the quick start above takes a few
seconds in release. In Xcode use the Release configuration for anything that fits.

## Validation

All EDX quantification and all EELS thickness report `validation: "none"`. What that means:

- The code reproduces exSpy's numbers (the tests compare against exSpy, HyperSpy, RosettaSciIO, SciPy and NumPy outputs, often
  bit for bit) and recovers values planted in synthetic spectra, with the biases it finds written next to the claims.
- It has **not** been compared with a sample of known composition (EDX) or known thickness (EELS), so no atomic percent or
  thickness it prints is a validated measurement. The k-factors are computed from tabulated cross sections, not calibrated
  on standards; the absorption correction is checked for plumbing, not against a known geometry.
- Nothing is called validated until it has recovered a planted value and a sample of known composition.

Each result carries its sigma and the terms in it; read what a sigma leaves out (the doc comments say) before using one.

## Tests

```sh
tools/test.sh                         # the gate: swift test -c release
tools/consumer-check/run.sh           # builds the code in this README, and a second consumer, in Debug: both without a warning
```

`tools/consumer-check/run.sh` builds two separate packages that depend on this one by path, exactly as a stranger's package
would: one uses the public API of `SpectroCore` and `SpectroEELS`, the other (`tools/consumer-check/readme`) is the code blocks
of this README and nothing else, and `check-readme.py` fails if the README and `Examples/QuantifyEDX` differ.

## Documentation

- [`docs/consumers-0.5.0.md`](docs/consumers-0.5.0.md): what 0.5.0 adds (every suite policy a parameter with today's value as
  the default) and changes; [`docs/consumers-0.4.0.md`](docs/consumers-0.4.0.md): where the readers went (FormatoKit).
- [`docs/status.md`](docs/status.md): the state, the gate's counts and the open items; [`docs/parity.md`](docs/parity.md):
  SpectroKit against exSpy's documented API, row by row.
- [`docs/`](docs): the registrations (what was decided before the code, and what the tests must show).
- [`NOTICE`](NOTICE): the licences and credits in full.

## Licence and credits

GPL-3.0 ([`LICENSE`](LICENSE)); an application that links SpectroKit must be GPL-compatible. It is a port of, and is compared
against, the work of others, and is not affiliated with them:

- **exSpy** and **HyperSpy** (GPL-3.0-or-later): the EDS and EELS methods, the line table, the element data, the channel
  rounding. **RosettaSciIO** (GPL-3.0-or-later): the file-format rules, via FormatoKit, and the public Velox test files in
  `Tests/SpectroEDXTests/Fixtures/public/`.
- **NIST EPQ** (public domain, 17 USC 105): X-ray line weights, mass absorption coefficients (FFAST, Chantler et al.),
  Bote-Salvat ionisation cross sections, Krause fluorescence yields; **FFAST** and **Krause** terms are carried as a recorded risk.
- **SciPy** and **NumPy** (BSD-3-Clause): the Savitzky-Golay derivative, Simpson rule, spline and summation order EELS reproduces.
- The **dft generalised oscillator strengths** of Segger, Guzzinati and Kohl, v1.5.0, CC BY 4.0 (for C, N and O K), as exSpy
  fetches them.
- **HDF5**, libaec and libsz (BSD-style), shipped by FormatoKit.

Read [`NOTICE`](NOTICE) for the full texts, versions, commits and checksums.
