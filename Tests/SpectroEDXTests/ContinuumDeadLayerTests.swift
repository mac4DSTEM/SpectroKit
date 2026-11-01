import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// SpectroKit#8: the optional detector Si dead-layer term of the continuum (`FitPolicy.continuumDeadLayer`, `DeadLayerFit`)
/// on planted pools of `tools/edx-sim/forward.py`.
///
/// Pools (noise-free expected spectra, 1e4 identical recipe-A matrix pixels, Al 98.8 / Mg 0.6 / Si 0.6 at%, 80 nm):
///  * `eds-dead-layer-truth.json` (`dead_layer_sim.py`): seen through a 0.3 um Si dead layer, an 11 % continuum step at the
///    Si K edge (1.839 keV), 0.1 keV above Si K-alpha.
///  * `eds-absorption-truth.json` (`absorption_truth_sim.py`): the same pool with no dead layer.
///
/// Truth is the planted Si K-alpha area (`areas` / `areas_with_absorption`), as the absorption-truth tests. The kit's
/// planted-recovery tolerance for Si on this recipe is that of `SpectroscopyAbsorptionTruthTests`: 3 x the fit's own sigma
/// plus the Si bias envelope measured on the no-dead-layer pool, 164 + 3 x 40 counts.
///
/// Physics, stated before the runs. Without the term the order-5 segment above the Al K edge smooths across the step, so it
/// sits too low under Si K-alpha and Si reads HIGH by the step's share; a typed thickness puts the step in the continuum and
/// takes that shift out. What is left is the pool's own bias without a dead layer (-150 counts, -8 %: the continuum cannot
/// follow the sample's Al-absorption recovery above 1.56 keV, and a 236-count Si internal-fluorescence peak sits under
/// Si K-alpha), which this term does not address.
///
/// Measured (2026-10-31, noise-free): no dead layer, default fit Si 1729.9 (planted 1879.5, -149.6). Dead-layer pool, planted
/// 1841.8: without the term 1840.2 (-1.6; the step's +148 cancels the pool's -150 by accident), typed 0.3 um 1629.1
/// (-212.7), fitted (0.394 um) 1566.2 (-275.6); sigma 67-69. The fitted thickness is not identifiable on this continuum: on the
/// pool without a dead layer it reads 0.207 um and moves Si by -155 counts (-2.3 sigma), so the term is not neutral there and
/// stays off by default. validation: "none".
struct ContinuumDeadLayerTests {

    private struct Pool: Decodable {
        let offset: Double, scale: Double, size: Int, npix: Int
        let expected: [Double]
        let areas: [String: Double]?
        let areasWithAbsorption: [String: Double]?
        let deadLayerUm: Double?
        enum CodingKeys: String, CodingKey {
            case offset, scale, size, npix, expected, areas
            case areasWithAbsorption = "areas_with_absorption", deadLayerUm = "dead_layer_um"
        }
        var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
        var plantedSi: Double { (areas ?? areasWithAbsorption!)["Si_Ka"]! }
    }

    private static func load(_ name: String) -> Pool {
        try! JSONDecoder().decode(Pool.self, from: Data(contentsOf: EDXFixtures.dir.appendingPathComponent(name)))
    }
    private static let deadLayerPool = load("eds-dead-layer-truth.json")
    private static let plainPool = load("eds-absorption-truth.json")
    private static let table = MassAbsorptionTable.bundled!
    private static let elements = ["Al", "Mg", "Si", "Cu", "O"]
    /// `SpectroscopyAbsorptionTruthTests.biasEnvelopeCounts["Si"]`: 164 + 3 x 40 counts.
    private static let siBiasEnvelope = 164.0 + 3 * 40.0

    private static func settings(_ p: Pool) -> FitSettings {
        FitSettings.standard(elements: elements, axis: p.axis, resolutionMnKaEV: 130, beamEnergy: 200)
    }

    /// Si K-alpha area and sigma of the noise-free fit, with the dead layer of `microns` (nil: the term off).
    private static func si(_ p: Pool, microns: Double?) throws -> (area: Double, sigma: Double) {
        var s = settings(p)
        if let t = microns { s = DeadLayerFit.settings(s, base: nil, microns: t, table: table) }
        let r = try EDSFit.run(counts: p.expected, axis: p.axis, settings: s)
        let i = try #require(r.groupIDs.firstIndex(of: "Si_Ka"))
        return (r.values[i], r.sigma(at: i))
    }

    private static func fitted(_ p: Pool) throws -> DeadLayerFit.Result {
        try DeadLayerFit.fit(counts: p.expected, axis: p.axis, settings: settings(p), base: nil, table: table, maximumMicrons: 1)
    }

    private static func note(_ s: String) { FileHandle.standardError.write(Data(("DL " + s + "\n").utf8)) }

    /// On the dead-layer pool, Si is recovered within the kit's planted tolerance with the term on, typed and fitted; and
    /// without it (shown, see the header for why it passes too).
    @Test func testSiOnTheDeadLayerPoolIsWithinThePlantedToleranceWithTheTermOnAndOff() throws {
        let p = Self.deadLayerPool
        let planted = p.plantedSi
        let t = try #require(p.deadLayerUm)
        #expect(t == 0.3)
        let fit = try Self.fitted(p)
        let cases: [(String, Double?)] = [("off", nil), ("typed", t), ("fitted", fit.microns)]
        for (name, microns) in cases {
            let r = try Self.si(p, microns: microns)
            let tol = 3 * r.sigma + Self.siBiasEnvelope
            Self.note(String(format: "%@ t %@ Si %.1f planted %.1f diff %+.1f sigma %.1f tol %.1f", name,
                             microns.map { String(format: "%.4f", $0) } ?? "-", r.area, planted, r.area - planted, r.sigma, tol))
            #expect(abs(r.area - planted) <= tol, "\(name): Si \(r.area) vs planted \(planted), tolerance \(tol)")
        }
        #expect(fit.microns > 0 && fit.microns < 1, "fitted \(fit.microns) um")
        #expect(!fit.atUpperBound)
        #expect(fit.objective <= fit.objectiveAtZero)
    }

    /// The search finds the minimum: the objective 1e-3 um either side of the fitted thickness is not lower. A tight bound
    /// sits at the bound and says so.
    @Test func testTheSearchReturnsTheMinimumAndFlagsTheUpperBound() throws {
        let p = Self.deadLayerPool
        let fit = try Self.fitted(p)
        func objective(_ t: Double) throws -> Double {
            let r = try EDSFit.run(counts: p.expected, axis: p.axis,
                                   settings: DeadLayerFit.settings(Self.settings(p), base: nil, microns: t, table: Self.table),
                                   computeCovariance: false)
            return r.residual.reduce(0) { $0 + $1 * $1 }
        }
        #expect(isEqual(try objective(fit.microns), fit.objective, accuracy: 1e-9 * fit.objective))
        for t in [max(fit.microns - 1e-3, 0), min(fit.microns + 1e-3, 1)] {
            #expect(try objective(t) >= fit.objective, "objective at \(t) um below the fitted \(fit.microns) um")
        }
        let tight = try DeadLayerFit.fit(counts: p.expected, axis: p.axis, settings: Self.settings(p), base: nil, table: Self.table,
                                         maximumMicrons: 0.1)
        #expect(tight.atUpperBound && tight.microns == 0.1, "\(tight.microns)")
    }

    /// The typed term reduces the shift the dead layer causes from 2.2 sigma to under 1 sigma (it over-corrects: -63 counts).
    /// The bounds are the fit's own counting sigma: below 1 sigma a residual shift is not resolvable on this pool, and the
    /// unmodelled step must be resolvable (2 sigma) for the pool to test anything. Red before the term existed: the step is
    /// unmodelled.
    @Test func testTheTypedTermReducesTheShiftTheDeadLayerCauses() throws {
        let base = try Self.si(Self.plainPool, microns: nil)
        let baseError = base.area - Self.plainPool.plantedSi
        let p = Self.deadLayerPool
        let on = try Self.si(p, microns: p.deadLayerUm ?? .nan)
        let off = try Self.si(p, microns: nil)
        let shiftOn = (on.area - p.plantedSi) - baseError
        let shiftOff = (off.area - p.plantedSi) - baseError
        Self.note(String(format: "base error %+.1f; shift with the term %+.1f (%.2f sigma), without %+.1f (%.2f sigma)",
                         baseError, shiftOn, shiftOn / on.sigma, shiftOff, shiftOff / off.sigma))
        #expect(abs(shiftOn) <= on.sigma, "with the typed term: \(shiftOn) counts, sigma \(on.sigma)")
        #expect(shiftOff > 2 * off.sigma, "without the term the dead layer reads Si high: \(shiftOff) counts, sigma \(off.sigma)")
    }

    /// Why the term is off by default: on the pool WITHOUT a dead layer the fitted thickness is not 0 and Si moves by more
    /// than 1 sigma (the step absorbs part of the sample-side continuum misfit, open item 12). Neutrality is the goal, so it is
    /// asserted as a known issue: when the continuum follows the sample's Al-absorption recovery, this goes green and says so.
    /// Typed 0 is the default fit exactly.
    @Test func testTheFittedTermIsNotYetNeutralOnThePoolWithoutADeadLayerSoTheDefaultIsOff() throws {
        #expect(FitPolicy.default.continuumDeadLayer == nil)
        let p = Self.plainPool
        let off = try Self.si(p, microns: nil)
        let zero = try Self.si(p, microns: 0)
        #expect(zero.area == off.area && zero.sigma == off.sigma)
        let fit = try Self.fitted(p)
        let on = try Self.si(p, microns: fit.microns)
        Self.note(String(format: "no dead layer: fitted %.4f um, Si %.1f -> %.1f (%.2f sigma)", fit.microns, off.area, on.area,
                         (on.area - off.area) / off.sigma))
        #expect(fit.microns > 0)
        withKnownIssue("open item 12: the fitted dead layer is not neutral on a pool without one") {
            #expect(abs(on.area - off.area) <= off.sigma)
        }
    }

    /// The transmission is exp(-mu_Si rho t) on the kit's FFAST table: the same number as the dead-layer factor of the SDD
    /// model, and the pool's own stored transmissions (the simulator's FFAST log-log interpolation) to 1e-9.
    @Test func testTransmissionMatchesTheSDDDeadLayerFactorAndTheSimulator() throws {
        let dl = SiliconDeadLayer(microns: 0.3, table: Self.table)
        for e in [1.2536, 1.4865, 1.7397, 1.835, 1.845, 5.0] {
            let sdd0 = SDDEfficiency(table: Self.table, deadLayerMicrons: 0).efficiency(energyKeV: e)
            let sdd = SDDEfficiency(table: Self.table, deadLayerMicrons: 0.3).efficiency(energyKeV: e)
            #expect(isEqual(dl.efficiency(energyKeV: e), sdd / sdd0, accuracy: 1e-12), "\(e) keV")
        }
        struct T: Decodable {
            let t: [String: Double], edge: [String: Double]
            enum CodingKeys: String, CodingKey { case t = "dead_layer_transmission", edge = "dead_layer_transmission_at_si_k_edge" }
        }
        let s = try JSONDecoder().decode(T.self, from: Data(contentsOf: EDXFixtures.dir.appendingPathComponent("eds-dead-layer-truth.json")))
        let energy = ["Al_Ka": 1.4865, "Mg_Ka": 1.2536, "Si_Ka": 1.7397, "below_1.835": 1.835, "above_1.845": 1.845]
        for (k, v) in s.t.merging(s.edge, uniquingKeysWith: { a, _ in a }) {
            #expect(isEqual(dl.efficiency(energyKeV: try #require(energy[k])), v, accuracy: 1e-9), "\(k)")
        }
        #expect(dl.efficiency(energyKeV: 1.845) < 0.92 * dl.efficiency(energyKeV: 1.835))   // the step at the Si K edge (0.908)
    }

    // MARK: Through the public API

    private static func input(policy: QuantificationPolicy) -> PooledQuantificationInput {
        let p = deadLayerPool
        var m = QuantificationMethod()
        m.elements = elements.map { QuantificationMethod.ElementState(symbol: $0, role: ["Cu", "O"].contains($0) ? .fitOnly : .quantify, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = true
        let meta = SpectrumImageMetadata(fileName: "sim", filePath: "sim", scanWidth: 100, scanHeight: 100, channelCount: p.size,
                                         energyOffsetEV: p.offset * 1000, energyDispersionEV: p.scale * 1000)
        return PooledQuantificationInput(counts: p.expected.map { UInt64($0.rounded()) }, axis: p.axis, method: m, metadata: meta,
                                         regionName: "dead-layer pool", pixelCount: p.npix, resolutionMnKaEV: 130, policy: policy)
    }

    @Test func testPooledQuantifierRunsTheTermTypedAndFittedAndNamesIt() throws {
        let off = try PooledQuantifier.run(Self.input(policy: .default), tables: nil)
        #expect(off.continuumDeadLayerMicrons == nil)
        #expect(!off.footerLines.joined().contains("dead layer"))

        let typed = try PooledQuantifier.run(Self.input(policy: QuantificationPolicy(fit: FitPolicy(continuumDeadLayer: .given(microns: 0.3)))), tables: nil)
        #expect(typed.continuumDeadLayerMicrons == 0.3)
        #expect(typed.fit.backgroundLabel.contains("Si dead layer 0.3000"), Comment(rawValue: typed.fit.backgroundLabel))
        #expect(typed.footerLines.contains { $0.hasPrefix("policy (non-default): fit.continuumDeadLayer = {") })

        let fitted = try PooledQuantifier.run(Self.input(policy: QuantificationPolicy(fit: FitPolicy(continuumDeadLayer: .fitted()))), tables: nil)
        let t = try #require(fitted.continuumDeadLayerMicrons)
        #expect(t > 0 && t < 1)
        #expect(fitted.fit.backgroundLabel.contains("Si dead layer"))
        #expect(fitted.warnings.contains { $0.hasPrefix("Si dead layer fitted:") && $0.contains("conditional") }, Comment(rawValue: fitted.warnings.joined(separator: " | ")))
        let tight = try PooledQuantifier.run(Self.input(policy: QuantificationPolicy(fit: FitPolicy(continuumDeadLayer: .fitted(maximumMicrons: 0.1)))), tables: nil)
        #expect(tight.warnings.contains { $0.contains("upper bound") })
        var poly = Self.input(policy: QuantificationPolicy(fit: FitPolicy(continuumDeadLayer: .given(microns: 0.3))))
        poly.method.background = .wholeRangePolynomial6
        let polyRun = try PooledQuantifier.run(poly, tables: nil)
        #expect(polyRun.continuumDeadLayerMicrons == nil)
        #expect(polyRun.warnings.contains { $0.contains("not used with the polynomial background") })
        func si(_ q: PooledQuantification) throws -> Double { try #require(q.rows.first { $0.element == "Si" }).net }
        // The modelled step raises the continuum under Si K-alpha relative to the smoothed one, so Si reads lower.
        #expect(try si(typed) < si(off))
        #expect(try si(fitted) < si(off))

        // With the SDD layers as well, the two efficiencies multiply.
        let both = try PooledQuantifier.run(Self.input(policy: QuantificationPolicy(fit: FitPolicy(continuumEfficiency: .default,
                                                                                                    continuumDeadLayer: .given(microns: 0.3)))), tables: nil)
        #expect(both.fit.backgroundLabel.contains("EPQ") && both.fit.backgroundLabel.contains("Si dead layer 0.3000"))
    }

    /// The fitted thickness is fitted without the sum/escape model; the warning says so whenever the final fit includes it, also
    /// when that model comes from `FitPolicy.sumPeaks` (no `sumEscape` passed), and not when the final fit has none. Red before:
    /// the clause was read from `input.sumEscape` alone.
    @Test func testTheFittedDeadLayerWarningNamesTheSumEscapeModelWhenThePolicyKeepsIt() throws {
        let clause = "fitted without the sum/escape model"
        func note(_ q: PooledQuantification) throws -> String { try #require(q.warnings.first { $0.hasPrefix("Si dead layer fitted:") }) }
        let kept = try PooledQuantifier.run(Self.input(policy: QuantificationPolicy(fit: FitPolicy(sumPeaks: .always, continuumDeadLayer: .fitted()))), tables: nil)
        #expect(kept.appliedSumEscape != nil)
        let keptNote = try note(kept)
        #expect(keptNote.contains(clause), Comment(rawValue: keptNote))
        let off = try PooledQuantifier.run(Self.input(policy: QuantificationPolicy(fit: FitPolicy(sumPeaks: .off, continuumDeadLayer: .fitted()))), tables: nil)
        #expect(off.appliedSumEscape == nil)
        let offNote = try note(off)
        #expect(!offNote.contains(clause), Comment(rawValue: offNote))
        var passed = Self.input(policy: QuantificationPolicy(fit: FitPolicy(sumPeaks: .off, continuumDeadLayer: .fitted())))
        passed.sumEscape = SumEscapeModel(sumPeaks: true)
        let passedNote = try note(PooledQuantifier.run(passed, tables: nil))
        #expect(passedNote.contains(clause), Comment(rawValue: passedNote))
    }

    /// The range-sensitivity refit repeats the reported fit's dead layer: its nets are those of the alternative range with the
    /// reported thickness typed, not with a thickness fitted again on the longer range (which differs, so the check can tell).
    /// The default range is cut to 10 keV so that the pool's 20 keV axis runs past it. Red before: the refit fitted its own.
    @Test func testTheRangeSensitivityRefitKeepsTheReportedDeadLayer() throws {
        let fit = FitPolicy(defaultUpperLimitKeV: 10, sumPeaks: .off, continuumDeadLayer: .fitted())
        let input = Self.input(policy: QuantificationPolicy(fit: fit))
        let q = try PooledQuantifier.run(input, tables: nil)
        let t = try #require(q.continuumDeadLayerMicrons)
        let to = try #require(FitRangeSensitivityCheck.alternative(for: q))
        let s = try #require(FitRangeSensitivityCheck.run(input: input, quantification: q))
        #expect(s.failure == nil && s.alternativeToKeV == to && !s.moves.isEmpty)

        var pinned = input
        pinned.method.fitToKeV = to
        pinned.refinement = q.refinement
        pinned.sumEscape = SumEscapeModel()
        pinned.policy.fit.continuumDeadLayer = .given(microns: t)
        let expected = try PooledQuantifier.run(pinned, tables: nil)
        var free = pinned
        free.policy.fit.continuumDeadLayer = .fitted()
        let refitted = try #require(try PooledQuantifier.run(free, tables: nil).continuumDeadLayerMicrons)
        Self.note(String(format: "range check: reported %.4f um (to %g keV), fitted again on to %g keV %.4f um", t, q.fitRange.toKeV, to, refitted))
        #expect(abs(refitted - t) > 1e-3, "the longer range must fit another thickness for this test to discriminate")
        for m in s.moves {
            let row = try #require(expected.rows.first { $0.element == m.element })
            #expect(m.after == row.net, "\(m.element): refit \(m.after), with the reported \(t) um \(row.net)")
        }
    }

    @Test func testPolicyRefusesANegativeOrEmptyDeadLayer() {
        #expect(FitPolicy(continuumDeadLayer: .given(microns: -0.1)).problem != nil)
        #expect(FitPolicy(continuumDeadLayer: .fitted(maximumMicrons: 0)).problem != nil)
        #expect(FitPolicy(continuumDeadLayer: .given(microns: 0)).problem == nil)
        #expect(FitPolicy(continuumDeadLayer: .fitted()).problem == nil)
    }
}
