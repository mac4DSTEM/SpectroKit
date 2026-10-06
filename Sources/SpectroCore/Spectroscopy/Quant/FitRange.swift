//
//  FitRange.swift
//  Role: WP3c, "the default fit range, not the continuum" (docs/archive/v5/wp3c-fit-range-preregistration-2026-10-06.md).
//        The Quantify fit's upper energy limit as one value with its provenance (`FitRangeChoice`, the footer's "fit range"
//        line), and the range-sensitivity statement (`FitRangeSensitivity`): when the axis runs past the default range, one
//        extra fit to the axis end, reported per quantified element as a named statement, never as a sigma term.
//
//  Why a range and not a model change: with a complete element list the continuum (Kramers x Bernstein(9, 5), Al K split)
//  is unbiased on a weak line at every upper limit from 11 to 60 keV and biased only at the end of an 80 keV axis (Ti -8 %,
//  z -2.28 on the realistic-L synthetic, E1); the orders were measured on 20 keV axes (`Continuum.swift`). So the default
//  stops at 20 keV (`FitSettings.defaultUpperLimitKeV`) and the user may type a longer range under Expert.
//
//  The statement is a statement, not an uncertainty (the absorption AM/GM precedent): it says how far one other defensible
//  range moves each net, it is kept out of `SigmaTerms` and out of every shown sigma, and a model-uncertainty sigma
//  (list x range x estimator) is its own registration.
//
//  It runs with the unlisted-line check (WP3b F1), after each fit, in the same detached task (`SpectroscopyRoomController`):
//  the check's proposer and refit first, then this one refit; neither runs the other's work, and the proposer runs once.
//  The refit reuses the reported fit's axis refinement, so only the range differs; the element list is the reported fit's.
//

import Foundation

/// The fitted range as run: 0.2 keV to `toKeV`, and where `toKeV` came from.
package nonisolated struct FitRangeChoice: Sendable, Equatable {
    package enum Source: String, Sendable, Equatable {
        /// The default 20 keV limit, below the axis end and the beam energy.
        case defaultLimit
        /// The default reached the axis end or the beam energy before 20 keV (every fixture axis ends at 19.997-20.03 keV).
        case defaultReach
        /// eXSpy's whole-range polynomial (the parity path) keeps the whole axis, as eXSpy fits it.
        case polynomialWholeRange
        /// Typed under Expert (`QuantificationMethod.fitToKeV`), possibly clamped to the axis end or the beam energy.
        case typed
    }

    package var fromKeV = 0.2
    package var toKeV: Double
    package var source: Source
    /// The FILE's axis end (what the footer names) and the beam energy.
    package var axisEndKeV: Double
    package var beamEnergyKeV: Double
    /// How far this fit can reach: min(the used axis end, beam energy). The used axis is the refined one unless locked.
    package var reachKeV: Double
    /// The typed value as typed (it may exceed the reach); nil unless `source == .typed`.
    package var typedKeV: Double?

    /// The default is decided on the FILE axis: when min(file axis end, beam) is at most `FitSettings.defaultUpperLimitKeV`, the
    /// fit runs to the used axis end exactly as before WP3c (so a 19.997 keV file whose refined axis ends at 20.002 keV fits the
    /// same channels as it always did); past it, the fit stops at 20 keV. Deciding on the refined axis instead put a 20.002 keV
    /// refined end "past the default" and ran a second fit on every 20 keV file (P3.log, lane C, refuted and fixed).
    package init(method: QuantificationMethod, fileAxis: EnergyAxis, usedAxis: EnergyAxis, beamEnergy: Double) {
        axisEndKeV = fileAxis.highValue
        beamEnergyKeV = beamEnergy
        let reach = min(usedAxis.highValue, beamEnergy)
        reachKeV = reach
        if let t = method.fitToKeV {
            typedKeV = t; toKeV = min(t, reach); source = .typed
        } else if method.background == .wholeRangePolynomial6 {
            toKeV = reach; source = .polynomialWholeRange
        } else if FitSettings.defaultFitTo(axis: fileAxis, beamEnergy: beamEnergy) < min(fileAxis.highValue, beamEnergy),
                  FitSettings.defaultUpperLimitKeV < reach {
            toKeV = FitSettings.defaultUpperLimitKeV; source = .defaultLimit
        } else {
            toKeV = reach; source = .defaultReach
        }
    }

    private static func keV(_ v: Double) -> String { String(format: "%g", v) }
    /// Four significant digits for the reach (79.97, 20.03): the exact value is in the axis readout.
    static func shortKeV(_ v: Double) -> String { String(format: "%.4g", v) }

    /// "0.2–20 keV"
    package var rangeText: String { "\(Self.keV(fromKeV))\u{2013}\(Self.keV(toKeV)) keV" }

    /// The reach in words: "axis to 80 keV" or "beam energy 30 keV".
    private var reachText: String {
        axisEndKeV <= beamEnergyKeV ? "axis to \(Self.shortKeV(axisEndKeV)) keV" : "beam energy \(Self.shortKeV(beamEnergyKeV)) keV"
    }

    /// The footer's line, e.g. "fit range 0.2–20 keV (default; axis to 79.97 keV)".
    package var footerText: String {
        let why: String
        switch source {
        case .defaultLimit: why = "default; \(reachText)"
        case .defaultReach: why = axisEndKeV <= beamEnergyKeV ? "default; the axis end" : "default; the beam energy"
        case .polynomialWholeRange: why = "whole range, eXSpy parity"
        case .typed:
            let t = typedKeV ?? toKeV
            why = t > toKeV ? "typed \(Self.shortKeV(t)) keV, clamped: \(reachText)" : "typed; \(reachText)"
        }
        return "fit range \(rangeText) (\(why))"
    }
}

/// What a fit to the axis end does to each quantified net (WP3c). Kept out of every sigma.
package nonisolated struct FitRangeSensitivity: Sendable, Equatable {
    package struct Move: Sendable, Equatable {
        package var element: String
        package var group: String
        /// The reported (default-range) net and its reported sigma; the net of the fit to `alternativeToKeV`.
        package var before: Double
        package var sigma: Double
        package var after: Double

        /// (after - before) / before; nil when the reported net is 0 (held at the bound).
        package var relative: Double? { before > 0 ? (after - before) / before : nil }
        package var inSigma: Double? { sigma > 0 ? (after - before) / sigma : nil }
    }

    package var alternativeToKeV: Double
    package var moves: [Move]
    /// Why the extra fit could not run; nothing else is said then.
    package var failure: String?

    package init(alternativeToKeV: Double, moves: [Move], failure: String? = nil) {
        self.alternativeToKeV = alternativeToKeV; self.moves = moves; self.failure = failure
    }

    /// The footer's line: "range sensitivity (not in σ): if fitted to 80 keV, Ti −9.3 % (−2.7 σ), Si +0.1 % (+0.6 σ)".
    package var line: String {
        let to = FitRangeChoice.shortKeV(alternativeToKeV)
        if let failure { return "range sensitivity: the fit to \(to) keV could not run (\(failure))" }
        let parts = moves.map { m -> String in
            let s = m.inSigma.map { String(format: " (%+.1f \u{03C3})", $0) } ?? ""
            if let r = m.relative { return String(format: "%@ %+.1f %%", m.element, 100 * r) + s }
            return String(format: "%@ %+.0f counts", m.element, m.after - m.before) + s
        }
        return "range sensitivity (not in \u{03C3}): if fitted to \(to) keV, " + parts.joined(separator: ", ")
    }
}

package nonisolated enum FitRangeSensitivityCheck {

    /// The range of the one extra fit, or nil when no statement applies: a typed range (the user chose it), the polynomial
    /// parity path (it already fits the whole axis), or a default that already reaches the axis end or the beam energy (every
    /// axis ending at or below 20 keV: no second fit runs).
    package static func alternative(for q: PooledQuantification) -> Double? {
        guard q.fitRange.source == .defaultLimit else { return nil }
        return q.fitRange.reachKeV
    }

    /// The extra fit: `input` is the reported fit's input, `q` its result. Nil when `alternative` is nil. No tables: only nets
    /// are read. The refit reuses `q`'s axis refinement, as the unlisted-line check's refit does.
    package static func run(input: PooledQuantificationInput, quantification q: PooledQuantification) -> FitRangeSensitivity? {
        guard let to = alternative(for: q) else { return nil }
        var refit = input
        refit.method.fitToKeV = to
        refit.refinement = q.refinement
        let after: PooledQuantification
        do { after = try PooledQuantifier.run(refit, tables: nil) }
        catch {
            return FitRangeSensitivity(alternativeToKeV: to, moves: [],
                                       failure: (error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        var moves: [FitRangeSensitivity.Move] = []
        for row in q.rows where row.failure == nil {
            guard let new = after.rows.first(where: { $0.element == row.element && $0.failure == nil }) else { continue }
            moves.append(.init(element: row.element, group: row.groupID, before: row.net, sigma: row.sigma, after: new.net))
        }
        return FitRangeSensitivity(alternativeToKeV: to, moves: moves)
    }

    /// The result with the statement attached and its line added to the footer (and so to the export's `#` lines).
    package static func attaching(_ q: PooledQuantification, _ s: FitRangeSensitivity) -> PooledQuantification {
        var out = q
        out.rangeSensitivity = s
        out.footerLines.removeAll { $0.hasPrefix("range sensitivity") }
        // After the "fit range" line, which it qualifies.
        let at = (out.footerLines.firstIndex { $0.hasPrefix("fit range") }).map { $0 + 1 } ?? out.footerLines.count
        out.footerLines.insert(s.line, at: at)
        return out
    }
}
