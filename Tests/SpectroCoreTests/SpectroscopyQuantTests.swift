import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// WP3 lane K: k-factors, Cliff-Lorimer / zeta / cross-section quantification and
/// absorption. Every expected number below was produced by running eXSpy 7185a4d1
/// + hyperspy 2.4.0 (venv under the research scratchpad; logs in
/// docs/archive/v5/edx-research-2026-10-05/) -- full precision where the upstream
/// test's own tolerance is looser. The Al-Zn window intensities are the values the
/// synthetic image in eXSpy's test_eds_tem.py yields from `get_lines_intensity()`.
final class SpectroscopyQuantTests: XCTestCase {
    // MARK: fixtures

    private static let resources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("mac4DSTEM/Resources/Spectroscopy")

    private static let table: MassAbsorptionTable = {
        try! MassAbsorptionTable(contentsOf: resources.appendingPathComponent("FFastMAC.csv"))
    }()

    // TEMPORARY local line energies (keV, eXSpy xray_lines.json); the supervisor
    // replaces these with lane C's XRayLines lookup.
    private static let lineKeV: [String: Double] = [
        "Al_Ka": 1.4865, "Zn_Ka": 8.6389, "Zn_La": 1.0116, "C_Ka": 0.2774, "Fe_Ka": 6.4039, "Pt_La": 9.4421,
        "Cu_La": 0.9295, "Nb_La": 2.1659, "Mg_Ka": 1.2536, "Si_Ka": 1.7397, "Cu_Ka": 8.0478, "Sn_La": 3.444,
    ]

    private let alZnIntensities = [20144.936982693434, 34268.40763971257]
    private let alZnK = [1.0, 2.0009344042484134]
    private var alZnSetup: AbsorptionSetup {
        AbsorptionSetup(elements: ["Al", "Zn"], lineEnergiesKeV: [Self.lineKeV["Al_Ka"]!, Self.lineKeV["Zn_Ka"]!],
                        geometry: SingleDetectorGeometry(takeOffDegrees: 35), table: Self.table)
    }

    private func rel(_ a: Double, _ b: Double) -> Double { abs(a - b) / abs(b) }
    private func assertRel(_ a: Double, _ b: Double, _ tol: Double = 1e-9, _ msg: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(rel(a, b), tol, "\(msg) got \(a), want \(b)", file: file, line: line)
    }

    // MARK: take-off angle

    func testTakeOffPins() {
        assertRel(TakeOff.angle(tiltAlpha: 30, azimuth: 0, elevation: 10), 40.0)
        assertRel(TakeOff.angle(tiltAlpha: 0, azimuth: 90, elevation: 10, tiltBeta: 30), 40.0)
        assertRel(TakeOff.angle(tiltAlpha: 45, azimuth: 45, elevation: 45, tiltBeta: 45), 73.15788376370121)
        assertRel(TakeOff.angle(tiltAlpha: 10, azimuth: 45, elevation: 22), 28.865971201155283)
        // TM002: azimuth 0, elevation 37 -> 37.0; stage tilt 20 -> 57.0.
        assertRel(TakeOff.angle(tiltAlpha: 0, azimuth: 0, elevation: 37), 37.0)
        assertRel(TakeOff.angle(tiltAlpha: 20, azimuth: 0, elevation: 37), 57.0)
    }

    // MARK: mass absorption

    func testMassAbsorptionPins() throws {
        let t = Self.table
        assertRel(try t.mac(element: "Al", energyKeV: 3.5), 506.0153356472)
        let ta = try [1.0, 3.2, 2.3].map { try t.mac(element: "Ta", energyKeV: $0) }
        assertRel(ta[0], 3343.7083701143229); assertRel(ta[1], 1540.0819991890); assertRel(ta[2], 3011.264941118)
        assertRel(try t.mac(element: "Zn", energyKeV: Self.lineKeV["Zn_La"]!), 1413.291119134)
        assertRel(try t.mac(element: "Zn", energyKeV: Self.lineKeV["Cu_La"]!), 1704.7912903000029)
        assertRel(try t.mac(element: "Zn", energyKeV: Self.lineKeV["Nb_La"]!), 1881.2081950943339)
        assertRel(try t.mac(element: "Al", energyKeV: Self.lineKeV["C_Ka"]!), 26330.38933817723)
        assertRel(try t.mac(element: "Al", energyKeV: Self.lineKeV["Al_Ka"]!), 372.02616732154314)
        // Mixtures.
        assertRel(try t.mixture(elements: ["Al", "Zn"], weights: [50, 50], energyKeV: Self.lineKeV["Al_Ka"]!), 2587.4161643905127)
        assertRel(try t.mixture(elements: ["Cu", "Sn"], weights: [88, 12], energyKeV: 0.5), 8003.05391481, 1e-9)
        assertRel(try t.mixture(elements: ["Cu", "Sn"], weights: [88, 12], energyKeV: Self.lineKeV["Al_Ka"]!), 4213.4235561, 1e-9)
    }

    func testSentinelIsStrippedAndOutsideTableRefuses() throws {
        // Above the last real FFAST point (and the (0,0) row) the answer is a refusal.
        XCTAssertThrowsError(try Self.table.mac(element: "Al", energyKeV: 5000)) {
            XCTAssertEqual($0 as? QuantError, .outsideTable("Al", energyKeV: 5000))
        }
        XCTAssertThrowsError(try Self.table.mac(element: "Al", energyKeV: 1e-6))
        // The last REAL point (432.9451 keV) is served; a kept sentinel row would sit
        // after it in the searched list and break the search.
        assertRel(try Self.table.mac(element: "Al", energyKeV: 432.9451), 0.00016838, 1e-9)
        XCTAssertGreaterThan(try Self.table.mac(element: "Al", energyKeV: 300), 0)
        // Sentinel gone: the last entry is the 432.9451 keV point, not (0, 0), for all 90 elements.
        XCTAssertEqual(Self.table.energyRange(element: "Al")?.upperBound, 432.9451)
        for z in ["Li", "C", "Fe", "Zn", "Pt", "U"] {
            XCTAssertGreaterThan(Self.table.energyRange(element: z)!.lowerBound, 0, z)
            XCTAssertGreaterThan(Self.table.energyRange(element: z)!.upperBound, 100, z)
        }
        XCTAssertThrowsError(try Self.table.mac(element: "Al", energyKeV: 500))
        // The table covers all 90 elements eXSpy has (Z = 3...92 minus none); H and He are absent.
        XCTAssertTrue(Self.table.hasElement("Al")); XCTAssertTrue(Self.table.hasElement("U"))
    }

    // MARK: Cliff-Lorimer

    func testCliffLorimerAlZnAndFePt() throws {
        let w = try CliffLorimer.weightFractions(intensities: alZnIntensities, kFactors: alZnK)
        assertRel(w[0] * 100, 22.70778972092306)
        assertRel(w[1] * 100, 77.29221027907694)
        // Order invariance (eXSpy test_quant_lorimer_ac reversed lists).
        let r = try CliffLorimer.weightFractions(intensities: alZnIntensities.reversed(), kFactors: alZnK.reversed())
        assertRel(r[1], w[0], 1e-12)
        // FePt, k [1.450226, 5.075602]. NOTE the pre-registration pairs 15.409297 at% with
        // the raw windows 3710/15872; eXSpy's own run (fept_quant-2026-10-05.log) gets it
        // from the BACKGROUND-SUBTRACTED windows 2754/15090. Raw windows give 18.9171866.
        func feAt(_ i: [Double]) throws -> (wt: Double, at: Double) {
            let f = try CliffLorimer.weightFractions(intensities: i, kFactors: [1.450226, 5.075602])
            let a = try CompositionConversion.weightToAtomic(f.map { $0 * 100 }, elements: ["Fe", "Pt"])
            return (f[0] * 100, a[0])
        }
        let bg = try feAt([2754, 15090])
        assertRel(bg.at, 15.40929664); assertRel(bg.at, 15.409297, 1e-7); assertRel(bg.wt, 4.95617605)
        assertRel(try feAt([3710, 15872]).at, 18.9171866)
        assertRel(try feAt([2800.0213, 14921.183]).at, 15.77546544)   // model-fit route, 15.775466
    }

    func testCuSnWeightToAtomic() throws {
        let a = try CompositionConversion.weightToAtomic([88, 12], elements: ["Cu", "Sn"])
        assertRel(a[0], 93.19698614474471); assertRel(a[1], 6.803013855255298)
        assertRel(a[0], 93.196986, 1e-8)
        let w = try CompositionConversion.atomicToWeight([93.2, 6.8], elements: ["Cu", "Sn"])
        assertRel(w[0], 88.0050198855369); assertRel(w[1], 11.994980114463088)
    }

    func testCliffLorimerZeroHandlingTable() throws {
        // eXSpy test_quant_zeros: first line above 0.1 are the references; k [1,1,3].
        let cases: [([Double], [Double])] = [
            ([0.5, 0.5, 0.5], [0.2, 0.2, 0.6]),
            ([0.0, 0.5, 0.5], [0.0, 0.25, 0.75]),
            ([0.5, 0.0, 0.5], [0.25, 0.0, 0.75]),
            ([0.5, 0.5, 0.0], [0.5, 0.5, 0.0]),
        ]
        for (i, want) in cases {
            let got = try CliffLorimer.weightFractions(intensities: i, kFactors: [1, 1, 3])
            for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: 1e-15, "\(i)") }
        }
        // Single line: eXSpy says 100 %; here a refusal, with the parity switch for the pin.
        XCTAssertThrowsError(try CliffLorimer.weightFractions(intensities: [0.5, 0, 0], kFactors: [1, 1, 3])) {
            XCTAssertEqual($0 as? QuantError, .needTwoLines(linesAbove: 1))
        }
        let hundred = try CliffLorimer.weightFractions(intensities: [0.5, 0, 0], kFactors: [1, 1, 3], singleLine: .exspyHundredPercent)
        XCTAssertEqual(hundred, [1, 0, 0])
        XCTAssertThrowsError(try CliffLorimer.weightFractions(intensities: [0, 0, 0], kFactors: [1, 1, 3]))
        // A line at the floor (0.1) is NOT above it: eXSpy uses a strict >.
        XCTAssertThrowsError(try CliffLorimer.weightFractions(intensities: [0.5, 0.1, 0], kFactors: [1, 1, 3]))
    }

    func testMassThicknessCL() throws {
        let w = try CliffLorimer.weightFractions(intensities: alZnIntensities, kFactors: alZnK)
        let mt = try CliffLorimer.massThickness(weightPercent: w.map { $0 * 100 }, elements: ["Al", "Zn"], thicknessNm: 100)
        assertRel(mt, 6.1317741e-4, 1e-7)
    }

    // MARK: absorption iteration

    func testCLAbsorptionPinsBothCriteria() throws {
        for crit in [AbsorptionIterationOptions.Criterion.exspySigned, .absolute] {
            let opts = AbsorptionIterationOptions(criterion: crit)
            let t1 = try AbsorptionCorrection.cliffLorimer(intensities: alZnIntensities, kFactors: alZnK, setup: alZnSetup, thicknessNm: 1, options: opts)
            let t300 = try AbsorptionCorrection.cliffLorimer(intensities: alZnIntensities, kFactors: alZnK, setup: alZnSetup, thicknessNm: 300, options: opts)
            // Measured 2026-10-05: on these two-element pins the criteria stop on the same
            // iteration (2 and 4), so both reproduce eXSpy to rounding.
            let tol = 1e-9
            XCTAssertEqual(t1.iterations, 2); XCTAssertEqual(t300.iterations, 4)
            assertRel(t1.composition[0], 22.74301268687288, tol, "\(crit) t=1")
            assertRel(t300.composition[0], 31.81690816938681, tol, "\(crit) t=300")
            assertRel(t300.massThickness, 0.0017181987831837676, tol)
            assertRel(t1.massThickness, 6.130210236702844e-06, tol)
        }
        // t -> 0: no correction (eXSpy: atol 1e-5 against the uncorrected value).
        let t0 = try AbsorptionCorrection.cliffLorimer(intensities: alZnIntensities, kFactors: alZnK, setup: alZnSetup, thicknessNm: 1e-4)
        XCTAssertEqual(t0.composition[0], 22.70778972092306, accuracy: 1e-5)
        // Exactly zero thickness: the x -> 0 limit, finite (eXSpy gives nan).
        let z = try AbsorptionCorrection.cliffLorimer(intensities: alZnIntensities, kFactors: alZnK, setup: alZnSetup, thicknessNm: 0)
        XCTAssertEqual(z.composition[0], 22.70778972092306, accuracy: 1e-9)
    }

    func testConvergenceMeasure() {
        // Changes sum to zero (percent), so with >= 3 elements a signed max can sit below
        // the true largest change: eXSpy would stop here, the default does not.
        let new = [49.2, 25.4, 25.4], old = [50.0, 25.0, 25.0]
        XCTAssertEqual(AbsorptionCorrection.change(new: new, old: old, criterion: .exspySigned), 0.4, accuracy: 1e-12)
        XCTAssertEqual(AbsorptionCorrection.change(new: new, old: old, criterion: .absolute), 0.8, accuracy: 1e-12)
        XCTAssertEqual(AbsorptionIterationOptions().criterion, .absolute)
    }

    func testZetaAndCrossSectionPins() throws {
        let dose = ZetaFactor.dose(liveTime: 2.5, beamCurrentNA: 0.05)
        assertRel(dose, 780188634.3075954)
        let z = try ZetaFactor.quantify(intensities: alZnIntensities, zetaFactors: [20, 50], dose: dose)
        assertRel(z.weightFractions[1] * 100, 80.96228798699575)
        assertRel(z.weightFractions[1] * 100, 80.962287987, 1e-11)
        assertRel(z.massThickness, 0.0027125736374225646)
        let za = try AbsorptionCorrection.zeta(intensities: alZnIntensities, zetaFactors: [20, 50], dose: dose, setup: alZnSetup,
                                               options: .init(criterion: .exspySigned))
        assertRel(za.composition[1], 65.58669966722857)
        assertRel(za.massThickness, 0.003390174665329003)

        let d2 = ZetaFactor.doseCrossSection(liveTime: 2.5, beamCurrentNA: 0.05, probeAreaNm2: 0.25)
        assertRel(d2, 3120754537.2303815)
        let x = try ZetaFactor.crossSection(intensities: alZnIntensities, sectionsBarn: [3, 5], dose: d2)
        assertRel(x.atoms[0], 21517.16488471592); assertRel(x.atoms[1], 21961.616801893826)
        assertRel(x.atomicFractions[0] * 100, 49.48888641776871)
        // zeta <-> cross-section.
        let zf = try ZetaFactor.zetaFromCrossSection([3, 6], elements: ["Pt", "Ni"])
        assertRel(zf[0], 1079.815344601809); assertRel(zf[1], 162.4378061421024)
        let back = try ZetaFactor.crossSectionFromZeta(zf, elements: ["Pt", "Ni"])
        assertRel(back[0], 3, 1e-12); assertRel(back[1], 6, 1e-12)
        // Cross-section with absorption, factors from zeta [20, 50] (eXSpy test_quant_cross_section_ac).
        let sig = try ZetaFactor.crossSectionFromZeta([20, 50], elements: ["Al", "Zn"])
        assertRel(sig[0], 22.401949468879568); assertRel(sig[1], 21.713208842365216)
        let xa = try AbsorptionCorrection.crossSection(intensities: alZnIntensities, sectionsBarn: sig, dose: d2, probeAreaNm2: 0.25,
                                                       setup: alZnSetup, options: .init(criterion: .exspySigned))
        assertRel(xa.composition[1], 44.02533964410216)
        assertRel(xa.composition[0], 55.97466035589784)
    }

    // MARK: four detectors

    private func fourSegments(shadow: [Double] = [0, 0, 0, 0]) -> [DetectorSegment] {
        (0..<4).map { DetectorSegment(label: "S\($0 + 1)", azimuthDegrees: 45 + 90 * Double($0), elevationDegrees: 22,
                                       solidAngleSr: 0.2, holderShadowFraction: shadow[$0]) }
    }

    func testFourIdenticalSegmentsEqualSingleDetector() throws {
        let segs = (0..<4).map { DetectorSegment(label: "S\($0)", azimuthDegrees: 0, elevationDegrees: 35, solidAngleSr: 0.17) }
        let four = try FourDetectorGeometry(segments: segs, tiltAlphaDegrees: 0)
        let setup = AbsorptionSetup(elements: ["Al", "Zn"], lineEnergiesKeV: [1.4865, 8.6389], geometry: four, table: Self.table)
        for crit in [AbsorptionIterationOptions.Criterion.exspySigned] {
            let r = try AbsorptionCorrection.cliffLorimer(intensities: alZnIntensities, kFactors: alZnK, setup: setup, thicknessNm: 300,
                                                          options: .init(criterion: crit))
            let single = try AbsorptionCorrection.cliffLorimer(intensities: alZnIntensities, kFactors: alZnK, setup: alZnSetup, thicknessNm: 300,
                                                               options: .init(criterion: crit))
            assertRel(r.composition[0], single.composition[0], 1e-13, "four identical == single")
            assertRel(r.composition[0], 31.81690816938681, 1e-9)
        }
    }

    func testWeightedMeanIsNotGeometricMeanAndShadowWeights() throws {
        // Stage tilt -16.9 deg: the four segments see very different take-off angles.
        let g = try FourDetectorGeometry(segments: fourSegments(), tiltAlphaDegrees: -16.9)
        let takeOffs = g.segments.map(\.takeOffDegrees)
        XCTAssertGreaterThan((takeOffs.max()! - takeOffs.min()!), 10, "segments must differ: \(takeOffs)")
        let mac = 3000.0 * 0.1 /* m^2/kg */, mt = 0.003
        let am = g.meanTransmission(macM2PerKg: mac, massThickness: mt)
        let gm = g.geometricMeanTransmission(macM2PerKg: mac, massThickness: mt)
        XCTAssertGreaterThan(am - gm, 1e-4, "weighted \(am) vs geometric \(gm)")
        // Hand computation of the weighted mean over the four resolved take-offs.
        var num = 0.0
        for t in takeOffs { let x = mac * mt / abs(sin(t * .pi / 180)); num += (1 - exp(-x)) / x }
        assertRel(am, num / 4, 1e-12)
        // A half-shadowed segment carries half the weight.
        let gs = try FourDetectorGeometry(segments: fourSegments(shadow: [0.5, 0, 0, 0]), tiltAlphaDegrees: -16.9)
        var n2 = 0.0, d2 = 0.0
        for (i, t) in takeOffs.enumerated() {
            let w = i == 0 ? 0.5 : 1.0
            let x = mac * mt / abs(sin(t * .pi / 180)); n2 += w * (1 - exp(-x)) / x; d2 += w
        }
        assertRel(gs.meanTransmission(macM2PerKg: mac, massThickness: mt), n2 / d2, 1e-12)
        XCTAssertGreaterThan(abs(gs.meanTransmission(macM2PerKg: mac, massThickness: mt) - am), 1e-6)
        // Hand-computed weighted geometric mean (the reported comparison).
        var lg = 0.0, dg = 0.0
        for (i, t) in takeOffs.enumerated() {
            let w = i == 0 ? 0.5 : 1.0
            let x = mac * mt / abs(sin(t * .pi / 180)); lg += w * log((1 - exp(-x)) / x); dg += w
        }
        assertRel(gs.geometricMeanTransmission(macM2PerKg: mac, massThickness: mt), exp(lg / dg), 1e-12)
    }

    func testFourDetectorRefusals() {
        var segs = fourSegments()
        XCTAssertThrowsError(try FourDetectorGeometry(segments: segs, tiltAlphaDegrees: nil)) { XCTAssertEqual($0 as? QuantError, .missingTilt) }
        segs[2].elevationDegrees = nil
        XCTAssertThrowsError(try FourDetectorGeometry(segments: segs, tiltAlphaDegrees: 0)) {
            XCTAssertEqual($0 as? QuantError, .missingGeometry(segment: "S3", field: "elevation"))
        }
        segs = fourSegments(); segs[0].solidAngleSr = nil
        XCTAssertThrowsError(try FourDetectorGeometry(segments: segs, tiltAlphaDegrees: 0))
        segs = fourSegments(); segs[1].azimuthDegrees = nil
        XCTAssertThrowsError(try FourDetectorGeometry(segments: segs, tiltAlphaDegrees: 0))
        // Elevation 0 and no tilt: the detector looks along the film.
        let flat = [DetectorSegment(label: "F", azimuthDegrees: 0, elevationDegrees: 0, solidAngleSr: 0.1)]
        XCTAssertThrowsError(try FourDetectorGeometry(segments: flat, tiltAlphaDegrees: 0))
    }

    func testThicknessSigmaByFiniteDifference() throws {
        let g = try FourDetectorGeometry(segments: fourSegments(), tiltAlphaDegrees: -16.9)
        let setup = AbsorptionSetup(elements: ["Al", "Zn"], lineEnergiesKeV: [1.4865, 8.6389], geometry: g, table: Self.table)
        let f: (Double) throws -> Double = {
            try AbsorptionCorrection.cliffLorimer(intensities: self.alZnIntensities, kFactors: self.alZnK, setup: setup, thicknessNm: $0).composition[0]
        }
        let s = try ThicknessPropagation.sigma(at: 80, sigmaNm: 15, f: f)
        // The full-step estimate (c(t+sigma) - c(t-sigma))/2 agrees within 5 % for this smooth curve.
        let full = abs(try f(95) - f(65)) / 2
        XCTAssertGreaterThan(s, 0)
        assertRel(s, full, 0.05)
        XCTAssertEqual(try ThicknessPropagation.sigma(at: 80, sigmaNm: 0, f: f), 0)
    }

    // MARK: k-factors

    func testKFactorSourceAndRatioSigma() throws {
        let k = KFactorSet(kind: .typed, elements: ["Mg", "Si"], values: [1.0, 1.1], source: "test table", date: "2026-10-05")!
        XCTAssertEqual(k.relativeSigma, [0.2, 0.2])
        assertRel(RatioSigma.kTerm(k, numerator: "Mg", denominator: "Si")!, 0.28284271247461906, 1e-12)
        XCTAssertEqual(RatioSigma.kTerm(k, numerator: "Mg", denominator: "Si", sameKSetInBothRatios: true), 0)
        XCTAssertNil(KFactorSet(kind: .typed, elements: ["Mg"], values: [1], source: "  ", date: "2026-10-05"))
        XCTAssertNil(KFactorSet(kind: .typed, elements: ["Mg"], values: [-1], source: "x", date: "2026-10-05"))
    }

    // Toy models, labelled as such: they test the k ALGEBRA, not any published cross-section.
    private struct ToySigma: IonisationCrossSection {
        let sourceName = "TOY (test only)"
        func sigma(element: String, line: String, beamEnergyKeV: Double) -> Double? {
            ["Mg": 3.0, "Si": 2.0, "Cu": 0.7][element]
        }
    }
    private struct ToyOmega: FluorescenceYield {
        let sourceName = "TOY (test only)"
        func omega(element: String, line: String) -> Double? { ["Mg": 0.03, "Si": 0.05, "Cu": 0.4][element] }
    }

    func testComputedKClosedLoop() throws {
        let eff = TabulatedEfficiency(points: [(0.5, 0.2), (2.0, 0.9), (9.0, 0.5)], sourceName: "typed test curve")!
        let ck = ComputedKFactor(cross: ToySigma(), yield: ToyOmega(), efficiency: eff, beamEnergyKeV: 200)
        let lines = [
            LineIngredients(element: "Mg", line: "Ka", energyKeV: 1.2536, lineWeight: 0.9),
            LineIngredients(element: "Si", line: "Ka", energyKeV: 1.7397, lineWeight: 0.9),
            LineIngredients(element: "Cu", line: "Ka", energyKeV: 8.0478, lineWeight: 0.8),
        ]
        let k = try ck.kFactors(lines: lines)
        XCTAssertEqual(k[0], 1)
        // Forward model: a known weight composition -> intensities -> Cliff-Lorimer.
        let truth = [0.2, 0.5, 0.3]
        var intensities: [Double] = []
        for (l, c) in zip(lines, truth) {
            let a = QuantElementData.entry(l.element)!.atomicWeight
            intensities.append(c / a * ToySigma().sigma(element: l.element, line: l.line, beamEnergyKeV: 200)!
                * ToyOmega().omega(element: l.element, line: l.line)! * l.lineWeight * eff.efficiency(energyKeV: l.energyKeV) * 1e4)
        }
        let w = try CliffLorimer.weightFractions(intensities: intensities, kFactors: k)
        for (g, t) in zip(w, truth) { XCTAssertEqual(g, t, accuracy: 1e-12) }
        XCTAssertTrue(ck.sourceDescription.contains("TOY") && ck.sourceDescription.contains("typed test curve"))
        // A missing ingredient is a refusal, never a default.
        let bad = LineIngredients(element: "Zn", line: "Ka", energyKeV: 8.6, lineWeight: 0.9)
        XCTAssertThrowsError(try ck.kFactors(lines: [lines[0], bad]))
        XCTAssertFalse(eff.covers(10)); XCTAssertNil(TabulatedEfficiency(points: [(1, 1)], sourceName: "x"))
    }

    // MARK: EPQ line weights

    func testEPQLineWeights() throws {
        let lw = try EPQLineWeights(contentsOf: Self.resources.appendingPathComponent("LineWeights.csv"))
        XCTAssertEqual(lw.weight(element: "Mg", transition: "K-L3"), 1.0)
        XCTAssertEqual(lw.weight(element: "Mg", transition: "K-L2"), 0.507)
        XCTAssertEqual(lw.weight(element: "Al", transition: "K-M3"), 0.0316)
        // Al Ka share of the K shell: (1 + 0.505) / (1 + 0.505 + 0.0316 + 0.0158).
        assertRel(lw.fraction(element: "Al", shell: "K", transitions: ["K-L3", "K-L2"])!, 1.505 / 1.5524, 1e-9)
    }
}
