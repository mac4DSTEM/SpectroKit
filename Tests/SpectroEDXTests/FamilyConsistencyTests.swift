//
//  FamilyConsistencyTests.swift
//  Role: R4, the family-consistency rule of the element proposer (`ProposerPolicy.familyConsistency`): a proposed element must show
//        the other lines its proposal implies. Noise-free planted spectra as in ProposerPolicyTests, so each statement is about the
//        rule, not about a draw. Red before the rule existed: the lone-line tests (the lone line was proposed), the sum-peak bound and the refinement
//        test (no such field). The whole-family test is the control: it holds with and without the rule (it needs the field to compile).
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct FamilyConsistencyTests {

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

    /// Continuum x dose, plus each planted column x dose: the group's lines that `keep` accepts.
    private static func expected(_ planted: [(id: String, area: Double, keep: @Sendable (FitLine) -> Bool)], dose k: Double = 10) -> [Double] {
        var out = energies.map { $0 >= 0.2 ? k * kramers($0) : 0 }
        for (id, area, keep) in planted {
            let g = group(id)
            let col = EDSLineModel.column(of: g.lines.filter(keep), energies: energies, scale: axis.scale)
            for i in out.indices { out[i] += k * area * col[i] }
        }
        return out
    }

    private static func propose(_ counts: [Double], policy: ProposerPolicy = .default) throws -> ProposalResult {
        try ElementProposer(policy: policy).propose(
            counts: counts, axis: axis, settings: FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200))
    }
    private static func candidate(_ r: ProposalResult, _ el: String) -> ElementCandidate? { r.candidates.first { $0.element == el } }

    private static let whole: @Sendable (FitLine) -> Bool = { _ in true }
    private static let alphaOnly: @Sendable (FitLine) -> Bool = { $0.weight == 1 }

    private static let loneGaL = expected([("Al_Ka", 9000, whole), ("Ga_La", 300, alphaOnly)])
    private static let off = ProposerPolicy(familyConsistency: false)

    @Test func testAnLLineWithoutItsKLineIsWithheld() throws {
        let old = try Self.propose(Self.loneGaL, policy: Self.off)
        #expect(Self.candidate(old, "Ga")?.isProposed == true)
        let r = try Self.propose(Self.loneGaL)
        let ga = try #require(Self.candidate(r, "Ga"))
        #expect(!ga.isProposed && ga.aboveDetectionLimit)
        let note = try #require(ga.familyNote)
        #expect(note.contains("Ga K\u{03B1}") && note.contains("below the 3 \u{03C3}"), "\(note)")
        #expect(!r.proposed.contains { $0.element == "Ga" })
        #expect(r.notes.contains { $0.hasPrefix("Confirmation withheld Ga") })
        // A consumer sees it through the rules' result too.
        let ruled = ProposalRules.shipped.apply(r)
        // The rerun without Ga may withhold the next phantom its counts moved to, so Ga is among the withheld, not alone.
        #expect(ruled.familyWithheld.map(\.element).contains("Ga") && !ruled.picks.contains { $0.element == "Ga" }, "\(ruled.familyWithheld.map(\.element))")
    }

    /// The K line is planted weaker than the L line (a fifth), so the L group stays the element's best group and the check runs; the K line is
    /// still far above its own limit, so Ga is kept.
    @Test func testAnLLineWithItsKLineIsKept() throws {
        let counts = Self.expected([("Al_Ka", 9000, Self.whole), ("Ga_La", 300, Self.whole), ("Ga_Ka", 60, Self.whole)])
        let r = try Self.propose(counts)
        let ga = try #require(Self.candidate(r, "Ga"))
        #expect(ga.group == "Ga_La", "the L group is the best group, so the companion check ran")
        #expect(ga.isProposed && ga.familyNote == nil)
        #expect(r.proposed.contains { $0.element == "Ga" })
    }

    /// An M line needs its L line: Hf Mα alone (Hf Lα 7.90 keV is in range, the beam 25 times above it) is withheld.
    @Test func testAnMLineWithoutItsLLineIsWithheld() throws {
        let r = try Self.propose(Self.expected([("Al_Ka", 9000, Self.whole), ("Hf_Ma", 300, Self.alphaOnly)]))
        let hf = try #require(Self.candidate(r, "Hf"))
        #expect(!hf.isProposed && hf.familyNote?.contains("Hf L\u{03B1}") == true, "\(hf.familyNote ?? "no note")")
    }

    /// Below the overvoltage bar the companion is not demanded: at a 12 keV beam Ga Kα (9.25 keV) is less than twice below it, so a lone Ga L line is not withheld.
    /// 0.11.0: it is not proposed either: the confirmation cannot be checked, so the element carries `possibleReason` ("Found by its Lα alone").
    @Test func testACompanionBelowTheOvervoltageBarIsNotDemanded() throws {
        let settings = FitSettings.standard(elements: ["Al"], axis: Self.axis, resolutionMnKaEV: 130, beamEnergy: 12)
        let r = try ElementProposer().propose(counts: Self.loneGaL, axis: Self.axis, settings: settings)
        let ga = try #require(Self.candidate(r, "Ga"))
        #expect(ga.familyNote == nil && !ga.isProposed && ga.unconfirmable && ga.possibleReason?.contains("alone") == true, "\(ga.possibleReason ?? "no reason")")
        let demanded = try ElementProposer(policy: ProposerPolicy(familyOvervoltage: 1.2)).propose(counts: Self.loneGaL, axis: Self.axis, settings: settings)
        #expect(Self.candidate(demanded, "Ga")?.familyNote != nil, "at 1.2 the 12 keV beam clears 9.25 keV and the K line is demanded")
    }

    /// A pile-up peak is a few percent of its parents: Si Kα (1.740 keV) on the Mg+O sum energy (1.779 keV) is a sum-peak question only when its net
    /// could be that small. Red before the bound: Si carried the question whatever its size.
    @Test func testASumPeakQuestionNeedsPlausibleParents() throws {
        let counts = Self.expected([("Al_Ka", 9000, Self.whole), ("O_Ka", 3000, Self.whole), ("Mg_Ka", 300, Self.whole), ("Si_Ka", 6000, Self.whole)])
        let r = try Self.propose(counts)
        let si = try #require(Self.candidate(r, "Si"))
        #expect(!si.hasSumPeakQuestion && r.proposed.contains { $0.element == "Si" }, "\(si.conflicts.map(\.question))")
        let loose = try Self.propose(counts, policy: ProposerPolicy(sumPeakFraction: 1000))
        #expect(Self.candidate(loose, "Si")?.hasSumPeakQuestion == true, "with no bound the Mg+O sum claims Si")
    }

    /// A self pair spends two photons of one line on each pile-up event, so its sum peak is at most half its parent (a pair of two lines at most
    /// the smaller parent). Ar Kα (2.957 keV) sits 17 eV from the Al+Al sum (2.974 keV): planted at two thirds of Al it is too large for that sum
    /// and carries no question; at a third it keeps it. Red before the half bound: the 6000-count Ar carried the question.
    @Test func testASelfPairSumPeakIsAtMostHalfItsParent() throws {
        let big = try Self.propose(Self.expected([("Al_Ka", 9000, Self.whole), ("Ar_Ka", 6000, Self.whole)]))
        let ar = try #require(Self.candidate(big, "Ar"))
        #expect(!ar.hasSumPeakQuestion, "\(ar.conflicts.map(\.question))")
        let small = try Self.propose(Self.expected([("Al_Ka", 9000, Self.whole), ("Ar_Ka", 3000, Self.whole)]))
        let arSmall = try #require(Self.candidate(small, "Ar"))
        #expect(arSmall.hasSumPeakQuestion, "a third of Al can be the Al+Al sum")
    }

    /// The rule off is the old run (no note, no withheld). The rule on: the withheld keep the numbers of their own test fit, and every other
    /// candidate has the numbers of the old run made without the withheld elements in the pool (the model is settled again without them, so their
    /// counts return to the lines they belong to).
    @Test func testFamilyConsistencyOffReproducesTheOldRunAndOnSettlesAgainWithoutTheWithheld() throws {
        let a = try Self.propose(Self.loneGaL, policy: Self.off)
        let b = try Self.propose(Self.loneGaL)
        #expect(Set(a.candidates.map(\.element)) == Set(b.candidates.map(\.element)))
        #expect(a.candidates.allSatisfy { $0.familyNote == nil } && !a.notes.contains { $0.contains("Family consistency") })
        let out = b.withheld.map(\.element)
        #expect(out.contains("Ga"), "\(out)")
        let ga = try #require(Self.candidate(b, "Ga")), gaOld = try #require(Self.candidate(a, "Ga"))
        // 0.11.0: a withheld element never enters the model, so its numbers are those of its own test fit (the identification fit), while the rule-off
        // run reports Ga from the final standard fit; both state a net and a limit.
        #expect(ga.net > 0 && ga.detectionLimit.isFinite && gaOld.net > 0 && gaOld.detectionLimit.isFinite, "\(ga.net) \(gaOld.net)")
        var without = Self.off
        without.pool = ElementProposer.defaultPool.filter { !out.contains($0) }
        let c = try Self.propose(Self.loneGaL, policy: without)
        for cb in b.candidates where cb.familyNote == nil {
            let cc = try #require(Self.candidate(c, cb.element), Comment(rawValue: cb.element))
            #expect(cb.net == cc.net && cb.detectionLimit == cc.detectionLimit && cb.criticalLevel == cc.criticalLevel && cb.isProposed == cc.isProposed, "\(cb.element)")
        }
        // 0.11.0: the rule runs at nomination time, so there is no "Settled again without" pass; the withheld element is named in the notes.
        #expect(b.notes.contains { $0.hasPrefix("Confirmation withheld Ga") })
    }

    @Test func testTheNoteLineNamesTheFamilyFields() {
        #expect(ProposerPolicy(familyOvervoltage: 3).noteLine?.contains("familyOvervoltage = 3") == true)
        #expect(ProposerPolicy(familyConsistency: false).noteLine?.contains("familyConsistency = false") == true)
        #expect(ProposerPolicy.default.noteLine == nil)
    }
}
