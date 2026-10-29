import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// eXSpy quantification pins (tools/edx-exspy-pins/quant_pins.py).
/// Every expected number in `Fixtures/eds-quant-pins-exspy-7185a4d1.json` is what eXSpy 7185a4d1 + hyperspy 2.4.0 returned
/// from `EDSTEMSpectrum.quantification` (generator `tools/edx-pins/quant_pins.py`): Cliff-Lorimer and zeta, with and without the
/// absorption correction, on eXSpy's FePt example and on synthetic 2-, 3- and 4-element and near-zero intensity sets. This file
/// feeds the same intensities and factors to `CliffLorimer`, `ZetaFactor` and `AbsorptionCorrection`.
///
/// Tolerances (stated before the run, derived here):
///  * no absorption: closed-form arithmetic on identical inputs, 1e-9 relative (exact zeros must be exact zeros);
///  * absorption, `.exspySigned`: our loop is eXSpy's loop step for step on the same FFAST table (equal value for value),
///    so it must stop on the SAME iteration -- asserted -- and match to 1e-9 relative;
///  * absorption, `.absolute` (the app's default): it stops no earlier than eXSpy's signed maximum does, so it ends at a later
///    iterate of the same contraction. Both iterates sit within eXSpy's own stopping error of the fixed point, so the
///    comparison is 1.0 percentage point absolute per element (twice the 0.5 convergence criterion), and the result must lie
///    no farther from eXSpy's converged fixed point (stored in the fixture) than eXSpy's own stopped result does.
struct EDSQuantPinsTests {

    // MARK: fixture

    struct Run: Decodable {
        let method: String
        let factors: [Double]
        let absorption: Bool
        let label: String?
        let thicknessNm: Double?
        let beamCurrentNA: Double?
        let liveTimeS: Double?
        let dose: Double?
        let weightPercent: [Double]?
        let atomicPercent: [Double]?
        let massThickness: Double?
        let iterations: Int?
        let fixedPointWeightPercent: [Double]?
        let fixedPointMassThickness: Double?
        let exspyError: String?
    }
    struct Case: Decodable {
        let name: String
        let source: String
        let lines: [String]
        let elements: [String]
        let lineEnergiesKeV: [Double]
        let intensities: [Double]
        let takeOffDegrees: Double
        let runs: [Run]
    }
    struct Pins: Decodable { let minIntensity: Double; let cases: [Case] }

    private static let fixturesDir = FixtureDirs.tests.appendingPathComponent("SpectroCoreTests")
    private static let pins: Pins = {
        let data = try! Data(contentsOf: fixturesDir.appendingPathComponent("Fixtures/eds-quant-pins-exspy-7185a4d1.json"))
        return try! JSONDecoder().decode(Pins.self, from: data)
    }()
    private static let table: MassAbsorptionTable = {
        let url = fixturesDir.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/SpectroEDX/Resources/Spectroscopy/FFastMAC.csv")
        return try! MassAbsorptionTable(contentsOf: url)
    }()

    // MARK: helpers

    /// Relative difference; an exact zero in the pin must come back as an exact zero.
    private func close(_ a: Double, _ b: Double, _ tol: Double) -> Bool {
        if b == 0 { return a == 0 }
        return abs(a - b) <= tol * abs(b)
    }
    private func assertVector(_ a: [Double], _ b: [Double], _ tol: Double, _ msg: String,
                              fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) {
        let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
        #expect(a.count == b.count, "\(msg)", sourceLocation: sourceLocation)
        for (i, (x, y)) in zip(a, b).enumerated() {
            #expect(close(x, y, tol), "\(msg)[\(i)] got \(x) want \(y) (rel \(abs(x - y) / abs(y)))", sourceLocation: sourceLocation)
        }
    }
    private func setup(_ c: Case) -> AbsorptionSetup {
        AbsorptionSetup(elements: c.elements, lineEnergiesKeV: c.lineEnergiesKeV,
                        geometry: SingleDetectorGeometry(takeOffDegrees: c.takeOffDegrees), table: Self.table)
    }
    private func atomic(_ weightPercent: [Double], _ c: Case) throws -> [Double] {
        try CompositionConversion.weightToAtomic(weightPercent, elements: c.elements)
    }
    private func runs(_ method: String, absorption: Bool) -> [(Case, Run)] {
        Self.pins.cases.flatMap { c in c.runs.filter { $0.method == method && $0.absorption == absorption }.map { (c, $0) } }
    }
    private func tag(_ c: Case, _ r: Run) -> String { "\(c.name) \(r.method)\(r.absorption ? "+abs" : "") \(r.label ?? "")" }
    private func aboveFloor(_ c: Case) -> Int { c.intensities.filter { $0 > Self.pins.minIntensity }.count }
    private func cl(_ c: Case, _ r: Run, k: [Double]? = nil) throws -> [Double] {
        try CliffLorimer.weightFractions(intensities: c.intensities, kFactors: k ?? r.factors, singleLine: .exspyHundredPercent).map { $0 * 100 }
    }

    // MARK: fixture shape

    @Test func testFixtureCoversThePreRegisteredCases() {
        let names = Self.pins.cases.map(\.name)
        #expect(names.contains("fept_bw5_2"))
        let lineCounts: Set<Int> = Set(Self.pins.cases.map { (c: Case) -> Int in c.lines.count })
        let wanted: Set<Int> = [2, 3, 4]
        #expect(lineCounts.intersection(wanted) == wanted, "2-, 3- and 4-element sets")
        #expect(Self.pins.cases.contains { $0.intensities.contains { $0 > 0 && $0 < 1 } }, "a near-zero intensity")
        #expect(Self.pins.minIntensity == CliffLorimer.minIntensity)
        for c in Self.pins.cases { for r in c.runs { #expect(r.exspyError == nil, "\(c.name): eXSpy itself failed on a pinned case") } }
        // The FePt documentation numbers (eds.rst:712-713, 723-725): 15.41 / 84.59 at%, 4.96 / 95.04 wt%.
        let fept = Self.pins.cases.first { $0.name == "fept_bw5_2" }!
        let r = fept.runs.first { $0.method == "CL" && !$0.absorption }!
        #expect(isEqual(r.atomicPercent![0], 15.41, accuracy: 5e-3))
        #expect(isEqual(r.weightPercent![0], 4.96, accuracy: 5e-3))
    }

    // MARK: Cliff-Lorimer

    @Test func testCliffLorimerWithoutAbsorption() throws {
        let rs = runs("CL", absorption: false)
        #expect(rs.count >= 10)
        for (c, r) in rs {
            let w = try cl(c, r)
            assertVector(w, r.weightPercent!, 1e-9, tag(c, r) + " wt%")
            assertVector(try atomic(w, c), r.atomicPercent!, 1e-9, tag(c, r) + " at%")
            // DEVIATION check: where eXSpy answers "100 % of the one line" our default refuses.
            if aboveFloor(c) < 2 {
                if let error = #expect(throws: (any Error).self, "\(tag(c, r))", performing: { try CliffLorimer.weightFractions(intensities: c.intensities, kFactors: r.factors) }) {
                    #expect((error as? QuantError) == .needTwoLines(linesAbove: self.aboveFloor(c)))
                }
            }
        }
    }

    @Test func testCliffLorimerAbsorptionMatchesEXSpyIterationForIteration() throws {
        let rs = runs("CL", absorption: true)
        #expect(rs.count >= 10)
        for (c, r) in rs {
            let res = try AbsorptionCorrection.cliffLorimer(intensities: c.intensities, kFactors: r.factors, setup: setup(c),
                                                            thicknessNm: r.thicknessNm!, options: .init(criterion: .exspySigned))
            #expect(res.iterations == r.iterations, "\(tag(c, r) + " iterations")")
            assertVector(res.composition, r.weightPercent!, 1e-9, tag(c, r) + " wt%")
            assertVector(try atomic(res.composition, c), r.atomicPercent!, 1e-9, tag(c, r) + " at%")
            #expect(close(res.massThickness, r.massThickness!, 1e-9), "\(tag(c, r) + " mass thickness \(res.massThickness) vs \(r.massThickness!)")")
        }
    }

    // MARK: zeta

    @Test func testZetaWithoutAbsorption() throws {
        let rs = runs("zeta", absorption: false)
        #expect(rs.count >= 10)
        for (c, r) in rs {
            let dose = ZetaFactor.dose(liveTime: r.liveTimeS!, beamCurrentNA: r.beamCurrentNA!)
            #expect(close(dose, r.dose!, 1e-12), "\(tag(c, r) + " dose \(dose) vs \(r.dose!)")")
            let q = try ZetaFactor.quantify(intensities: c.intensities, zetaFactors: r.factors, dose: dose)
            let w = q.weightFractions.map { $0 * 100 }
            assertVector(w, r.weightPercent!, 1e-9, tag(c, r) + " wt%")
            assertVector(try atomic(w, c), r.atomicPercent!, 1e-9, tag(c, r) + " at%")
            #expect(close(q.massThickness, r.massThickness!, 1e-9), "\(tag(c, r) + " mass thickness \(q.massThickness) vs \(r.massThickness!)")")
        }
    }

    @Test func testZetaAbsorptionMatchesEXSpyIterationForIteration() throws {
        let rs = runs("zeta", absorption: true)
        #expect(rs.count >= 8)
        for (c, r) in rs {
            let dose = ZetaFactor.dose(liveTime: r.liveTimeS!, beamCurrentNA: r.beamCurrentNA!)
            let res = try AbsorptionCorrection.zeta(intensities: c.intensities, zetaFactors: r.factors, dose: dose, setup: setup(c),
                                                    options: .init(criterion: .exspySigned))
            #expect(res.iterations == r.iterations, "\(tag(c, r) + " iterations")")
            assertVector(res.composition, r.weightPercent!, 1e-9, tag(c, r) + " wt%")
            assertVector(try atomic(res.composition, c), r.atomicPercent!, 1e-9, tag(c, r) + " at%")
            #expect(close(res.massThickness, r.massThickness!, 1e-9), "\(tag(c, r) + " mass thickness \(res.massThickness) vs \(r.massThickness!)")")
        }
    }

    // MARK: the app's default stopping rule

    @Test func testAbsoluteCriterionStaysWithinEXSpysStoppingError() throws {
        var compared = 0
        for (c, r) in runs("CL", absorption: true) + runs("zeta", absorption: true) {
            let opts = AbsorptionIterationOptions(criterion: .absolute)
            let res: AbsorptionResult
            if r.method == "CL" {
                res = try AbsorptionCorrection.cliffLorimer(intensities: c.intensities, kFactors: r.factors, setup: setup(c),
                                                            thicknessNm: r.thicknessNm!, options: opts)
            } else {
                let dose = ZetaFactor.dose(liveTime: r.liveTimeS!, beamCurrentNA: r.beamCurrentNA!)
                res = try AbsorptionCorrection.zeta(intensities: c.intensities, zetaFactors: r.factors, dose: dose, setup: setup(c), options: opts)
            }
            #expect(res.iterations >= r.iterations!, "\(tag(c, r) + ": absolute stops no earlier than the signed maximum")")
            for i in res.composition.indices {
                let ours = res.composition[i], theirs = r.weightPercent![i], fixed = r.fixedPointWeightPercent![i]
                #expect(abs(ours - theirs) <= 1.0, "\(tag(c, r)) [\(i)] \(ours) vs eXSpy \(theirs)")
                #expect(abs(ours - fixed) <= (abs(theirs - fixed) + 1e-9), "\(tag(c, r)) [\(i)] no farther from the fixed point \(fixed)")
            }
            compared += 1
        }
        #expect(compared >= 20)
    }

    /// Where eXSpy's signed maximum stops early (the criterion_split cases: 3 and 4 elements), the default `.absolute` rule runs on
    /// and ends nearer the fixed point; the difference is bounded by the stopping error. Without these two cases the comparison above
    /// would hold trivially (every two-element set, and every other set here, stops on the same iteration under both rules).
    @Test func testAbsoluteCriterionRunsOnWhereEXSpyStopsEarly() throws {
        var split = 0
        for (c, r) in runs("CL", absorption: true) where c.name.hasPrefix("criterion_split") {
            let signed = try AbsorptionCorrection.cliffLorimer(intensities: c.intensities, kFactors: r.factors, setup: setup(c),
                                                               thicknessNm: r.thicknessNm!, options: .init(criterion: .exspySigned))
            let absolute = try AbsorptionCorrection.cliffLorimer(intensities: c.intensities, kFactors: r.factors, setup: setup(c),
                                                                 thicknessNm: r.thicknessNm!, options: .init(criterion: .absolute))
            #expect(signed.iterations == r.iterations, "\(tag(c, r))")
            #expect(absolute.iterations > signed.iterations, "\(tag(c, r) + ": absolute must run on")")
            let gap = zip(absolute.composition, signed.composition).map { abs($0 - $1) }.max()!
            #expect(gap > (1e-3), "\(tag(c, r) + ": the extra iteration moves the composition")")
            #expect(gap <= 1.0, "\(tag(c, r))")
            split += 1
        }
        #expect(split == 2)
    }

    // MARK: the pins can tell the inputs apart (so a swapped k order or a dropped dose cannot pass)

    @Test func testPinsDistinguishKOrderAndDose() throws {
        var checked = 0
        for (c, r) in runs("CL", absorption: false) where aboveFloor(c) >= 2 && Set(r.factors).count == r.factors.count {
            let swapped = try cl(c, r, k: Array(r.factors.reversed()))
            let diff = zip(swapped, r.weightPercent!).map { abs($0 - $1) }.max()!
            #expect(diff > (1e-3), "\(tag(c, r) + ": reversed k-factors must move the composition")")
            checked += 1
        }
        #expect(checked >= 6)
        // ζ: the dose does not change the composition but sets the mass thickness; with absorption it changes the composition too.
        for (c, r) in runs("zeta", absorption: false) {
            let q = try ZetaFactor.quantify(intensities: c.intensities, zetaFactors: r.factors, dose: 1)
            #expect(!close(q.massThickness, r.massThickness!, 1e-3), "\(tag(c, r) + ": dose = 1 must not reproduce the pinned mass thickness")")
        }
        let (c, r) = runs("zeta", absorption: true).first { $0.0.name == "fept_bw5_2" && $0.1.label == "test dose 0.05 nA 2.5 s" }!
        let wrong = try AbsorptionCorrection.zeta(intensities: c.intensities, zetaFactors: r.factors, dose: ZetaFactor.dose(liveTime: 1.5, beamCurrentNA: 0.5),
                                                  setup: setup(c), options: .init(criterion: .exspySigned))
        #expect(abs(wrong.composition[0] - r.weightPercent![0]) > 0.1, "the other dose must give another absorbed composition")
    }
}
