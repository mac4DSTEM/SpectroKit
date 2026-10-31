import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// v5.0 lane A4: the absorption correction against the simulator's TRUTH geometry (open item "The absorption test checks
/// plumbing only"). Pool: 1e4 identical recipe-A matrix pixels of `tools/edx-sim/forward.py` (Al 98.8 / Mg 0.6 / Si 0.6 at%,
/// 80 nm, 2.70 g/cm3, the simulator's four segments with unequal solid angles 0.4/0.2/0.1/0.3, alpha -16.87, elevation 22,
/// depth weight beta 0.2, oxide O in the medium); `tools/edx-sim/absorption_truth_sim.py` wrote the fixture.
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
final class SpectroscopyAbsorptionTruthTests {

    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/SpectroEDX/Resources/Spectroscopy")
    static let tables = try! QuantificationTables(directory: resources)

    private struct Pool: Decodable {
        let npix: Int, offset: Double, scale: Double, size: Int
        let thicknessNm: Double
        let truthAtPct: [String: Double]
        let areasWithAbsorption: [String: Double], areasAbsorptionFree: [String: Double], tEff: [String: Double]
        let trueK: [String: Double]
        /// The detector Si internal-fluorescence peak the simulator plants at Si K-alpha (forward.py `Si_Ka_internal`), counts.
        let areaSiKaInternal: Double
        let expected: [Double]
        enum CodingKeys: String, CodingKey {
            case npix, offset, scale, size, expected
            case areaSiKaInternal = "area_si_ka_internal"
            case thicknessNm = "thickness_nm", truthAtPct = "truth_at_pct", areasWithAbsorption = "areas_with_absorption"
            case areasAbsorptionFree = "areas_absorption_free", tEff = "t_eff", trueK = "true_k_counts_per_atom_nm2"
        }
        var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    }
    private static let pool: Pool = {
        let url = EDXFixtures.dir.appendingPathComponent("eds-absorption-truth.json")
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
    @Test func testExactAreasRecoverTruthWithTheSimulatorsGeometryAndTheUncorrectedIsOffAsPredicted() throws {
        let p = Self.pool
        let I = Self.elements.map { p.areasAbsorptionFree[$0 + "_Ka"]! * p.tEff[$0 + "_Ka"]! }
        let k = Self.typedK.map(\.1)
        let truth = Self.elements.map { p.truthAtPct[$0]! }

        // The k conversion itself: absorption-free areas must give truth (guards the test's own arithmetic).
        let free = Self.elements.map { p.areasAbsorptionFree[$0 + "_Ka"]! }
        let freeAt = try Self.at(try CliffLorimer.weightFractions(intensities: free, kFactors: k).map { $0 * 100 })
        for (a, t) in zip(freeAt, truth) { #expect(isEqual(a, t, accuracy: 1e-5)) }   // the test types Al 26.9815, the app 26.9815386

        let geometry = try FourDetectorGeometry(segments: Self.segments(), tiltAlphaDegrees: -16.87)
        let energies = try Self.elements.map { try #require(XRayLines.line($0 + "_Ka")?.energy) }
        let setup = AbsorptionSetup(elements: Self.elements, lineEnergiesKeV: energies, geometry: geometry, table: Self.tables.mac)
        let r = try AbsorptionCorrection.cliffLorimer(intensities: I, kFactors: k, setup: setup, thicknessNm: p.thicknessNm,
                                                      options: .init(convergence: 1e-7, maxIterations: 200))
        let withAt = try Self.at(r.composition)
        let withoutAt = try Self.at(try CliffLorimer.weightFractions(intensities: I, kFactors: k).map { $0 * 100 })

        // Direction: 1/T Si > Mg > Al > 1; the correction raises Si and Mg and lowers Al.
        #expect(r.factors[2] > r.factors[1]); #expect(r.factors[1] > r.factors[0]); #expect(r.factors[0] > 1)
        #expect(withAt[2] > withoutAt[2]); #expect(withAt[1] > withoutAt[1]); #expect(withAt[0] < withoutAt[0])

        // Recovery inside the derived bound, element by element.
        let cAl = r.factors[0] - 1
        for i in 0..<3 {
            let bound = truth[i] * Self.modelGap * ((r.factors[i] - 1) + cAl) + 1e-6
            note(String(format: "L1 %@ with %.5f without %.5f truth %.1f 1/T %.4f bound %.5f", Self.elements[i], withAt[i], withoutAt[i], truth[i], r.factors[i], bound))
            #expect(abs(withAt[i] - truth[i]) <= bound, "\(Self.elements[i]): \(withAt[i]) vs truth \(truth[i]), bound \(bound)")
        }
        // Uncorrected: Si is low by about the predicted 13 % (the simulator's own T_eff gives the exact number).
        let predictedSiRatio = (p.tEff["Si_Ka"]! / p.tEff["Al_Ka"]!)             // Si/Al read without correction, relative to truth
        #expect(isEqual((withoutAt[2] / withoutAt[0]) / (truth[2] / truth[0]), predictedSiRatio, accuracy: 1e-5))
        #expect(isEqual(withoutAt[2] / truth[2] - 1, -0.132, accuracy: 0.003), "uncorrected Si share vs truth: \(withoutAt[2] / truth[2] - 1)")
        #expect(abs(withAt[2] - truth[2]) < (abs(withoutAt[2] - truth[2]) / 10), "the correction removes at least 90 % of the Si error")
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
        m.kSource = "tools/edx-sim/forward.py true k (Gp x s x eps), weight convention"; m.kDate = "2026-10-06"; m.kReference = "Al"
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

    /// The planted Si K-alpha a fit sees: the sample line (1879.5 counts) PLUS the detector Si internal-fluorescence peak the
    /// simulator puts at the same energy (236.3 counts), 2115.8 in all. exSpy, the reference, fits one Gaussian per X-ray line
    /// (`EDSModel.add_family_lines`) and has no internal-fluorescence term, no dead layer and no detector efficiency (the k-factor
    /// carries the efficiency), so its `Si_Ka` area takes both (all but a few % of the internal peak, as Si K-beta is tied to
    /// K-alpha by weight and the internal peak has no K-beta); so does SpectroKit's default fit (the `.countsAboveEdge` reference
    /// shape is opt-in and off here). Comparing the fit with the sample line alone hid the internal-fluorescence counts and
    /// understated the Si bias by about half (issue: the truth test leaves the Si internal-fluorescence peak out).
    private static var plantedSiKa: Double { pool.areasWithAbsorption["Si_Ka"]! + pool.areaSiKaInternal }

    /// Atomic percent from the planted noise-free areas with the simulator's own transmission (1/T_eff), Si K-alpha raised by
    /// `siExtra` counts. The planted areas are already after pile-up; dividing the detector-made internal-fluorescence counts by
    /// T_eff is not physics, but it is what the reference and the corrected fit both do to the whole Si K-alpha area.
    private static func plantedAt(siExtra: Double) throws -> [Double] {
        let a = pool.areasWithAbsorption
        let areas = [a["Al_Ka"]!, a["Mg_Ka"]!, a["Si_Ka"]! + siExtra]
        let factors = elements.map { 1 / pool.tEff[$0 + "_Ka"]! }
        return try at(try CliffLorimer.weightFractions(intensities: areas, kFactors: typedK.map(\.1), absorption: factors).map { $0 * 100 })
    }

    /// The Si share a fit that measures the whole planted Si K-alpha peak reads: the sample truth scaled by what the
    /// internal-fluorescence counts add (0.6 -> about 0.675 at%). This, not 0.6, is what the reference would report.
    private static func siTargetAtPct() throws -> Double {
        let truth = pool.truthAtPct["Si"]!
        return truth * (try plantedAt(siExtra: pool.areaSiKaInternal)[2]) / (try plantedAt(siExtra: 0)[2])
    }

    /// Fit bias envelope in counts, per element. Mg: the note's -402 +- 33 (402 + 3 x 33), against the planted Mg K-alpha.
    /// Si: measured on this fixture against the WHOLE planted Si K-alpha peak (`plantedSiKa`), 4 seeds: nets 1750 / 1648 / 1632 /
    /// 1714, mean 1686, so -430 counts of 2116 (-20.3 %), sd 56 counts; envelope 430 + 3 x 56. (Against the sample line alone the
    /// same nets read -193 of 1879, -10.3 %: the number the test reported before, as -8.7 %.)
    private static let biasEnvelopeCounts = ["Mg": 402.0 + 3 * 33.0, "Si": 430.0 + 3 * 56.0]
    /// The measured Si bias against the whole planted peak, mean of the 4 fixed seeds, with a regression band of 3 seed-sd over
    /// sqrt(4) (3 x 56 / 2 / 2116 = 0.040, about 85 counts). The seeds are fixed, so this is a regression pin, not a confidence
    /// interval and not validation. A known deviation: pinned so that a change either way fails and is looked at. It is the real
    /// Si gate; the per-seed tolerance above only bounds each draw.
    private static let siBiasFraction = -0.203, siBiasBand = 0.040

    /// Per-seed numbers go to stderr: `print` stays in the hosted app's stdout and never reaches the xcodebuild log.
    /// Also kept as an attachment (read it from the xcresult: `xcresulttool export attachments`, or the test run's attachments folder).
    /// One instance per test (Swift Testing), so the notes are the test's own, attached when it ends.
    private var notes: [String] = []
    private func note(_ s: String) { notes.append(s); FileHandle.standardError.write(Data(("A4 " + s + "\n").utf8)) }
    deinit {
        Attachment.record(notes.joined(separator: "\n"), named: "notes")
    }

    /// The pooled fit (Poisson draw, simulator's k typed, true axis locked, 80 nm typed) against `phases_at_pct`.
    /// Predicted before any Swift run: Mg reads LOW by the documented weak-line bias (952 planted counts, ~300-400 lost,
    /// so about 0.40 at% rather than 0.60; the Al-flank bias is the reason, not the absorption); Si with the correction
    /// ~0.60, without ~0.52; Al ~98.8-99. Per element the tolerance is 3 x the result's own counting sigma + the bias
    /// envelope as a share of that line's counts (Mg from the note, Si measured on this fixture); Al: 3 sigma + 0.05 at% (the 1.5 % Al K-alpha
    /// tail left in the continuum moves Al by 1.5 % x the 1.2 at % non-Al share). Pile-up takes the same ~6 % from all
    /// three lines (kappa x a_Al), so it cancels in a ratio. Refuted if any share leaves its tolerance, or if with-absorption
    /// is not above without for Si and Mg (and below for Al) on every seed.
    /// Si is held against what the reference measures, the whole planted Si K-alpha peak (`plantedSiKa`, `siTargetAtPct`), not
    /// the sample truth 0.6: the fit reads it about 20 % low in counts (`siBiasFraction`), the honest size of the Si bias.
    @Test func testPooledFitRecoversTruthAndTheCorrectionMovesTheSharesTheRightWay() throws {
        let p = Self.pool
        let siTarget = try Self.siTargetAtPct()
        // The target arithmetic: without the internal-fluorescence counts the planted areas give Si and Mg back in the truth
        // ratio (both read +1.5 %: the Al K-alpha tail the simulator splits off its Al line, which the ratio in siTargetAtPct cancels).
        let sampleOnly = try Self.plantedAt(siExtra: 0)
        #expect(abs((sampleOnly[2] / sampleOnly[1]) / (p.truthAtPct["Si"]! / p.truthAtPct["Mg"]!) - 1) < 1e-3, "planted areas give \(sampleOnly) at%")
        note(String(format: "L2 Si planted K-alpha %.1f (sample %.1f + internal fluorescence %.1f), Si target %.4f at%% (sample truth %.1f)",
                    Self.plantedSiKa, p.areasWithAbsorption["Si_Ka"]!, p.areaSiKaInternal, siTarget, p.truthAtPct["Si"]!))
        var siGain: [Double] = []
        var siNet: [Double] = []
        for seed in Self.seeds {
            let on = try PooledQuantifier.run(Self.input(seed: seed, absorption: true), tables: Self.tables)
            let off = try PooledQuantifier.run(Self.input(seed: seed, absorption: false), tables: Self.tables)
            guard case .applied = on.absorption else { Issue.record("\(on.absorption)"); return }
            #expect(off.absorption == .off)
            func row(_ r: PooledQuantification, _ el: String) throws -> PooledQuantification.Row { try #require(r.rows.first { $0.element == el }) }
            var line = "seed \(seed):"
            for el in Self.elements {
                let a = try row(on, el), b = try row(off, el)
                let truth = el == "Si" ? siTarget : p.truthAtPct[el]!
                let planted = el == "Si" ? Self.plantedSiKa : p.areasWithAbsorption[el + "_Ka"]!
                let at = try #require(a.atomicPercent), atOff = try #require(b.atomicPercent)
                let sigmaCounting = try #require(a.atomicTerms)[.counting] * at
                let tol = el == "Al" ? 3 * sigmaCounting + 0.05
                                      : 3 * sigmaCounting + truth * Self.biasEnvelopeCounts[el]! / planted
                line += String(format: " %@ %.4f (off %.4f, target %.4f, tol %.3f, net %.0f of %.0f)", el, at, atOff, truth, tol, a.net, planted)
                #expect(abs(at - truth) <= tol, "\(el) \(line)")
                switch el {
                case "Al": #expect(at < atOff, "\(line)")
                default: #expect(at > atOff, "\(line)")
                }
                if el == "Si" { siGain.append(at - atOff); siNet.append(a.net) }
            }
            note("L2 " + line)
        }
        // The Si bias against the whole planted Si K-alpha peak, stated and pinned.
        let siBias = siNet.reduce(0, +) / Double(siNet.count) / Self.plantedSiKa - 1
        note(String(format: "L2 Si bias against the planted K-alpha peak %.4f (pinned %.3f +- %.3f); against the sample line alone %.4f",
                    siBias, Self.siBiasFraction, Self.siBiasBand, siNet.reduce(0, +) / Double(siNet.count) / p.areasWithAbsorption["Si_Ka"]! - 1))
        #expect(abs(siBias - Self.siBiasFraction) <= Self.siBiasBand, "Si bias against the planted K-alpha peak: \(siBias), nets \(siNet)")
        // The Si correction is a property of the geometry, not of the draw: the same on every seed (predicted +0.078 at%).
        let spread = (siGain.max() ?? 0) - (siGain.min() ?? 0)
        #expect(spread < 0.01, "Si correction by seed: \(siGain)")
        #expect(isEqual(siGain.reduce(0, +) / Double(siGain.count), 0.078, accuracy: 0.015), "\(siGain)")
    }

    /// Same fitted areas, two corrections: the app's (closed form, element-density mass thickness, no O) against the
    /// SIMULATOR's own per-line T_eff (`t_eff` in the fixture, the depth-weighted path integral). Counting statistics and the
    /// weak-line bias are in both areas, so they cancel; what is left is the correction model, bounded as in the header.
    /// Predicted: |difference| <= bound for Mg, Si and Al on every seed (Si ~0.002 at%, bound ~0.006).
    @Test func testPooledCorrectionAgreesWithTheSimulatorsOwnTransmissionOnTheSameFittedAreas() throws {
        let p = Self.pool
        let k = Self.typedK.map(\.1)
        for seed in Self.seeds {
            let on = try PooledQuantifier.run(Self.input(seed: seed, absorption: true), tables: Self.tables)
            let nets = try Self.elements.map { el in try #require(on.rows.first { $0.element == el }).net }
            let simFactors = Self.elements.map { 1 / p.tEff[$0 + "_Ka"]! }
            let simAt = try Self.at(try CliffLorimer.weightFractions(intensities: nets, kFactors: k, absorption: simFactors).map { $0 * 100 })
            let rawAt = try Self.at(try CliffLorimer.weightFractions(intensities: nets, kFactors: k).map { $0 * 100 })
            let cAl = simFactors[0] - 1
            for (i, el) in Self.elements.enumerated() {
                let app = try #require(on.rows.first { $0.element == el }?.atomicPercent)
                let bound = simAt[i] * Self.modelGap * ((simFactors[i] - 1) + cAl) + 1e-6
                #expect(abs(app - simAt[i]) <= bound, "seed \(seed) \(el): app \(app), simulator-geometry \(simAt[i]), bound \(bound)")
                // and the correction is real: the simulator-geometry result is far from the uncorrected one for Si
                note(String(format: "L2b seed %llu %@ app %.4f simulator-geometry %.4f raw %.4f bound %.4f", seed, el, app, simAt[i], rawAt[i], bound))
                if el == "Si" { #expect((simAt[i] - rawAt[i]) > 0.05, "seed \(seed): \(simAt[i]) vs raw \(rawAt[i])") }
            }
        }
    }
}
