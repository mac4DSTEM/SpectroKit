//
//  UnlistedLineCheck.swift
//  Role: WP3b F1, "name what is missing before at%" (docs/archive/v5/wp3b-fit-robustness-preregistration-2026-10-06.md).
//        After a Quantify fit the element proposer runs on the SAME pooled spectrum with the listed set; every candidate it
//        finds at or above Currie's L_D is named, and at% is withheld only when fitting those candidates (as Fit only) moves
//        a quantified element's net by more than the sigma the table reports for it. Nothing here edits an element list.
//
//  Why both bars (the refuted first proposal, D6):
//    * Proposals alone miss real lines: the proposer files Cu and Ga, real lines on the drive's spectrum and on the
//      synthetic one, as "sum peak or this element?" questions. Both kinds count as candidates here.
//    * Withholding at% on any candidate would block honest spectra: a complete list still gave a chance proposal on 1 of 3
//      synthetic seeds (Lu M-alpha at 1.08 L_D). So a candidate is always NAMED, and at% is withheld only when the refit
//      shows it matters to a quantified net.
//
//  The sigma of the bar is the row's reported sigma (`PooledQuantification.Row.sigma`, the fit covariance: counting only).
//  The refit reuses the reported fit's axis refinement (same axis, same width), so only the element set differs.
//  Withheld together with at%/wt%: the k-free ratios, since they are ratios of the same nets and read as a composition.
//  The nets stay: they are the fit's areas under the stated model, and the reason line says what moves them.
//  Excluded: elements a person switched Off (role `.off` in the method, recorded by the replay step): the same rule as
//  Auto ID, which never suggests an element a person already decided.
//

import Foundation

package nonisolated struct UnlistedLineCheck: Sendable, Equatable {
    package struct Candidate: Sendable, Equatable {
        package var element: String
        /// The proposer's best group, e.g. "Ge_Ka".
        package var group: String
        package var net: Double
        package var detectionLimit: Double
        /// The proposer filed it as "sum peak or this element?": counted, because a real line can sit there (Cu, Ga; D6).
        package var sumPeakQuestion: Bool

        package init(element: String, group: String, net: Double, detectionLimit: Double, sumPeakQuestion: Bool) {
            self.element = element; self.group = group; self.net = net; self.detectionLimit = detectionLimit
            self.sumPeakQuestion = sumPeakQuestion
        }
    }

    /// A quantified element whose net moved by more than its reported sigma when the candidates were fitted.
    package struct Move: Sendable, Equatable {
        package var element: String
        package var before: Double
        package var after: Double
        package var sigma: Double
    }

    package var candidates: [Candidate]
    package var moves: [Move]
    /// The quantified row with the largest |delta net| / sigma in the refit, whether or not it crossed the bar (the quantity is
    /// shipped so a reader sees the margin, not only the verdict); nil when nothing was refitted.
    package var largest: Move?
    /// Why the check could not run (the proposer or the refit failed). The candidates found, if any, are still named; at% is
    /// not withheld on a failure of the check, and the line says it was not checked.
    package var failure: String?

    package init(candidates: [Candidate], moves: [Move], largest: Move? = nil, failure: String? = nil) {
        self.candidates = candidates; self.moves = moves; self.largest = largest; self.failure = failure
    }

    /// "largest move 0.4 σ (Si)"; nil when nothing was refitted.
    package var largestText: String? {
        guard let m = largest else { return nil }
        let r = m.sigma > 0 ? abs(m.after - m.before) / m.sigma : .infinity
        return String(format: "largest move %.1f \u{03C3} (%@)", r, m.element)
    }

    package static func failed(_ reason: String) -> UnlistedLineCheck { .init(candidates: [], moves: [], failure: reason) }

    package var withholds: Bool { !moves.isEmpty }
    package var names: [String] { candidates.map(\.element) }

    /// The one line under the table.
    package var line: String {
        if let failure, candidates.isEmpty { return "Unlisted lines: not checked (\(failure))" }
        if candidates.isEmpty { return "Unlisted lines: none at or above L_D" }
        return "Unlisted lines found: \(names.joined(separator: ", "))"   // the room's two buttons carry the actions
    }

    /// The at% refusal when the check withholds; nil otherwise.
    package var withheldReason: String? {
        guard withholds else { return nil }
        let moved = moves.map { m in
            String(format: "%@ by %+.0f counts (\u{03C3} %.0f)", m.element, m.after - m.before, m.sigma)
        }.joined(separator: ", ")
        return "fitting the unlisted \(names.joined(separator: ", ")) as Fit only moves \(moved); at% and the k-free ratios are withheld until they are listed or dismissed"
    }

    /// The export's `#` line: what was found, how, and what it did to the numbers.
    package var summary: String {
        if let failure, candidates.isEmpty { return "not checked: \(failure)" }
        if candidates.isEmpty { return "no unlisted line at or above Currie L_D (proposer on this pooled spectrum, sum-peak questions counted)" }
        let found = candidates.map { c in
            String(format: "%@ (%@, net %.0f, L_D %.0f%@)", c.element, c.group, c.net, c.detectionLimit, c.sumPeakQuestion ? ", sum-peak question" : "")
        }.joined(separator: "; ")
        let margin = largestText.map { "; \($0)" } ?? ""
        if let r = withheldReason { return "found \(found); \(r)\(margin)" }
        if let failure { return "found \(found); the refit could not run (\(failure)), at% not checked against them" }
        return "found \(found); fitting them as Fit only moves no quantified net by more than its \u{03C3}\(margin)"
    }
}

package nonisolated enum UnlistedLineChecker {

    /// The proposer on the reported fit's own settings: its axis (refined or the file's), width, range, continuum and escape
    /// setting, with the listed elements (quantified and Fit only) as the current set. The proposer forces least squares.
    package static func proposerSettings(_ q: PooledQuantification) -> FitSettings {
        var s = q.fitSettings
        s.method = .leastSquares
        return s
    }

    package static func propose(counts: [Double], quantification q: PooledQuantification,
                                proposer: ElementProposer = ElementProposer()) throws -> ProposalResult {
        try proposer.propose(counts: counts, axis: q.usedAxis, settings: proposerSettings(q))
    }

    /// The decision for one proposal. `input` is the reported fit's input (counts, axis, method); `q` its result.
    package static func check(proposal: ProposalResult, input: PooledQuantificationInput, quantification q: PooledQuantification) -> UnlistedLineCheck {
        let dismissed = Set(q.method.elements.filter { $0.role == .off }.map(\.symbol))
        // `isProposed` = proposed and sum-peak questions alike (both at or above L_D), strongest first.
        let found = proposal.candidates.filter { $0.isProposed && !dismissed.contains($0.element) }
        let candidates = found.map {
            UnlistedLineCheck.Candidate(element: $0.element, group: $0.group, net: $0.net, detectionLimit: $0.detectionLimit,
                                        sumPeakQuestion: $0.hasSumPeakQuestion)
        }
        guard !candidates.isEmpty else { return .init(candidates: [], moves: []) }

        // The refit: the same method with the candidates as Fit only, the same axis refinement. No tables: only nets are read.
        var refit = input
        refit.method.elements.removeAll { e in candidates.contains { $0.element == e.symbol } }
        refit.method.elements += candidates.map { .init(symbol: $0.element, role: .fitOnly, isManual: false) }
        refit.refinement = q.refinement
        let after: PooledQuantification
        do { after = try PooledQuantifier.run(refit, tables: nil) }
        catch { return .init(candidates: candidates, moves: [], failure: (error as? LocalizedError)?.errorDescription ?? "\(error)") }

        var moves: [UnlistedLineCheck.Move] = []
        var largest: (move: UnlistedLineCheck.Move, ratio: Double)?
        for row in q.rows where row.failure == nil {
            guard let new = after.rows.first(where: { $0.element == row.element && $0.failure == nil }) else { continue }
            let move = UnlistedLineCheck.Move(element: row.element, before: row.net, after: new.net, sigma: row.sigma)
            let delta = abs(new.net - row.net)
            if delta > row.sigma { moves.append(move) }
            let ratio = row.sigma > 0 ? delta / row.sigma : (delta > 0 ? .infinity : 0)
            if ratio > (largest?.ratio ?? -1) { largest = (move, ratio) }
        }
        return .init(candidates: candidates, moves: moves, largest: largest?.move)
    }

    /// The result as it may be shown: the check attached and, when it withholds, at%/wt% and the k-free ratios removed with
    /// the reason (the nets and their sigma stay).
    package static func withholding(_ q: PooledQuantification, _ c: UnlistedLineCheck) -> PooledQuantification {
        var out = q
        out.unlistedCheck = c
        out.unlistedCheckPending = false
        guard let reason = c.withheldReason else { return out }
        blankAbundance(&out)
        out.abundanceRefusal = reason   // shown as the "at% not computed" note; not repeated in the footer
        return out
    }

    /// The result while the check runs (WP3b F1, session decision 2026-10-06, Fable's recommendation): the nets only; at%,
    /// wt%, the k-free ratios and the Mg/Si line wait for the check, so a number never appears and then vanishes.
    package static func holding(_ q: PooledQuantification) -> PooledQuantification {
        var out = q
        blankAbundance(&out)
        out.abundanceRefusal = "the unlisted-line check has not finished"
        out.unlistedCheckPending = true
        return out
    }

    private static func blankAbundance(_ out: inout PooledQuantification) {
        for i in out.rows.indices {
            out.rows[i].atomicPercent = nil; out.rows[i].atomicSigma = nil; out.rows[i].atomicTerms = nil
            out.rows[i].weightPercent = nil; out.rows[i].weightSigma = nil; out.rows[i].weightTerms = nil
            out.rows[i].absorptionSpreadAtomic = nil; out.rows[i].absorptionSpreadWeight = nil
            out.rows[i].atomicTermsText = ""; out.rows[i].weightTermsText = ""
            out.rows[i].kFreeRatio = nil; out.rows[i].kFreeSigma = nil; out.rows[i].isReference = false
        }
        out.referenceElement = nil
    }
}
