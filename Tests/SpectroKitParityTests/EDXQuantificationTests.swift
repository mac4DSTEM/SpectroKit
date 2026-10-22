import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// The public per-pixel EDX quantification against eXSpy 0.3.2 / HyperSpy 2.4.0 (`tools/edx-quant-maps/pins.py`, fixture
/// `Fixtures/edx-quant-maps-exspy.json`): `EDSTEMSpectrum.quantification` on a 3 x 4 intensity image per method.
///
/// Tolerances are exSpy's own (`exspy/tests/signals/test_eds_tem.py`): `assert_allclose(..., atol=1e-3)` on percent, with and
/// without the absorption correction (exSpy's absorption tests use 1e-3 too; this port's per-pixel iteration agrees with the
/// image-wide one to better than 1e-9 on these cases). Mass thickness and atoms: `assert_allclose` default rtol 1e-7; with the
/// absorption correction 1e-5, because exSpy's cross-section atoms come from the iteration before its last composition update
/// (4e-6 apart on pixel 0 of the cross-section runs) and states no tolerance of its own for them. exSpy
/// returns no mass thickness for `cross_section`; the pin is its own `get_abs_corr_cross_section` total-mass formula on its atoms.
struct EDXQuantificationTests {
    struct Run: Decodable {
        let method: String; let units: String; let absorption: Bool
        let factors: [Double]; let thicknessNm: Double?
        let mask: [[Int]]?
        let tight: Bool
        let massThickness: [[Double]]?
        let atoms: [[[Double]]]?
        let composition: [[[Double]]]?
        let exspyError: String?
    }
    struct Case: Decodable {
        let name: String; let elements: [String]; let lines: [String]
        let intensities: [[[Double]]]
        let rows: Int; let cols: Int
        let takeOffDegrees: Double; let beamCurrentNA: Double; let liveTimeSeconds: Double; let probeAreaNm2: Double
        let runs: [Run]
    }
    struct Pins: Decodable { let cases: [Case] }

    private static let pins: Pins = {
        let url = EDXFixtures.url("edx-quant-maps-exspy.json")
        return try! JSONDecoder().decode(Pins.self, from: Data(contentsOf: url))
    }()

    static func setup(_ c: Case, _ r: Run, singleLine: SingleLineRule = .exspyHundredPercent) -> EDXQuantificationSetup {
        let method: EDXQuantificationMethod
        switch r.method {
        case "CL": method = .cliffLorimer(kFactors: r.factors, thicknessNm: r.thicknessNm)
        case "zeta": method = .zeta(zetaFactors: r.factors)
        default: method = .crossSection(sectionsBarn: r.factors, probeAreaNm2: c.probeAreaNm2)
        }
        let abs = r.absorption ? EDXAbsorptionSetting(takeOffDegrees: c.takeOffDegrees,
                                                      lineEnergiesKeV: c.lines.map { XRayLines.line($0)!.energy },
                                                      convergencePercent: r.tight ? 1e-8 : 0.5, maxIterations: r.tight ? 200 : 30) : nil
        return EDXQuantificationSetup(elements: c.elements, method: method, absorption: abs,
                                      beamCurrentNA: c.beamCurrentNA, liveTimeSeconds: c.liveTimeSeconds, singleLine: singleLine)
    }

    static func flat(_ m: [[Double]]) -> [Double] { m.flatMap { $0 } }

    @Test func everyRunMatchesExspy() throws {
        var checked = 0
        for c in Self.pins.cases {
            let maps = c.intensities.map(Self.flat)
            for r in c.runs {
                #expect(r.exspyError == nil, "\(c.name) \(r.method): exSpy refused: \(r.exspyError ?? "")")
                guard let expected = r.composition else { continue }
                let mask = r.mask.map { Self.flat($0.map { $0.map(Double.init) }).map { $0 != 0 } }
                let q = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols,
                                                           setup: Self.setup(c, r), navigationMask: mask)
                let got = r.units == "weight" ? q.weightPercent : q.atomicPercent
                let tol = r.tight ? 1e-5 : 1e-3   // tight: both converge to the fixed point, so the physics is compared
                for e in 0..<c.elements.count {
                    let want = Self.flat(expected[e])
                    for p in 0..<want.count {
                        #expect(isEqual(got[e][p], want[p], accuracy: tol), "\(c.name) \(r.method) \(r.units) abs=\(r.absorption) el \(e) px \(p): \(got[e][p]) vs \(want[p])")
                    }
                }
                if let mt = r.massThickness {   // CL with absorption, zeta; cross section: exSpy's own total_mass formula on its atoms
                    let want = Self.flat(mt)
                    for p in 0..<want.count {
                        let rel = r.tight || r.absorption ? 1e-5 : 1e-7
                        #expect(isEqual(q.massThickness![p], want[p], accuracy: rel * abs(want[p])), "\(c.name) \(r.method) \(r.units) abs=\(r.absorption) mass thickness px \(p): \(q.massThickness![p]) vs \(want[p])")
                    }
                }
                if r.method == "cross_section", let at = r.atoms {
                    for e in 0..<c.elements.count {
                        let want = Self.flat(at[e])
                        for p in 0..<want.count {
                            let rel = r.tight || r.absorption ? 1e-5 : 1e-7
                            #expect(isEqual(q.atoms![e][p], want[p], accuracy: rel * abs(want[p])), "atoms el \(e) px \(p)")
                        }
                    }
                }
                #expect(q.validation == "none")
                checked += 1
            }
        }
        #expect(checked == 36)
    }

    @Test func aSinglePixelEqualsTheMapAndSinglelineIsRefusedByDefault() throws {
        let c = Self.pins.cases[0]
        let r = c.runs.first { $0.method == "CL" && !$0.absorption && $0.units == "weight" }!
        let maps = c.intensities.map(Self.flat)
        let q = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols,
                                                   setup: Self.setup(c, r, singleLine: .refuse))
        // Pixel 0 has one line above the floor: a refusal, NaN with a reason, not a 100 %.
        #expect(q.weightPercent[0][0].isNaN && q.failures[0] != nil)
        #expect(q.failures[1] == nil)
        let one = try EDXQuantification.quantify(intensities: maps.map { $0[5] }, setup: Self.setup(c, r, singleLine: .refuse))
        #expect(one.weightPercent[0] == q.weightPercent[0][5] && one.atomicPercent[1] == q.atomicPercent[1][5])
        #expect(abs(one.weightPercent.reduce(0, +) - 100) < 1e-9)
        #expect(one.validation == "none" && q.validation == "none")   // the badge is carried by both entry points
    }

    @Test func liveTimeNormalisedDoseScalesMassThicknessAndNotTheComposition() throws {
        let c = Self.pins.cases[0]
        let r = c.runs.first { $0.method == "zeta" && !$0.absorption }!
        let maps = c.intensities.map(Self.flat)
        let n = c.rows * c.cols
        let live = (0..<n).map { 1.0 + Double($0) * 0.25 }
        let setup = Self.setup(c, r)
        let a = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: setup)
        let b = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: setup, liveTimesSeconds: live)
        for p in 0..<n {
            #expect(isEqual(b.weightPercent[0][p], a.weightPercent[0][p], accuracy: 1e-12))
            // dose = t * I / e, so the zeta sum over dose: mass thickness times (2.5 / t_pixel).
            #expect(isEqual(b.massThickness![p], a.massThickness![p] * c.liveTimeSeconds / live[p], accuracy: 1e-12 * abs(a.massThickness![p]) * 10))
        }
        // No dose, no number.
        var noDose = setup; noDose.liveTimeSeconds = nil
        let z = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: noDose)
        #expect(z.failures.allSatisfy { $0 != nil } && z.weightPercent[0][0].isNaN)
    }

    /// A take-off angle per pixel (0.8.3): equal angles reproduce the single-angle run; a different angle at a pixel gives that pixel the result
    /// of a run at that angle; a missing absorption setting, a wrong count and a grazing angle are refused or fail the one pixel.
    @Test func aTakeOffAnglePerPixelEqualsASingleAngleRunAtThatAngle() throws {
        let c = Self.pins.cases[1]
        let r = c.runs.first { $0.method == "zeta" && $0.absorption && $0.units == "weight" }!
        let maps = c.intensities.map(Self.flat)
        let n = c.rows * c.cols
        let setup = Self.setup(c, r)
        let base = try #require(setup.absorption).takeOffDegrees
        let reference = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: setup)
        let same = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: setup, takeOffDegreesPerPixel: [Double](repeating: base, count: n))
        #expect(same.weightPercent == reference.weightPercent)
        var angles = [Double](repeating: base, count: n)
        angles[1] = 20
        angles[2] = 0
        let mixed = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: setup, takeOffDegreesPerPixel: angles)
        var atTwenty = setup
        atTwenty.absorption!.takeOffDegrees = 20
        let twenty = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: atTwenty)
        #expect(mixed.weightPercent[0][1] == twenty.weightPercent[0][1] && mixed.weightPercent[0][1] != reference.weightPercent[0][1])
        #expect(mixed.failures[2] != nil && mixed.weightPercent[0][2].isNaN)
        #expect(mixed.weightPercent[0][3] == reference.weightPercent[0][3])
        #expect(throws: (any Error).self) { try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: setup, takeOffDegreesPerPixel: [30]) }
        var plain = setup; plain.absorption = nil
        #expect(throws: (any Error).self) { try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: c.rows, columns: c.cols, setup: plain, takeOffDegreesPerPixel: angles) }
    }

    @Test func aLargeImageEqualsPixelByPixelAcrossTheChunks() throws {
        let c = Self.pins.cases[1]
        let r = c.runs.first { $0.method == "zeta" && $0.absorption && $0.units == "weight" }!
        let rows = 61, cols = 83          // 5063 pixels: three parallel chunks
        let n = rows * cols
        let maps: [[Double]] = (0..<3).map { e in
            (0..<n).map { p in let x = Double(p) * 0.6180339887498949 + Double(e) * 0.31; return [300.0, 500, 700][e] * (0.4 + 1.2 * (x - x.rounded(.down))) }
        }
        let mask = (0..<n).map { $0 % 97 == 0 }
        let setup = Self.setup(c, r)
        let q = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: rows, columns: cols, setup: setup, navigationMask: mask)
        for p in stride(from: 0, to: n, by: 61) {
            if mask[p] { #expect(q.weightPercent[0][p] == 0 && q.massThickness![p] == 0); continue }
            let one = try EDXQuantification.quantify(intensities: maps.map { $0[p] }, setup: setup)
            #expect(one.weightPercent == (0..<3).map { q.weightPercent[$0][p] } && one.massThickness == q.massThickness![p] && one.iterations == q.iterations[p])
        }
    }

    @Test func clMassThicknessEqualsExspyCLGetMassThickness() throws {
        // exspy test_CL_get_mass_thickness (test_eds_tem.py:532-545): assert_allclose default rtol 1e-7; value from exSpy's own run
        // (tools/edx-quant-maps/pins.py case AlZn, CL, weight, absorption: mass thickness map at 80 nm) is in the fixture; here the
        // same composition without the correction must give the same formula: sum(wt% x t x rho x 1e-8).
        let s = EDXQuantificationSetup(elements: ["Al", "Zn"], method: .cliffLorimer(kFactors: [1, 1.9], thicknessNm: 80))
        let q = try EDXQuantification.quantify(intensities: [300, 500], setup: s)
        let rho = [2.7, 7.14]   // g/cm^3, QuantElementData
        let want = zip(q.weightPercent, rho).map { $0 * 80 * $1 * 1e-8 }.reduce(0, +)
        #expect(isEqual(q.massThickness!, want, accuracy: 1e-7 * want))
    }

    @Test func invalidInputsAreRefusedAndBadPixelsFail() throws {
        let el = ["Al", "Zn"]
        func cl(_ k: [Double]) -> EDXQuantificationSetup { .init(elements: el, method: .cliffLorimer(kFactors: k, thicknessNm: nil)) }
        #expect(throws: QuantError.self) { try EDXQuantification.quantify(intensities: [10, 20], setup: cl([0, 1])) }
        #expect(throws: QuantError.self) { try EDXQuantification.quantify(intensities: [10, -20], setup: cl([1, 1])) }
        #expect(throws: QuantError.self) { try EDXQuantification.quantify(intensities: [10, .nan], setup: cl([1, 1])) }
        let bad = EDXQuantificationSetup(elements: el, method: .cliffLorimer(kFactors: [1, 1], thicknessNm: 50),
                                         absorption: EDXAbsorptionSetting(takeOffDegrees: 35, lineEnergiesKeV: [1.5, 8.6], convergencePercent: 0))
        #expect(throws: QuantError.self) { try EDXQuantification.quantify(intensities: [10, 20], setup: bad) }
        // Cross section on a zero pixel fails with a reason instead of returning NaN as a number.
        let cs = EDXQuantificationSetup(elements: el, method: .crossSection(sectionsBarn: [3, 5], probeAreaNm2: 0.25), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)
        let q = try EDXQuantification.quantifyMaps(intensityMaps: [[0, 100], [0, 200]], rows: 1, columns: 2, setup: cs)
        #expect(q.failures[0] != nil && q.failures[1] == nil)
        // Mask applies to every method; wrong lengths throw.
        let z = EDXQuantificationSetup(elements: el, method: .zeta(zetaFactors: [20, 50]), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)
        let m = try EDXQuantification.quantifyMaps(intensityMaps: [[100, 100], [200, 200]], rows: 1, columns: 2, setup: z, navigationMask: [true, false])
        #expect(m.weightPercent[0][0] == 0 && m.weightPercent[0][1] > 0)
        #expect(throws: QuantError.self) { try EDXQuantification.quantifyMaps(intensityMaps: [[1, 1], [2, 2]], rows: 1, columns: 2, setup: z, navigationMask: [true]) }
        #expect(throws: QuantError.self) { try EDXQuantification.quantifyMaps(intensityMaps: [[1, 1], [2, 2]], rows: 1, columns: 2, setup: z, liveTimesSeconds: [1]) }
        // Per-pixel live time on cross section: atoms scale with 1/dose, fractions do not.
        let two = try EDXQuantification.quantifyMaps(intensityMaps: [[100, 100], [200, 200]], rows: 1, columns: 2, setup: cs, liveTimesSeconds: [2.5, 5])
        #expect(isEqual(two.atomicPercent[0][0], two.atomicPercent[0][1], accuracy: 1e-12))
        #expect(isEqual(two.atoms![0][0], 2 * two.atoms![0][1], accuracy: 1e-9 * two.atoms![0][0]))
    }

    @Test func conversionsAndRefusals() throws {
        // exSpy test_material / test_eds_tem: 22.70779 at% sanity is covered by the maps; here the round trips and the guards.
        let w = [60.0, 40.0]
        let a = try EDXQuantification.weightToAtomic(w, elements: ["Al", "Zn"])
        let w2 = try EDXQuantification.atomicToWeight(a, elements: ["Al", "Zn"])
        #expect(isEqual(w2[0], 60, accuracy: 1e-9) && isEqual(a.reduce(0, +), 100, accuracy: 1e-9))
        let z = try EDXQuantification.zetaFactors(fromCrossSectionsBarn: [3, 6], elements: ["Al", "Zn"])
        let back = try EDXQuantification.crossSectionsBarn(fromZetaFactors: z, elements: ["Al", "Zn"])
        #expect(isEqual(back[0], 3, accuracy: 1e-9) && isEqual(back[1], 6, accuracy: 1e-9))
        #expect(isEqual(EDXQuantification.takeOffAngle(tiltAlpha: 30, azimuth: 0, elevation: 10), 40, accuracy: 1e-9))   // exspy test_takeoff_angle
        let s = EDXQuantificationSetup(elements: ["Al", "Zn"], method: .cliffLorimer(kFactors: [1, 2], thicknessNm: nil),
                                       absorption: EDXAbsorptionSetting(takeOffDegrees: 35, lineEnergiesKeV: [1.4865, 8.6389]))
        #expect(throws: QuantError.self) { try EDXQuantification.quantify(intensities: [10, 20], setup: s) }   // absorption needs a thickness
        #expect(throws: QuantError.self) { try EDXQuantification.quantify(intensities: [10], setup: s) }
        let ev = LineConflict(id: "x", kind: .sumPeak, element: "Mg", line: nil, energiesKeV: [1.25], requires: ["Al"], question: "?", remedy: "")
        #expect(ev.element == "Mg")
    }
}
