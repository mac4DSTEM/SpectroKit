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
///   **The derivative is SciPy's bit for bit** (`savgol_filter(..., deriv=1, mode="interp")` as HyperSpy calls it on the whole
///   image: LAPACK `dgelsd` coefficients, `_fit_edge` polynomial fits, SciPy's accumulation order), so the threshold channel is
///   exSpy's, also where a channel's |derivative| equals `tol` to rounding. The edge fits are one least-squares call over the
///   image's spectra, as in SciPy, whose bits depend on how many spectra there are: a pixel's derivative, and so (very rarely,
///   at such a tie) its threshold, can differ in the last bits between a small image and the same pixel in a larger one, in exSpy
///   as here. **Narrower than exSpy:** the port refuses an even `windowLength`, one below 3, a `polynomialOrder` below 1 (SciPy
///   returns zeros) and one of `windowLength` or more; exSpy accepts some of these.
/// - `.fixed(eV)`: one threshold for every pixel (exSpy `threshold=<float>`). Rounded to a channel by HyperSpy's
///   `value2index` (a value up to half a channel off is the same channel). **`.fixed(3)` is 3.0 eV**; exSpy treats a Python
///   `int` threshold as a channel index, which this type cannot express.
/// - `.perPixel`: one threshold in eV per pixel, row-major `y * nx + x` (exSpy `threshold=<signal>`); NaN marks a pixel with none.
///   A threshold outside the energy axis gives that pixel no t/λ (a nil pixel with a reason); exSpy raises for the whole map.
public nonisolated enum ThresholdRule: Sendable, Equatable {
    case estimated(window: Double = 10.0, start: Double = 1.0, windowLength: Int = 5, polynomialOrder: Int = 3,
                   tolerance: Double? = nil)
    case fixed(Double)
    case perPixel([Double])
}
