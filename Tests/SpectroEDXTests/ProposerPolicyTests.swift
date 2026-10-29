//
//  ProposerPolicyTests.swift
//  Role: `ProposerPolicy` and `UnlistedLineRules`. The default
//        policy reproduces the proposer built without one; each non-default field moves the candidates the way section 5 predicted
//        before the code was written. Noise-free planted spectra (the fit's own line model plus a continuum), so every
//        statement is about the policy, not about a draw.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct ProposerPolicyTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)   // 0 to 10.99 keV
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }

    private static let kramers: @Sendable (Double) -> Double = { e in
        let x = max(e, 0.05)
        return 60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5
    }

    /// Expected counts (not drawn): the continuum x dose plus the named line groups' areas x dose.
    private static func expected(areas: [String: Double], dose k: Double = 1, continuum: @Sendable (Double) -> Double = kramers) -> [Double] {
        var out = energies.map { $0 >= 0.2 ? k * continuum($0) : 0 }
        for (id, area) in areas {
            let el = String(id.prefix { $0 != "_" })
            let g = EDSLineModel.build(elements: [el], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == id }!
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in out.indices { out[i] += k * area * col[i] }
        }
        return out
    }

    private static func settings(_ current: [String]) -> FitSettings {
        FitSettings.standard(elements: current, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
    }

    private static func propose(_ counts: [Double], current: [String] = ["Al"], policy: ProposerPolicy = .default,
                                hole: [Double]? = nil, settings s: FitSettings? = nil) throws -> ProposalResult {
        try ElementProposer(policy: policy).propose(counts: counts, axis: axis, settings: s ?? settings(current), holeCounts: hole)
    }
    private static func candidate(_ r: ProposalResult, _ el: String) -> ElementCandidate? { r.candidates.first { $0.element == el } }

    private static let base = expected(areas: ["Al_Ka": 9000, "Mg_Ka": 90], dose: 10)

    // MARK: The default is the old behaviour

    @Test func testDefaultPolicyEqualsTheProposerWithoutOne() throws {
        let counts = Self.base
        let a = try ElementProposer().propose(counts: counts, axis: Self.axis, settings: Self.settings(["Al"]))
        let b = try Self.propose(counts)
        #expect(a.candidates == b.candidates && a.notes == b.notes && a.passes == b.passes && a.settled == b.settled)
        #expect(a.reducedChiSquared == b.reducedChiSquared)
        let d = ProposerPolicy.default
        #expect(d.currie == .standard && d.pool == nil && d.excluded == ElementProposer.defaultExcluded
                && d.minimumLineEnergyKeV == 0.45 && d.thresholds == .default
                && d.rangeMarginFWHM == 0.5 && d.sumPeakToleranceKeV == 0.06 && d.context == .default)
        let c = ElementContext.default
        #expect(c.quantifyByDefault == ["Cu"] && c.gridElements == ["Cu"] && c.implantedElements == ["Ga"])
        let u = UnlistedLineRules.default
        #expect(u.besideLineFWHM == 2 && u.besideEdgeFWHM == 1 && u.moveSigmaFactor == 1)
        #expect(try JSONDecoder().decode(UnlistedLineRules.self, from: JSONEncoder().encode(UnlistedLineRules(besideLineFWHM: 3))) == UnlistedLineRules(besideLineFWHM: 3))
        #expect(try JSONDecoder().decode(IdentificationThresholds.self, from: JSONEncoder().encode(IdentificationThresholds(peakSigma: 4))) == IdentificationThresholds(peakSigma: 4))
        #expect(try JSONDecoder().decode(ElementContext.self, from: JSONEncoder().encode(ElementContext(gridElements: ["Ni"]))) == ElementContext(gridElements: ["Ni"]))
    }

    // MARK: E1 Currie

    @Test func testStricterCurrieRaisesTheDetectionLimit() throws {
        let a = try Self.propose(Self.base)
        let b = try Self.propose(Self.base, policy: ProposerPolicy(currie: Currie(alpha: 0.01, beta: 0.01)))
        for ca in a.candidates {
            let cb = try #require(Self.candidate(b, ca.element))
            #expect(cb.detectionLimit > ca.detectionLimit && cb.criticalLevel > ca.criticalLevel, "\(ca.element)")
        }
        #expect(b.proposed.count <= a.proposed.count)
        #expect(b.currie == Currie(alpha: 0.01, beta: 0.01) && b.notes.contains { $0.contains("0.01") })
    }

    // MARK: E2 the pool

    @Test func testPoolAndExclusions() throws {
        #expect(!ElementProposer.defaultPool.contains("Ne") && ElementProposer.defaultPool(excluding: []).contains("Ne"))
        #expect(ElementProposer.defaultPool == ElementProposer.defaultPool(excluding: ElementProposer.defaultExcluded))
        let small = try Self.propose(Self.base, policy: ProposerPolicy(pool: ["Mg", "Si"]))
        // 0.11.0: an element is a candidate only where the residual has a peak for it, so the pool bounds the candidates from above.
        #expect(Set(small.candidates.map(\.element)).isSubset(of: ["Mg", "Si"]))
        // Neon planted (Ne K-alpha 0.85 keV): an excluded element is never a candidate; with nothing excluded it is found.
        let neon = Self.expected(areas: ["Al_Ka": 9000, "Ne_Ka": 3000], dose: 10)
        let none = try Self.propose(neon)
        let all = try Self.propose(neon, policy: ProposerPolicy(excluded: []))
        #expect(Self.candidate(none, "Ne") == nil && Self.candidate(all, "Ne") != nil)
    }

    // MARK: E8 the range margin

    @Test func testRangeMarginAddsAGroupAtTheRangeStart() throws {
        // 0.11.0: the group that takes the peak at the range start is whichever explains it best (Tb M-alpha 1.2326 keV beside Mg K-alpha
        // 1.2536 keV); what the margin decides is whether a line 3 to 23 eV inside the range may be tested at all. Half a width (36 eV) is the default margin.
        var s = Self.settings(["Al"]); s.fitFrom = 1.23
        let counts = Self.expected(areas: ["Al_Ka": 9000, "Mg_Ka": 9000], dose: 10)   // large enough to leave a 5 sigma residual peak
        let normal = try Self.propose(counts, settings: s)
        let zero = try Self.propose(counts, policy: ProposerPolicy(rangeMarginFWHM: 0), settings: s)
        let atStart: (ElementCandidate) -> Bool = { $0.energyKeV >= 1.23 && $0.energyKeV < 1.23 + 0.036 }
        #expect(!normal.candidates.contains(where: atStart), "the default margin keeps the groups within 36 eV of the range start out")
        #expect(zero.candidates.contains(where: atStart), "no margin: a group within 36 eV of the range start is tested: \(zero.candidates.map(\.group))")
    }

    // MARK: E9 the sum-peak tolerance, E10 the element context

    @Test func testSumPeakToleranceAndElementContext() throws {
        let parents = [SumParent(element: "Al", energyKeV: 1.4865)]
        let ar = XRayLines.line("Ar_Ka")!.energy                       // 2.9577 keV, 15 eV from the Al+Al sum (2.973 keV)
        #expect(LineConflicts.conflicts(element: "Ar", line: "Ar_Ka", lineEnergyKeV: ar, parents: parents).contains { $0.kind == .sumPeak })
        #expect(LineConflicts.conflicts(element: "Ar", line: "Ar_Ka", lineEnergyKeV: ar, parents: parents, toleranceKeV: 0.005).isEmpty)
        // Through the proposer: the same candidate, with a strong Al listed.
        let counts = Self.expected(areas: ["Al_Ka": 90000, "Ar_Ka": 900], dose: 10)
        let d = try Self.propose(counts)
        let n = try Self.propose(counts, policy: ProposerPolicy(sumPeakToleranceKeV: 0.005))
        #expect(try #require(Self.candidate(d, "Ar")).hasSumPeakQuestion)
        #expect(!(try #require(Self.candidate(n, "Ar")).hasSumPeakQuestion))
        // 0.11.0: the proposer is the identification loop; "the pile-up has no column of its own while Ar claims the energy, one at 0.005 keV"
        // and "Ar+ sums get columns once Ar is a parent" (proactive sum columns, exact-energy dedup) no longer exist.

        // Context: Cu, Ga and a made-up grid and implantation element.
        let cu = Self.expected(areas: ["Al_Ka": 9000, "Cu_Ka": 900, "Ga_La": 900, "Ni_Ka": 900], dose: 10)
        let hole = Self.expected(areas: ["Al_Ka": 9000], dose: 10)
        let normal = try Self.propose(cu, hole: hole)
        #expect(try #require(Self.candidate(normal, "Cu")).suggestedRole == .quantify && Self.candidate(normal, "Cu")?.holeRegionNote != nil)
        #expect(try #require(Self.candidate(normal, "Ga")).conflicts.contains { $0.kind == .fibContamination })
        #expect(try #require(Self.candidate(normal, "Ni")).conflicts.isEmpty && Self.candidate(normal, "Ni")?.suggestedRole == .fitOnly)
        let empty = try Self.propose(cu, policy: ProposerPolicy(context: ElementContext(quantifyByDefault: [], gridElements: [], implantedElements: [])), hole: hole)
        #expect(try #require(Self.candidate(empty, "Cu")).suggestedRole == .fitOnly && Self.candidate(empty, "Cu")?.holeRegionNote == nil)
        #expect(try #require(Self.candidate(empty, "Cu")).conflicts.isEmpty)
        #expect(try #require(Self.candidate(empty, "Ga")).conflicts.isEmpty)
        let other = try Self.propose(cu, policy: ProposerPolicy(context: ElementContext(quantifyByDefault: ["Ni"], gridElements: ["Ni"], implantedElements: ["Ni"])), hole: hole)
        let ni = try #require(Self.candidate(other, "Ni"))
        #expect(ni.suggestedRole == .quantify && ni.holeRegionNote != nil && ni.holeRegionNote!.contains("Ni"))
        #expect(Set(ni.conflicts.map(\.id)) == ["ni-fib", "ni-grid"])
    }

    // MARK: E4 - E5 (already parameters) keep working through the policy

    @Test func testPeakCapAndLowestLine() throws {
        let r = try Self.propose(Self.base, policy: ProposerPolicy(thresholds: IdentificationThresholds(maximumPeaks: 1)))
        #expect(r.proposed.count <= 1)
        let carbon = Self.expected(areas: ["Al_Ka": 9000, "C_Ka": 3000], dose: 10)
        let low = try Self.propose(carbon, policy: ProposerPolicy(minimumLineEnergyKeV: 0.2))
        let normal = try Self.propose(carbon)
        #expect(Self.candidate(low, "C") != nil && Self.candidate(normal, "C") == nil)
        #expect(normal.refused.contains { $0.element == "C" })
    }

    // MARK: U1 - U3 the unlisted-line check

    @Test func testBesideLineAndBesideEdgeDistances() throws {
        let al = EDSLineModel.build(elements: ["Al"], axis: Self.axis, beamEnergy: 200, resolutionMnKaEV: 130).groups
        let ka = XRayLines.line("Al_Ka")!.energy
        let w = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: ka + 0.08)!
        let e = ka + w                                                      // about 1 FWHM above the listed alpha line
        let wide = UnlistedLineChecker.neighbour(energyKeV: e, listedGroups: al, resolutionMnKaEV: 130, edges: [])
        #expect(wide?.line == "Al K\u{03B1}")
        #expect(UnlistedLineChecker.neighbour(energyKeV: e, listedGroups: al, resolutionMnKaEV: 130, edges: [],
                                              rules: UnlistedLineRules(besideLineFWHM: 0.5)) == nil)
        let edge = 1.5596
        let f = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: edge + 0.04)!
        let near = edge + 0.5 * f
        #expect(UnlistedLineChecker.neighbour(energyKeV: near, listedGroups: [], resolutionMnKaEV: 130, edges: [edge])?.line.contains("continuum split") == true)
        #expect(UnlistedLineChecker.neighbour(energyKeV: near, listedGroups: [], resolutionMnKaEV: 130, edges: [edge],
                                              rules: UnlistedLineRules(besideEdgeFWHM: 0.25)) == nil)
    }

    @Test func testMoveBarSelectsTheMovedNets() throws {
        let counts = Self.expected(areas: ["Al_Ka": 30000, "Mg_Ka": 4000, "Si_Ka": 12000, "Zn_La": 3000, "Zn_Ka": 9000], dose: 3)
        var m = QuantificationMethod()
        m.elements = ["Al", "Mg", "Si"].map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200; m.lockEnergyAxis = true
        let meta = SpectrumImageMetadata(fileName: "p", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: Self.axis.size,
                                         energyOffsetEV: 0, energyDispersionEV: 10)
        let input = PooledQuantificationInput(counts: counts.map { UInt64($0.rounded()) }, axis: Self.axis, method: m, metadata: meta,
                                              regionName: "p", pixelCount: 1)
        let q = try PooledQuantifier.run(input, tables: nil)
        let proposal = try UnlistedLineChecker.propose(counts: counts.map { Double(UInt64($0.rounded())) }, quantification: q)
        func check(_ factor: Double) -> UnlistedLineCheck {
            UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q, rules: UnlistedLineRules(moveSigmaFactor: factor))
        }
        let d = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q)
        let zero = check(0), huge = check(1e9), one = check(1)
        #expect(one.moves == d.moves)
        #expect(!zero.moves.isEmpty, "the refit moved nothing: \(zero.names)")
        #expect(huge.moves.isEmpty)
        #expect(d.moves.count <= zero.moves.count)
        #expect(zero.largest == d.largest && huge.largest == d.largest)
    }
}
