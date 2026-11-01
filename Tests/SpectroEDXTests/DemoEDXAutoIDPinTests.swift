import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// Auto ID (`ElementProposer.proposeOnRefinedAxis`, nothing listed) on the Poisson counts of the public AlMgSi demo pools
/// (mac4DSTEM `demo-edx`, `sim_edx.py` v2.0, `edx-demo-pools.json`). The truth is PLANTED ON SYNTHETIC DATA, not a measurement:
/// Al, Mg, Si, O, stray Cu K and sum peaks; no Ta. Every result stays `validation: "none"`.
///
/// These pins state what the kit does today on two findings of the demo run, so a change to the loop shows up here:
/// - Ta M-alpha (1.710 keV) beside an unclaimed Si K-alpha (1.740 keV). Ta is never proposed on any pool; on recipe A it ties
///   with Si for the 1.727 keV peak, so both are only possible and the planted Si is not proposed (a known issue: the Ta trial
///   is not withheld by the confirmation rule; its L-alpha line at 8.15 keV sits beside the stray Cu K-alpha at 8.05 keV, which
///   the loop has not modelled on this pool).
/// - Mg and O in the matrix pools, planted near 1 L_D. They are missed by the loop's published bars, not by a bias: the residual
///   peak needs 5 sigma of the top-hat residual (7.5 below 1 keV) and a new element a gain of 100. At 3 sigma (and no low-energy
///   factor) Mg and O are nominated on the matrix map and then fail the gain bar at about 1 and 2 L_D.
struct DemoEDXAutoIDPinTests {
    static func autoID(_ name: String, thresholds: IdentificationThresholds = .default) throws -> ProposalResult {
        let c = DemoEDXPoolTests.named(name)
        let input = DemoEDXPoolTests.input(c, noiseFree: false)
        return try ElementProposer(policy: ProposerPolicy(thresholds: thresholds))
            .proposeOnRefinedAxis(spectrum: input.counts, axis: c.axis, beamEnergy: 200, listed: [], metadata: input.metadata,
                                  regionName: name, tables: DemoEDXPoolTests.tables).result
    }

    /// No Ta is planted: it is never proposed, never a sum-peak question and never withheld-as-found on any demo pool.
    @Test(arguments: ["L5", "L6", "L7", "M_A", "M_matrix"])
    func taIsNeverProposed(_ name: String) throws {
        let p = try Self.autoID(name)
        DemoEDXPoolTests.say("\(name) auto ID: proposed \(p.proposed.map(\.element)), possible \(p.possible.map(\.element))")
        #expect(!p.proposed.contains { $0.element == "Ta" }, "\(name): Ta proposed")
        #expect(!p.sumPeakQuestions.contains { $0.element == "Ta" }, "\(name): Ta is a sum-peak question")
        if let ta = p.candidates.first(where: { $0.element == "Ta" }) { #expect(!ta.isProposed, "\(name)") }
    }

    /// Recipe A: Ta and Si tie for the 1.727 keV peak; the reasons name each other, and both stay possible only.
    @Test func recipeATaTiesWithSi() throws {
        let p = try Self.autoID("M_A")
        let ta = try #require(p.candidates.first { $0.element == "Ta" })
        let si = try #require(p.candidates.first { $0.element == "Si" })
        #expect(ta.group == "Ta_Ma" && p.possible.contains(ta), "\(ta.group) \(ta.possibleReason ?? "-")")
        #expect(ta.possibleReason?.contains("went to Si") == true, "\(ta.possibleReason ?? "-")")
        #expect(si.possibleReason?.contains("Ta explains the peak") == true, "\(si.possibleReason ?? "-")")
        #expect(si.aboveDetectionLimit)
        #expect(ta.familyNote == nil, "Ta was withheld: \(ta.familyNote ?? "-")")
        withKnownIssue("The planted Si is not proposed on recipe A: the Ta M-alpha rival keeps the 1.727 keV peak ambiguous") {
            #expect(p.proposed.contains { $0.element == "Si" })
        }
    }

    /// The matrix pools miss Mg and O at the default bars: neither is even a candidate.
    @Test(arguments: ["L5", "M_A", "M_matrix"])
    func mgAndOAreNotNominatedAtTheDefaultBars(_ name: String) throws {
        let p = try Self.autoID(name)
        #expect(!p.candidates.contains { $0.element == "Mg" }, "\(name)")
        #expect(!p.candidates.contains { $0.element == "O" }, "\(name)")
    }

    /// The cheap experiment that names the cause: with the residual bar at 3 sigma and no low-energy factor, the matrix map nominates
    /// Mg and O, and both fail the gain bar (a new element needs 100) near their detection limit. Refuted if they stayed absent.
    @Test func atALowerPeakBarMgAndOFailTheGainBar() throws {
        let p = try Self.autoID("M_matrix", thresholds: IdentificationThresholds(peakSigma: 3, lowEnergyFactor: 1))
        for el in ["Mg", "O"] {
            let c = try #require(p.candidates.first { $0.element == el }, "\(el) not nominated")
            DemoEDXPoolTests.say(String(format: "M_matrix 3 sigma: %@ %.2f L_D | %@", el, c.significance, c.possibleReason ?? "-"))
            #expect(!c.isProposed)
            #expect(c.possibleReason?.contains("below the 100 a new line needs") == true, "\(el): \(c.possibleReason ?? "-")")
            #expect(c.significance > 0.5 && c.significance < 3, "\(el): \(c.significance)")
        }
    }
}
