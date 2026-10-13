// SpectroKit S1 test partition (ADR 064 section 3.3): the methods of SpectroscopyUnlistedLineTests that move with the EDX core;
// the rest stay in SpectroscopyUnlistedLineTests.swift. Helpers are duplicated, not shared, across the split.
import XCTest
import DSTEMCore

/// WP3b F1 (docs/archive/v5/wp3b-fit-robustness-preregistration-2026-10-06.md, P4 and P5): after a Quantify fit the
/// proposer names every unlisted line at or above L_D (sum-peak questions included), and at% is withheld only when fitting
/// them moves a quantified net by more than its reported sigma. Synthetic pool: `Fixtures/eds-unlisted-sim.json`
/// (generator `tools/edx-pins/unlisted_sim.py`, the refuter's S2c recipe), seeded Poisson noise here. The assertions are
/// the DECISIONS (named, withheld), not exact nets, so a continuum change (lane F23) does not re-band them.
@MainActor
final class SpectroscopyUnlistedLineSpectro: XCTestCase {

    private typealias Q = SpectroscopyQuantifySpectro

    /// The measured outcomes for the lane report ($UNLISTED_NOTES via TEST_RUNNER_UNLISTED_NOTES); silent otherwise.
    private func note(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["UNLISTED_NOTES"] else { return }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close() }
        else { try? (s + "\n").write(toFile: path, atomically: false, encoding: .utf8) }
    }

    // MARK: The synthetic pool

    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    /// As SpectroscopyProposerTests (PTRS above 10, inversion below): platform independent.
    private static func poisson(_ lam: Double, _ rng: inout SplitMix64) -> UInt64 {
        if lam <= 0 { return 0 }
        if lam < 10 {
            let l = exp(-lam); var k = 0.0; var p = 1.0
            repeat { k += 1; p *= rng.uniform() } while p > l
            return UInt64(k - 1)
        }
        let slam = lam.squareRoot(), loglam = log(lam)
        let b = 0.931 + 2.53 * slam, a = -0.059 + 0.02483 * b
        let invalpha = 1.1239 + 1.1328 / (b - 3.4), vr = 0.9277 - 3.6224 / (b - 2)
        while true {
            let u = rng.uniform() - 0.5, v = rng.uniform()
            let us = 0.5 - abs(u)
            let k = ((2 * a / us + b) * u + lam + 0.43).rounded(.down)
            if us >= 0.07 && v <= vr { return UInt64(k) }
            if k < 0 || (us < 0.013 && v > us) { continue }
            if log(v) + log(invalpha) - log(a / (us * us) + b) <= -lam + k * loglam - lgamma(k + 1) { return UInt64(k) }
        }
    }

    private struct Pool { let expected: [Double]; let axis: EnergyAxis; let beam: Double }

    private static let pool: Pool = {
        let url = Q.fixtures.appendingPathComponent("eds-unlisted-sim.json")
        let o = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let e = o["expected"] as! [Double]
        return Pool(expected: e, axis: EnergyAxis(offset: o["offset"] as! Double, scale: o["scale"] as! Double, size: e.count),
                    beam: o["beam"] as! Double)
    }()

    /// `plant`: extra families (group id -> area) added to the expected counts with the fit's own line shapes before the noise.
    private static func input(seed: UInt64, elements: [(String, QuantificationMethod.ElementRole)],
                              plant: [String: Double] = [:]) -> PooledQuantificationInput {
        var expected = pool.expected
        if !plant.isEmpty {
            let symbols = Array(Set(plant.keys.map { String($0.split(separator: "_")[0]) }))
            let model = EDSLineModel.build(elements: symbols, axis: pool.axis, beamEnergy: pool.beam, resolutionMnKaEV: 130, escapePeaks: false)
            let energies = (0..<pool.axis.size).map { pool.axis.energy(ofChannel: $0) }
            for g in model.groups { if let area = plant[g.id] {
                let col = EDSLineModel.column(of: g.lines, energies: energies, scale: pool.axis.scale)
                for i in expected.indices { expected[i] += area * col[i] }
            } }
        }
        var rng = SplitMix64(state: seed)
        let counts = expected.map { poisson($0, &rng) }
        var m = QuantificationMethod()
        m.elements = elements.map { .init(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = pool.beam
        m.absorptionCorrection = false
        let meta = SpectrumImageMetadata(fileName: "eds-unlisted-sim.json", filePath: "", scanWidth: 1, scanHeight: 1,
                                         channelCount: pool.axis.size, energyOffsetEV: pool.axis.offset * 1000,
                                         energyDispersionEV: pool.axis.scale * 1000)
        return PooledQuantificationInput(counts: counts, axis: pool.axis, method: m, metadata: meta, regionName: "synthetic", pixelCount: 1)
    }

    private static let four: [(String, QuantificationMethod.ElementRole)] = [("O", .quantify), ("Si", .quantify), ("Ti", .quantify), ("Ni", .quantify)]
    private static let seven = four + [("Ge", .fitOnly), ("Cu", .fitOnly), ("Ga", .fitOnly)]

    // MARK: P5

    /// P5: the complete list. Over seeds 0-2 at% is never withheld; where the proposer makes a (chance) proposal, it is named
    /// (beside the Al K split: as an unexplained excess, never as an element) and the refit moves no quantified net by more than its sigma. Measured seeds are in the lane report.
    /// Mutation: `withholds` true whenever a candidate exists - red on a seed with a chance proposal.
    func testP5CompleteListNamesAChanceProposalButDoesNotWithhold() throws {
        var namedSomewhere = false
        for seed: UInt64 in [0, 1, 2] {
            let input = Self.input(seed: seed, elements: Self.seven)
            let q = try PooledQuantifier.run(input, tables: Q.tables)
            let proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q)
            let check = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q)
            note("P5 seed \(seed): " + check.summary + " | moves \(check.moves.count)")
            XCTAssertFalse(check.withholds, "seed \(seed): \(check.summary)")
            XCTAssertFalse(check.names.contains("Lu"), "seed \(seed): a chance Lu is never named as an element: \(check.names)")
            if !check.elementNames.isEmpty { XCTAssertTrue(check.summary.contains("largest move"), check.summary) }
            XCTAssertTrue(UnlistedLineChecker.withholding(q, check).hasAbundance)
            if !check.candidates.isEmpty {
                namedSomewhere = true
                XCTAssertTrue(check.line.hasPrefix("Unlisted lines found: "), check.line)
            }
        }
        // The Lu M-alpha proposal of seeds 0-2 sits at the Al K split (a continuum artefact lane F23 may remove), so P5 does not
        // rest on it alone: a weak real line (Ca K-alpha, ~2.5 L_D) on the complete list is named and does not withhold.
        let input = Self.input(seed: 0, elements: Self.seven, plant: ["Ca_Ka": 1200])
        let q = try PooledQuantifier.run(input, tables: Q.tables)
        let proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q)
        let check = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q)
        note("P5b seed 0 + Ca Ka 1200: " + check.summary + " | moves \(check.moves.count)")
        XCTAssertTrue(check.names.contains("Ca"), check.summary)
        XCTAssertFalse(check.withholds, check.summary)
        XCTAssertTrue(namedSomewhere || check.names.contains("Ca"))
    }

    // MARK: A2 (Gate D 2026-10-06: ship the quantity, label what is beside a listed line)

    private func groups(_ elements: [String]) -> [FitLineGroup] {
        EDSLineModel.build(elements: elements, axis: Self.pool.axis, beamEnergy: Self.pool.beam, resolutionMnKaEV: 130, escapePeaks: false).groups
    }

    /// T1: `neighbour` is a geometry rule on the STRONGEST (alpha) line of each listed group, +-2 FWHM(E) at the candidate's energy, nearest in
    /// FWHM units; a split edge within +-1 FWHM only when no group qualifies; never a beta line. Lu 1.581 keV is 1.15 FWHM from Al K-alpha
    /// (FWHM 78 eV at 130 eV Mn); with Al and Si listed Al K-alpha is still the nearest (Si K-alpha 1.87 FWHM, also inside). Cu K-alpha 8.041
    /// is 3.0 FWHM from Ni K-alpha (Ni K-beta, 217 eV away, is no reference): nil. Hf L-alpha 7.899 is 0.75 FWHM from Cu K-alpha.
    /// Mutations: (m1) measure against every line of the group -> the Cu/Ni case returns "Ni K\u{03B1}"; (m2) `2 * fwhm` -> `1 * fwhm` ->
    /// the Lu/Al case is nil. Each red before the test is trusted.
    func testT1NeighbourIsAGeometryRule() throws {
        let al = groups(["Al"])
        let n = try XCTUnwrap(UnlistedLineChecker.neighbour(energyKeV: 1.581, listedGroups: al, resolutionMnKaEV: 130, edges: [], nets: ["Al_Ka": 6000]))
        XCTAssertEqual(n.line, "Al K\u{03B1}"); XCTAssertEqual(n.net, 6000)
        XCTAssertEqual(UnlistedLineChecker.neighbour(energyKeV: 1.581, listedGroups: groups(["Al", "Si"]), resolutionMnKaEV: 130, edges: [])?.line, "Al K\u{03B1}")
        XCTAssertNil(UnlistedLineChecker.neighbour(energyKeV: 2.957, listedGroups: al, resolutionMnKaEV: 130, edges: []))
        XCTAssertNil(UnlistedLineChecker.neighbour(energyKeV: 8.041, listedGroups: groups(["Ni"]), resolutionMnKaEV: 130, edges: []), "Cu beside Ni K-beta is not beside Ni")
        XCTAssertEqual(UnlistedLineChecker.neighbour(energyKeV: 7.899, listedGroups: groups(["Cu"]), resolutionMnKaEV: 130, edges: [])?.line, "Cu K\u{03B1}")
        XCTAssertNil(UnlistedLineChecker.neighbour(energyKeV: 7.899, listedGroups: groups(["Si"]), resolutionMnKaEV: 130, edges: []))
        let split = UnlistedLineChecker.neighbour(energyKeV: 1.581, listedGroups: groups(["Si"]), resolutionMnKaEV: 130, edges: [1.5596])
        XCTAssertEqual(split?.line, "the continuum split at 1.560 keV"); XCTAssertEqual(split?.net, 0)
        XCTAssertNil(UnlistedLineChecker.neighbour(energyKeV: 1.65, listedGroups: groups(["O"]), resolutionMnKaEV: 130, edges: [1.5596]), "1.14 FWHM from the edge: clear")
    }

    /// T2: a Lu M-alpha beside a listed line is named as an unexplained excess beside it, never as Lu, and not refitted. Then a planted Lu M-alpha at 20 % of a listed Al K-alpha (the spec said 1 %: at 1 % the refit with Lu moves Al by 0.07 sigma and the proposer does not find it), large enough that a refit WITH it moves Al by more
    /// than sigma (asserted, so the case is a test of the rule), is still beside Al K-alpha and moves nothing.
    /// Mutation: let beside candidates into the refit (`elements` -> `candidates` in `check`'s refit) - red on the planted case.
    func testT2BesideCandidatesAreExcessesNotElementsAndNeverRefitted() throws {
        // The spec's seed-0 chance Lu M-alpha is gone from this tree (P5 seeds 0-2 now propose nothing), so the case is planted:
        // Lu M-alpha 3 000 counts at 1.581 keV on the seven-element list. Si K-alpha (listed, 159 eV away = 1.9 FWHM at the fit's
        // refined width) is the nearest line, so the excess is "beside Si K-alpha" - lines come before the split edge.
        let input0 = Self.input(seed: 0, elements: Self.seven, plant: ["Lu_Ma": 3000])
        let q0 = try PooledQuantifier.run(input0, tables: Q.tables)
        let c0 = UnlistedLineChecker.check(proposal: try UnlistedLineChecker.propose(counts: input0.counts.map { Double($0) }, quantification: q0),
                                           input: input0, quantification: q0)
        note("T2 split: " + c0.summary)
        let lu0 = try XCTUnwrap(c0.candidates.first { $0.element == "Lu" }, "premise: the planted Lu is proposed: \(c0.summary)")
        XCTAssertEqual(lu0.besideLine, "Si K\u{03B1}", c0.summary)
        XCTAssertNotNil(lu0.fractionOfNeighbour)
        XCTAssertTrue(lu0.shownName.hasPrefix("unexplained excess beside Si K\u{03B1}: "), lu0.shownName)
        XCTAssertFalse(c0.names.contains { $0.contains("Lu") }, "\(c0.names)")
        XCTAssertFalse(c0.elementNames.contains("Lu"))
        XCTAssertFalse(c0.withholds, c0.summary)
        XCTAssertTrue(c0.summary.contains("proposer's label Lu M\u{03B1}"), c0.summary)
        XCTAssertTrue(try XCTUnwrap(UnlistedLineChecker.withholding(q0, c0).abundanceCaveat).contains("excess beside Si K\u{03B1} (net "))

        // Planted: Al listed, Al K-alpha 100 000, Lu M-alpha 20 000 (20 %).
        let withAl = Self.seven + [("Al", .quantify)]
        let plant = ["Al_Ka": 100_000.0, "Lu_Ma": 20_000.0]
        let input = Self.input(seed: 0, elements: withAl, plant: plant)
        let q = try PooledQuantifier.run(input, tables: Q.tables)
        let check = UnlistedLineChecker.check(proposal: try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q),
                                              input: input, quantification: q)
        // The premise: a refit WITH Lu as Fit only moves Al by more than its sigma.
        var with = input; with.method.elements.append(.init(symbol: "Lu", role: .fitOnly, isManual: false)); with.refinement = q.refinement
        let qLu = try PooledQuantifier.run(with, tables: nil)
        let alBefore = try XCTUnwrap(q.rows.first { $0.element == "Al" }), alAfter = try XCTUnwrap(qLu.rows.first { $0.element == "Al" })
        note("T2 planted: Al \(alBefore.net) +- \(alBefore.sigma) -> \(alAfter.net) with Lu; " + check.summary)
        XCTAssertGreaterThan(abs(alAfter.net - alBefore.net), alBefore.sigma, "premise: the planted Lu matters to Al")
        let lu = try XCTUnwrap(check.candidates.first { $0.element == "Lu" }, check.summary)
        XCTAssertEqual(lu.besideLine, "Al K\u{03B1}")
        XCTAssertNotNil(lu.fractionOfNeighbour)
        XCTAssertFalse(check.withholds, check.summary)
        XCTAssertTrue(check.moves.isEmpty, check.summary)
        XCTAssertFalse(check.names.contains("Lu"))
        XCTAssertTrue(check.names.contains { $0.hasPrefix("unexplained excess beside Al K\u{03B1}: ") && $0.contains("% of Al K\u{03B1}") }, "\(check.names)")
        XCTAssertTrue(UnlistedLineChecker.withholding(q, check).hasAbundance)
    }

    /// T3: ship the quantity. The same P4 check as before names Ge, Cu, Ga and moves Ti; at% is non-nil on every row that had one
    /// and the caveat names the unlisted elements and the largest move; while the check runs the at% is shown with "running".
    /// Mutation: `withholding` blanks at% again when `c.withholds` - red; `holding` blanking - red.
    func testT3TheQuantityShipsWithTheCaveat() throws {
        let input = Self.input(seed: 0, elements: Self.four)
        let q = try PooledQuantifier.run(input, tables: Q.tables)
        let check = UnlistedLineChecker.check(proposal: try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q),
                                              input: input, quantification: q)
        XCTAssertTrue(check.withholds)
        XCTAssertEqual(Set(check.moves.map(\.element)).contains("Ti"), true, check.summary)
        let shown = UnlistedLineChecker.withholding(q, check)
        XCTAssertEqual(shown.rows.map(\.atomicPercent), q.rows.map(\.atomicPercent))
        XCTAssertEqual(shown.rows.map(\.weightPercent), q.rows.map(\.weightPercent))
        XCTAssertTrue(shown.rows.allSatisfy { $0.atomicPercent != nil })
        XCTAssertNil(shown.abundanceRefusal)
        XCTAssertTrue(try XCTUnwrap(shown.abundanceCaveat).contains("Ge (net "))
        let holding = UnlistedLineChecker.holding(q)
        XCTAssertEqual(holding.rows.map(\.atomicPercent), q.rows.map(\.atomicPercent))
        XCTAssertEqual(holding.abundanceCaveat, "unlisted-line check running")
        XCTAssertTrue(holding.unlistedCheckPending)
        // A complete list with nothing found carries no caveat, and the replaced caveat leaves no trace.
        let landed = UnlistedLineChecker.withholding(holding, UnlistedLineCheck(candidates: [], moves: []))
        XCTAssertNil(landed.abundanceCaveat); XCTAssertFalse(landed.unlistedCheckPending)
    }

    /// The refit uses the reported fit's own axis refinement. The reported fit here ran on a refinement made on the spectrum
    /// shifted by 3 channels (60 eV), so its axis is off; a refit on that same axis moves no net (Ca K has nothing to take),
    /// a refit that refined again would land on the right axis and move every net by many sigma.
    /// Mutation: `refit.refinement = q.refinement` removed - red.
    func testTheRefitUsesTheSameAxisRefinement() throws {
        var input = Self.input(seed: 3, elements: Self.seven)
        let shifted = Array(input.counts.dropFirst(3)) + [0, 0, 0]
        let probe = try PooledQuantifier.run(PooledQuantificationInput(counts: shifted, axis: input.axis, method: input.method,
                                                                      metadata: input.metadata, regionName: "shifted", pixelCount: 1), tables: nil)
        let wrong = try XCTUnwrap(probe.refinement)
        input.refinement = wrong
        let q = try PooledQuantifier.run(input, tables: nil)
        XCTAssertEqual(q.usedAxis, wrong.refinedAxis, "the reported fit ran on the shifted refinement")
        let ca = ElementCandidate(element: "Ca", group: "Ca_Ka", energyKeV: 3.6917, net: 1000, sigma: 100, sigmaZero: 100,
                                  criticalLevel: 200, detectionLimit: 400, conflicts: [], suggestedRole: .fitOnly, holeRegionNote: nil, misfit: 1)
        let proposal = ProposalResult(candidates: [ca], sumPeaks: [], refused: [], currie: .standard, notes: [], passes: 1, settled: true)
        var refitInput = input; refitInput.refinement = nil   // as the controller passes it when nothing was cached
        let check = UnlistedLineChecker.check(proposal: proposal, input: refitInput, quantification: q)
        note("refinement guard: " + check.summary)
        XCTAssertFalse(check.withholds, check.summary)
    }

    /// R8: Al K-alpha (1.4865 keV) sits 73 eV below the Al K edge the continuum is split at: with nothing listed it is Al itself, not
    /// "an excess beside the split". Lu M-alpha (1.581) with only Si listed still is. Si K-alpha at the Si edge (1.839, when split).
    /// Mutation: drop `&& !(element != nil && edgeOwner($0) == element)` in `neighbour` - the Al case returns the split line, red.
    func testR8TheOwnerOfASplitEdgeIsNeverBesideIt() {
        XCTAssertNil(UnlistedLineChecker.neighbour(energyKeV: 1.4865, listedGroups: [], resolutionMnKaEV: 130, edges: [1.5596], element: "Al"))
        XCTAssertEqual(UnlistedLineChecker.neighbour(energyKeV: 1.4865, listedGroups: [], resolutionMnKaEV: 130, edges: [1.5596], element: "Lu")?.line,
                       "the continuum split at 1.560 keV", "another element there is still beside the split")
        XCTAssertEqual(UnlistedLineChecker.neighbour(energyKeV: 1.581, listedGroups: groups(["Si"]), resolutionMnKaEV: 130, edges: [1.5596], element: "Lu")?.line,
                       "the continuum split at 1.560 keV")
        XCTAssertNil(UnlistedLineChecker.neighbour(energyKeV: 1.7400, listedGroups: [], resolutionMnKaEV: 130, edges: [1.839], element: "Si"))
        XCTAssertEqual(UnlistedLineChecker.edgeOwner(1.5596), "Al"); XCTAssertNil(UnlistedLineChecker.edgeOwner(3.0))
    }
}
