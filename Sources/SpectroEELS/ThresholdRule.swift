//
//  ThresholdRule.swift
//  Role: How the zero-loss intensity I_0 is cut from a low-loss spectrum: the energy up to which counts are zero-loss.
//

import Foundation

/// The energy threshold θ that ends the zero-loss sum, `I_0 = sum of channels [0, value2index(θ))` (exSpy
/// `estimate_elastic_scattering_intensity`, `_eels.py:566-639`; the channel at θ is not in the sum).
///
/// - `.estimated`: exSpy's `estimate_elastic_scattering_threshold` (`_eels.py:641-753`): the first inflexion of the spectrum's
///   Savitzky–Golay derivative inside `[start, start + window)` eV, where "inflexion" means the first channel with
///   |derivative| ≤ `tol`. When `tolerance` is nil, `tol` is ONE number for the whole image: the largest over pixels of each
///   pixel's smallest |derivative| in the range. So one pixel's threshold depends on every other pixel; and **on noisy
///   data the threshold is not stable** (a single noisy pixel sets `tol` for all): on the registration's planted noisy image
///   the thresholds ran from 1.30 to 8.65 eV where the noiseless ones ran from 1.20 to 1.35 eV, and `sigmaCounting` leaves
///   that variability out (see `ThicknessMap`). Noisy data want `.fixed`.
///   `windowLength == 0` uses `numpy.gradient` instead of Savitzky–Golay (exSpy's `window_length=0`).
///   A pixel whose first inflexion is the search range's first channel (or that has none) has no threshold (exSpy: NaN).
///   The Savitzky–Golay polynomial is fitted by LAPACK's SVD (`dgelsd`), as SciPy's `savgol_coeffs` does. With automatic tolerance, derivative magnitudes within `64 * Double.ulpOfOne * peak * coefficientL1`
///   of `tol` are tied; the first channel wins. Here `peak` is the largest absolute cropped input count in that pixel and
///   `coefficientL1` is the sum of absolute interior filter coefficients. This roundoff allowance intentionally differs
///   from raw exSpy's CPU-dependent choices at ties, and can change I_0 and thickness. A supplied `tolerance` uses an exact
///   comparison with no allowance. The gradient path is unchanged.
///   **Narrower than exSpy:** the port refuses an even `windowLength`, one below 3, a `polynomialOrder` below 1 (SciPy
///   returns zeros) and one of `windowLength` or more; exSpy accepts some of these.
/// - `.fixed(eV)`: one threshold for every pixel (exSpy `threshold=<float>`). Rounded to a channel by HyperSpy's
///   `value2index` (a value up to half a channel off is the same channel). **`.fixed(3)` is 3.0 eV**; exSpy treats a Python
///   `int` threshold as a channel index, which this type cannot express.
/// - `.perPixel`: one threshold in eV per pixel, row-major `y * nx + x` (exSpy `threshold=<signal>`); NaN marks a pixel with none.
///   A threshold outside the energy axis gives that pixel no t/λ (a nil pixel with a reason); exSpy raises for the whole map.
///
/// The defaults of `.estimated` (window 10 eV, start 1 eV, Savitzky–Golay window length 5, order 3, tolerance from the data) are exSpy's
/// `estimate_elastic_scattering_threshold` (`_eels.py:641-643`). The automatic first-index tie allowance is SpectroKit's
/// documented deviation from exSpy's platform-dependent rounding at ties.
public nonisolated enum ThresholdRule: Sendable, Equatable {
    case estimated(window: Double = 10.0, start: Double = 1.0, windowLength: Int = 5, polynomialOrder: Int = 3,
                   tolerance: Double? = nil)
    case fixed(Double)
    case perPixel([Double])
}
