import XCTest
import DSTEMCore

/// Auto ID failed on six of the owner's Velox entries with `ProposerError.rankDeficient`: `ElementProposer.sumColumns` added
/// one pile-up column per parent pair, and two pairs whose energies coincide in the line table (Dy+Ti and Cs+Ho at 11.0061 keV)
/// gave two identical design columns. Registered fix: `docs/archive/v5/sum-column-dedup-preregistration-2026-10-08.md`
/// (a sum column within `sumPeakToleranceKeV` of one already added in the pass is not added again; the kept column's label names
/// every pair). The spectra are generated from the fit's own line model with seeded Gaussian-approximated counting noise.
final class SumColumnDedupTests: XCTestCase {

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { (Double(next() >> 11) + 0.5) / Double(1 << 53) }
        mutating func normal() -> Double { (-2 * log(uniform())).squareRoot() * cos(2 * Double.pi * uniform()) }
    }

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }

    /// Kramers x window continuum (as SpectroscopyProposerTests), E0 = 200 keV, plus the planted line areas (counts) of the fit's own groups.
    private static func spectrum(areas: [String: Double], seed: UInt64) -> [Double] {
        var mean = energies.map { e -> Double in
            guard e >= 0.2 else { return 0 }
            let x = max(e, 0.05)
            return (60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5) * 20
        }
        for (id, area) in areas {
            let el = String(id.prefix { $0 != "_" })
            let g = EDSLineModel.build(elements: [el], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == id }!
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mean.indices { mean[i] += area * col[i] }
        }
        var rng = SplitMix64(state: seed)
        return mean.map { max(0, ($0 + $0.squareRoot() * rng.normal()).rounded()) }
    }

    private static func settings() -> FitSettings {
        FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
    }

    private func propose(_ areas: [String: Double], pool: [String], seed: UInt64) throws -> ProposalResult {
        try ElementProposer(pool: pool).propose(counts: Self.spectrum(areas: areas, seed: seed), axis: Self.axis, settings: Self.settings())
    }

    /// The four parents. Dy L-alpha 6.4952 + Ti K-alpha 4.5108 = Cs L-alpha 4.2865 + Ho L-alpha 6.7198 = 11.006 keV (table values).
    private static let fourPlanted: [String: Double] = ["Dy_La": 40000, "Ti_Ka": 40000, "Cs_La": 40000, "Ho_La": 40000]
    private static let fourPool = ["Dy", "Ti", "Cs", "Ho", "Mg", "Al", "Fe"]

    // MARK: P3: the failing case

    /// Without the fix this throws `rankDeficient` (both pairs enter one pass as identical columns); with it the run scores,
    /// the four elements are proposed, and the one column at 11.006 keV names both pairs.
    func testTwoCoincidingSumPairsScoreAndTheKeptColumnNamesBoth() throws {
        let e1 = XRayLines.line("Dy_La")!.energy + XRayLines.line("Ti_Ka")!.energy
        let e2 = XRayLines.line("Cs_La")!.energy + XRayLines.line("Ho_La")!.energy
        XCTAssertEqual(e1, e2, accuracy: 1e-3, "the premise: the two pairs coincide in the line table")
        let r: ProposalResult
        do { r = try propose(Self.fourPlanted, pool: Self.fourPool, seed: 11) }
        catch { XCTFail("the run must score, not throw: \(error) (old code: rankDeficient)"); return }
        for el in ["Dy", "Ti", "Cs", "Ho"] { XCTAssertTrue(r.candidates.first { $0.element == el }!.isProposed, "\(el) is proposed") }
        let at = r.sumPeaks.filter { abs($0.energyKeV - e1) <= LineConflicts.sumPeakToleranceKeV }
        XCTAssertEqual(at.count, 1, "one column at the coinciding energy, not two")
        let col = try XCTUnwrap(at.first)
        XCTAssertTrue(col.label.contains("Dy+Ti") && col.label.contains("Cs+Ho"), "the label names both pairs: \(col.label)")
        XCTAssertEqual(Set(col.elements), ["Dy", "Ti", "Cs", "Ho"])
    }

    // MARK: A lone pair is unchanged

    /// One planted pair of parents (Al + Mg-like): every sum column is a lone pair, with the plain label and elements.
    func testALonePairKeepsItsPlainLabelAndElements() throws {
        let r = try propose(["Dy_La": 40000, "Ti_Ka": 40000], pool: ["Dy", "Ti", "Mg", "Al"], seed: 12)
        let dyTi = try XCTUnwrap(r.sumPeaks.first { $0.label == "Dy+Ti sum" }, "labels: \(r.sumPeaks.map(\.label))")
        XCTAssertEqual(dyTi.elements, ["Dy", "Ti"])
        XCTAssertFalse(r.sumPeaks.contains { $0.label.contains(" / ") }, "no merged column when no two pairs coincide")
        let self2 = try XCTUnwrap(r.sumPeaks.first { $0.label == "Dy+Dy sum" })
        XCTAssertEqual(self2.elements, ["Dy", "Dy"], "a self pair keeps both entries")
    }

    // MARK: Near is not equal

    /// Si+Ti (6.2506 keV) and Ca+Ru (6.2502 keV) are 0.4 eV apart in the table: near, not equal. The exact rule keeps two
    /// columns; a tolerance of 0.06 keV would merge them (the refuted rule, `sum-column-dedup-results-2026-10-08.md`).
    func testNearPairsFourHundredEVApartStayTwoColumns() throws {
        let e1 = XRayLines.line("Si_Ka")!.energy + XRayLines.line("Ti_Ka")!.energy
        let e2 = XRayLines.line("Ca_Ka")!.energy + XRayLines.line("Ru_La")!.energy
        XCTAssertEqual(abs(e1 - e2), 0.0004, accuracy: 1e-6, "the premise: the two pairs differ by 0.0004 keV")
        let r = try propose(["Si_Ka": 40000, "Ti_Ka": 40000, "Ca_Ka": 40000, "Ru_La": 40000],
                            pool: ["Si", "Ti", "Ca", "Ru", "Mg", "Al", "Fe"], seed: 13)
        let cols = r.sumPeaks.filter { abs($0.energyKeV - e1) <= 0.01 }
        XCTAssertEqual(cols.count, 2, "two columns, not one merged column: \(r.sumPeaks.map(\.label))")
        XCTAssertFalse(cols.contains { $0.label.contains(" / ") }, "neither column names both pairs")
    }
}
