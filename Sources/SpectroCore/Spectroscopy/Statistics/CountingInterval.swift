//
//  CountingInterval.swift
//  Role: Poisson counting statistics for window counts: the Garwood exact
//        interval at EVERY count (ADR 054 addendum: the "~20 counts" switch was a
//        threshold and is dropped), and the net count N = G - s*B with
//        Var = G + s^2*B. Inputs are plain numbers (gross G, background B, scale
//        s = signal-window / background-window channel ratio), so the layer does
//        not depend on the spectrum-image types.
//
//  Garwood (1936): for an observed count n the two-sided interval with
//  confidence 1 - alpha on the Poisson mean is
//      lower = chi2(alpha/2; 2n) / 2          (0 when n = 0)
//      upper = chi2(1 - alpha/2; 2n + 2) / 2
//  i.e. the gamma quantiles with shapes n and n + 1. Exact intervals over-cover
//  a discrete Poisson by construction; the coverage test measures by how much.
//

import Foundation

package nonisolated struct CountingInterval: Equatable, Sendable {
    /// One line the room can show beside a Garwood interval (measured coverage of the
    /// exact interval at nominal 68 %: 0.96 at N = 0.3 down to 0.69 at N = 30).
    package static let roomCaption = "68 % exact Poisson interval; conservative below ~10 counts"

    package let count: Double
    package let lower: Double
    package let upper: Double
    package let confidence: Double

    /// Garwood interval for a (non-negative, normally integer) observed count.
    /// Non-integer counts use the gamma generalisation (shapes n, n + 1).
    package static func garwood(count n: Double, confidence: Double = 0.95) -> CountingInterval {
        precondition(n >= 0 && n.isFinite, "a count must be finite and >= 0")
        precondition(confidence > 0 && confidence < 1, "confidence must be in (0, 1)")
        let alpha = 1 - confidence
        let lower = n == 0 ? 0 : IncompleteGamma.gammaQuantile(p: alpha / 2, shape: n)
        let upper = IncompleteGamma.gammaQuantile(p: 1 - alpha / 2, shape: n + 1)
        return CountingInterval(count: n, lower: lower, upper: upper, confidence: confidence)
    }

    package var width: Double { upper - lower }
    package func contains(_ mean: Double) -> Bool { mean >= lower && mean <= upper }

    /// The same interval shrunk about the observed count by `factor` (0.5 =
    /// halved). Used only by the coverage test to prove it can fail.
    package func scaled(about centre: Double? = nil, by factor: Double) -> CountingInterval {
        let c = centre ?? count
        return CountingInterval(count: count, lower: c - (c - lower) * factor,
                                upper: c + (upper - c) * factor, confidence: confidence)
    }
}

/// Net counts of a line window: N = G - s*B with Var = G + s^2*B, where G is the
/// gross count in the signal window, B the count in the background window(s) and
/// s the ratio (signal channels) / (background channels) that scales B into the
/// signal window. The room shows net ± sigma (measured coverage 0.68 even at net 0)
/// and the Garwood interval for the GROSS count; there is no exact interval for the
/// net, so none is offered (an interval-arithmetic one measured 0.81-0.86 at nominal 0.68).
package nonisolated struct NetCounts: Equatable, Sendable {
    package let gross: Double
    package let background: Double
    package let scale: Double

    package init(gross: Double, background: Double, scale: Double) {
        precondition(gross >= 0 && background >= 0 && scale > 0, "G, B >= 0 and s > 0")
        self.gross = gross
        self.background = background
        self.scale = scale
    }

    package var net: Double { gross - scale * background }
    package var variance: Double { gross + scale * scale * background }
    package var sigma: Double { variance.squareRoot() }

    package func grossInterval(confidence: Double = 0.95) -> CountingInterval {
        CountingInterval.garwood(count: gross, confidence: confidence)
    }
}
