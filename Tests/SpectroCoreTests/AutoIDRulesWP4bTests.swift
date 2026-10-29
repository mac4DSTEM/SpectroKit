//
//  AutoIDRulesWP4bTests.swift
//  The beside-K guard option of `ProposalRules` on hand-built `ProposalResult`s (R1b: an L/M pick within 1.5 FWHM of another PROPOSED candidate's
//  K alpha is dropped only when its net / L_D is at or below that K candidate's). The option is off in none / registered / shipped.
//  Every test names the mutation it catches.
//

import SpectroCore
import Foundation
import Testing
import SpectroEDX

@MainActor
struct AutoIDRulesWP4bTests {
    /// net / L_D = `significance` exactly (L_D 300).
    private func candidate(_ element: String, _ group: String, energy: Double? = nil, significance: Double) -> ElementCandidate {
        ElementCandidate(element: element, group: group, energyKeV: energy ?? XRayLines.line(group)!.energy, net: significance * 300, sigma: 30, sigmaZero: 90,
                         criticalLevel: 150, detectionLimit: 300, conflicts: [], suggestedRole: .fitOnly, holeRegionNote: nil, misfit: 1)
    }
    private func proposal(_ candidates: [ElementCandidate]) -> ProposalResult {
        ProposalResult(candidates: candidates, sumPeaks: [], refused: [], currie: .standard, notes: [], passes: 1, settled: true)
    }
    private func picked(_ rules: ProposalRules, _ candidates: [ElementCandidate]) -> [String] { rules.apply(proposal(candidates)).picks.map(\.element) }

    private let r1 = ProposalRules(hygiene: true, corroboration: false, release: false)
    private let r1b = ProposalRules(hygiene: true, besideK: true, besideKGuard: true, corroboration: false, release: false)

    /// Hf La 1.0 FWHM from Cu Ka: the L pick stays beside a weaker K, goes beside a stronger or equal K.
    /// Mutations: flip `<=` to `>=` (the stronger Hf would be dropped), `<=` to `<` (the equal case would stay), or drop the guard clause (Hf dropped at 12).
    @Test func testGuardKeepsAStrongerLBesideAWeakerKAndDropsAWeakerOne() {
        let cu = XRayLines.line("Cu_Ka")!.energy
        let hfLa = XRayLines.line("Hf_La")!.energy
        let w = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: hfLa)!
        #expect(abs(hfLa - cu) <= (1.5 * w), "the test pair is inside the beside-K window")
        let weakCu = candidate("Cu", "Cu_Ka", significance: 5), strongCu = candidate("Cu", "Cu_Ka", significance: 40)
        let hf = candidate("Hf", "Hf_La", significance: 12)
        #expect(picked(r1b, [weakCu, hf]) == ["Cu", "Hf"], "12 x L_D Hf beside 5 x L_D Cu: stays")
        #expect(picked(r1b, [strongCu, hf]) == ["Cu"], "12 x L_D Hf beside 40 x L_D Cu: dropped")
        let ruled = r1b.apply(proposal([strongCu, hf]))
        #expect(ruled.withheld.map(\.candidate.element) == ["Hf"])
        #expect(ruled.withheld.first?.rule == .hygiene)
        let why = ruled.withheld.first?.why ?? ""
        #expect(why.contains("within 1.5 FWHM of Cu K\u{03B1}") && why.contains("12.0 \u{00D7} L_D \u{2264} 40.0 \u{00D7} L_D"), "the why says the comparison: \(why)")
        // equal significance: at or below -> dropped
        #expect(picked(r1b, [candidate("Cu", "Cu_Ka", significance: 12), hf]) == ["Cu"], "equal: dropped (the guard is 'at or below')")
    }

    /// With two K candidates in the window the L/M pick is dropped when ANY of them is at least as significant (the rule's evidence reading: a K reading
    /// that is at least as strong explains the peak). Mutation: the guard tests only the first K candidate found (`first(where:)` before the significance test).
    @Test func testGuardWithTwoKCandidatesInTheWindowDropsWhenAnyOneIsAtLeastAsStrong() {
        // Ga Ka and Pt La are 1.2 FWHM apart; a second K candidate (Ge) is placed at Ga's energy.
        let ga = candidate("Ga", "Ga_Ka", significance: 3)
        let ga2 = candidate("Ge", "Ge_Ka", energy: XRayLines.line("Ga_Ka")!.energy + 0.01, significance: 30)
        let pt = candidate("Pt", "Pt_La", significance: 10)
        #expect(picked(r1b, [ga, pt]) == ["Ga", "Pt"], "beside one weak K: stays")
        #expect(picked(r1b, [ga, ga2, pt]) == ["Ga", "Ge"], "one of two Ks in the window is stronger: dropped")
    }

    /// Mutation: the guard path also applies to a K pick, or to an L pick beside an L pick, or ignores `besideK` (applies the guard when besideK is off).
    @Test func testGuardChangesNothingOutsideItsClause() {
        let cu = candidate("Cu", "Cu_Ka", significance: 40), hf = candidate("Hf", "Hf_La", significance: 12)
        let guardOnly = ProposalRules(hygiene: true, besideK: false, besideKGuard: true, corroboration: false, release: false)
        #expect(picked(guardOnly, [cu, hf]) == ["Cu", "Hf"], "the guard is a modifier of besideK: alone it drops nothing")
        let th = candidate("Th", "Th_Ma", significance: 5)
        #expect(picked(r1b, [th, cu]) == ["Cu"], "the actinide half is unchanged")
        let w = candidate("W", "W_La", energy: XRayLines.line("Hf_La")!.energy + 0.01, significance: 8)
        #expect(Set(picked(r1b, [hf, w])) == ["Hf", "W"], "an L beside an L stays")
        // far from the K: no effect either way
        let far = candidate("V", "V_La", energy: XRayLines.line("Cu_Ka")!.energy + 2, significance: 2)
        #expect(Set(picked(r1b, [cu, far])) == ["Cu", "V"])
    }

    /// Shipped / registered / none behave exactly as before: the guard is off in all three, and with it off the unguarded drop is byte-identical.
    /// Mutations: `shipped` or `registered` built with besideKGuard true, or the unguarded branch compares significance anyway.
    @Test func testShippedRegisteredAndNoneAreUnchanged() {
        #expect(!ProposalRules.none.besideKGuard); #expect(!ProposalRules.registered.besideKGuard); #expect(!ProposalRules.shipped.besideKGuard)
        #expect(ProposalRules.shipped.hygiene); #expect(!ProposalRules.shipped.besideK)
        #expect(ProposalRules.registered.besideK)
        let cu = candidate("Cu", "Cu_Ka", significance: 5), hf = candidate("Hf", "Hf_La", significance: 12)
        #expect(picked(ProposalRules.shipped, [cu, hf]) == ["Cu", "Hf"])
        #expect(picked(ProposalRules.registered, [cu, hf]) == ["Cu"], "registered drops Hf however strong")
        let plain = r1.apply(proposal([cu, hf]))
        #expect(plain.picks.map(\.element) == ["Cu"], "R1 unguarded: dropped regardless of significance")
        #expect(plain.withheld.first?.why == "within 1.5 FWHM of Cu K\u{03B1}", "the unguarded text is unchanged")
        #expect(picked(.none, [cu, hf]) == ["Cu", "Hf"])
    }
}
