//
//  EELSThickness.swift
//  Role: EELS slice 1 (docs/eels-slice-1-registration.md): the t/λ thickness map of a low-loss spectrum image by the
//        log-ratio method, a port of exSpy 7185a4d1's `estimate_thickness` (`exspy/signals/_eels.py:755-868`) with its
//        threshold (`:641-753`) and zero-loss sum (`:566-639`).
//

import Foundation
import SpectroCore

public nonisolated enum EELSThickness {

    /// The method named in every result.
    public static let methodName = "log-ratio, exSpy 7185a4d1"

    /// t/λ = ln(I_t / I_0) per pixel, with I_t the sum over every channel and I_0 the zero-loss sum from `threshold` (or the sum of
    /// `zeroLoss`); optionally the absolute thickness from a mean free path.
    ///
    /// - Parameters:
    ///   - image: the low-loss spectrum image; the zero-loss peak at 0 eV, counts per channel (see `LowLossSpectrumImage`).
    ///   - threshold: how I_0 is cut (`ThresholdRule`). Ignored when `zeroLoss` is given (exSpy: `zlp` takes precedence, `_eels.py:810-813`).
    ///   - zeroLoss: a zero-loss spectrum image with the same `nx`, `ny` (any channel count: only its sum per pixel is used, so its counts
    ///     must be on the same scale as `image`'s). I_0 is that sum.
    ///   - meanFreePath: the λ source for `thicknessNM`; nil gives t/λ only.
    ///   - cancelled: asked once per block of pixels; true throws `SpectroCancelled` and nothing is kept.
    ///   - progress: fraction 0...1, monotone, ends at 1.
    /// - Throws: `EELSThicknessError` for inputs the method cannot start from; a pixel it cannot answer is a nil with a reason, not a throw.
    public static func logRatio(
        _ image: LowLossSpectrumImage,
        threshold: ThresholdRule = .estimated(),
        zeroLoss: LowLossSpectrumImage? = nil,
        meanFreePath: MeanFreePathSource? = nil,
        cancelled: @Sendable () -> Bool = SpectroCancellation.task,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ThicknessMap {
        let nx = image.nx, ny = image.ny, nch = image.channels, np = image.pixelCount
        if let z = zeroLoss, z.nx != nx || z.ny != ny {
            throw EELSThicknessError.zeroLossShapeMismatch(expectedNx: nx, expectedNy: ny, gotNx: z.nx, gotNy: z.ny)
        }
        let lambda = try meanFreePath.map { try InelasticMeanFreePath.resolve($0) }
        let axis = try EELSAxis(offset: image.energyOffsetEV, scale: image.energyScaleEV, size: nch)

        // The route to I_0, validated before any pixel is touched.
        enum Route {
            case zeroLossSpectrum
            case fixed(energy: Double, stop: Int)
            case perPixel(energies: [Double], unavailableForNaN: ThicknessUnavailable)
        }
        var route: Route
        var estimatedTolerance: Double?
        var progressBase = 0.0                           // the threshold search, when there is one, takes the first half of the progress
        var zeroLossSource: ZeroLossSource
        if zeroLoss != nil {
            route = .zeroLossSpectrum; zeroLossSource = .zeroLossSpectrum
        } else {
            zeroLossSource = .threshold(threshold)
            switch threshold {
            case .fixed(let theta):
                route = .fixed(energy: theta, stop: try axis.zeroLossStop(forFixedThreshold: theta))
            case .perPixel(let thetas):
                guard thetas.count == np else { throw EELSThicknessError.perPixelThresholdCount(expected: np, got: thetas.count) }
                route = .perPixel(energies: thetas, unavailableForNaN: .thresholdNotANumber)
            case .estimated(let window, let start, let windowLength, let polynomialOrder, let tolerance):
                let found = try image.counts.withUnsafeBufferPointer { buf in
                    try ElasticThreshold.estimate(
                        counts: buf, pixelCount: np, channels: nch, axis: axis, window: window, start: start,
                        windowLength: windowLength, polynomialOrder: polynomialOrder, tolerance: tolerance,
                        cancelled: cancelled, progress: progress.map { p in { @Sendable f in p(0.5 * f) } })
                }
                estimatedTolerance = found.tolerance
                progressBase = 0.5
                route = .perPixel(energies: found.thresholdEV, unavailableForNaN: .noInflexionFound)
            }
        }

        var pixels = [ThicknessPixel]()
        pixels.reserveCapacity(np)
        let correction = lambda?.correction
        let lambdaNM = lambda?.lambdaNM
        let block = 2048
        try image.counts.withUnsafeBufferPointer { buf in
            try (zeroLoss?.counts ?? []).withUnsafeBufferPointer { zbuf in
                for p in 0..<np {
                    if p % block == 0 {
                        try SpectroCancellation.check(cancelled)
                        progress?(progressBase + (1 - progressBase) * Double(p) / Double(np))
                    }
                    let row = buf.baseAddress! + p * nch
                    let iTotal = NumpySum.pairwise(row, count: nch)
                    var centre = 0
                    var best = row[0]
                    for c in 1..<nch where row[c] > best { best = row[c]; centre = c }
                    let zlpCentre = axis.energy(ofChannel: centre)

                    var i0: Double?
                    var thetaEV: Double?
                    var thetaChannel: Int?
                    var missing: ThicknessUnavailable?
                    switch route {
                    case .zeroLossSpectrum:
                        i0 = NumpySum.pairwise(zbuf.baseAddress! + p * zeroLoss!.channels, count: zeroLoss!.channels)
                    case .fixed(let energy, let stop):
                        thetaEV = energy; thetaChannel = stop
                        i0 = NumpySum.pairwise(row, count: stop)
                    case .perPixel(let energies, let nanReason):
                        let theta = energies[p]
                        if theta.isNaN {
                            missing = nanReason
                        } else if let ind = axis.channel(ofEnergy: theta) {
                            thetaEV = theta; thetaChannel = ind
                            i0 = NumpySum.pairwise(row, count: ind)
                        } else {
                            thetaEV = theta
                            missing = .thresholdOutsideAxis
                        }
                    }

                    var t: Double?, sigma: Double?, sigmaWhy: SigmaUnavailable?, thickness: Double?
                    if missing == nil, let i0v = i0 {
                        if !(i0v > 0) {
                            missing = .zeroLossIntensityNotPositive
                        } else if !(iTotal > 0) {
                            missing = .totalIntensityNotPositive
                        } else {
                            let ratio = log(iTotal / i0v)
                            t = ratio
                            if case .zeroLossSpectrum = route {
                                sigmaWhy = .zeroLossFromSeparateSpectrum
                            } else if iTotal >= i0v {
                                sigma = (1 / i0v - 1 / iTotal).squareRoot()
                            } else {
                                sigmaWhy = .totalBelowZeroLoss
                            }
                            if let lambdaNM {
                                // exSpy: t_over_lambda *= correction (with a density), then s.data *= mean_free_path (:828, :850).
                                let corrected = correction.map { ratio * $0 } ?? ratio
                                thickness = corrected * lambdaNM
                            }
                        }
                    }
                    pixels.append(ThicknessPixel(
                        tOverLambda: t, sigmaCounting: sigma, i0: i0, iTotal: iTotal, thresholdEV: thetaEV,
                        thresholdChannel: thetaChannel, zlpCentreEV: zlpCentre, thicknessNM: thickness,
                        unavailable: missing, sigmaUnavailable: sigmaWhy))
                }
            }
        }
        progress?(1)
        return ThicknessMap(nx: nx, ny: ny, pixels: pixels, method: methodName, zeroLoss: zeroLossSource,
                            meanFreePath: meanFreePath, meanFreePathNM: lambdaNM, angularCorrection: correction,
                            estimatedTolerance: estimatedTolerance, validation: "none")
    }
}
