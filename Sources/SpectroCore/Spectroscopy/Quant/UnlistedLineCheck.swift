//
//  UnlistedLineCheck.swift
//  Role: WP3b F1, "name what is missing before at%" (docs/archive/v5/wp3b-fit-robustness-preregistration-2026-10-06.md).
//        After a Quantify fit the element proposer runs on the SAME pooled spectrum with the listed set; every candidate it
//        finds at or above Currie's L_D is named. At% is NEVER blanked by the check (A2, Gate D 2026-10-06): when candidates
//        exist the result carries `abundanceCaveat` (what is unlisted, the largest move) and the export carries it too.
//        Nothing here edits an element list.
//
//  A2 (docs/archive/v5, Gate D on the real Al-alloy fit): the "> sigma" bar that used to blank at% was measured on synthetic
//  pools (0.3-0.9 sigma harmless, 27-33 sigma missing) and did not separate on the real ones (1.1 sigma to 25 sigma on pools with
//  nothing wrong a person could name), so by the threshold rule the quantity ships and the reader judges. The blanking was one
//  function (`withholding`); it now sets the caveat instead.
//
//  A candidate BESIDE a listed line is not an element: the proposer's name for a residual within +-2 FWHM(E) of a listed
//  group's STRONGEST (alpha) line (or within +-1 FWHM of a continuum split edge) is a misfit of that line's shape or the continuum, not a
//  detected element (Lu M-alpha 20-95 eV above Al K-alpha / the Al K split). It is reported as "unexplained excess beside
//  Al K-alpha", never under the element symbol, and does not enter the refit. +-2 and +-1 FWHM are a geometry convention,
//  not a measured bar; beta lines are excluded because shape misfit lives at the strong line; no count threshold anywhere.
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
//  The nets, at%, wt% and the k-free ratios all stay: the caveat says what moves them.
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
        /// The listed line (or "the continuum split at 1.560 keV") the candidate sits beside, e.g. "Al K\u{03B1}"; nil when it
        /// is clear of every listed line. A beside candidate is an unexplained excess, not an element (never refitted).
        package var besideLine: String?
        /// Candidate net / the neighbour group's net; nil without a line neighbour or when its net is 0.
        package var fractionOfNeighbour: Double?

        package init(element: String, group: String, net: Double, detectionLimit: Double, sumPeakQuestion: Bool,
                     besideLine: String? = nil, fractionOfNeighbour: Double? = nil) {
            self.element = element; self.group = group; self.net = net; self.detectionLimit = detectionLimit
            self.sumPeakQuestion = sumPeakQuestion; self.besideLine = besideLine; self.fractionOfNeighbour = fractionOfNeighbour
        }

        /// "Lu M\u{03B1}" for group "Lu_Ma".
        package var proposerLabel: String { UnlistedLineChecker.displayName(group) }

        /// What is shown: the element symbol, or for a beside candidate the excess it is.
        package var shownName: String {
            guard let b = besideLine else { return element }
            var t = "unexplained excess beside \(b): \(UnlistedLineChecker.grouped(net)) counts"
            if let f = fractionOfNeighbour { t += String(format: ", %.1f %% of %@", 100 * f, b) }
            return t
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

    /// True when fitting the element candidates moves a quantified net by more than its sigma. A statement about the numbers:
    /// since A2 it blanks nothing (the caveat carries it).
    package var withholds: Bool { !moves.isEmpty }
    /// What each candidate is called on screen: an element symbol, or the excess beside a listed line.
    package var names: [String] { candidates.map(\.shownName) }
    /// The candidates that are elements (clear of every listed line): the ones that can be added as Fit only.
    package var elementNames: [String] { candidates.filter { $0.besideLine == nil }.map(\.element) }

    /// The one line under the table.
    package var line: String {
        if let failure, candidates.isEmpty { return "Unlisted lines: not checked (\(failure))" }
        if candidates.isEmpty { return "Unlisted lines: none at or above L_D" }
        return "Unlisted lines found: \(names.joined(separator: ", "))"   // the room's two buttons carry the actions
    }

    /// What fitting the element candidates does to the quantified nets; nil when nothing moved by more than its sigma.
    package var moveReason: String? {
        guard withholds else { return nil }
        let moved = moves.map { m in
            String(format: "%@ by %+.0f counts (\u{03C3} %.0f)", m.element, m.after - m.before, m.sigma)
        }.joined(separator: ", ")
        return "fitting the unlisted \(elementNames.joined(separator: ", ")) as Fit only moves \(moved)"
    }

    /// The caveat on the at% rows when candidates exist: what is unlisted and the largest move; nil when none.
    package var caveat: String? {
        guard !candidates.isEmpty else { return nil }
        let unlisted = candidates.map { c -> String in
            c.besideLine.map { "excess beside \($0) (net \(UnlistedLineChecker.grouped(c.net)))" }
                ?? "\(c.element) (net \(UnlistedLineChecker.grouped(c.net)))"
        }.joined(separator: ", ")
        var t = "assumes the listed elements only; unlisted: \(unlisted)"
        if let l = largestText { t += "; \(l)" }
        if let failure { t += "; the refit could not run (\(failure))" }
        return t
    }

    /// The export's `#` line: what was found, how, and what it did to the numbers.
    package var summary: String {
        if let failure, candidates.isEmpty { return "not checked: \(failure)" }
        if candidates.isEmpty { return "no unlisted line at or above Currie L_D (proposer on this pooled spectrum, sum-peak questions counted)" }
        let found = candidates.map { c -> String in
            if c.besideLine != nil {
                return String(format: "%@ (proposer's label %@, L_D %.0f%@)", c.shownName, c.proposerLabel, c.detectionLimit,
                              c.sumPeakQuestion ? ", sum-peak question" : "")
            }
            return String(format: "%@ (%@, net %.0f, L_D %.0f%@)", c.element, c.group, c.net, c.detectionLimit, c.sumPeakQuestion ? ", sum-peak question" : "")
        }.joined(separator: "; ")
        let margin = largestText.map { "; \($0)" } ?? ""
        if let r = moveReason { return "found \(found); \(r)\(margin); at% is shown with this caveat" }
        if let failure { return "found \(found); the refit could not run (\(failure)), at% not checked against them" }
        if elementNames.isEmpty { return "found \(found)\(margin.isEmpty ? "" : margin)" }
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

    /// "Al_Ka" -> "Al K\u{03B1}", "Lu_Ma" -> "Lu M\u{03B1}", "Cu_Lb1" -> "Cu L\u{03B2}1".
    package static func displayName(_ id: String) -> String {
        let parts = id.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return id }
        let line = parts[1].map { c -> String in
            switch c { case "a": return "\u{03B1}"; case "b": return "\u{03B2}"; case "g": return "\u{03B3}"; default: return String(c) }
        }.joined()
        return "\(parts[0]) \(line)"
    }

    /// 44913 -> "44 913" (a plain space, whatever the locale).
    package static func grouped(_ x: Double) -> String {
        let digits = String(Int(x.rounded()))
        var out = "", n = 0
        for ch in digits.reversed() {
            if ch != "-" && n > 0 && n % 3 == 0 { out.append(" ") }
            out.append(ch); n += 1
        }
        return String(out.reversed())
    }

    /// What a candidate at `energyKeV` sits beside: the alpha line of a listed group within +-2 FWHM(E) (FWHM at the
    /// candidate's energy), else a continuum split edge within +-1 FWHM, else nil. `nets` maps a group id to its fitted net
    /// (the listed lines' areas; absent = 0). For an edge the net is 0. Geometry convention, not a measured bar (file header).
    ///
    /// R8: a split edge is the K edge of an element (Al 1.5596 keV, Si 1.839): the candidate of the element that OWNS the edge is
    /// that element's own line group sitting on its own edge, never an "excess beside the split". `element` is the candidate's
    /// symbol; nil (or an edge with no known owner) exempts nothing.
    package static func neighbour(energyKeV e: Double, listedGroups: [FitLineGroup], resolutionMnKaEV: Double,
                                  edges: [Double], nets: [String: Double] = [:], element: String? = nil) -> (line: String, net: Double)? {
        guard let fwhm = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: e) else { return nil }
        // The STRONGEST (alpha, the group's first) line of each listed group is the reference, the nearest in FWHM units wins; the
        // net it carries (and the fraction against it) is that group's alpha area. Never a beta line: the shape misfit the label
        // stands for lives at the strong line (Gate D 2026-10-06, beside-decision).
        var best: (group: String, d: Double)?
        for g in listedGroups {
            guard let l = g.lines.first else { continue }
            let d = abs(l.energy - e)
            if d <= 2 * fwhm, d < (best?.d ?? .infinity) { best = (g.id, d) }
        }
        if let b = best { return (displayName(b.group), nets[b.group] ?? 0) }
        if let edge = edges.filter({ abs($0 - e) <= fwhm && !(element != nil && edgeOwner($0) == element) })
            .min(by: { abs($0 - e) < abs($1 - e) }) {
            return (String(format: "the continuum split at %.3f keV", edge), 0)
        }
        return nil
    }

    /// The element whose K edge sits at `edge` keV (within 1 eV), for the edges a continuum is split at; nil for any other energy.
    package static func edgeOwner(_ edge: Double) -> String? {
        [(ContinuumForm.alKEdge, "Al"), (EDSLineModel.siKEdge, "Si")].first { abs($0.0 - edge) < 0.001 }?.1
    }

    /// The decision for one proposal. `input` is the reported fit's input (counts, axis, method); `q` its result.
    package static func check(proposal: ProposalResult, input: PooledQuantificationInput, quantification q: PooledQuantification) -> UnlistedLineCheck {
        let dismissed = Set(q.method.elements.filter { $0.role == .off }.map(\.symbol))
        // `isProposed` = proposed and sum-peak questions alike (both at or above L_D), strongest first.
        let found = proposal.candidates.filter { $0.isProposed && !dismissed.contains($0.element) }

        // Beside a listed line or a split edge: an unexplained excess, not an element (A2). Listed = the reported fit's own list,
        // axis and width; nets from the fit's group values.
        let fs = q.fitSettings
        let listed = EDSLineModel.build(elements: fs.elements, axis: q.usedAxis, beamEnergy: fs.beamEnergy,
                                        resolutionMnKaEV: fs.resolutionMnKaEV, escapePeaks: fs.escapePeaks).groups
        var nets: [String: Double] = [:]
        for (id, v) in zip(q.fit.groupIDs, q.fit.values) { nets[id] = v }
        var edges: [Double] = []
        if case .continuum(let form) = fs.background { edges = form.edges }
        let candidates = found.map { c -> UnlistedLineCheck.Candidate in
            var cand = UnlistedLineCheck.Candidate(element: c.element, group: c.group, net: c.net, detectionLimit: c.detectionLimit,
                                                   sumPeakQuestion: c.hasSumPeakQuestion)
            if let n = neighbour(energyKeV: c.energyKeV, listedGroups: listed, resolutionMnKaEV: fs.resolutionMnKaEV, edges: edges, nets: nets, element: c.element) {
                cand.besideLine = n.line
                if n.net > 0 { cand.fractionOfNeighbour = c.net / n.net }
            }
            return cand
        }
        guard !candidates.isEmpty else { return .init(candidates: [], moves: []) }
        let elements = candidates.filter { $0.besideLine == nil }
        guard !elements.isEmpty else { return .init(candidates: candidates, moves: []) }

        // The refit: the same method with the element candidates as Fit only, the same axis refinement. No tables: only nets are read.
        var refit = input
        refit.method.elements.removeAll { e in elements.contains { $0.element == e.symbol } }
        refit.method.elements += elements.map { .init(symbol: $0.element, role: .fitOnly, isManual: false) }
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

    /// The result as it may be shown: the check attached and the caveat set (A2: at%, wt% and the k-free ratios are never
    /// blanked by the check; they stay with the caveat that says what is unlisted and the largest move). To restore the old
    /// blanking, re-add `blankAbundance` from 94e26370 and call it here when `c.withholds`.
    package static func withholding(_ q: PooledQuantification, _ c: UnlistedLineCheck) -> PooledQuantification {
        var out = q
        out.unlistedCheck = c
        out.unlistedCheckPending = false
        out.abundanceCaveat = c.caveat
        return out
    }

    /// The result while the check runs: everything shown at once, with the caveat "unlisted-line check running", replaced when
    /// the check lands (a number never vanishes).
    package static func holding(_ q: PooledQuantification) -> PooledQuantification {
        var out = q
        out.abundanceCaveat = "unlisted-line check running"
        out.unlistedCheckPending = true
        return out
    }
}
