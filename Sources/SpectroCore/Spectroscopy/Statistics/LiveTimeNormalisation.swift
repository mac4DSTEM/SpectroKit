//
//  LiveTimeNormalisation.swift
//  Role: Put regions with different dead time on a common footing (ADR 054,
//        V5-Q5). Route 1: per-pixel live time, when the file carries it, gives a
//        rate = net counts / summed live time. Route 2: no live time, so the net
//        count of a line is expressed relative to the Al K-alpha net count of the
//        same region (the internal reference). The result NAMES the route.
//
//  The Al-reference route divides two counts of one region; both scale with the
//  same live time, so the ratio is dead-time independent. Its sigma is the delta
//  method with the two nets treated as uncorrelated (DEVIATION from an exact
//  treatment: the fitted Mg and Al amplitudes share the overlap, so their true
//  covariance is not zero. When lane F's covariance is at hand, pass it through
//  `FittedAmplitudes.ratioRelativeVariance` instead).
//

import Foundation

package nonisolated struct NormalisedQuantity: Equatable, Sendable {
    package enum Route: Equatable, Sendable {
        case perPixelLiveTime
        case alKAlphaInternalReference(fallbackReason: String)
        package var label: String {
            switch self {
            case .perPixelLiveTime: return "per-pixel live time"
            case .alKAlphaInternalReference: return "Al Kα internal reference"
            }
        }
    }
    package let value: Double
    package let sigma: Double
    /// "counts/s" for the live-time route, "net / Al Kα net" for the reference route.
    package let unit: String
    package let route: Route
}

package nonisolated enum LiveTimeNormalisation {

    /// Sum of per-pixel live times (seconds) over a region. Pixels with live time <= 0 recorded no
    /// exposure (and no counts) and are left out of the sum. Nil when the file has none, or a value is
    /// not finite (corrupt), or nothing is left: then the reference route runs.
    package static func pooledLiveTime(perPixel: [Double]?) -> Double? {
        guard let t = perPixel, !t.isEmpty, t.allSatisfy({ $0.isFinite }) else { return nil }
        let live = t.filter { $0 > 0 }.reduce(0, +)
        return live > 0 ? live : nil
    }

    /// Normalise a region's net line counts. `liveTimes` = the live time of each
    /// pooled pixel (nil when the file has none). `referenceNet` / `referenceVariance`
    /// = the Al Kα net count and variance of the SAME region.
    package static func normalise(net: Double, variance: Double,
                                  liveTimes: [Double]?,
                                  referenceNet: Double, referenceVariance: Double) -> NormalisedQuantity? {
        if let live = pooledLiveTime(perPixel: liveTimes) {
            return NormalisedQuantity(value: net / live, sigma: variance.squareRoot() / live,
                                      unit: "counts/s", route: .perPixelLiveTime)
        }
        guard referenceNet > 0 else { return nil }
        let reason: String
        if liveTimes == nil || liveTimes?.isEmpty == true { reason = "no per-pixel live time in the file" }
        else { reason = "per-pixel live time is not finite and positive" }
        let ratio = net / referenceNet
        let relVar = (net == 0 ? 0 : variance / (net * net)) + referenceVariance / (referenceNet * referenceNet)
        let sigma = abs(ratio) * relVar.squareRoot()
            + (net == 0 ? variance.squareRoot() / referenceNet : 0)
        return NormalisedQuantity(value: ratio, sigma: sigma, unit: "net / Al Kα net",
                                  route: .alKAlphaInternalReference(fallbackReason: reason))
    }

    /// Whether two normalised quantities agree within `k` combined sigma.
    package static func agree(_ a: NormalisedQuantity, _ b: NormalisedQuantity, withinSigmas k: Double = 1) -> Bool {
        abs(a.value - b.value) <= k * (a.sigma * a.sigma + b.sigma * b.sigma).squareRoot()
    }
}
