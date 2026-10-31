//
//  SumEscapeExplainedTests.swift
//  Role: the sum/escape model's peaks are explained counts for the element proposer and the unlisted-line check. Before, a Quantify fit
//        with `SumEscapeModel` on modelled the pile-up and escape peaks, but the check proposed on the bare spectrum and named
//        them as elements (measured on the tools/edx-sim pool below: Ar, Ag, Pd at 100 counts/px; Rh, Ar, In, Sn, Pd, Ag, Cd, Ru,
//        Bi, K at 300 counts/px; La, Ce, Cr, Cs at the planted Fe escape with the free escape columns off). Planted truth only; the
//        model is `validation: "none"` and eXSpy has no sum or escape model to compare with.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

struct SumEscapeExplainedTests {

    private struct SimPools: Decodable {
        struct Region: Decodable { let label: String; let expected: [Double]; let components: [String: Double] }
        let offset: Double, scale: Double, size: Int
        let regions: [Region]
        var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    }

    /// tools/edx-sim/proposer_sim.py: region 1 is the Al matrix at 100 counts/px (Al+Al sum 1845 counts), region 2 the beta''
    /// pixel at 300 counts/px (six sum peaks, 454 to 8553 counts).
    private static let sim: SimPools = {
        let url = EDXFixtures.dir.appendingPathComponent("eds-proposer-sim.json")
        return try! JSONDecoder().decode(SimPools.self, from: Data(contentsOf: url))
    }()

    private static func input(counts: [Double], axis: EnergyAxis, elements: [String], sumEscape: SumEscapeModel?,
                              policy: QuantificationPolicy = .default) -> PooledQuantificationInput {
        var m = QuantificationMethod()
        m.elements = elements.map { .init(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200
        m.absorptionCorrection = false
        m.lockEnergyAxis = true
        let meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                                         energyOffsetEV: axis.offset * 1000, energyDispersionEV: axis.scale * 1000)
        return PooledQuantificationInput(counts: counts.map { UInt64(max($0, 0).rounded()) }, axis: axis, method: m, metadata: meta,
                                         regionName: "planted", pixelCount: 1, policy: policy, sumEscape: sumEscape)
    }

    private static func check(_ input: PooledQuantificationInput) throws -> (UnlistedLineCheck, PooledQuantification) {
        let q = try PooledQuantifier.run(input, tables: QuantificationTables.bundled())
        let proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q)
        return (UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q), q)
    }

    private static func simCounts(_ region: Int, plant: [String: Double] = [:]) -> [Double] {
        var expected = sim.regions[region].expected
        if !plant.isEmpty {
            let axis = sim.axis
            let symbols = Array(Set(plant.keys.map { String($0.split(separator: "_")[0]) }))
            let model = EDSLineModel.build(elements: symbols, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: false)
            let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
            for g in model.groups { if let a = plant[g.id] {
                let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
                for i in expected.indices { expected[i] += a * col[i] }
            } }
        }
        var rng = Xoshiro256StarStar(seed: UInt64(77 + region))
        return expected.map { rng.poisson($0) }
    }

    private static let listed = ["Al", "Mg", "Si", "O", "Cu"]

    /// Red before: with the model on, the check named the sum peaks as Ar, Ag, Pd (100 counts/px) and Rh, Ar, In, Sn, Pd, Ag, Cd,
    /// Ru, Bi, K (300 counts/px). With the model off nothing changes: the proposer's own sum columns win those peaks and the check
    /// still names the elements it lost them to as sum-peak questions (D6).
    @Test(arguments: [1, 2])
    func simSumPeaksTheModelCoversAreNotNamed(region: Int) throws {
        let counts = Self.simCounts(region)
        // Off: an explicit model with both terms off (the default runs sum peaks when the data support them, below).
        let (off, qOff) = try Self.check(Self.input(counts: counts, axis: Self.sim.axis, elements: Self.listed, sumEscape: SumEscapeModel()))
        #expect(qOff.sumEscapeCounts == nil)
        #expect(off.names.contains("Ar"), "premise: without the model the Al+Al sum is named as Ar: \(off.summary)")
        // The default (`SumPeakRule.whenSignificant`): the Al+Al self pair is significant, the sum peaks are kept and explained.
        let (byDefault, qDefault) = try Self.check(Self.input(counts: counts, axis: Self.sim.axis, elements: Self.listed, sumEscape: nil))
        #expect(qDefault.appliedSumEscape == SumEscapeModel(sumPeaks: true))
        #expect(qDefault.sumEscapeCounts != nil)
        #expect(!byDefault.names.contains("Ar") && !byDefault.names.contains("Ag"), "the default explains the Al+Al sum: \(byDefault.summary)")
        let (on, q) = try Self.check(Self.input(counts: counts, axis: Self.sim.axis, elements: Self.listed, sumEscape: .both))
        let sumCounts = try #require(q.sumEscapeCounts)
        #expect(sumCounts.reduce(0, +) > 0.5 * Self.sim.regions[region].components.filter { $0.key.hasPrefix("sum_") }.values.reduce(0, +))
        #expect(on.candidates.isEmpty, "the modelled sum peaks are explained: \(on.summary)")
    }

    /// A real line between two sum peaks is still found with the model on: K K-alpha (3.314 keV, between Al+Si 3.226 and Si+Si 3.479),
    /// the strongest candidate. (The elements its peak was tested against, In and Cd among them, are named beside it as the check
    /// always names every tested candidate at or above L_D; that is the check's rule, not pile-up.)
    @Test func aRealLineBesideTheSumPeaksIsStillNamed() throws {
        let counts = Self.simCounts(2, plant: ["K_Ka": 3000])
        let (on, _) = try Self.check(Self.input(counts: counts, axis: Self.sim.axis, elements: Self.listed, sumEscape: .both))
        #expect(on.elementNames.first == "K", "\(on.summary)")
    }

    /// Red before: a common escape fraction with the free escape columns off left the Fe K-alpha escape (4.66 keV) to the proposer,
    /// which named it La (L-alpha 4.651 keV), with Ce, Cr and Cs beside it.
    @Test func theCommonEscapeIsExplained() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 2000)
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mu = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? 2.0 * max(200 - e, 0) / x * exp(-pow(0.3 / x, 3)) / 40 : 0
        }
        let model = EDSLineModel.build(elements: ["Al", "Fe"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: true)
        for g in model.groups where g.id == "Al_Ka" || g.id == "Fe_Ka" {
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += 300_000 * col[i] }
            if !g.escapes.isEmpty {
                let ec = EDSLineModel.column(of: g.escapes, energies: energies, scale: axis.scale)
                for i in mu.indices { mu[i] += 0.01 * 300_000 * ec[i] }
            }
        }
        var rng = Xoshiro256StarStar(seed: 3)
        let counts = mu.map { rng.poisson($0) }
        var policy = QuantificationPolicy.default
        policy.fit.escapePeaks = false
        let (on, q) = try Self.check(Self.input(counts: counts, axis: axis, elements: ["Al", "Fe"],
                                                sumEscape: SumEscapeModel(commonEscapeFraction: true), policy: policy))
        #expect(q.sumEscapeCounts != nil)
        #expect(on.candidates.isEmpty, "the modelled Fe escape is explained: \(on.summary)")
    }

    /// The proposer itself: the sum/escape fit's components as `explained` remove the sum peaks from what it can propose; nil runs it
    /// as before (the same result as no argument).
    @Test func theProposerTakesTheComponentsAsExplained() throws {
        let axis = Self.sim.axis
        let counts = Self.simCounts(2)
        let st = FitSettings.standard(elements: Self.listed, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        let r = try EDSSumEscapeFit.run(counts: counts, axis: axis, settings: st, model: .both)
        #expect(r.componentCounts.count == r.fit.channels.count)
        var explained = [Double](repeating: 0, count: axis.size)
        for (k, ch) in r.fit.channels.enumerated() { explained[ch] = r.componentCounts[k] }
        let bare = try ElementProposer().propose(counts: counts, axis: axis, settings: st)
        let none = try ElementProposer().propose(counts: counts, axis: axis, settings: st, explained: nil)
        #expect(bare.candidates == none.candidates)
        #expect(bare.candidates.contains { $0.aboveDetectionLimit })
        let shared = try ElementProposer().propose(counts: counts, axis: axis, settings: st, explained: explained)
        #expect(!shared.candidates.contains { $0.aboveDetectionLimit }, "\(shared.candidates.map(\.group))")
        #expect(throws: ProposerError.lengthMismatch) {
            _ = try ElementProposer().propose(counts: counts, axis: axis, settings: st, explained: [1, 2])
        }
        let off = try EDSSumEscapeFit.run(counts: counts, axis: axis, settings: st, model: SumEscapeModel())
        #expect(off.componentCounts.allSatisfy { $0 == 0 } && off.componentCounts.count == off.fit.channels.count)
    }
}
