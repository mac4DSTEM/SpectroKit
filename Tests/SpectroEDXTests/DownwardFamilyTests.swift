//
//  DownwardFamilyTests.swift
//  Role: The downward confirmation rule (`ProposerPolicy.downwardFamilyMinimumZ`, opt-in): a K pick of Z >= 30 must show its L alpha line; and
//        the uncorroborated tier of `ProposalResult`. Noise-free planted spectra as in FamilyConsistencyTests. Red before: the field and the
//        tier did not exist (the tests did not compile), and a lone Zn K line was proposed whatever the policy.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct DownwardFamilyTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)   // 0 to 10.99 keV
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }

    private static let kramers: @Sendable (Double) -> Double = { e in
        let x = max(e, 0.05)
        return 60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5
    }

    private static func group(_ id: String) -> FitLineGroup {
        let el = String(id.prefix { $0 != "_" })
        return EDSLineModel.build(elements: [el], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == id }!
    }

    private static func expected(_ planted: [(id: String, area: Double)], dose k: Double = 10) -> [Double] {
        var out = energies.map { $0 >= 0.2 ? k * kramers($0) : 0 }
        for (id, area) in planted {
            let col = EDSLineModel.column(of: group(id).lines, energies: energies, scale: axis.scale)
            for i in out.indices { out[i] += k * area * col[i] }
        }
        return out
    }

    private static func propose(_ counts: [Double], policy: ProposerPolicy = .default, beam: Double = 200) throws -> ProposalResult {
        try ElementProposer(policy: policy).propose(
            counts: counts, axis: axis, settings: FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: 130, beamEnergy: beam))
    }
    private static func candidate(_ r: ProposalResult, _ el: String) -> ElementCandidate? { r.candidates.first { $0.element == el } }

    private static let on = ProposerPolicy(downwardFamilyMinimumZ: 30)
    private static let loneZnK = expected([("Al_Ka", 9000), ("Zn_Ka", 3000)])

    @Test func testALoneZnKLineIsProposedWithTheRuleOff() throws {
        let r = try Self.propose(Self.loneZnK)
        #expect(r.proposed.contains { $0.element == "Zn" })
        #expect(!r.notes.contains { $0.hasPrefix("Downward confirmation") })
    }

    @Test func testALoneZnKLineIsWithheldWithTheRuleOn() throws {
        let r = try Self.propose(Self.loneZnK, policy: Self.on)
        let zn = try #require(Self.candidate(r, "Zn"))
        #expect(!zn.isProposed && zn.aboveDetectionLimit)
        let note = try #require(zn.familyNote)
        #expect(note.contains("Zn L\u{03B1}") && note.contains("below the 3 \u{03C3}"), "\(note)")
        #expect(r.withheld.contains { $0.element == "Zn" } && !r.proposed.contains { $0.element == "Zn" })
        #expect(r.notes.contains { $0.hasPrefix("Downward confirmation") && $0.contains("Z \u{2265} 30") })
    }

    @Test func testAZnKLineWithItsLLineIsKept() throws {
        let r = try Self.propose(Self.expected([("Al_Ka", 9000), ("Zn_Ka", 3000), ("Zn_La", 600)]), policy: Self.on)
        let zn = try #require(Self.candidate(r, "Zn"))
        #expect(zn.isProposed && zn.familyNote == nil, "\(zn.familyNote ?? "") \(zn.possibleReason ?? "")")
    }

    /// Below the bar the rule does not look: a lone Cu K line (Z = 29) stays proposed with the rule on at 30.
    @Test func testAKPickBelowTheBarIsNotChecked() throws {
        let r = try Self.propose(Self.expected([("Al_Ka", 9000), ("Cu_Ka", 3000)]), policy: Self.on)
        #expect(r.proposed.contains { $0.element == "Cu" })
    }

    @Test func testTheRuleNeedsFamilyConsistency() throws {
        let r = try Self.propose(Self.loneZnK, policy: ProposerPolicy(familyConsistency: false, downwardFamilyMinimumZ: 30))
        #expect(r.proposed.contains { $0.element == "Zn" })
    }

    @Test func testTheNoteLineNamesTheField() {
        #expect(Self.on.noteLine?.contains("downwardFamilyMinimumZ = 30") == true)
        #expect(ProposerPolicy.default.noteLine == nil)
        let r = try? ElementProposer(policy: Self.on).propose(counts: Self.loneZnK, axis: Self.axis,
            settings: FitSettings.standard(elements: ["Al"], axis: Self.axis, resolutionMnKaEV: 130, beamEnergy: 200))
        #expect(r?.notes.contains { $0.contains("downwardFamilyMinimumZ = 30") } == true, "the policy round-trips into the proposer's own note")
    }

    /// The uncorroborated tier: a lone Ga L line at a 12 keV beam (its K line is less than twice below the beam) is possible only, and the tier
    /// lists it; at 200 keV the same spectrum withholds Ga instead, so the tier is empty of it.
    @Test func testTheUncorroboratedTierListsTheUnconfirmableFinds() throws {
        let gaL = Self.expected([("Al_Ka", 9000), ("Ga_La", 300)])
        let low = try Self.propose(gaL, beam: 12)
        #expect(low.uncorroborated.map(\.element).contains("Ga"))
        #expect(low.uncorroborated.allSatisfy { $0.unconfirmable && !$0.isProposed })
        let high = try Self.propose(gaL)
        #expect(!high.uncorroborated.contains { $0.element == "Ga" })
        #expect(high.withheld.contains { $0.element == "Ga" }, "at 200 keV the K line is demanded and Ga is withheld")
    }
}
