import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// v5.0 lane A4: the absorption correction against the simulator's TRUTH geometry (open item "The absorption test checks
/// plumbing only"). Pool: 1e4 identical recipe-A matrix pixels of `tools/demo-edx/forward.py` (Al 98.8 / Mg 0.6 / Si 0.6 at%,
/// 80 nm, 2.70 g/cm3, the simulator's four segments with unequal solid angles 0.4/0.2/0.1/0.3, alpha -16.87, elevation 22,
/// depth weight beta 0.2, oxide O in the medium); `tools/edx-pins/absorption_truth_sim.py` wrote the fixture.
///
/// k: the simulator's "true k" (Gp x sensitivity x eps, absorption-free) is NOT the app's Bote-Salvat k (sensitivities
/// Al 1.0 / Mg 0.55 / Si 1.2 are arbitrary), so the SIMULATOR's k is typed, converted to the Cliff-Lorimer weight convention
/// C_i ~ k_i I_i: k_i = M_i / kc_i, relative to Al. With the absorption-free areas it returns 98.8 / 0.6 / 0.6 exactly.
///
/// Physics, stated before any run. Al K edge 1.5596 keV. Al K-alpha 1.4865 and Mg K-alpha 1.2536 lie BELOW it (mu/rho in Al
/// ~407 and ~614 cm2/g), Si K-alpha 1.7397 lies ABOVE it (~3250, x8 Al). So 1/T is largest for Si (about +17 %), then Mg
/// (+3 %), then Al (+2 %). Uncorrected, Si is read LOW (~-13 %), Mg ~-1 %, Al a hair high. With Al the reference the
/// correction therefore RAISES Si and Mg and lowers Al.
///
/// Where the app and the simulator legitimately differ (this is what the tolerance is derived from, not tuned):
///  * T: the app uses the closed form (1 - e^-x)/x (g = 1), the simulator g(s) = 1 + 0.2 (s - 1/2). To first order
///    T = 1 - x (1/2 + beta/12) against 1 - x/2, so the correction is short by beta/6 = 3.3 % of itself.
///  * Medium: the simulator's includes the oxide O (1.17 wt %, in no quantified element), the app's is Al/Mg/Si only; so mu/rho
///    differs: O absorbs about 7x Al per gram below the Al K edge, so 1.17 wt % O raises mu/rho by +3.3 % (Al K-alpha), +3.5 % (Mg K-alpha)
///    and lowers it by 0.8 % (Si K-alpha) (recomputed in review from FFAST). Mass thickness: the app's rho is the weight mean of the
///    element densities (2.693) against the typed 2.70: 0.3 %. Together at most 4 % of the correction.
///  So the error of an element's share is at most at%_X x (beta/6 + 0.04) x (c_X + c_Al), c = 1/T - 1 the app's own factor
///  (the reference's error enters the ratio too).
/// Level 2 adds counting statistics (the result's own counting term, 3 sigma) and the documented weak-line bias next to Al
/// K-alpha (`ContinuumForm.weakLineBiasNote`: -295 +- 31 at 900, -310 +- 23 at 882, -402 +- 33 at 3000 Mg counts, so
/// 402 + 3 x 33 = 501 counts as an envelope; it is MEASURED for Mg only and ASSUMED to bound Si here).
final class SpectroscopyAbsorptionTruthTests: XCTestCase {

    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("mac4DSTEM/Resources/Spectroscopy")
    static let tables = try! QuantificationTables(directory: resources)

    private struct Pool: Decodable {
        let npix: Int, offset: Double, scale: Double, size: Int
        let thicknessNm: Double
        let truthAtPct: [String: Double]
        let areasWithAbsorption: [String: Double], areasAbsorptionFree: [String: Double], tEff: [String: Double]
        let trueK: [String: Double]
        let expected: [Double]
        enum CodingKeys: String, CodingKey {
            case npix, offset, scale, size, expected
            case thicknessNm = "thickness_nm", truthAtPct = "truth_at_pct", areasWithAbsorption = "areas_with_absorption"
            case areasAbsorptionFree = "areas_absorption_free", tEff = "t_eff", trueK = "true_k_counts_per_atom_nm2"
        }
        var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    }
    private static let pool: Pool = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/eds-absorption-truth.json")
        return try! JSONDecoder().decode(Pool.self, from: Data(contentsOf: url))
    }()

    private static let elements = ["Al", "Mg", "Si"]
    /// The simulator's atomic masses (forward.py ATOMIC_MASS) and geometry (forward.py SEG_*, TILT_ALPHA).
    private static let mass = ["Al": 26.9815, "Mg": 24.305, "Si": 28.0855]
    private static let azimuths = [45.0, 135.0, 225.0, 315.0], solidAngles = [0.4, 0.2, 0.1, 0.3]
    private static let beta = 0.2
    /// beta/6 (depth weight) + 4 % (oxide O absent from the app's medium: +3.5 % mu/rho at most, density mean 0.3 %), see the header.
    private static let modelGap = beta / 6 + 0.04

    /// The simulator's k in the weight convention C ~ k I, relative to Al (k_Al = 1).
    private static var typedK: [(String, Double)] {
        let w = elements.map { mass[$0]! / pool.trueK[$0]! }
        return zip(elements, w).map { ($0, $1 / w[0]) }
    }

    private static func segments() -> [DetectorSegment] {
        zip(azimuths, solidAngles).enumerated().map { i, a in
            DetectorSegment(label: "SuperXG1\(i + 1)", azimuthDegrees: a.0, elevationDegrees: 22, solidAngleSr: a.1)
        }
    }

    private static func at(_ wt: [Double]) throws -> [Double] { try CompositionConversion.weightToAtomic(wt, elements: elements) }

    // MARK: Level 1 - exact areas through the absorption correction

    /// The areas the forward model made BEFORE its tail / pile-up bookkeeping: a_free x T_eff, the quantity an absorption
    /// model is about. Exact: no counting noise, no fit.
    /// Predicted (python replica of the app's iteration, 2026-10-06, before any Swift run): with the correction
    /// Al 98.802 / Mg 0.5995 / Si 0.5981 (Si -0.31 % from truth), factors 1/T = 1.0201 / 1.0303 / 1.1722; without it
    /// Al 98.885 / Mg 0.5941 / Si 0.5209 (Si -13.2 %). Refuted if any share leaves the derived bound, or if the
    /// correction does not raise Si and Mg and lower Al.
    func testExactAreasRecoverTruthWithTheSimulatorsGeometryAndTheUncorrectedIsOffAsPredicted() throws {
        let p = Self.pool
        let I = Self.elements.map { p.areasAbsorptionFree[$0 + "_Ka"]! * p.tEff[$0 + "_Ka"]! }
        let k = Self.typedK.map(\.1)
        let truth = Self.elements.map { p.truthAtPct[$0]! }

        // The k conversion itself: absorption-free areas must give truth (guards the test's own arithmetic).
        let free = Self.elements.map { p.areasAbsorptionFree[$0 + "_Ka"]! }
        let freeAt = try Self.at(try CliffLorimer.weightFractions(intensities: free, kFactors: k).map { $0 * 100 })
        for (a, t) in zip(freeAt, truth) { XCTAssertEqual(a, t, accuracy: 1e-5) }   // the test types Al 26.9815, the app 26.9815386

        let geometry = try FourDetectorGeometry(segments: Self.segments(), tiltAlphaDegrees: -16.87)
        let energies = try Self.elements.map { try XCTUnwrap(XRayLines.line($0 + "_Ka")?.energy) }
        let setup = AbsorptionSetup(elements: Self.elements, lineEnergiesKeV: energies, geometry: geometry, table: Self.tables.mac)
        let r = try AbsorptionCorrection.cliffLorimer(intensities: I, kFactors: k, setup: setup, thicknessNm: p.thicknessNm,
                                                      options: .init(convergence: 1e-7, maxIterations: 200))
        let withAt = try Self.at(r.composition)
        let withoutAt = try Self.at(try CliffLorimer.weightFractions(intensities: I, kFactors: k).map { $0 * 100 })

        // Direction: 1/T Si > Mg > Al > 1; the correction raises Si and Mg and lowers Al.
        XCTAssertGreaterThan(r.factors[2], r.factors[1]); XCTAssertGreaterThan(r.factors[1], r.factors[0]); XCTAssertGreaterThan(r.factors[0], 1)
        XCTAssertGreaterThan(withAt[2], withoutAt[2]); XCTAssertGreaterThan(withAt[1], withoutAt[1]); XCTAssertLessThan(withAt[0], withoutAt[0])

        // Recovery inside the derived bound, element by element.
        let cAl = r.factors[0] - 1
        for i in 0..<3 {
            let bound = truth[i] * Self.modelGap * ((r.factors[i] - 1) + cAl) + 1e-6
            Self.note(String(format: "L1 %@ with %.5f without %.5f truth %.1f 1/T %.4f bound %.5f", Self.elements[i], withAt[i], withoutAt[i], truth[i], r.factors[i], bound))
            XCTAssertLessThanOrEqual(abs(withAt[i] - truth[i]), bound, "\(Self.elements[i]): \(withAt[i]) vs truth \(truth[i]), bound \(bound)")
        }
        // Uncorrected: Si is low by about the predicted 13 % (the simulator's own T_eff gives the exact number).
        let predictedSiRatio = (p.tEff["Si_Ka"]! / p.tEff["Al_Ka"]!)             // Si/Al read without correction, relative to truth
        XCTAssertEqual((withoutAt[2] / withoutAt[0]) / (truth[2] / truth[0]), predictedSiRatio, accuracy: 1e-5)
        XCTAssertEqual(withoutAt[2] / truth[2] - 1, -0.132, accuracy: 0.003, "uncorrected Si share vs truth: \(withoutAt[2] / truth[2] - 1)")
        XCTAssertLessThan(abs(withAt[2] - truth[2]), abs(withoutAt[2] - truth[2]) / 10, "the correction removes at least 90 % of the Si error")
    }

    // MARK: Level 2 - the pooled fit on a Poisson draw of the simulator's spectrum

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

    /// Poisson sample: Knuth below 10, Hoermann's PTRS above (the numpy algorithm), as `SpectroscopyFitTests`.
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

    private static func input(seed: UInt64, absorption: Bool) -> PooledQuantificationInput {
        let p = pool
        var rng = SplitMix64(state: seed)
        let counts = p.expected.map { poisson($0, &rng) }
        var m = QuantificationMethod()
        let roles: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Mg", .quantify), ("Si", .quantify), ("Cu", .fitOnly), ("O", .fitOnly)]
        m.elements = roles
            .map { QuantificationMethod.ElementState(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = true                       // the generator's own axis: the refinement is not under test here
        m.kFactorSource = .typed
        m.kSource = "tools/demo-edx/forward.py true k (Gp x s x eps), weight convention"; m.kDate = "2026-10-06"; m.kReference = "Al"
        m.typedK = typedK.map { .init(element: $0.0, k: $0.1, relativeSigma: 0) }
        m.thickness = .init(nanometres: p.thicknessNm, sigmaNanometres: 0)
        m.absorptionCorrection = absorption
        var meta = SpectrumImageMetadata(fileName: "sim", filePath: "sim", scanWidth: 100, scanHeight: 100, channelCount: p.size,
                                         energyOffsetEV: p.offset * 1000, energyDispersionEV: p.scale * 1000)
        meta.origin = .veloxEMD
        meta.alphaTiltDegrees = -16.87; meta.betaTiltDegrees = 0
        meta.detectors = zip(azimuths, solidAngles).enumerated().map { i, a in
            SpectrumDetectorSegment(name: "SuperXG1\(i + 1)", azimuthDegrees: a.0, elevationDegrees: 22, solidAngle: a.1)
        }
        return PooledQuantificationInput(counts: counts, axis: p.axis, method: m, metadata: meta, regionName: "recipe A pool",
                                         pixelCount: p.npix, resolutionMnKaEV: 130)
    }

    private static let seeds: [UInt64] = [11, 12, 13, 14]
    /// Fit bias envelope in counts, per element. Mg: the note's -402 +- 33 (402 + 3 x 33). Si: measured on this fixture, 4 seeds
    /// (the simulator-geometry column of the L2b run is independent of the app's geometry): -164 counts of 1879 (-8.7 %),
    /// sd 0.018 at % = ~40 counts, so 164 + 3 x 40.
    private static let biasEnvelopeCounts = ["Mg": 402.0 + 3 * 33.0, "Si": 164.0 + 3 * 40.0]

    /// Per-seed numbers go to stderr: `print` stays in the hosted app's stdout and never reaches the xcodebuild log.
    /// Also kept as an attachment (read it from the xcresult: `xcresulttool export attachments`).
    nonisolated(unsafe) private static var notes: [String] = []
    private static func note(_ s: String) { notes.append(s); FileHandle.standardError.write(Data(("A4 " + s + "\n").utf8)) }
    override func tearDown() {
        let a = XCTAttachment(string: Self.notes.joined(separator: "\n")); a.lifetime = .keepAlways; add(a)
        Self.notes = []
        super.tearDown()
    }

    /// The pooled fit (Poisson draw, simulator's k typed, true axis locked, 80 nm typed) against `phases_at_pct`.
    /// Predicted before any Swift run: Mg reads LOW by the documented weak-line bias (952 planted counts, ~300-400 lost,
    /// so about 0.40 at% rather than 0.60; the Al-flank bias is the reason, not the absorption); Si with the correction
    /// ~0.60, without ~0.52; Al ~98.8-99. Per element the tolerance is 3 x the result's own counting sigma + the bias
    /// envelope as a share of that line's counts (Mg from the note, Si measured on this fixture); Al: 3 sigma + 0.05 at% (the 1.5 % Al K-alpha
    /// tail left in the continuum moves Al by 1.5 % x the 1.2 at % non-Al share). Pile-up takes the same ~6 % from all
    /// three lines (kappa x a_Al), so it cancels in a ratio. Refuted if any share leaves its tolerance, or if with-absorption
    /// is not above without for Si and Mg (and below for Al) on every seed.
    func testPooledFitRecoversTruthAndTheCorrectionMovesTheSharesTheRightWay() throws {
        let p = Self.pool
        var siGain: [Double] = []
        for seed in Self.seeds {
            let on = try PooledQuantifier.run(Self.input(seed: seed, absorption: true), tables: Self.tables)
            let off = try PooledQuantifier.run(Self.input(seed: seed, absorption: false), tables: Self.tables)
            guard case .applied = on.absorption else { return XCTFail("\(on.absorption)") }
            XCTAssertEqual(off.absorption, .off)
            func row(_ r: PooledQuantification, _ el: String) throws -> PooledQuantification.Row { try XCTUnwrap(r.rows.first { $0.element == el }) }
            var line = "seed \(seed):"
            for el in Self.elements {
                let a = try row(on, el), b = try row(off, el)
                let truth = p.truthAtPct[el]!
                let at = try XCTUnwrap(a.atomicPercent), atOff = try XCTUnwrap(b.atomicPercent)
                let sigmaCounting = try XCTUnwrap(a.atomicTerms)[.counting] * at
                let tol = el == "Al" ? 3 * sigmaCounting + 0.05
                                      : 3 * sigmaCounting + truth * Self.biasEnvelopeCounts[el]! / p.areasWithAbsorption[el + "_Ka"]!
                line += String(format: " %@ %.4f (off %.4f, truth %.1f, tol %.3f, net %.0f)", el, at, atOff, truth, tol, a.net)
                XCTAssertLessThanOrEqual(abs(at - truth), tol, "\(el) \(line)")
                switch el {
                case "Al": XCTAssertLessThan(at, atOff, line)
                default: XCTAssertGreaterThan(at, atOff, line)
                }
                if el == "Si" { siGain.append(at - atOff) }
            }
            Self.note("L2 " + line)
        }
        // The Si correction is a property of the geometry, not of the draw: the same on every seed (predicted +0.078 at%).
        let spread = (siGain.max() ?? 0) - (siGain.min() ?? 0)
        XCTAssertLessThan(spread, 0.01, "Si correction by seed: \(siGain)")
        XCTAssertEqual(siGain.reduce(0, +) / Double(siGain.count), 0.078, accuracy: 0.015, "\(siGain)")
    }

    /// Same fitted areas, two corrections: the app's (closed form, element-density mass thickness, no O) against the
    /// SIMULATOR's own per-line T_eff (`t_eff` in the fixture, the depth-weighted path integral). Counting statistics and the
    /// weak-line bias are in both areas, so they cancel; what is left is the correction model, bounded as in the header.
    /// Predicted: |difference| <= bound for Mg, Si and Al on every seed (Si ~0.002 at%, bound ~0.006).
    func testPooledCorrectionAgreesWithTheSimulatorsOwnTransmissionOnTheSameFittedAreas() throws {
        let p = Self.pool
        let k = Self.typedK.map(\.1)
        for seed in Self.seeds {
            let on = try PooledQuantifier.run(Self.input(seed: seed, absorption: true), tables: Self.tables)
            let nets = try Self.elements.map { el in try XCTUnwrap(on.rows.first { $0.element == el }).net }
            let simFactors = Self.elements.map { 1 / p.tEff[$0 + "_Ka"]! }
            let simAt = try Self.at(try CliffLorimer.weightFractions(intensities: nets, kFactors: k, absorption: simFactors).map { $0 * 100 })
            let rawAt = try Self.at(try CliffLorimer.weightFractions(intensities: nets, kFactors: k).map { $0 * 100 })
            let cAl = simFactors[0] - 1
            for (i, el) in Self.elements.enumerated() {
                let app = try XCTUnwrap(on.rows.first { $0.element == el }?.atomicPercent)
                let bound = simAt[i] * Self.modelGap * ((simFactors[i] - 1) + cAl) + 1e-6
                XCTAssertLessThanOrEqual(abs(app - simAt[i]), bound, "seed \(seed) \(el): app \(app), simulator-geometry \(simAt[i]), bound \(bound)")
                // and the correction is real: the simulator-geometry result is far from the uncorrected one for Si
                Self.note(String(format: "L2b seed %llu %@ app %.4f simulator-geometry %.4f raw %.4f bound %.4f", seed, el, app, simAt[i], rawAt[i], bound))
                if el == "Si" { XCTAssertGreaterThan(simAt[i] - rawAt[i], 0.05, "seed \(seed): \(simAt[i]) vs raw \(rawAt[i])") }
            }
        }
    }
}
