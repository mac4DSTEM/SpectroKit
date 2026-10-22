//
//  TailEstimate.swift
//  Role: Measure the low-energy tail of the line shape (`LineTail`) on a spectrum of listed elements: the tail fraction and slope that
//        minimise the fit's residual sum of squares. A grid search (11 fractions x 11 log-spaced slopes), then two passes that halve the
//        grid about the best point. One linear fit (`EDSFit.run`, the settings' own background and method) per grid point.
//        No Python counterpart; `validation: "none"` until measured on a standard.
//

import Foundation
import SpectroCore

public nonisolated enum TailEstimate {

    /// The tail that best fits `counts`, with the residual norm (square root of the residual sum of squares over the fitted channels)
    /// with it and without it. `elements` replaces `settings.elements`; every other setting is the fit's own. Cancellation is checked
    /// between fits.
    public static func measure(
        counts: [Double], axis: EnergyAxis, settings: FitSettings, elements: [String],
        searchFraction: ClosedRange<Double> = 0...0.2, searchSlopeKeV: ClosedRange<Double> = 0.05...1.0,
        cancelled: @Sendable () -> Bool = SpectroCancellation.task
    ) throws -> (tail: LineTail, residualNorm: Double, residualNormWithout: Double) {
        var s = settings
        s.elements = elements
        let channels = axis.fitChannels(from: s.fitFrom, to: s.fitTo)

        func rss(_ tail: LineTail?) throws -> Double {
            try SpectroCancellation.check(cancelled)
            s.lineTail = tail
            let r = try EDSFit.run(counts: counts, axis: axis, settings: s, channels: channels, computeCovariance: false)
            return r.residual.reduce(0) { $0 + $1 * $1 }
        }

        let without = try rss(nil)
        let m = 11
        var fLo = searchFraction.lowerBound, fHi = searchFraction.upperBound
        var bLo = log(searchSlopeKeV.lowerBound), bHi = log(searchSlopeKeV.upperBound)
        var best = (f: fLo, beta: exp((bLo + bHi) / 2), rss: Double.infinity)
        for pass in 0..<3 {   // the grid, then two halvings about the best
            if pass > 0 {
                let fw = (fHi - fLo) / 2, bw = (bHi - bLo) / 2
                fLo = max(searchFraction.lowerBound, best.f - fw / 2); fHi = min(searchFraction.upperBound, best.f + fw / 2)
                bLo = max(log(searchSlopeKeV.lowerBound), log(best.beta) - bw / 2)
                bHi = min(log(searchSlopeKeV.upperBound), log(best.beta) + bw / 2)
            }
            for i in 0..<m {
                let f = fLo + (fHi - fLo) * Double(i) / Double(m - 1)
                for j in 0..<m {
                    let beta = exp(bLo + (bHi - bLo) * Double(j) / Double(m - 1))
                    let v = try rss(LineTail(fraction: f, slopeKeV: beta, source: ""))
                    if v < best.rss { best = (f, beta, v) }
                }
            }
        }
        guard best.rss.isFinite else { throw EDSFitError.noChannels }   // every grid point failed to fit: nothing to measure
        let before = without.squareRoot(), after = best.rss.squareRoot()
        let source = "measured on \(channels.count) channels, residual \(String(format: "%.4g", before)) to \(String(format: "%.4g", after))"
        // A fraction of 0 is "no tail found": the slope is then the grid's edge and means nothing; the source says so.
        let found = best.f > 0 ? source : "no tail found (fraction 0)"
        return (LineTail(fraction: best.f, slopeKeV: best.beta, source: found), after, before)
    }
}
