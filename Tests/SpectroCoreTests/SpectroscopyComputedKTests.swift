import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// WP3 lane K round 2: computed k from NIST EPQ data (Bote-Salvat 2008 sigma, Krause 1979 omega,
/// generic SDD epsilon). NO JVM was available, so EVERY expected number below is from an
/// independent Python re-implementation of the EPQ formulas (laneK/bs_ref.py, same CSVs, EPQ's
/// own CODATA 2002 constants) -- a re-implementation, not EPQ itself.
final class SpectroscopyComputedKTests: XCTestCase {
    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("mac4DSTEM/Resources/Spectroscopy")
    private static let bs = try! BoteSalvatCrossSection(directory: dir)
    private static let krause = try! KrauseFluorescenceYield(contentsOf: dir.appendingPathComponent("Krause1979.csv"))
    private static let mac = try! MassAbsorptionTable(contentsOf: dir.appendingPathComponent("FFastMAC.csv"))
    private static let weights = try! EPQLineWeights(contentsOf: dir.appendingPathComponent("LineWeights.csv"))
    private static let sdd = SDDEfficiency(table: mac)

    private func rel(_ a: Double, _ b: Double) -> Double { abs(a - b) / abs(b) }
    private func assertRel(_ a: Double, _ b: Double, _ tol: Double = 1e-12, _ m: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(rel(a, b), tol, "\(m) got \(a) want \(b)", file: file, line: line)
    }

    func testBoteSalvatMatchesReimplementation() {
        // [Z: sigma_K at 3, 15, 20, 100, 200 keV in cm^2] (3 and 15-20 keV straddle U = 16 for Mg/Al/Si:
        // 3 keV is U < 16 for all three; 20 keV and up is U > 16 for Mg, Al, Si).
        let want: [Int: [Double]] = [
            12: [1.7931390061084167e-20, 1.279279806365956e-20, 1.0820459550453443e-20, 3.874812706402355e-21, 2.6748281197328863e-21],
            13: [1.1266368050966297e-20, 9.838128870816253e-21, 8.394821499902708e-21, 3.090547230061663e-21, 2.1425204610989484e-21],
            14: [6.867488509587773e-21, 7.67498285981728e-21, 6.620809840144854e-21, 2.5093304295493816e-21, 1.7473762161829248e-21],
            26: [0, 6.047370512213423e-22, 6.656643822497671e-22, 4.270311078084073e-22, 3.1842713042007985e-22],
            29: [0, 3.156949369148222e-22, 3.925760687800297e-22, 3.0756102829727654e-22, 2.348148198806e-22],
            30: [0, 2.4913405765642304e-22, 3.279684818277925e-22, 2.772500023505385e-22, 2.1347970638732373e-22],
        ]
        for (z, vals) in want {
            for (e, v) in zip([3e3, 15e3, 20e3, 100e3, 200e3], vals) {
                let s = Self.bs.sigma(z: z, shell: 0, energyEV: e)!
                if v == 0 { XCTAssertEqual(s, 0, "Z=\(z) E=\(e)") } else { assertRel(s, v, 1e-12, "Z=\(z) E=\(e)") }
            }
        }
        // Other shells use the same code: Cu L3 at 20 keV (U < 16), Au M5 at 200 keV (U > 16).
        assertRel(Self.bs.sigma(z: 29, shell: 3, energyEV: 20e3)!, 3.651280333970885e-20)
        assertRel(Self.bs.sigma(z: 79, shell: 8, energyEV: 200e3)!, 5.253274533767374e-21)
    }

    func testBoteSalvatEdgesAndMonotonicity() {
        XCTAssertEqual(Self.bs.edgeEV(z: 12, shell: 0), 1294.51)
        XCTAssertEqual(Self.bs.edgeEV(z: 14, shell: 0), 1828.5)
        XCTAssertNil(Self.bs.edgeEV(z: 1, shell: 3))
        XCTAssertNil(Self.bs.sigma(z: 1, shell: 3, energyEV: 1e5))
        XCTAssertNil(Self.bs.sigma(z: 120, shell: 0, energyEV: 1e5))
        // sigma_K at fixed E0 falls as Ec rises (Mg < Al < Si < Fe < Cu < Zn edges).
        var prev = Double.infinity
        for z in [12, 13, 14, 26, 29, 30] {
            let s = Self.bs.sigma(z: z, shell: 0, energyEV: 200e3)!
            XCTAssertLessThan(s, prev, "Z=\(z)"); prev = s
        }
        // Below threshold: zero, not nil.
        XCTAssertEqual(Self.bs.sigma(z: 26, shell: 0, energyEV: 5e3), 0)
        // The protocol entry maps K lines only, in keV.
        assertRel(Self.bs.sigma(element: "Si", line: "Ka", beamEnergyKeV: 200)!, 1.7473762161829248e-21)
        XCTAssertNil(Self.bs.sigma(element: "Si", line: "La", beamEnergyKeV: 200))
        XCTAssertTrue(Self.bs.sourceName.contains("Bote-Salvat") && Self.bs.sourceName.contains("not Velox"))
    }

    func testKrauseK() {
        XCTAssertEqual(Self.krause.omegaK(z: 12), 0.030); XCTAssertEqual(Self.krause.omegaK(z: 13), 0.039)
        XCTAssertEqual(Self.krause.omegaK(z: 14), 0.050); XCTAssertEqual(Self.krause.omegaK(z: 29), 0.44)
        XCTAssertEqual(Self.krause.omegaK(z: 5), 1.7e-3)
        for z in 1...4 { XCTAssertNil(Self.krause.omegaK(z: z), "Z=\(z)") }
        // Physical data rows after the // comments, like EPQ's loadTable (measured 2026-10-06: 110 -- not 99).
        XCTAssertEqual(Self.krause.rowCount, 110)
        // A leading-space comment is still a comment; a blank line in the data advances Z.
        let k = KrauseFluorescenceYield(csv: "  // hdr\n,,\n\n0.5,0.1\n")
        XCTAssertEqual(k.rowCount, 3); XCTAssertNil(k.omegaK(z: 1)); XCTAssertNil(k.omegaK(z: 2)); XCTAssertEqual(k.omegaK(z: 3), 0.5)
        XCTAssertNil(Self.krause.omega(element: "Cu", line: "La"))
    }

    func testSDDEfficiencyPins() {
        // EPQ getDefaultSDDProperties: Au 0, Al 10 nm, dead layer 0, Si 450 um.
        for (e, v) in [(0.5, 0.9828437971989638), (1.2536, 0.9984004525127538), (1.4865, 0.9989960336600073),
                       (1.7397, 0.9911253410184239), (5.0, 0.9995004644266257)] {
            assertRel(Self.sdd.efficiency(energyKeV: e), v, 1e-12, "E=\(e)")
        }
        // Bare 450 um Si: only the absorber term, no layers.
        XCTAssertEqual([Self.sdd.goldNm, Self.sdd.aluminiumNm, Self.sdd.deadLayerMicrons, Self.sdd.siliconMicrons], [0, 10, 0, 450])
        // All four thicknesses stay parameters: the SiLi-style layers change eps and the source string.
        let layered = SDDEfficiency(table: Self.mac, goldNm: 8, aluminiumNm: 10, deadLayerMicrons: 0.085)
        XCTAssertLessThan(layered.efficiency(energyKeV: 0.5), Self.sdd.efficiency(energyKeV: 0.5))
        XCTAssertTrue(layered.sourceName.contains("Au 8.0 nm") && layered.sourceName.contains("0.085"))
        let bare = SDDEfficiency(table: Self.mac, goldNm: 0, aluminiumNm: 0, deadLayerMicrons: 0)
        let si = try! Self.mac.mac(element: "Si", energyKeV: 1.4865)
        assertRel(bare.efficiency(energyKeV: 1.4865), 1 - exp(-si * 2.33 * 450e-4), 1e-12)
        XCTAssertEqual(Self.sdd.efficiency(energyKeV: 1e-6), 0)   // outside FFAST: refusal value
        let s = Self.sdd.sourceName
        for needle in ["EPQ getDefaultSDDProperties", "generic SDD model", "not the owner's Super-X", "Au 0.0 nm", "Al 10.0 nm",
                       "dead layer 0.0", "Si 450.0", "FFAST"] {
            XCTAssertTrue(s.contains(needle), "\(needle) in \(s)")
        }
    }

    private func lines(_ els: [(String, Double)]) -> [LineIngredients] {
        els.map { LineIngredients.kAlpha(element: $0.0, energyKeV: $0.1, weights: Self.weights)! }
    }
    private func model(_ e0: Double = 200) -> ComputedKFactor {
        ComputedKFactor(cross: Self.bs, yield: Self.krause, efficiency: Self.sdd, beamEnergyKeV: e0)
    }

    func testComputedKRatiosAndSet() throws {
        let l = lines([("Mg", 1.2536), ("Al", 1.4865), ("Si", 1.7397)])
        XCTAssertEqual(l.map(\.lineWeight).map { ($0 * 1e9).rounded() / 1e9 },
                       [0.982911558, 0.969466632, 0.945945946])
        let set = try model().kFactorSet(lines: l, reference: 2, date: "2026-10-05")
        XCTAssertEqual(set.k("Si"), 1)
        assertRel(set.k("Mg")!, 0.9001781036540543, 1e-9, "k_Mg/k_Si at 200 kV")
        assertRel(set.k("Al")!, 0.9724105488987975, 1e-9, "k_Al/k_Si at 200 kV")
        assertRel(try model(100).kFactors(lines: l, reference: 2)[0], 0.8923701665989099, 1e-9)
        assertRel(try model(100).kFactors(lines: l, reference: 2)[1], 0.9680787512002906, 1e-9)
        // Printed to four digits (Fable's independent value): 0.9002 / 0.9724.
        XCTAssertEqual(set.k("Mg")!, 0.9002, accuracy: 5e-5); XCTAssertEqual(set.k("Al")!, 0.9724, accuracy: 5e-5)
        XCTAssertEqual(set.kind, .computed); XCTAssertEqual(set.reference, "Si")
        XCTAssertEqual(set.relSigma("Si"), 0); XCTAssertEqual(set.relSigma("Mg"), 0.2)
        for needle in ["Bote-Salvat", "Krause 1979", "EPQ getDefaultSDDProperties", "generic SDD", "relative to Si", "UNVALIDATED", "200.0 keV"] {
            XCTAssertTrue(set.source.contains(needle), "\(needle) in \(set.source)")
        }
        // Reference carries no sigma: Mg/Si against Si is 20 %; two independent factors would be 28 %.
        assertRel(RatioSigma.kTerm(set, numerator: "Mg", denominator: "Si")!, 0.2, 1e-12)
        let free = KFactorSet(kind: .computed, elements: ["Mg", "Si"], values: [0.93, 1], source: "x", date: "2026-10-05")!
        assertRel(RatioSigma.kTerm(free, numerator: "Mg", denominator: "Si")!, 0.28284271247461906, 1e-12)
    }

    func testClosedLoopWithRealModels() throws {
        let l = lines([("Mg", 1.2536), ("Al", 1.4865), ("Si", 1.7397)])
        let k = try model().kFactors(lines: l, reference: 2)
        let truth = [0.05, 0.15, 0.80]    // wt fractions
        var intensities: [Double] = []
        for (li, c) in zip(l, truth) {
            let a = QuantElementData.entry(li.element)!.atomicWeight
            intensities.append(c / a * Self.bs.sigma(element: li.element, line: "Ka", beamEnergyKeV: 200)!
                * Self.krause.omega(element: li.element, line: "Ka")! * li.lineWeight
                * Self.sdd.efficiency(energyKeV: li.energyKeV) * 1e30)
        }
        let w = try CliffLorimer.weightFractions(intensities: intensities, kFactors: k)
        for (g, t) in zip(w, truth) { XCTAssertEqual(g, t, accuracy: 1e-12) }
        // A line the model does not cover is a refusal.
        let bad = LineIngredients(element: "Si", line: "La", energyKeV: 0.1, lineWeight: 1)
        XCTAssertThrowsError(try model().kFactors(lines: [l[0], bad]))
        // Z = 3 has no Krause yield.
        let li = LineIngredients(element: "Li", line: "Ka", energyKeV: 0.05, lineWeight: 1)
        XCTAssertThrowsError(try model().kFactors(lines: [l[0], li]))
    }
}
