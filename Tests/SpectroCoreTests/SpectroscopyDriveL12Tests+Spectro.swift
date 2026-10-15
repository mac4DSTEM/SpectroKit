// SpectroKit S1 test partition (ADR 064 section 3.3): the methods of SpectroscopyDriveL12Tests that move with the EDX core;
// the rest stay in SpectroscopyDriveL12Tests.swift. Helpers are duplicated, not shared, across the split.
//
//  SpectroscopyDriveL12Tests.swift
//  Lane L12 (WP4): the three registered Auto ID rules (`ProposalRules`, Core) on hand-built `ProposalResult`s, and how
//  `AutoIDPresentation.outcome(rules:)` shows them. No compute, no app driving. Every test names the mutation it catches.
//  Registration: docs/archive/v5/wp4-autoid-velox-preregistration-2026-10-07.md (H1 never Z >= 89 and drop an L/M pick within
//  1.5 FWHM of another proposed candidate's K alpha; H2 an L/M pick needs net / L_D >= 3; H3 a held sum-peak candidate at
//  net / L_D >= 10 is released).
//
import Foundation
import Testing
import SpectroCore
import SpectroEDX

@MainActor
struct SpectroscopyDriveL12Spectro {
    /// net / L_D = `significance` exactly (L_D 300).
    private func candidate(_ element: String, _ group: String, energy: Double? = nil, significance: Double,
                           conflicts: [LineConflict] = []) -> ElementCandidate {
        ElementCandidate(element: element, group: group, energyKeV: energy ?? XRayLines.line(group)!.energy, net: significance * 300, sigma: 30, sigmaZero: 90,
                         criticalLevel: 150, detectionLimit: 300, conflicts: conflicts,
                         suggestedRole: .fitOnly, holeRegionNote: nil, misfit: 1)
    }

    /// A candidate the proposer would hold back: its alpha sits on the sum of an Al pair half its energy.
    private func held(_ element: String, _ group: String, significance: Double) -> ElementCandidate {
        let e = XRayLines.line(group)!.energy
        let conflicts = LineConflicts.conflicts(element: element, line: group, lineEnergyKeV: e, parents: [SumParent(element: "Al", energyKeV: e / 2)])
        return candidate(element, group, significance: significance, conflicts: conflicts)
    }

    private func proposal(_ candidates: [ElementCandidate]) -> ProposalResult {
        ProposalResult(candidates: candidates, sumPeaks: [], refused: [], currie: .standard, notes: ["the proposer's own note"], passes: 1, settled: true)
    }

    private func picked(_ rules: ProposalRules, _ candidates: [ElementCandidate]) -> [String] {
        rules.apply(proposal(candidates)).picks.map(\.element)
    }

    private let r1 = ProposalRules(hygiene: true, corroboration: false, release: false)
    private let r2 = ProposalRules(hygiene: false, corroboration: true, release: false)
    private let r3 = ProposalRules(hygiene: false, corroboration: false, release: true)

    // MARK: R1

    /// Mutation: `>= actinideZ` -> `> actinideZ + 1` (Th, Z 90, would pass), or the clause dropped.
    @Test func testR1NeverPicksAnActinide() {
        let th = candidate("Th", "Th_Ma", significance: 50), u = candidate("U", "U_Ma", significance: 50), pb = candidate("Pb", "Pb_La", significance: 50)
        #expect(picked(r1, [th, u, pb]) == ["Pb"], "Th (90) and U (92) are never picked; Pb (82) is")
        let w = r1.apply(proposal([th, u, pb])).withheld
        #expect(w.map(\.rule) == [.hygiene, .hygiene])
        #expect(w[0].why.contains("89"), "\(w[0].why)")
        #expect(picked(.none, [th, u, pb]) == ["Th", "U", "Pb"], "with no rule the proposer's picks stand")
        #expect(picked(r2, [th]) == ["Th"], "R1 alone owns Z: R2's L/M bar does not touch a 50 x L_D Th")
    }

    /// Mutation: the beside-K clause accepts L/M-vs-L/M neighbours (drop the `family == .K` test on the other candidate), or
    /// takes only picked candidates as the K reference (drop `proposedAll` for `proposed`), or 1.5 -> 1.7 / 1.3.
    @Test func testR1DropsAnLOrMPickBesideAnotherProposedCandidatesKAlpha() {
        let o = candidate("O", "O_Ka", significance: 12)
        let k = XRayLines.line("O_Ka")!.energy
        let w = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: k)!
        let vNear = candidate("V", "V_La", energy: k + 1.4 * w, significance: 8)
        let vFar = candidate("V", "V_La", energy: k + 1.6 * w, significance: 8)
        #expect(picked(r1, [o, vNear]) == ["O"], "1.4 FWHM from O Ka: the K reading explains the peak")
        #expect(picked(r1, [o, vFar]) == ["O", "V"], "1.6 FWHM away: both stay")
        #expect(r1.apply(proposal([o, vNear])).withheld.first?.why == "within 1.5 FWHM of O K\u{03B1}")
        // a candidate that is NOT proposed (below L_D) is no reference
        let weakO = candidate("O", "O_Ka", significance: 0.5)
        #expect(picked(r1, [weakO, vNear]) == ["V"], "a K candidate under L_D does not explain the peak")
        // only a K alpha is a reference: an L pick beside an L pick stays
        let hf = candidate("Hf", "Hf_La", significance: 8), w2 = candidate("W", "W_La", energy: XRayLines.line("Hf_La")!.energy + 0.01, significance: 8)
        #expect(Set(picked(r1, [hf, w2])) == ["Hf", "W"])
        // a K pick is never dropped by the rule, whatever stands beside it
        let cu = candidate("Cu", "Cu_Ka", significance: 5), hfAtCu = candidate("Hf", "Hf_La", energy: XRayLines.line("Cu_Ka")!.energy, significance: 8)
        #expect(picked(r1, [cu, hfAtCu]) == ["Cu"])
        #expect(picked(r2, [o, vNear]) == ["O", "V"], "R1 alone owns the distance rule: R2 keeps a 8 x L_D L pick")
        // a K candidate the proposer HOLDS back (a sum-peak question) still explains the peak beside it: Ar K-alpha 2.957 keV, Ag L-alpha 2.984
        let ar = held("Ar", "Ar_Ka", significance: 12), ag = candidate("Ag", "Ag_La", significance: 8)
        #expect(picked(r1, [ar, ag]) == [], "Ag L is dropped beside the held Ar K")
    }

    // MARK: R2

    /// Mutation: `<` -> `<=` (3.0 itself would go), 3 -> 2 or 4, or the K test dropped (a K pick at 1.5 would go).
    @Test func testR2AnLOrMPickNeedsThreeDetectionLimitsAKPickKeepsTheBar() {
        #expect(picked(r2, [candidate("Eu", "Eu_La", significance: 2.9)]) == [], "2.9 x L_D: withheld")
        #expect(picked(r2, [candidate("Eu", "Eu_La", significance: 3.0)]) == ["Eu"], "exactly 3: kept")
        #expect(picked(r2, [candidate("Eu", "Eu_La", significance: 3.1)]) == ["Eu"])
        #expect(picked(r2, [candidate("Ta", "Ta_Ma", significance: 2.9)]) == [], "an M pick is held to the same bar")
        #expect(picked(r2, [candidate("Cu", "Cu_Ka", significance: 1.0)]) == ["Cu"], "a K pick keeps the proposer's L_D bar")
        #expect(picked(.none, [candidate("Eu", "Eu_La", significance: 2.9)]) == ["Eu"])
        #expect(picked(r1, [candidate("Eu", "Eu_La", significance: 2.9)]) == ["Eu"], "R2 alone owns the 3 x L_D bar")
        let w = r2.apply(proposal([candidate("Eu", "Eu_La", significance: 1.9)])).withheld
        #expect(w.map(\.rule) == [.corroboration])
        #expect(w.first?.why == "1.9 \u{00D7} L_D < 3")
    }

    // MARK: R3

    /// Mutation: `>=` -> `>` (10.0 stays held), 10 -> 9 or 11, or the release also applied below the proposer's own L_D (a candidate under 1 is never held at all).
    @Test func testR3ReleasesAHeldSumPeakCandidateAtTenDetectionLimits() {
        let low = held("Ar", "Ar_Ka", significance: 9.9), high = held("Ar", "Ar_Ka", significance: 10.0)
        #expect(proposal([low]).proposed.isEmpty, "precondition: the proposer files it as a sum-peak question")
        #expect(picked(r3, [low]) == [])
        #expect(r3.apply(proposal([low])).heldQuestions.map(\.element) == ["Ar"], "9.9: still the question")
        #expect(picked(r3, [high]) == ["Ar"], "10.0: released")
        let ruled = r3.apply(proposal([high]))
        #expect(ruled.heldQuestions == [], "a released candidate is no longer a held question")
        #expect(ruled.released.map(\.candidate.element) == ["Ar"])
        #expect(picked(.none, [high]) == [], "no rule: the hold stays")
        #expect(picked(r1, [high]) == [], "R3 alone owns the release")
        #expect(picked(r2, [high]) == [])
        #expect(ruled.ruleReason(for: "Ar")?.hasPrefix("Rule R3") ?? false)
    }

    /// A released candidate still meets R1: an actinide, or an L/M line on a proposed K alpha, stays held.
    /// Mutation: skip `verdict(c) == nil` in the release branch.
    @Test func testAReleasedCandidateStillMeetsR1() {
        let thHeld = held("Th", "Th_Ma", significance: 40)
        #expect(picked(.registered, [thHeld]) == [], "Z >= 89 is never picked, released or not")
        #expect(ProposalRules.registered.apply(proposal([thHeld])).heldQuestions.map(\.element) == ["Th"])
    }

    // MARK: registered, independence, raw output

    @Test func testRegisteredNamesTheThreeCutsAndShippedKeepsOnlyR1() {
        let r = ProposalRules.registered
        #expect(r.hygiene && r.corroboration && r.release)
        #expect(r.actinideZ == 89); #expect(r.besideKFWHM == 1.5); #expect(r.lineMinimumSignificance == 3); #expect(r.releaseSignificance == 10)
        #expect(ProposalRules.Rule.allCases.map(\.rawValue) == ["R1", "R2", "R3"])
        #expect(ProposalRules.source.contains("unvalidated"))
        // What the room applies: R3 was refuted on the dose ladder (Ar released from the Al+Al sum), R2 missed its hold-out bar.
        // Mutation: `shipped` = `registered`.
        let s = ProposalRules.shipped
        #expect(s.hygiene); #expect(!s.corroboration); #expect(!s.release)
        #expect(picked(s, [candidate("Eu", "Eu_La", significance: 1.5), held("Ar", "Ar_Ka", significance: 20)]) == ["Eu"], "shipped: no 3 x L_D bar, no release")
    }

    /// A mixed result through the registered rules: K untouched, L/M cut at 3, actinide gone, strong hold released; the proposer's own result is unchanged.
    /// Mutation: `apply` rebuilds `raw` with the picks (the raw proposed list would shrink).
    @Test func testRegisteredOnAMixedResultAndTheRawProposalIsUntouched() {
        let cs = [candidate("Cu", "Cu_Ka", significance: 27), candidate("Ho", "Ho_La", significance: 1.9), candidate("In", "In_La", significance: 11.7),
                  candidate("Th", "Th_Ma", significance: 50), held("Ar", "Ar_Ka", significance: 14), held("Zr", "Zr_Ka", significance: 2)]
        let r = proposal(cs)
        let ruled = ProposalRules.registered.apply(r)
        #expect(Set(ruled.picks.map(\.element)) == ["Cu", "In", "Ar"])
        #expect(Set(ruled.withheld.map(\.candidate.element)) == ["Ho", "Th"])
        #expect(ruled.heldQuestions.map(\.element) == ["Zr"])
        #expect(ruled.raw.proposed.map(\.element) == ["Cu", "Ho", "In", "Th"], "the proposer's own picks stand beside the ruled ones")
        #expect(ruled.raw.sumPeakQuestions.map(\.element) == ["Ar", "Zr"])
        #expect(ruled.ruleReason(for: "In")?.hasPrefix("Rule R2") == true, "an L pick that cleared R2 says so")
        #expect(ruled.ruleReason(for: "Cu") == nil, "a K pick above L_D is the proposer's own")
        #expect(ProposalRules.none.apply(r).picks.map(\.element) == r.proposed.map(\.element))
    }

    /// Supervisor, after the refuter (2026-10-07): the shipped set drops an actinide but keeps an L pick beside a proposed Kα (Hf Lα
    /// 1.0 FWHM from Cu Kα: real on a Cu grid). Mutation: `shipped.besideK` true → red.
    @Test func testTheShippedSetKeepsAnLPickBesideAProposedK() throws {
        #expect(ProposalRules.shipped.hygiene); #expect(!ProposalRules.shipped.besideK)
        #expect(ProposalRules.registered.besideK, "the registration had both halves")
        let hf = candidate("Hf", "Hf_La", significance: 4)
        let cu = candidate("Cu", "Cu_Ka", significance: 30)
        let th = candidate("Th", "Th_Ma", significance: 5)
        let r = proposal([hf, cu, th])
        let ruled = ProposalRules.shipped.apply(r)
        #expect(Set(ruled.picks.map(\.element)) == ["Hf", "Cu"], "Hf stays; Th goes")
        #expect(ruled.withheld.map(\.candidate.element) == ["Th"])
        #expect(Set(ProposalRules.registered.apply(r).picks.map(\.element)) == ["Cu"], "the registered set would have dropped Hf")
    }
}
