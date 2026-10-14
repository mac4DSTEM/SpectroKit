//
//  EELSThicknessError.swift
//  Role: Everything the thickness map refuses to do, as one error type. A pixel the method cannot answer is NOT an
//        error (it is a `nil` with a `ThicknessUnavailable` reason in the result); these are the calls that cannot start.
//

import Foundation

public nonisolated enum EELSThicknessError: Error, Equatable, Sendable {
    /// `nx`, `ny` or `channels` is not positive, or `counts.count != nx * ny * channels`.
    case invalidShape(nx: Int, ny: Int, channels: Int, counts: Int)
    /// The energy axis needs a finite offset and a finite scale > 0 (HyperSpy's `UniformDataAxis` with a positive scale).
    case invalidEnergyAxis(offsetEV: Double, scaleEV: Double)
    /// A count is NaN or infinite (exSpy would carry the NaN into `tol` and mark every pixel "no inflexion").
    case nonFiniteCounts(pixel: Int)
    /// exSpy `_eels.py:713-714`: the search range holds fewer than 10 channels ("Please select a bigger window").
    case searchWindowTooShort(channels: Int)
    /// `start` or `window` is NaN or infinite, or `window` is negative (HyperSpy `value_range_to_indices` raises on v1 > v2).
    case invalidSearchWindow(startEV: Double, windowEV: Double)
    /// The Savitzky–Golay window or order is outside what SciPy computes (and this port supports): the reason says which.
    case invalidSavitzkyGolay(String)
    /// `tolerance` is NaN or negative.
    case invalidTolerance(Double)
    /// `.perPixel` thresholds must hold one value per pixel.
    case perPixelThresholdCount(expected: Int, got: Int)
    /// A fixed threshold that is NaN, or below the first channel of the axis (exSpy `axes.py:457-461` raises `IndexError`).
    case invalidFixedThreshold(Double)
    /// The zero-loss spectrum image must have the low-loss image's `nx` and `ny` (its channel count may differ: only its sum is used).
    case zeroLossShapeMismatch(expectedNx: Int, expectedNy: Int, gotNx: Int, gotNy: Int)
    /// A mean free path source with a non-finite or non-positive number, or one the model cannot evaluate.
    case invalidMeanFreePath(String)
}
