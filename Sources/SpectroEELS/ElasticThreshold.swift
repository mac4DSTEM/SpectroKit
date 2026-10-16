//
//  ElasticThreshold.swift
//  Role: exSpy's `estimate_elastic_scattering_threshold` (`exspy/signals/_eels.py:641-753`, at 7185a4d1): the energy where
//        a low-loss spectrum's derivative first reaches `tol`, found per pixel in the search range `[start, start+window)`.
//
//  Steps, as exSpy takes them (line numbers `_eels.py`):
//   1. `[min, max) = axis.value_range_to_indices(start, start + window)` (:712); fewer than 10 channels is an error (:713-714).
//   2. crop `isig[min:max]` (:715); first derivative of each cropped row: Savitzky–Golay (:716-721) or, with
//      `window_length == 0`, `numpy.gradient` on the cropped axis (:722-724).
//   3. `tol` (when not given) = max over pixels of min over the range of |derivative| (:724-725): ONE number for the image.
//   4. per pixel `inflexion = argmax(|derivative| <= tol)`, the first such index, 0 if none (:726-727);
//      threshold = the cropped axis value there, NaN where `inflexion == 0` (:730-735).
//  The cropped axis is `offset_c + scale * i` with `offset_c = (offset + scale * arange(size))[min]` (HyperSpy `_slice_me` /
//  `update_axis`, `axes.py:1351`), so the energy can differ by an ulp from the full axis's.
//

import Foundation
import SpectroCore

package nonisolated struct EstimatedThresholds: Sendable {
    /// `min` of step 1: the first channel of the search range.
    package let firstChannel: Int
    /// `max - min`: the number of channels in the search range.
    package let channels: Int
    package let tolerance: Double
    /// Per pixel, the smallest |derivative| in the range.
    package let minAbsDerivative: [Double]
    /// Per pixel, the index within the range of the first |derivative| <= tol (0 where there is none).
    package let inflexionIndex: [Int]
    /// Per pixel, the threshold in eV; NaN where `inflexionIndex == 0`.
    package let thresholdEV: [Double]
}

package nonisolated enum ElasticThreshold {

    package static let minimumChannels = 10

    /// The per-row derivative kernel of step 2.
    package nonisolated enum Kernel: Sendable {
        case savitzkyGolay(SavitzkyGolayFirstDerivative, SavitzkyGolayEdgeTable)
        case gradient(NumpyGradient)

        /// Pixel `p`'s derivative (the Savitzky-Golay edges come from the image-wide table).
        package func apply(_ f: UnsafeBufferPointer<Double>, into out: UnsafeMutableBufferPointer<Double>, pixel p: Int) {
            switch self {
            case .savitzkyGolay(let sg, let table): sg.apply(f, into: out, pixel: p, table: table)
            case .gradient(let g): g.apply(f, into: out)
            }
        }
    }

    /// `row(p)` is pixel `p`'s cropped spectrum; the pixels are `nx` wide (row-major `y * nx + x`).
    package static func kernel(windowLength: Int, polynomialOrder: Int, scale: Double, croppedAxis: [Double],
                               nx: Int, ny: Int, row: (Int) -> UnsafeBufferPointer<Double>,
                               coefficientsOverride: [Double]? = nil) throws -> Kernel {
        if windowLength != 0 {
            guard windowLength <= croppedAxis.count else {
                throw EELSThicknessError.invalidSavitzkyGolay(
                    "window_length \(windowLength) exceeds the \(croppedAxis.count) channels of the search range (mode=\"interp\")")
            }
            let sg = try SavitzkyGolayFirstDerivative(
                windowLength: windowLength, polynomialOrder: polynomialOrder, delta: scale, coefficientsOverride: coefficientsOverride)
            return .savitzkyGolay(sg, try sg.edgeTable(nx: nx, ny: ny, row: row))
        }
        return .gradient(NumpyGradient(axis: croppedAxis))
    }

    package static func estimate(
        counts: UnsafeBufferPointer<Double>, pixelCount: Int, navigationWidth nx: Int, channels nch: Int, axis: EELSAxis,
        window: Double, start: Double, windowLength: Int, polynomialOrder: Int, tolerance userTolerance: Double?,
        coefficientsOverride: [Double]? = nil,
        cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?
    ) throws -> EstimatedThresholds {
        guard start.isFinite, window.isFinite, window >= 0 else {
            throw EELSThicknessError.invalidSearchWindow(startEV: start, windowEV: window)
        }
        if let t = userTolerance, t.isNaN || t < 0 { throw EELSThicknessError.invalidTolerance(t) }
        // 1. the search range
        let (i1, i2) = try axis.valueRangeToIndices(start, start + window)
        guard i2 >= i1 + minimumChannels else { throw EELSThicknessError.searchWindowTooShort(channels: i2 - i1) }
        let length = i2 - i1
        let croppedOffset = axis.energy(ofChannel: i1)
        var croppedAxis = [Double](repeating: 0, count: length)
        for i in 0..<length {
            let step = axis.scale * Double(i)
            croppedAxis[i] = croppedOffset + step
        }
        // 2. the derivative kernel
        precondition(nx > 0 && pixelCount % nx == 0)
        let kernel = try kernel(windowLength: windowLength, polynomialOrder: polynomialOrder, scale: axis.scale,
                                croppedAxis: croppedAxis, nx: nx, ny: pixelCount / nx,
                                row: { p in UnsafeBufferPointer(start: counts.baseAddress! + p * nch + i1, count: length) },
                                coefficientsOverride: coefficientsOverride)

        var derivative = [Double](repeating: 0, count: length)
        var minAbs = [Double](repeating: 0, count: pixelCount)
        let block = 2048
        // pass 1: each pixel's smallest |derivative|
        try derivative.withUnsafeMutableBufferPointer { d in
            for p in 0..<pixelCount {
                if p % block == 0 { try SpectroCancellation.check(cancelled); progress?(0.5 * Double(p) / Double(pixelCount)) }
                let row = UnsafeBufferPointer(start: counts.baseAddress! + p * nch + i1, count: length)
                kernel.apply(row, into: d, pixel: p)
                var m = abs(d[0])
                for i in 1..<length { m = min(m, abs(d[i])) }
                minAbs[p] = m
            }
        }
        // 3. tol: one number for the image (or the caller's)
        var tol = minAbs[0]
        for p in 1..<pixelCount { tol = max(tol, minAbs[p]) }
        if let t = userTolerance { tol = t }
        // A mathematically tied derivative can straddle the automatic tolerance after roundoff. For SG only, choose
        // the first channel within a per-pixel roundoff allowance: 64 eps * max|cropped input| * sum|interior weights|.
        // This deterministic tie policy intentionally differs from raw exSpy/LAPACK channel choices. A caller-supplied
        // tolerance remains exact, the gradient path is unchanged, and the reported tolerance is not expanded.
        var coefficientL1 = 0.0
        if userTolerance == nil, case .savitzkyGolay(let sg, _) = kernel {
            for coefficient in sg.coefficients { coefficientL1 = coefficientL1 + abs(coefficient) }
        }
        // 4. the first channel at or below tol plus the automatic SG tie allowance, per pixel
        var inflexion = [Int](repeating: 0, count: pixelCount)
        var threshold = [Double](repeating: .nan, count: pixelCount)
        try derivative.withUnsafeMutableBufferPointer { d in
            for p in 0..<pixelCount {
                if p % block == 0 { try SpectroCancellation.check(cancelled); progress?(0.5 + 0.5 * Double(p) / Double(pixelCount)) }
                let row = UnsafeBufferPointer(start: counts.baseAddress! + p * nch + i1, count: length)
                kernel.apply(row, into: d, pixel: p)
                var maxAbsInput = 0.0
                if coefficientL1 > 0 { for value in row { maxAbsInput = max(maxAbsInput, abs(value)) } }
                let scaledEpsilon = (64 * Double.ulpOfOne) * maxAbsInput
                let allowance = scaledEpsilon * coefficientL1
                let comparisonTolerance = tol + allowance
                var first = 0
                for i in 0..<length where abs(d[i]) <= comparisonTolerance { first = i; break }
                inflexion[p] = first
                if first != 0 { threshold[p] = croppedAxis[first] }
            }
        }
        progress?(1)
        return EstimatedThresholds(firstChannel: i1, channels: length, tolerance: tol, minAbsDerivative: minAbs,
                                   inflexionIndex: inflexion, thresholdEV: threshold)
    }
}
