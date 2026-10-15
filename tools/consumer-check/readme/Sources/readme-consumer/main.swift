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
