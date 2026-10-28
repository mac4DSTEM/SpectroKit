//
//  Task16Checks.swift
//  Role: the public surface task 16 and 0.9.0 add, used from outside the package (only public API is named): zero-loss alignment, the
//        spectrum operations, Fourier-log and Fourier-ratio deconvolution, the edge model fit with composition and model curve, the region sum,
//        the bundled L edges, the per-pixel take-off angle, and the initialisers 0.9.0 opens for tests (windows, detector segments,
//        proposer results). Synthetic data only; the numbers are pinned in the package's own tests.
//

import Foundation
import SpectroCore
import SpectroEDX
import SpectroEELS

func task16Checks(_ r: inout Report) throws {
    // a 2 x 2 low loss: a zero-loss peak, a plasmon, a tail
    let n = 400, scale = 0.1, offset = -10.0
    func gauss(_ e: Double, _ c: Double, _ w: Double, _ a: Double) -> Double { a * exp(-0.5 * pow((e - c) / w, 2)) }
    var ll = [Double](), shifts = [0.0, 0.31, -0.42, 0.17]
    for p in 0 ..< 4 {
        for k in 0 ..< n {
            let e = offset + scale * Double(k)
            ll.append(gauss(e, shifts[p], 0.4, 1e5) + gauss(e, 15 + shifts[p], 3, 1.5e4) + (e > 2 ? 2e3 * pow(e, -1.5) : 0))
        }
    }
    shifts = []
    let low = try LowLossSpectrumImage(nx: 2, ny: 2, channels: n, counts: ll, energyOffsetEV: offset, energyScaleEV: scale)
    let aligned = try EELSAlignment.alignZeroLossPeak(low)
    let centres = try EELSAlignment.zeroLossPeakCentre(aligned.aligned)
    r.check("alignment brings every zero-loss peak to 0 eV", centres.allSatisfy { abs(($0 ?? .nan)) < 0.06 }, "\(centres)")
    r.check("the Hanning taper reports its width", try EELSSpectrumOps.hanningTaper(low).taperedChannels == 20)
    r.check("optimal FFT size follows SciPy", EELSDeconvolution.optimalFFTSize(1999, real: false) == 2000 && EELSDeconvolution.optimalFFTSize(13, real: true) == 15)
    let width = try EELSDeconvolution.peakWidth((0 ..< n).map { gauss(offset + scale * Double($0), 0, 0.4, 1) }, offsetEV: offset, scaleEV: scale)
    r.near("the half-maximum width of a Gaussian is 2.3548 sigma", width?.widthEV, 2.3548 * 0.4, 1e-3)
    let log = try EELSDeconvolution.fourierLog(low, zeroLoss: low)
    r.check("Fourier-log of a spectrum by itself is finite and keeps the size", log.image.channels == n && log.image.counts.allSatisfy { $0.isFinite })

    // a core loss: power law plus the Fe L edge, fitted
    let microscope = EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)
    let cn = 500, cScale = 0.5, cOffset = 600.0
    let energies = (0 ..< cn).map { cOffset + cScale * Double($0) }
    let l3 = try EELSEdgeQuantification.differentialCrossSection(edge: .ironL3, microscope: microscope, energiesEV: energies).barnPerEV
    let l2 = try EELSEdgeQuantification.differentialCrossSection(edge: .ironL2, microscope: microscope, energiesEV: energies).barnPerEV
    var core = [Double]()
    for p in 0 ..< 4 {
        let a = 1.5e12 * (1 + 0.2 * Double(p)), rr = 2.8, intensity = 4e5 * (1 + 0.1 * Double(p))
        for k in 0 ..< cn { core.append(a * pow(energies[k], -rr) * cScale + intensity * (l3[k] + l2[k]) * cScale) }
    }
    let image = try CoreLossSpectrumImage(nx: 2, ny: 2, channels: cn, counts: core, energyOffsetEV: cOffset, energyScaleEV: cScale)
    let fit = try EELSModelFit.fit(coreLoss: image, edges: [.ironL2, .ironL3], microscope: microscope)
    r.check("the fit finds one master for the L2,3 pair", fit.edges == [.ironL3] && fit.shells == [[.ironL2, .ironL3]])
    r.near("the fitted intensity equals the planted one", fit.pixels[2][0].intensity, 4e5 * 1.2, 1e-2)
    r.near("the fitted exponent equals the planted one", fit.backgrounds[2]?.r, 2.8, 1e-4)
    r.check("the model curve covers the axis", fit.modelCurve(pixel: 1)?.count == cn)
    r.check("the quantify text names the element", fit.quantifyText(pixel: 0).contains("Fe\t"))
    let comp = try EELSQuantification.composition(fit, symbols: ["Fe"])
    r.check("one element is 100 at% and 100 wt%", abs(comp[0].atomicPercent[0] - 100) < 1e-9 && comp[0].unavailable == nil)
    let region = try image.sum(mask: [true, false, true, false])
    r.check("the region sum is one pixel of the added counts", region.nx == 1 && region.counts[3] == core[3] + core[2 * cn + 3])
    r.check("the bundled edges include the L edges", CoreLossEdge.bundled("Cu", "L3") == .copperL3 && CoreLossEdge.bundled.count == 383)

    // initialisers opened for tests
    let segment = SpectrumDetectorSegment(name: "A", azimuthDegrees: 45, elevationDegrees: 20)
    let window = ResolvedWindow(signal: 10 ..< 20, background: ResolvedWindow.Background(left: 0 ..< 5, right: 25 ..< 30, scale: 1))
    let lineWindow = LineWindow(element: "Fe", id: "Fe Ka", energy: 6.4, fwhm: 0.13, window: window, failure: nil, conflicts: [])
    r.check("windows and detector segments can be built", segment.name == "A" && lineWindow.window == window && lineWindow.energy == 6.4)

    // per-pixel take-off angle
    let setup = EDXQuantificationSetup(elements: ["Fe", "Cu"], method: .cliffLorimer(kFactors: [1.5, 1.8], thicknessNm: 80),
                                       absorption: EDXAbsorptionSetting(takeOffDegrees: 25, lineEnergiesKeV: [6.4, 8.05]))
    let maps = try EDXQuantification.quantifyMaps(intensityMaps: [[1000, 1000], [500, 500]], rows: 1, columns: 2, setup: setup,
                                                  takeOffDegreesPerPixel: [25, 60])
    r.check("a take-off angle per pixel changes the absorption correction", maps.weightPercent[0][0] != maps.weightPercent[0][1] && maps.failures.allSatisfy { $0 == nil })
}
