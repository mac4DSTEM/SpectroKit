//
//  ProposalRules.swift
//  Role: The three cuts WP4 pre-registered on 2026-10-07 (docs/archive/v5/wp4-autoid-velox-preregistration-2026-10-07.md), as a
//        separate, named post-selection step on a `ProposalResult`. The proposer's own output is never altered: `apply` returns
//        a `RuledProposal` that holds the raw result beside the picks, so the room can say which rule picked or withheld what.
//
//  R1 hygiene          never Z >= 89 (Velox's own `includeInAutoPeakId` flag is false there); an L or M pick within 1.5 FWHM of
//                      another PROPOSED candidate's K alpha is dropped (a K reading explains the peak).
//  R2 corroboration    an L or M pick needs net / L_D >= 3; a K pick keeps the proposer's own L_D bar.
//  R3 release          a candidate the proposer held back as a sum-peak question is released when net / L_D >= 10, and then
//                      meets R1 and R2 like any other pick.
//
//  The cuts (3, 10 L_D, 1.5 FWHM) were read off 78 files of ONE operator, one detector, mostly Al-Mg-Si; CLAUDE.md: a threshold is
//  a property of the dataset until measured on every dataset it will touch. `UNVALIDATED` stays on the Auto ID row; the hold-out
//  and the demo-edx ladder are reported in docs/archive/v5/wp4-autoid-results-2026-10-07.md. A rule that did not hold there is
//  switched off in `shipped`, not retuned (a changed cut is a new registration): R1's actinide half ships, R1's beside-K half
//  is held by the independent refuter (2026-10-07): the sample never met a true L/M element beside a proposed K, and the line
//  table has pairs where it would drop a real one (Hf Lα 1.0 FWHM from Cu Kα on a Cu grid, Pt Lα 1.2 from Ga Kα on a FIB
//  lamella, Pb Lα 0.04 from As Kα); the proposer keeps one group per element, so the element would vanish. R2 and R3 are off.
//

import Foundation

package nonisolated struct ProposalRules: Equatable, Sendable {
    package enum Rule: String, Sendable, CaseIterable {
        case hygiene = "R1", corroboration = "R2", release = "R3"
        /// Plain words, as the row's hover and the notes say them.
        package var title: String {
            switch self {
            case .hygiene: return "hygiene"
            case .corroboration: return "L/M corroboration"
            case .release: return "sum-peak release"
            }
        }
    }

    package var hygiene: Bool
    /// R1's second half, separately switchable: the beside-K drop. Off in `shipped` (see the header).
    package var besideK: Bool
    /// WP4b (docs/archive/v5/wp4b-autoid-rules-preregistration-2026-10-07.md), an OPTION that is off in `none`, `registered` and `shipped`:
    /// with `besideK`, an L or M pick beside a proposed K alpha is dropped only when its net / L_D is at or below that K candidate's;
    /// a stronger L/M stays. Measured, not shipped: turning it on anywhere is the registration's ship rule, not this flag's existence.
    package var besideKGuard: Bool
    package var corroboration: Bool
    package var release: Bool
    /// R1: an element with Z at or above this is never picked.
    package var actinideZ = 89
    /// R1: an L or M pick closer than this many FWHM to another proposed candidate's K alpha is dropped.
    package var besideKFWHM = 1.5
    /// R2: the net / L_D an L or M pick needs.
    package var lineMinimumSignificance = 3.0
    /// R3: the net / L_D at which a held sum-peak candidate is released.
    package var releaseSignificance = 10.0

    package init(hygiene: Bool, besideK: Bool? = nil, besideKGuard: Bool = false, corroboration: Bool, release: Bool) {
        self.hygiene = hygiene; self.besideK = besideK ?? hygiene; self.besideKGuard = besideKGuard; self.corroboration = corroboration; self.release = release
    }

    /// No rule: `apply` returns the proposer's own picks.
    package static let none = ProposalRules(hygiene: false, corroboration: false, release: false)
    /// The three cuts exactly as registered, 2026-10-07.
    package static let registered = ProposalRules(hygiene: true, corroboration: true, release: true)
    /// What the room applies: R1 only. R3 was refuted on the demo-edx dose ladder (the Al+Al sum peak at 100 counts/px, 19.9 x L_D,
    /// was released as Ar, an element absent from truth) and R2 missed its hold-out bar (precision 38.7 % under 45 % on the nine June
    /// 2026 files); per the registration a cut that does not hold ships as the shown quantity (net / L_D beside each pick) and no
    /// rule. docs/archive/v5/wp4-autoid-results-2026-10-07.md. Changing a cut or turning a rule back on is a new registration.
    /// The beside-K half of R1 is off too (the refuter's finding above). WP4b (ADR 062) tested it with the evidence guard on true
    /// L/M + K pairs and refuted it: an L family's L_D is larger than a nearby K line's at equal area, so the guard still drops true Hf
    /// beside Cu and Pt beside Ga. R2 was refuted in-sample there too. A new beside-K test needs a different evidence term.
    package static let shipped = ProposalRules(hygiene: true, besideK: false, corroboration: false, release: false)
    /// Where the cuts come from (said in the notes, never hidden).
    package static let source = "registered 2026-10-07 (WP4), cuts read off 78 Velox-session files: unvalidated"
    package var isNone: Bool { !hygiene && !besideK && !corroboration && !release }   // besideKGuard alone acts only with besideK

    package nonisolated struct Withheld: Equatable, Sendable {
        package let candidate: ElementCandidate
        package let rule: Rule
        /// "Z >= 89", "within 1.5 FWHM of Cu Ka", "1.9 x L_D < 3".
        package let why: String
    }

    package nonisolated struct Release: Equatable, Sendable {
        package let candidate: ElementCandidate
    }

    /// Pure: the same result and rules always give the same picks. `resolutionMnKaEV` sets the FWHM that R1's distance is counted in
    /// (the room's detector width; the harness uses the app's default, 130 eV).
    package func apply(_ r: ProposalResult, resolutionMnKaEV: Double = 130) -> RuledProposal {
        let proposedAll = r.candidates.filter(\.isProposed)   // held candidates included: a K peak is a K peak
        func z(_ element: String) -> Int { XRayLines.lines(of: element).first?.atomicNumber ?? 0 }
        func family(_ group: String) -> XRayFamily { XRayLines.line(group)?.family ?? .K }
        func name(_ group: String) -> String { UnlistedLineChecker.displayName(group) }

        /// The first rule a pick fails, or nil.
        func verdict(_ c: ElementCandidate) -> (Rule, String)? {
            if hygiene, z(c.element) >= actinideZ { return (.hygiene, "Z \u{2265} \(actinideZ)") }
            let isK = family(c.group) == .K
            if besideK, !isK, let w = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: c.energyKeV),
               let k = proposedAll.first(where: {
                   $0.element != c.element && family($0.group) == .K && abs($0.energyKeV - c.energyKeV) <= besideKFWHM * w
                       // WP4b guard: a K candidate explains the peak only when it is at least as significant (net / L_D) as the L/M pick.
                       && (!besideKGuard || c.significance <= $0.significance)
               }) {
                if besideKGuard {
                    return (.hygiene, "within \(String(format: "%g", besideKFWHM)) FWHM of \(name(k.group)), \(String(format: "%.1f", c.significance)) \u{00D7} L_D \u{2264} \(String(format: "%.1f", k.significance)) \u{00D7} L_D")
                }
                return (.hygiene, "within \(String(format: "%g", besideKFWHM)) FWHM of \(name(k.group))")
            }
            if corroboration, !isK, c.significance < lineMinimumSignificance {
                return (.corroboration, String(format: "%.1f \u{00D7} L_D < %g", c.significance, lineMinimumSignificance))
            }
            return nil
        }

        var picks: [ElementCandidate] = [], withheld: [Withheld] = [], released: [Release] = []
        var stillHeld: [ElementCandidate] = []
        for c in r.candidates where c.isProposed {
            if !c.hasSumPeakQuestion {
                if let (rule, why) = verdict(c) { withheld.append(Withheld(candidate: c, rule: rule, why: why)) } else { picks.append(c) }
            } else if release, c.significance >= releaseSignificance, verdict(c) == nil {
                picks.append(c); released.append(Release(candidate: c))
            } else {
                stillHeld.append(c)
            }
        }
        let corroborated = corroboration ? picks.filter { family($0.group) != .K }.map(\.element) : []
        return RuledProposal(raw: r, rules: self, picks: picks, withheld: withheld, released: released, heldQuestions: stillHeld,
                             lineGroupsCorroborated: corroborated)
    }
}

/// A proposal after the rules: what the room picks, what each rule withheld or released, and the raw result untouched.
package nonisolated struct RuledProposal: Sendable {
    package let raw: ProposalResult
    package let rules: ProposalRules
    /// The picks, strongest first (the proposer's own order).
    package let picks: [ElementCandidate]
    package let withheld: [ProposalRules.Withheld]
    package let released: [ProposalRules.Release]
    /// Still at or above L_D and on a pile-up energy: not an element, shown as the sum-peak question.
    package let heldQuestions: [ElementCandidate]
    /// L and M picks that cleared R2 (empty when R2 is off).
    package let lineGroupsCorroborated: [String]

    /// "Rule R3: ..." for the pick's hover; nil when no rule acted on this element (a K pick above L_D is the proposer's own).
    package func ruleReason(for element: String) -> String? {
        if let r = released.first(where: { $0.candidate.element == element }) {
            return String(format: "Rule R3 (sum-peak release): %.1f \u{00D7} L_D \u{2265} %g.", r.candidate.significance, rules.releaseSignificance)
        }
        if lineGroupsCorroborated.contains(element), let c = picks.first(where: { $0.element == element }) {
            return String(format: "Rule R2 (L/M corroboration): %.1f \u{00D7} L_D \u{2265} %g.", c.significance, rules.lineMinimumSignificance)
        }
        return nil
    }
}
