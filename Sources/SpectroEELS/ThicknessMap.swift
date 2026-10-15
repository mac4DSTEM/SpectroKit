//
//  ThicknessMap.swift
//  Role: What the log-ratio method answers, per pixel, and how it was made.
//

import Foundation

/// Why a pixel has no t/λ.
public nonisolated enum ThicknessUnavailable: String, Sendable, Equatable, CustomStringConvertible {
    /// The estimated rule found no inflexion: the first channel of the search range is already at or below `tol`, or no
    /// channel is (exSpy marks the threshold NaN, `_eels.py:730-735`).
    case noInflexionFound
    /// A `.perPixel` threshold of NaN.
    case thresholdNotANumber
    /// The threshold rounds to a channel outside the axis (exSpy's `value2index` raises there, `_eels.py:614`).
    case thresholdOutsideAxis
    /// I_0 <= 0: ln(I_t / I_0) is undefined.
    case zeroLossIntensityNotPositive
    /// I_t <= 0 with I_0 > 0: ln of a non-positive ratio.
    case totalIntensityNotPositive

    public var description: String {
        switch self {
        case .noInflexionFound: "no inflexion point in the search range (the derivative is already at or below tol at its first channel, or never is)"
        case .thresholdNotANumber: "the per-pixel threshold is NaN"
        case .thresholdOutsideAxis: "the threshold lies outside the energy axis"
        case .zeroLossIntensityNotPositive: "I_0 <= 0, so t/lambda = ln(I_t/I_0) is undefined"
        case .totalIntensityNotPositive: "I_t <= 0, so t/lambda = ln(I_t/I_0) is undefined"
        }
    }
}

/// Why a pixel has a t/λ but no `sigmaCounting`.
public nonisolated enum SigmaUnavailable: String, Sendable, Equatable, CustomStringConvertible {
    /// I_0 comes from a separate zero-loss spectrum, not a subset of I_t: Var(ln I_t - ln I_0) = 1/I_t + 1/I_0 for two
    /// independent Poisson counts, but only if both are electron counts on the same scale, which the stored counts do not say.
    case zeroLossFromSeparateSpectrum
    /// I_t < I_0: the counts are not nested (the registration's formula needs I_0 to be a part of I_t).
    case totalBelowZeroLoss

    public var description: String {
        switch self {
        case .zeroLossFromSeparateSpectrum: "I_0 is from a separate zero-loss spectrum; the nested-counts formula does not apply"
        case .totalBelowZeroLoss: "I_t < I_0: the counts are not nested"
        }
    }
}

/// One pixel of a `ThicknessMap`.
public nonisolated struct ThicknessPixel: Sendable, Equatable {
    /// t/λ = ln(I_t / I_0), the log-ratio method (exSpy `_eels.py:817`). NOT multiplied by the angular correction, and not
    /// clipped: I_t <= I_0 is reported as t/λ <= 0. nil with `unavailable` where the method cannot answer.
    public let tOverLambda: Double?
    /// The counting-statistics standard deviation of t/λ, sqrt(1/I_0 - 1/I_t), when the stored counts are Poisson counts and
    /// I_0 is a part of I_t (registration section 6). It is a FIRST-ORDER (delta-method) value, not exact: a Monte Carlo by the Gate B
    /// refuter gave actual/formula standard deviation of 1.0009 at I_0 = 1000 (I_t/I_0 near 300), 1.009 at I_0 = 100 (20), 1.055
    /// at I_0 = 20 (5) and 1.129 at I_0 = 10 (3): the formula is about 13 % low at I_0 near 10 counts and good above I_0 near 100.
    /// I_0 = I_t gives 0. It does NOT include the threshold's variability (with the estimated rule
    /// on noisy data the standard deviation of t/λ was 1.0 to 3.2 times larger), the λ model, or the angular correction's inputs.
    public let sigmaCounting: Double?
    /// The zero-loss intensity: the sum of channels `[0, thresholdChannel)`, or the sum of the zero-loss spectrum. nil where no threshold.
    public let i0: Double?
    /// The sum over every channel of the spectrum.
    public let iTotal: Double
    /// The energy the zero-loss sum stops at, eV (the channel at it is not in the sum). nil with the zero-loss-spectrum route or where none was found.
    public let thresholdEV: Double?
    /// The channel `value2index(thresholdEV)`; the zero-loss sum is channels `[0, thresholdChannel)` (the channel count itself for a
    /// fixed threshold above the axis, where I_0 = I_t, exSpy `axes.py:462-466`).
    public let thresholdChannel: Int?
    /// The energy of the spectrum's maximum, eV: a diagnostic of zero-loss alignment (exSpy `estimate_zero_loss_peak_centre`,
    /// `_eels.py:271-312`, without its mask). Nothing is shifted.
    public let zlpCentreEV: Double
    /// Absolute thickness in nm: (t/λ · angular correction) · λ, or t/λ · λ with a bare given λ. nil without a λ source or t/λ.
    public let thicknessNM: Double?
    /// Why `tOverLambda` is nil.
    public let unavailable: ThicknessUnavailable?
    /// Why `sigmaCounting` is nil where `tOverLambda` is not.
    public let sigmaUnavailable: SigmaUnavailable?
}

/// How I_0 was obtained for a map.
public nonisolated enum ZeroLossSource: Sendable, Equatable {
    case threshold(ThresholdRule)
    /// The sum of a separate zero-loss spectrum image (exSpy `zlp=`, `_eels.py:810-811`).
    case zeroLossSpectrum
}

/// The t/λ thickness map of a low-loss spectrum image by the log-ratio method, ported from exSpy 7185a4d1
/// (`estimate_thickness`, `_eels.py:755-868`).
///
/// **Validation: none.** `validation` stays "none": agreement with exSpy and recovery of planted t/λ do not make a thickness
/// right on a real specimen (registration section 8). The method has its own bias (the plasmon below the threshold counts
/// as zero loss; the loss tail past the axis is missing from I_t), about 5e-4 at the planted t/λ = 2 with the estimated threshold
/// and more with a fixed one.
///
/// **`sigmaCounting` is the counting error at a given threshold, nothing more.** It leaves out the threshold's variability,
/// which, with the estimated rule on noisy data, made the standard deviation of t/λ 1.0 to 3.2 times larger on the registered
/// planted images (the estimated threshold is set by one global `tol`, which the noisiest pixel decides). Noisy data want a fixed threshold.
/// The stored counts are also not electron counts unless the detector's conversion has been applied; a consumer must carry the
/// λ source and its own uncertainty separately.
public nonisolated struct ThicknessMap: Sendable {
    public let nx: Int
    public let ny: Int
    /// Row-major `y * nx + x`.
    public let pixels: [ThicknessPixel]
    /// "log-ratio, exSpy 7185a4d1".
    public let method: String
    public let zeroLoss: ZeroLossSource
    public let meanFreePath: MeanFreePathSource?
    /// The λ in nm that multiplied t/λ (given, or Iakoubovskii's); nil without a λ source.
    public let meanFreePathNM: Double?
    /// exSpy's angular correction that multiplied t/λ before λ did; nil when no density was given.
    public let angularCorrection: Double?
    /// The global `tol` (counts/eV) the estimated rule used; nil for other rules.
    public let estimatedTolerance: Double?
    /// "none" until a sample of known thickness has been measured (registration section 8).
    public let validation: String

    public subscript(x: Int, y: Int) -> ThicknessPixel { pixels[y * nx + x] }
}
