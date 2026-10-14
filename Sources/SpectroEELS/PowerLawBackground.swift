//
//  PowerLawBackground.swift
//  Role: The pre-edge background A E^-r by HyperSpy 2.4.0's two-area estimate (`_components/power_law.py:100-187`,
//        `PowerLaw.estimate_parameters`), evaluated as `remove_background(fast=True)` evaluates it on a binned axis
//        (`_signals/signal1d.py:1102-1152`; `models/model1d.py:375-390`: the component's value times the channel width).
//        EELS slice 2, registration section 3.1.
//
//  Departure from HyperSpy, registered (section 1): where a window sum is not positive or A, r come out non-finite,
//  HyperSpy's `nan_to_num` (or, on a zero sum, the whole image's estimate failing) is replaced by a nil pixel with its
//  reason. Everything else is HyperSpy's arithmetic in its order.
//

import Foundation
import SpectroCore

package nonisolated struct PowerLawWindow: Sendable, Equatable {
    package let i1: Int, i2: Int, i3: Int
    package let x1: Double, x2: Double, x3: Double

    /// `value_range_to_indices(x1, x2)` and the parity rule (`power_law.py:127-135`).
    package init(axis: EELSAxis, from lo: Double, to hi: Double) throws {
        var (i1, i2) = try axis.valueRangeToIndices(lo, hi)
        if (i2 + i1) % 2 != 0 { i2 -= 1 }
        if i2 == i1 { i2 += 2 }
        let i3 = (i2 + i1) / 2
        guard i1 >= 0, i1 < i3, i3 < i2, i2 <= axis.size else {
            throw EELSEdgeError.backgroundWindowTooNarrow(fromEV: lo, toEV: hi)
        }
        self.i1 = i1; self.i2 = i2; self.i3 = i3
        x1 = axis.energy(ofChannel: i1); x2 = axis.energy(ofChannel: i2); x3 = axis.energy(ofChannel: i3)
        guard x1 > 0 else { throw EELSEdgeError.backgroundWindowNotPositive(fromEV: lo) }
    }
}

package nonisolated struct PowerLawFit: Sendable, Equatable {
    package let i1Sum: Double, i2Sum: Double
    package let r: Double, a: Double

    package init(i1Sum: Double, i2Sum: Double, r: Double, a: Double) {
        self.i1Sum = i1Sum; self.i2Sum = i2Sum; self.r = r; self.a = a
    }

    /// The two sums over `[i1, i3)` and `[i3, i2)` of one pixel's spectrum, then r and A. nil with a reason where the
    /// method cannot answer.
    package static func estimate(_ spectrum: UnsafeBufferPointer<Double>, window w: PowerLawWindow)
        -> Result<PowerLawFit, EdgeUnavailable> {
        let base = spectrum.baseAddress!
        let s1 = NumpySum.pairwise(base + w.i1, count: w.i3 - w.i1)
        let s2 = NumpySum.pairwise(base + w.i3, count: w.i2 - w.i3)
        guard s1 > 0, s2 > 0 else { return .failure(.backgroundSumNotPositive) }
        let r = 2 * (log(s1) - log(s2)) / (log(w.x2) - log(w.x1))
        let k = 1 - r
        let a = k * s2 / (Libm.pow(w.x2, k) - Libm.pow(w.x3, k))
        guard r.isFinite, a.isFinite else { return .failure(.backgroundNotFinite) }
        return .success(PowerLawFit(i1Sum: s1, i2Sum: s2, r: r, a: a))
    }

    /// The background in channel c on a binned axis: (0 + A (x - 0)^-r) * scale, 0 for x <= 0 (left_cutoff).
    package func counts(atEnergy x: Double, scale: Double) -> Double {
        guard 0 < x else { return 0 }
        let f = 0.0 + a * Libm.pow(-0.0 + x, -r)
        return f * scale
    }

    /// d(sum of the background over `energies`)/d(I1) and /d(I2), through r(I1, I2) and A(r, I2) (registration
    /// section 6), for the counting-statistics variance.
    package func backgroundSensitivity(window w: PowerLawWindow, energies: [Double], scale: Double)
        -> (dI1: Double, dI2: Double) {
        let k = 1 - r
        let l = log(w.x2) - log(w.x1)
        var s0 = 0.0, s1 = 0.0
        for x in energies where x > 0 {
            let p = pow(x, -r) * scale
            s0 += p
            s1 += p * log(x)
        }
        let d = pow(w.x2, k) - pow(w.x3, k)
        let dD = -pow(w.x2, k) * log(w.x2) + pow(w.x3, k) * log(w.x3)          // dD/dr
        let dAdI2 = k / d
        let dAdr = i2Sum * (-d - k * dD) / (d * d)
        let dBdA = s0, dBdr = -a * s1
        let total = dBdA * dAdr + dBdr                                          // dB/dr with A following r
        let drdI1 = 2 / (l * i1Sum), drdI2 = -2 / (l * i2Sum)
        return (total * drdI1, dBdA * dAdI2 + total * drdI2)
    }
}
