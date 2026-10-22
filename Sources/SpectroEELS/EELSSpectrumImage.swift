//
//  EELSSpectrumImage.swift
//  Role: What task 16's operations share (docs/design/eels-task-16.md sections 1 and 2): one protocol over the low-loss and the
//        core-loss spectrum image, so alignment, taper and extrapolation return the caller's own type; the per-pixel "no answer"
//        reasons; the error cases of alignment, deconvolution and the edge model.
//

import Foundation
import SpectroCore

/// A spectrum image on a uniform energy axis: `counts[(y * nx + x) * channels + c]`, channel `c` at `energyOffsetEV + energyScaleEV * c`.
/// `LowLossSpectrumImage` and `CoreLossSpectrumImage` conform; the initialiser validates as theirs do (finite counts, scale > 0).
public protocol EELSSpectrumImage: Sendable {
    var nx: Int { get }
    var ny: Int { get }
    var channels: Int { get }
    var counts: [Double] { get }
    var energyOffsetEV: Double { get }
    var energyScaleEV: Double { get }
    init(nx: Int, ny: Int, channels: Int, counts: [Double], energyOffsetEV: Double, energyScaleEV: Double) throws
}

extension LowLossSpectrumImage: EELSSpectrumImage {}
extension CoreLossSpectrumImage: EELSSpectrumImage {}

extension EELSSpectrumImage {
    public var pixelCount: Int { nx * ny }
}

/// A per-pixel answer a method could not give, with the reason (the kit's rule: nil with a reason, never NaN).
public nonisolated enum EELSUnavailable: String, Error, Sendable, Equatable {
    /// The pixel was masked out by the caller.
    case masked
    /// The result at this pixel is not finite (a division or a logarithm that left the real line).
    case nonFiniteResult
    /// The spectrum has no peak to measure (all channels equal or no finite channel).
    case noPeak
    /// A division by zero (a Richardson-Lucy iterate, a Fourier-ratio denominator).
    case divisionByZero
    /// The half-maximum has not exactly two roots, so no width (exSpy `estimate_peak_width` gives NaN).
    case noTwoRoots
}

public nonisolated enum EELSAlignmentError: Error, Equatable, Sendable {
    /// `mask` has the wrong number of entries (one per pixel, row-major).
    case maskShapeMismatch(expected: Int, got: Int)
    /// The `also` image at this index does not have the image's `nx` and `ny`.
    case alsoAlignShapeMismatch(index: Int)
    /// The search window lies wholly outside the axis (HyperSpy `IndexError` / `ValueError`).
    case signalRangeOutsideAxis(fromEV: Double, toEV: Double)
    /// The shifts leave no channel defined everywhere (cropping would empty the axis).
    case emptyAfterCrop
    /// A shift is NaN or infinite (pass nil, not NaN, to leave a pixel alone).
    case nonFiniteShift(pixel: Int)
    /// `interpolationPoints` below zero, or an empty / reversed search window.
    case invalidOption(String)
    /// The shift array does not hold one value per pixel.
    case shiftCountMismatch(expected: Int, got: Int)
}

public nonisolated enum EELSDeconvolutionError: Error, Equatable, Sendable {
    case shapeMismatch(expected: Int, got: Int)
    case kernelSizeMismatch(expected: Int, got: Int)
    case invalidFWHM(Double)
    case invalidIterations(Int)
    case extrapolationWindowTooWide(window: Int, channels: Int)
    case tooFewChannels(Int)
}

public nonisolated enum EELSModelError: Error, Equatable, Sendable {
    case noEdgeInRange(fromEV: Double, toEV: Double)
    case edgeNotBundled(String)
    case duplicateEdge(String)
    case lowLossShapeMismatch(expected: Int, got: Int)
    case backgroundWindowEmpty
    case fitDidNotConverge(pixel: Int)
}
