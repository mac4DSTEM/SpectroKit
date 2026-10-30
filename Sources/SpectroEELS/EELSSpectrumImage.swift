//
//  EELSSpectrumImage.swift
//  Role: What the EELS operations share (docs/design/eels-chain.md): one protocol over the low-loss and the
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
    /// The zero-loss threshold has no value for this pixel (no inflexion found, or the threshold lies outside the axis).
    case noThreshold
    /// The edge model could not be fitted at this pixel (the least-squares solve failed or the spectrum has no support).
    case fitFailed
    /// A composition cannot be formed: the fitted amounts sum to zero or an element's amount is missing.
    case noComposition
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
    /// `estimate_peak_width`'s `factor` must lie strictly between 0 and 1.
    case invalidPeakFactor(Double)
    /// The first low-loss spectrum has no two-root half-maximum, so no Gaussian width can be estimated (pass `fwhmEV`).
    case noPeakWidth
    case invalidIterations(Int)
    case extrapolationWindowTooWide(window: Int, channels: Int)
    case tooFewChannels(Int)
    /// Accelerate could not set up a transform of this length.
    case fftSetup(size: Int)
}

public nonisolated enum EELSModelError: Error, Equatable, Sendable {
    case noEdgeInRange(fromEV: Double, toEV: Double)
    case edgeNotBundled(String)
    case duplicateEdge(String)
    case lowLossShapeMismatch(expected: Int, got: Int)
    case backgroundWindowEmpty
    case fitDidNotConverge(pixel: Int)
    /// The low-loss channel width differs from the core loss's, so exSpy's convolution would shift the edge.
    case lowLossScaleMismatch(coreEV: Double, lowEV: Double)
    /// The low-loss axis has no zero-loss channel (exSpy's `value2index(0)` raises).
    case lowLossAxisHasNoZero
    /// `windowEV` or the pre-edge window cannot be placed on the axis (too few channels below the first edge).
    case preEdgeWindowTooNarrow(channels: Int)
    case invalidMicroscope
    case crossSectionFailed(String)
    /// A symbol passed to `composition` has no fitted edge.
    case symbolNotFitted(String)
    case invalidExponentRange
    case maskShapeMismatch(expected: Int, got: Int)
    case emptyMask
    /// `edgeWindows` must hold one entry per fitted edge (the result's `edges`: twins of one element and family are one), in onset order.
    case edgeWindowCountMismatch(expected: Int, got: Int)
    /// Two edges' signal windows share energies; each channel of the signal belongs to one edge.
    case overlappingSignalWindows(String, String)
    /// A window that is not finite, empty, too narrow (background 4 channels, signal 2), not inside the axis, or not at positive energy.
    case edgeWindowInvalid(edge: String, why: String)
    /// `EELSBackground.preview` could not estimate a power law (a window sum that is not positive, or a non-finite result).
    case backgroundNotEstimable(String)
}
