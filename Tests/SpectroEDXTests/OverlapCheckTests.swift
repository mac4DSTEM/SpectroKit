//
//  OverlapCheckTests.swift
//  Role: The overlap check of the identification loop (`ProposerPolicy.overlapCheck`): an element whose every line sits under a modelled line
//        leaves no residual peak, so the loop never nominates it; the check fits it once with the settled model and reports it as possible
//        only. Noise-free planted spectra (as in FamilyConsistencyTests), so each statement is about the rule, not about a draw. Red before
//        the check existed: the hidden element was not a candidate at all.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct OverlapCheckTests {

    /// 0 to 7.99 keV: Rb has only its L lines in range (Kα 13.40 keV), and both sit under the listed Si Kα (Rb Lα 1.694 and Lβ1 1.752 beside 1.740 keV).
    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 800)
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

    private static func propose(_ counts: [Double], policy: ProposerPolicy) throws -> ProposalResult {
        try ElementProposer(policy: policy).propose(
            counts: counts, axis: axis, settings: FitSettings.standard(elements: ["Al", "Si"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200))
    }

    private static let hidden = expected([("Al_Ka", 9000), ("Si_Ka", 9000), ("Rb_La", 200)])
    private static let on = ProposerPolicy(overlapCheck: true)

    @Test func testAnElementUnderAListedLineIsReportedPossibleByTheOverlapCheck() throws {
        let off = try Self.propose(Self.hidden, policy: .default)
        #expect(!off.candidates.contains { $0.element == "Rb" }, "without the check Rb leaves no residual peak: \(off.candidates.map(\.element))")
        let r = try Self.propose(Self.hidden, policy: Self.on)
        let rb = try #require(r.candidates.first { $0.element == "Rb" }, "\(r.candidates.map(\.element))")
        #expect(!rb.isProposed && rb.aboveDetectionLimit)
        #expect(rb.possibleReason?.contains("overlap check") == true && rb.possibleReason?.contains("Si") == true, "\(rb.possibleReason ?? "no reason")")
        #expect(r.possible.contains { $0.element == "Rb" } && !r.proposed.contains { $0.element == "Rb" })
        #expect(r.notes.contains { $0.hasPrefix("Overlap check") })
    }

    /// Without the hidden element the check reports nothing: every element it fits under Si and Al gains nothing.
    @Test func testTheOverlapCheckReportsNothingWhenNothingHides() throws {
        let clean = Self.expected([("Al_Ka", 9000), ("Si_Ka", 9000)])
        let a = try Self.propose(clean, policy: .default), b = try Self.propose(clean, policy: Self.on)
        #expect(Set(a.candidates.map(\.element)) == Set(b.candidates.map(\.element)), "\(b.candidates.map(\.element))")
        #expect(a.proposed.map(\.element) == b.proposed.map(\.element))
        #expect(b.notes.contains { $0.hasPrefix("Overlap check") && $0.contains("; 0 reached") }, "\(b.notes)")
    }

    @Test func testTheNoteLineNamesTheOverlapCheck() {
        #expect(Self.on.noteLine?.contains("overlapCheck = true") == true)
    }
}
