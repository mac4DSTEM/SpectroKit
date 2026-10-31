import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// Auto ID (`ElementProposer.proposeOnRefinedAxis`, nothing listed) on the Poisson counts of the public AlMgSi demo pools
/// (mac4DSTEM `demo-edx`, `sim_edx.py` v2.0, `edx-demo-pools.json`). The truth is PLANTED ON SYNTHETIC DATA, not a measurement:
/// Al, Mg, Si, O, stray Cu K and sum peaks; no Ar, Ag or Pd. Every result stays `validation: "none"`.
///
/// Red before: Ar K-alpha (2.957 keV, 15-27 L_D), Ag L-alpha (2.984 keV, 6-11 L_D) and Pd L-alpha (2.838 keV) were listed as
/// "possible" on every Al-rich pool, though the loop had already given their peak (2.97 keV) to the Al+Al sum column. Now they are
/// explained by that sum peak and are not possible.
struct DemoEDXAutoIDTests {
    static func autoID(_ name: String) throws -> ProposalResult {
        let c = DemoEDXPoolTests.named(name)
        let input = DemoEDXPoolTests.input(c, noiseFree: false)
        return try ElementProposer().proposeOnRefinedAxis(spectrum: input.counts, axis: c.axis, beamEnergy: 200, listed: [],
                                                          metadata: input.metadata, regionName: name, tables: DemoEDXPoolTests.tables).result
    }

    @Test(arguments: ["L5", "M_A", "M_matrix"])
    func theAlAlSumExplainsArAndAg(_ name: String) throws {
        let p = try Self.autoID(name)
        let possible = Set(p.possible.map(\.element)), explained = Set(p.explainedBySumPeaks.map(\.element))
        DemoEDXPoolTests.say("\(name) auto ID: proposed \(p.proposed.map(\.element)), possible \(possible.sorted()), explained \(explained.sorted())")
        #expect(p.proposed.contains { $0.element == "Al" }, "\(name)")
        #expect(p.sumPeaks.contains { $0.label == "Al+Al sum" && $0.detected }, "\(name): \(p.sumPeaks)")
        for el in ["Ar", "Ag"] {
            #expect(!possible.contains(el), "\(name): \(el) is still possible")
            #expect(!p.proposed.contains { $0.element == el } && !p.sumPeakQuestions.contains { $0.element == el })
            let c = try #require(p.candidates.first { $0.element == el }, "\(name): \(el) was not tested")
            #expect(c.explainedBySumPeak == "Al+Al sum", "\(name): \(el) \(c.explainedBySumPeak ?? "nil")")
            #expect(c.hasSumPeakQuestion, "\(name): \(el) has no Al+Al conflict")
        }
        #expect(p.notes.contains { $0.hasPrefix("Explained as pile-up") && $0.contains("Ar") && $0.contains("Al+Al sum") }, "\(name): \(p.notes)")
        // Explained is its own tier: never possible, proposed or withheld.
        for c in p.explainedBySumPeaks {
            #expect(!c.isProposed && c.familyNote == nil && !p.possible.contains(c))
        }
    }

    /// The other side: a real Ar line planted under the Al+Al sum of L5 (Ar K-alpha 2.957 keV, 16 eV from the sum, and its K-beta
    /// at 3.190 keV, 10 %). One spectrum cannot separate the two: with 1000 Ar counts (about half the sum) the sum column still
    /// explains the peak (gain there 105800 against 105591), so Ar is explained, but it keeps the sum-peak question and its
    /// two-current remedy; it is never dropped. With 4000 Ar counts it is a sum-peak question of the proposed tier.
    @Test(arguments: [1000.0, 4000.0])
    func aRealArLineKeepsTheSumPeakQuestion(_ arCounts: Double) throws {
        let c = DemoEDXPoolTests.named("L5")
        let input = DemoEDXPoolTests.input(c, noiseFree: false)
        var counts = input.counts.map { Double($0) }
        for (e, area) in [(2.9577, arCounts), (3.1905, 0.1 * arCounts)] {
            let fwhm = (130.0 * 130 + 2.5 * (e * 1000 - 5898.7)).squareRoot() / 1000, s = fwhm / 2.354820045
            for i in counts.indices {
                let x = c.axis.energy(ofChannel: i)
                counts[i] += area * c.axis.scale / (s * (2 * Double.pi).squareRoot()) * exp(-0.5 * pow((x - e) / s, 2))
            }
        }
        let r = try ElementProposer().proposeOnRefinedAxis(spectrum: counts.map { UInt64($0.rounded()) }, axis: c.axis, beamEnergy: 200, listed: [],
                                                           metadata: input.metadata, regionName: "L5+Ar", tables: DemoEDXPoolTests.tables).result
        let ar = try #require(r.candidates.first { $0.element == "Ar" })
        DemoEDXPoolTests.say(String(format: "L5 + %.0f Ar: Ar %.1f L_D, proposed %d, question %d, possible %d, explained %@ | %@", arCounts, ar.significance,
                                    r.proposed.contains(ar) ? 1 : 0, r.sumPeakQuestions.contains(ar) ? 1 : 0, r.possible.contains(ar) ? 1 : 0,
                                    ar.explainedBySumPeak ?? "-", ar.possibleReason ?? "-"))
        #expect(ar.hasSumPeakQuestion, "\(arCounts) Ar counts: no sum-peak question")
        #expect(ar.conflicts.contains { $0.kind == .sumPeak && $0.remedy.contains("different beam currents") })
        if arCounts >= 4000 {
            #expect(ar.explainedBySumPeak == nil && r.sumPeakQuestions.contains(ar), "\(arCounts) Ar counts: \(ar.possibleReason ?? "-")")
        } else {
            #expect(r.explainedBySumPeaks.contains(ar) || r.sumPeakQuestions.contains(ar) || r.possible.contains(ar))
        }
    }

    /// Pure Mg5Si6 (L7): no Al, so no Al+Al column and nothing is explained by it.
    @Test func noAlNoAlAlExplanation() throws {
        let p = try Self.autoID("L7")
        #expect(!p.sumPeaks.contains { $0.label == "Al+Al sum" })
        #expect(!p.explainedBySumPeaks.contains { $0.explainedBySumPeak == "Al+Al sum" })
    }
}
