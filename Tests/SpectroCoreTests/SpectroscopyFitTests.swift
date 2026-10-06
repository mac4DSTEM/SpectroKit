import XCTest
import DSTEMCore

/// v5.0 WP3 lane F: the EDX spectrum fit (line model, NNLS least squares, Poisson IRLS, continuum,
/// axis refinement, reference shapes). Pins come from RUNNING eXSpy 7185a4d1 / hyperspy 2.4.0
/// (`Fixtures/eds-fit-exspy-7185a4d1.json`, generator `gen/fit_pins.py` of the lane). Statistical tests use
/// this file's own Poisson synthetic spectra (the simulator's truth comes later); each says so.
final class SpectroscopyFitTests: XCTestCase {

    // MARK: Fixture (JSONDecoder: JSONSerialization parses 17-digit doubles up to 1 ulp off)

    private struct Fixture: Decodable {
        struct Group: Decodable { let name: String; let members: [String]; let energies: [Double]; let fwhm: [Double]; let weights: [Double] }
        struct Case: Decodable {
            let offset: Double, scale: Double, size: Int, binned: Bool
            let resolutionMnKa: Double, beamEnergy: Double
            let elements: [String]
            let data: [Double]
            let channelMask: [Int]
            let groups: [Group]
            let columns: [[Double]]
            let fitted: [String: Double]
            let polyCoeffs: [Double]
            let model: [Double]
            let rss: Double, redChisq: Double
            let pinFe: Double?, pinPt: Double?
            let nnlsRef: [String: Double]?
            let nnlsRefRss: Double?
            let lsRef: [String: Double]?
            let lsRefNegative: [String]?
            var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
        }
        struct NNLSCase: Decodable { let rows: Int, cols: Int; let A: [[Double]]; let y: [Double]; let nnls: [Double]; let lstsq: [Double] }
        let cases: [String: Case]
        let nnlsCases: [NNLSCase]
    }

    private static let fixture: Fixture = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/eds-fit-exspy-7185a4d1.json")
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    /// Measurements for the lane report: appended to $FIT_NOTES (pass TEST_RUNNER_FIT_NOTES=path to xcodebuild).
    private func note(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["FIT_NOTES"] else { return }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close() }
        else { try? (s + "\n").write(toFile: path, atomically: false, encoding: .utf8) }
    }

    private static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("mac4DSTEM/Resources/Spectroscopy")
    /// EPQ's default SDD efficiency (main's lane-K model) on the shipped FFAST table: the continuum's detector model.
    private static let sdd = SDDEfficiency(table: try! MassAbsorptionTable(contentsOf: resources.appendingPathComponent("FFastMAC.csv")))

    /// Lane S's forward model, pooled matrix spectra with Mg planted (tools/edx-pins/weakline_sim.py): EXPECTED counts + truth.
    private struct SimPools: Decodable {
        struct Level: Decodable { let fraction: Double; let expected: [Double]; let mgKa: Double; let alKa: Double; let alTail: Double }
        let offset: Double, scale: Double, size: Int
        let levels: [Level]
        var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    }
    private static let simPools: SimPools = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/eds-weakline-sim.json")
        return try! JSONDecoder().decode(SimPools.self, from: Data(contentsOf: url))
    }()

    // MARK: Random numbers (seeded; the fixtures never depend on a platform RNG)

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

    /// Poisson sample: Knuth below 10, Hoermann's PTRS transformed rejection above (the numpy algorithm).
    private static func poisson(_ lam: Double, _ rng: inout SplitMix64) -> Double {
        if lam <= 0 { return 0 }
        if lam < 10 {
            let l = exp(-lam); var k = 0.0; var p = 1.0
            repeat { k += 1; p *= rng.uniform() } while p > l
            return k - 1
        }
        let slam = lam.squareRoot(), loglam = log(lam)
        let b = 0.931 + 2.53 * slam, a = -0.059 + 0.02483 * b
        let invalpha = 1.1239 + 1.1328 / (b - 3.4), vr = 0.9277 - 3.6224 / (b - 2)
        while true {
            let u = rng.uniform() - 0.5, v = rng.uniform()
            let us = 0.5 - abs(u)
            let k = ((2 * a / us + b) * u + lam + 0.43).rounded(.down)
            if us >= 0.07 && v <= vr { return k }
            if k < 0 || (us < 0.013 && v > us) { continue }
            if log(v) + log(invalpha) - log(a / (us * us) + b) <= -lam + k * loglam - lgamma(k + 1) { return k }
        }
    }

    private static func poissonSpectrum(_ expected: [Double], seed: UInt64) -> [Double] {
        var rng = SplitMix64(state: seed)
        return expected.map { poisson($0, &rng) }
    }

    // MARK: Synthetic physics (independent of the fit's continuum basis)

    /// Continuum with a different functional form from `ContinuumForm`: Kramers x detector roll-off x
    /// Al-matrix absorption with an E^-2.8 MAC that jumps ~x8 at the Al K edge x a 2 % Si K dead-layer step.
    private static func truthContinuum(_ e: Double, beam: Double) -> Double {
        let kramers = (beam - e) / e
        let eff = 1 - exp(-pow(e / 0.5, 2.4))
        let tau = e < 1.5596 ? 0.04 * pow(1.5596 / e, 2.9) : 0.35 * pow(1.5596 / e, 2.7)
        let siStep = e >= 1.839 ? 0.98 : 1.0
        return kramers * eff * exp(-tau) * siStep
    }

    /// Expected counts per channel: line areas (counts) by group id + a scaled truth continuum + optional escape areas.
    private static func expected(
        axis: EnergyAxis, elements: [String], resolution: Double, beam: Double, areas: [String: Double],
        continuumTotal: Double, escapeFraction: Double = 0
    ) -> [Double] {
        let model = EDSLineModel.build(elements: elements, axis: axis, beamEnergy: beam, resolutionMnKaEV: resolution)
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var out = [Double](repeating: 0, count: axis.size)
        for g in model.groups {
            let a = areas[g.id] ?? 0
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in out.indices { out[i] += a * col[i] }
            if escapeFraction > 0, !g.escapes.isEmpty {
                let ec = EDSLineModel.column(of: g.escapes, energies: energies, scale: axis.scale)
                for i in out.indices { out[i] += a * escapeFraction * ec[i] }
            }
        }
        var bg = energies.map { $0 >= 0.2 ? truthContinuum($0, beam: beam) : 0 }
        let sum = bg.reduce(0, +)
        bg = bg.map { $0 / sum * continuumTotal }
        for i in out.indices { out[i] += bg[i] }
        return out
    }

    // MARK: 1. The design reproduces hyperspy's model components

    func testDesignColumnsMatchHyperspy() {
        for (name, c) in Self.fixture.cases {
            let axis = c.axis
            XCTAssertTrue(c.binned, "\(name): the fixture axis is binned, so A is an area in counts")
            let model = EDSLineModel.build(elements: c.elements, axis: axis, beamEnergy: c.beamEnergy,
                                           resolutionMnKaEV: c.resolutionMnKa, escapePeaks: false)
            XCTAssertEqual(model.groups.map(\.id), c.groups.map(\.name).sorted(), "\(name): groups")
            let design = LinearDesign.build(model: model, axis: axis, channels: 0..<axis.size, background: .none)
            for (gi, g) in model.groups.enumerated() {
                let ref = c.groups.first { $0.name == g.id }!
                XCTAssertEqual(g.lines.map(\.id), ref.members, "\(name) \(g.id) members")
                for (k, l) in g.lines.enumerated() {
                    XCTAssertEqual(l.energy, ref.energies[k], accuracy: 1e-12, "\(name) \(l.id) centre")
                    XCTAssertEqual(l.fwhm, ref.fwhm[k], accuracy: 1e-12, "\(name) \(l.id) FWHM")
                    XCTAssertEqual(l.weight, ref.weights[k], accuracy: 1e-12, "\(name) \(l.id) tied weight")
                }
                let refCol = c.columns[c.groups.firstIndex { $0.name == g.id }!]
                let mine = design.areaColumns[gi].values
                let peak = refCol.max()!
                var worst = 0.0
                for i in 0..<axis.size { worst = max(worst, abs(mine[i] - refCol[i])) }
                XCTAssertLessThan(worst / peak, 1e-9, "\(name) \(g.id) column")
            }
        }
    }

    // MARK: 2. Closed loop Fe/Cr/Zn (pin) and the poly-6 path

    private func closedLoop(escape: Bool = false) throws -> EDSFitResult {
        let c = Self.fixture.cases["closedLoop"]!
        let settings = FitSettings(elements: c.elements, resolutionMnKaEV: c.resolutionMnKa, beamEnergy: c.beamEnergy,
                                   background: .polynomial(order: 6), escapePeaks: escape)
        return try EDSFit.run(counts: c.data, axis: c.axis, settings: settings)
    }

    func testClosedLoopRecoversWeightFractions() throws {
        let r = try closedLoop()
        XCTAssertEqual(r.groupIDs, ["Cr_Ka", "Fe_Ka", "Zn_Ka"])
        for (v, expected) in zip(r.values, [0.5, 0.2, 0.3]) {
            XCTAssertEqual(v, expected, accuracy: 1e-4, "closed-loop pin (eXSpy test_edsmodel.py:53-59)")
        }
        let ref = Self.fixture.cases["closedLoop"]!.fitted
        for (id, v) in zip(r.groupIDs, r.values) { XCTAssertEqual(v, ref[id]!, accuracy: 1e-6, "vs eXSpy's own fit \(id)") }
        XCTAssertEqual(r.methodLabel, "least squares, unweighted")
        XCTAssertEqual(r.referenceShapesLabel, "reference shapes: none")
        XCTAssertEqual(r.escapeLabel, "escape peaks: off (eXSpy parity)")
    }

    /// The poly-6 path (Expert, parity) reproduces the whole eXSpy model, not just the areas.
    func testPoly6PathEqualsHyperspyModel() throws {
        let c = Self.fixture.cases["closedLoop"]!
        let r = try closedLoop()
        XCTAssertEqual(r.model.count, c.model.count)
        var worst = 0.0
        for i in r.model.indices { worst = max(worst, abs(r.model[i] - c.model[i])) }
        XCTAssertLessThan(worst, 1e-7, "model equals hyperspy's as_signal() to 1e-7 counts")
        XCTAssertEqual(r.backgroundNames.count, 7)
    }

    /// With escape peaks ON the closed loop still holds (no Si-escape signal in the data: those columns fit ~0).
    func testClosedLoopWithEscapeColumnsStillWithinPin() throws {
        let r = try closedLoop(escape: true)
        for (v, expected) in zip(r.values, [0.5, 0.2, 0.3]) { XCTAssertEqual(v, expected, accuracy: 1e-4) }
        XCTAssertTrue(r.escapeLabel.contains("fitted for 3 line groups"), r.escapeLabel)
    }

    // MARK: 3. FePt least squares (pin, tolerance measured first)

    func testFePtLeastSquaresPins() throws {
        let c = Self.fixture.cases["fept"]!
        let axis = c.axis
        // set_signal_range(5.5, 10.0) is inclusive of the last channel.
        let channels = axis.fitChannels(from: 5.5, to: 10.0)
        XCTAssertEqual(Array(channels), c.channelMask, "hyperspy's channel mask")
        let settings = FitSettings(elements: c.elements, resolutionMnKaEV: c.resolutionMnKa, beamEnergy: c.beamEnergy,
                                   fitFrom: 5.5, fitTo: 10.0, background: .polynomial(order: 6), escapePeaks: false)
        let r = try EDSFit.run(counts: c.data, axis: axis, settings: settings)
        let fe = r.values[r.groupIDs.firstIndex(of: "Fe_Ka")!]
        let pt = r.values[r.groupIDs.firstIndex(of: "Pt_La")!]
        // The pin 2800.0213 / 14921.183 is hyperspy's "lm" stopped 7e-5 / 3e-5 (relative) short of the exact minimum
        // 2800.2296 / 14920.805 (scipy NNLS and lstsq on hyperspy's own columns, fixture). Measured, then asserted:
        // against the pin 2e-4 relative (measured 7.4e-5 and 2.5e-5), against the exact minimiser 1e-6.
        XCTAssertEqual(c.pinFe!, 2800.0213390651193); XCTAssertEqual(c.pinPt!, 14921.182988439612)
        XCTAssertEqual(fe, c.pinFe!, accuracy: 2e-4 * c.pinFe!)
        XCTAssertEqual(pt, c.pinPt!, accuracy: 2e-4 * c.pinPt!)
        XCTAssertEqual(fe, c.nnlsRef!["Fe_Ka"]!, accuracy: 1e-6 * fe)
        XCTAssertEqual(pt, c.nnlsRef!["Pt_La"]!, accuracy: 1e-6 * pt)
        for (id, v) in zip(r.groupIDs, r.values) {
            XCTAssertGreaterThanOrEqual(v, 0, "\(id) area is non-negative")
            if let ref = c.nnlsRef?[id] { XCTAssertEqual(v, ref, accuracy: 1e-4 * max(abs(ref), 1) , id) }
        }
        // Pt_Ma lies 3.5 keV below the range: hyperspy leaves it at its start value; here it is unsupported and reported 0.
        XCTAssertFalse(r.supported[r.groupIDs.firstIndex(of: "Pt_Ma")!])
        // Fit quality: hyperspy's reduced chi-square (RSS / dof, unit variance) with its dof (every free parameter counted).
        XCTAssertEqual(r.degreesOfFreedom, channels.count - 13)
        // hyperspy divides by (n - p - 1) (model.py:1723), this fit by (n - p): same RSS, so rescale to compare.
        let hyperspyStyle = r.reducedChiSquared * Double(r.degreesOfFreedom) / Double(r.degreesOfFreedom - 1)
        XCTAssertEqual(hyperspyStyle, c.redChisq, accuracy: 1e-5 * c.redChisq)
        XCTAssertLessThanOrEqual(r.residual.reduce(0) { $0 + $1 * $1 }, c.rss * (1 + 1e-9), "never worse than hyperspy's RSS")
    }

    // MARK: 4. NNLS against scipy, on cases where the unbounded solution has negative entries

    func testNNLSMatchesScipyAndDiffersFromUnbounded() {
        for (k, c) in Self.fixture.nnlsCases.enumerated() {
            let a = ColumnMatrix(columns: c.A)
            let s = LeastSquaresFit.solve(nonNegative: a, y: c.y)
            for j in 0..<c.cols {
                XCTAssertEqual(s.nonNegative[j], c.nnls[j], accuracy: 1e-8, "case \(k) x[\(j)]")
                XCTAssertGreaterThanOrEqual(s.nonNegative[j], 0)
            }
            XCTAssertTrue(c.lstsq.contains { $0 < 0 }, "case \(k): the unbounded solution is negative somewhere")
            XCTAssertTrue(s.nonNegative.contains(0), "case \(k): a constraint is active")
        }
    }

    /// Free-sign columns are eliminated exactly: same minimiser as scipy's NNLS on a (+F, -F) split.
    func testFreeColumnsAreExactlyEliminated() {
        let c = Self.fixture.nnlsCases[0]
        // Treat the first column as free: compare with scipy-free reference solved here by brute force over the passive sets.
        let all = ColumnMatrix(columns: c.A)
        let free = all.selecting([0])
        let nn = all.selecting(Array(1..<c.cols))
        let s = LeastSquaresFit.solve(nonNegative: nn, free: free, y: c.y)
        // Optimality: gradient of the residual at the solution.
        var r = c.y
        let fit = nn.times(s.nonNegative); let f = free.times(s.free)
        for i in r.indices { r[i] -= fit[i] + f[i] }
        XCTAssertEqual(free.transposeTimes(r)[0], 0, accuracy: 1e-9, "free column: zero gradient")
        for (j, g) in nn.transposeTimes(r).enumerated() {
            if s.nonNegative[j] > 0 { XCTAssertEqual(g, 0, accuracy: 1e-8, "passive column \(j)") }
            else { XCTAssertLessThanOrEqual(g, 1e-8, "active column \(j): KKT") }
        }
    }

    // MARK: 5. Poisson IRLS

    /// A Fe/Cu spectrum at modest counts, Poisson noise from this file's seeded generator (NOT the simulator).
    private func irlsSpectrum(seed: UInt64) -> (axis: EnergyAxis, counts: [Double], settings: FitSettings) {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1000)
        let e = Self.expected(axis: axis, elements: ["Fe", "Cu"], resolution: 130, beam: 200,
                              areas: ["Fe_Ka": 1500, "Cu_Ka": 900], continuumTotal: 30000, escapeFraction: 0)
        let settings = FitSettings(elements: ["Fe", "Cu"], resolutionMnKaEV: 130, beamEnergy: 200,
                                   fitFrom: 5.0, fitTo: 9.5, background: .polynomial(order: 3), escapePeaks: false,
                                   method: .poissonML(IRLSSettings()))
        return (axis, Self.poissonSpectrum(e, seed: seed), settings)
    }

    func testIRLSDevianceNonIncreasingConvergesAndSatisfiesKKT() throws {
        let (axis, counts, settings) = irlsSpectrum(seed: 11)
        let r = try EDSFit.run(counts: counts, axis: axis, settings: settings)
        XCTAssertTrue(r.converged)
        XCTAssertLessThan(r.iterations, settings.method == .poissonML(IRLSSettings()) ? 200 : 0, "converges inside the cap")
        for k in 1..<r.devianceHistory.count {
            XCTAssertLessThanOrEqual(r.devianceHistory[k], r.devianceHistory[k - 1], "iteration \(k)")
        }
        XCTAssertEqual(r.irls, IRLSSettings(), "cap and tolerance are recorded")
        XCTAssertTrue(r.methodLabel.contains("cap 200"))
        // KKT of the Poisson likelihood, from first principles (independent of the IRLS weights):
        // g_j = sum_i D_ij (1 - y_i / mu_i) is 0 for a positive area and a free column, >= 0 at an active bound.
        let model = EDSLineModel.build(elements: ["Fe", "Cu"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: false)
        let d = LinearDesign.build(model: model, axis: axis, channels: r.channels, background: .polynomial(order: 3))
        let y = r.channels.map { counts[$0] }
        let w = zip(y, r.model).map { 1 - $0 / max($1, 1e-6) }
        var cols = d.areaColumns.map(\.values)
        cols.append(contentsOf: d.backgroundColumns.map(\.values))
        var worst = 0.0
        var checked = 0
        for (j, col) in cols.enumerated() {
            let norm = col.reduce(0) { $0 + abs($1) }
            if norm == 0 { continue }          // unsupported line: not in the fit
            let g = zip(col, w).reduce(0) { $0 + $1.0 * $1.1 }
            checked += 1
            if j < d.areaColumns.count, r.values[j] == 0 { XCTAssertGreaterThanOrEqual(g / norm, -1e-6) }
            else { worst = max(worst, abs(g) / norm) }
        }
        XCTAssertGreaterThanOrEqual(checked, 4)
        XCTAssertLessThan(worst, 1e-5, "Poisson score equations hold; measured value recorded in the report")
        note("IRLS KKT worst |g|/|col|_1 = \(worst), iterations \(r.iterations), deviance \(r.deviance), history \(r.devianceHistory.count)")
    }

    /// Low counts, where an undamped Fisher step can overshoot: 200 single pixels at ~10 counts, every deviance history non-increasing.
    /// With a non-negative model (lines only) every pixel ends converged or at a KKT-checked stationary point; with a SIGNED linear
    /// background many pixels reach a model below zero, where the clamped deviance has no maximum: those must say "stalled", not "converged".
    func testIRLSDevianceNonIncreasingOnLowCountPixels() throws {
        let axis = EnergyAxis(offset: 0.9, scale: 0.01, size: 100)
        let els = ["Mg", "Al"]
        let model = EDSLineModel.build(elements: els, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: false)
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        let mg = EDSLineModel.column(of: model.groups.first { $0.id == "Mg_Ka" }!.lines, energies: energies, scale: axis.scale)
        let al = EDSLineModel.column(of: model.groups.first { $0.id == "Al_Ka" }!.lines, energies: energies, scale: axis.scale)
        for (bgName, bg, bgTotal) in [("lines only", FitBackground.none, 0.0), ("signed linear", .polynomial(order: 1), 3.0)] {
            let expected = (0..<axis.size).map { 3 * mg[$0] + 4 * al[$0] + bgTotal / Double(axis.size) }
            let design = LinearDesign.build(model: model, axis: axis, channels: 0..<axis.size, background: bg)
            let settings = FitSettings(elements: els, resolutionMnKaEV: 130, beamEnergy: 200, background: bg,
                                       escapePeaks: false, method: .poissonML(IRLSSettings()))
            var rng = SplitMix64(state: 5)
            var increases = 0, steps = 0, stalled = 0, stalledWithNegativeModel = 0, inconsistent = 0
            for _ in 0..<200 {
                let counts = expected.map { Self.poisson($0, &rng) }
                let r = EDSFit.fit(design: design, model: model, counts: counts, settings: settings, computeCovariance: false)
                for k in 1..<r.devianceHistory.count { steps += 1; if r.devianceHistory[k] > r.devianceHistory[k - 1] { increases += 1 } }
                if r.exit.hasPrefix("stalled") { stalled += 1; if r.negativeModelChannels > 0 { stalledWithNegativeModel += 1 } }
                if r.converged != (r.exit == "converged" || r.exit.hasPrefix("stationary")) { inconsistent += 1 }
            }
            note("IRLS low-count (\(bgName)): \(steps) steps over 200 pixels, deviance increases \(increases), stalled \(stalled) (\(stalledWithNegativeModel) with a negative model)")
            XCTAssertEqual(increases, 0, bgName)
            XCTAssertEqual(inconsistent, 0, bgName)
            if bg == .none { XCTAssertEqual(stalled, 0, "a non-negative model always ends at a maximum") }
            else {
                XCTAssertGreaterThan(stalled, 0, "the signed background does reach a negative model, and says so")
                XCTAssertEqual(stalled, stalledWithNegativeModel, "every stall is a negative-model stall")
            }
        }
    }

    func testPoissonDevianceKnownValues() {
        // y = 0: 2 mu; y = mu: 0; y = 4, mu = 2: 2 (4 ln 2 - 2).
        XCTAssertEqual(PoissonMLFit.deviance(y: [0, 3, 4], mu: [1.5, 3, 2], floor: 1e-6), 2 * 1.5 + 0 + 2 * (4 * log(2.0) - 2), accuracy: 1e-12)
        // A model clamped at the floor stays finite.
        XCTAssertTrue(PoissonMLFit.deviance(y: [5], mu: [0], floor: 1e-6).isFinite)
    }

    // MARK: 6. Covariance (Monte Carlo, own Poisson synthetic data)

    func testCovarianceMatchesRepeatedFits() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1000)
        let truth = Self.expected(axis: axis, elements: ["Fe", "Cu"], resolution: 130, beam: 200,
                                  areas: ["Fe_Ka": 1500, "Cu_Ka": 900], continuumTotal: 30000)
        func settings(_ m: FitMethod) -> FitSettings {
            FitSettings(elements: ["Fe", "Cu"], resolutionMnKaEV: 130, beamEnergy: 200, fitFrom: 5.0, fitTo: 9.5,
                        background: .polynomial(order: 3), escapePeaks: false, method: m)
        }
        for method in [FitMethod.leastSquares, .poissonML(IRLSSettings())] {
            var fe: [Double] = [], cu: [Double] = []
            var predicted = 0.0, predictedCu = 0.0
            let iFe = EDSLineModel.build(elements: ["Fe", "Cu"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: false).groups.firstIndex { $0.id == "Fe_Ka" }!
            let iCu = EDSLineModel.build(elements: ["Fe", "Cu"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: false).groups.firstIndex { $0.id == "Cu_Ka" }!
            for rep in 0..<300 {
                let counts = Self.poissonSpectrum(truth, seed: UInt64(1000 + rep))
                let r = try EDSFit.run(counts: counts, axis: axis, settings: settings(method), computeCovariance: rep == 0)
                fe.append(r.values[iFe]); cu.append(r.values[iCu])
                if rep == 0 { predicted = r.sigma(at: iFe); predictedCu = r.sigma(at: iCu) }
            }
            func sd(_ v: [Double]) -> Double { let m = v.reduce(0, +) / Double(v.count); return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1)).squareRoot() }
            // Predicted sigma of ONE realisation uses its own mu; empirical over 300 has ~4 % relative error.
            XCTAssertEqual(predicted / sd(fe), 1, accuracy: 0.15, "\(method) Fe Ka sigma: predicted \(predicted) empirical \(sd(fe))")
            XCTAssertEqual(predictedCu / sd(cu), 1, accuracy: 0.15, "\(method) Cu Ka sigma")
        }
    }

    // MARK: 7. Continuum (F3), on a physically generated Al-matrix spectrum

    func testContinuumAlEdgeResidualIsFlat() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let areas = ["Al_Ka": 300_000.0, "Mg_Ka": 30_000, "Si_Ka": 20_000, "Cu_Ka": 40_000]
        let e = Self.expected(axis: axis, elements: ["Mg", "Al", "Si", "Cu"], resolution: 130, beam: 200, areas: areas,
                              continuumTotal: 400_000, escapeFraction: 0.01)
        let counts = Self.poissonSpectrum(e, seed: 3)
        XCTAssertGreaterThan(counts.reduce(0, +), 5e5)
        let settings = FitSettings.standard(elements: ["Mg", "Al", "Si", "Cu"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        let r = try EDSFit.run(counts: counts, axis: axis, settings: settings)
        var band: [Double] = []
        for (k, c) in r.channels.enumerated() {
            let en = axis.energy(ofChannel: c)
            if en >= 1.1 && en <= 1.9 { band.append(r.standardizedResidual[k]) }
        }
        XCTAssertGreaterThan(band.count, 70)
        let worst = band.map(abs).max()!
        let mean = band.reduce(0, +) / Double(band.count)
        note("F3 seed 3: band channels \(band.count), max |r| \(worst), mean r \(mean), Pearson reduced chi2 \(r.pearsonReducedChiSquared)")
        XCTAssertLessThanOrEqual(worst, 3, "every standardized residual in 1.1-1.9 keV within +-3")
        XCTAssertLessThanOrEqual(abs(mean), 1, "band mean")
        XCTAssertEqual(r.negativeModelChannels, 0)
        XCTAssertEqual(r.backgroundCoefficients.count, 16)
        XCTAssertTrue(r.backgroundCoefficients.allSatisfy { $0 >= 0 }, "non-negative Bernstein continuum")
        // The fitted Al area recovers truth within a few sigma.
        let iMg = r.groupIDs.firstIndex(of: "Mg_Ka")!
        XCTAssertEqual(r.values[iMg], 30_000, accuracy: 3 * r.sigma(at: iMg), "the planted Mg Ka is recovered within 3 sigma")
        let al = r.values[r.groupIDs.firstIndex(of: "Al_Ka")!]
        XCTAssertEqual(al, 300_000, accuracy: 5 * r.sigma(at: r.groupIDs.firstIndex(of: "Al_Ka")!) + 3000)
    }

    /// "All |r| <= 3 over ~80 channels" fails about 20 % of the time for a PERFECT model (0.9973^80 = 0.81), so the
    /// criterion is also measured across seeds against the true expectation. Own Poisson synthetic data.
    func testContinuumResidualAcrossSeedsMatchesPerfectModel() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let els = ["Mg", "Al", "Si", "Cu"]
        let e = Self.expected(axis: axis, elements: els, resolution: 130, beam: 200,
                              areas: ["Al_Ka": 300_000, "Mg_Ka": 30_000, "Si_Ka": 20_000, "Cu_Ka": 40_000],
                              continuumTotal: 400_000, escapeFraction: 0.01)
        let settings = FitSettings.standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        let seeds = 20
        var fitPass = 0, perfectPass = 0, worstMean = 0.0
        var maxima: [Double] = []
        for s in 0..<seeds {
            let counts = Self.poissonSpectrum(e, seed: UInt64(100 + s))
            let r = try EDSFit.run(counts: counts, axis: axis, settings: settings, computeCovariance: false)
            var fitBand: [Double] = [], truthBand: [Double] = []
            for (k, c) in r.channels.enumerated() {
                let en = axis.energy(ofChannel: c)
                guard en >= 1.1 && en <= 1.9 else { continue }
                fitBand.append(r.standardizedResidual[k])
                truthBand.append((counts[c] - e[c]) / max(e[c], 1).squareRoot())
            }
            let m = fitBand.map(abs).max()!
            maxima.append(m)
            if m <= 3 { fitPass += 1 }
            if truthBand.map(abs).max()! <= 3 { perfectPass += 1 }
            worstMean = max(worstMean, abs(fitBand.reduce(0, +) / Double(fitBand.count)))
        }
        note("F3 across \(seeds) seeds: fit passes max|r|<=3 in \(fitPass), perfect model in \(perfectPass); worst band |mean r| \(worstMean); max|r| per seed \(maxima.map { String(format: "%.2f", $0) })")
        XCTAssertLessThanOrEqual(worstMean, 1, "band mean |r| <= 1 in every seed")
        XCTAssertGreaterThanOrEqual(fitPass, perfectPass - 4, "the fit's residual is as flat as the true model's, within binomial scatter")
    }

    /// A polynomial that cannot step is visibly worse at the Al edge than the continuum with the step:
    /// the edge matters (otherwise the step in the default would be decoration).
    func testContinuumStepBeatsPlainPolynomialAtTheEdge() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let e = Self.expected(axis: axis, elements: ["Mg", "Al", "Si", "Cu"], resolution: 130, beam: 200,
                              areas: ["Al_Ka": 300_000, "Mg_Ka": 30_000, "Si_Ka": 20_000, "Cu_Ka": 40_000],
                              continuumTotal: 400_000, escapeFraction: 0.01)
        let counts = Self.poissonSpectrum(e, seed: 3)
        let els = ["Mg", "Al", "Si", "Cu"]
        let withStep = try EDSFit.run(counts: counts, axis: axis, settings: .standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200))
        var noStep = FitSettings.standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        noStep.background = .continuum(ContinuumForm(beamEnergy: 200, edges: [], orders: [9]))
        let plain = try EDSFit.run(counts: counts, axis: axis, settings: noStep)
        note("Pearson reduced chi2 with Al step \(withStep.pearsonReducedChiSquared), without \(plain.pearsonReducedChiSquared)")
        XCTAssertLessThan(withStep.pearsonReducedChiSquared, plain.pearsonReducedChiSquared)
        // The step belongs AT the Al K edge: the same form with the edge moved to 1.7 keV fits worse.
        XCTAssertEqual(ContinuumForm.alKEdge, 1.5596)
        var moved = FitSettings.standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        moved.background = .continuum(ContinuumForm(beamEnergy: 200, edges: [1.7], orders: [9, 5]))
        let misplaced = try EDSFit.run(counts: counts, axis: axis, settings: moved)
        note("Pearson reduced chi2 edge at 1.5596 \(withStep.pearsonReducedChiSquared), edge at 1.7 \(misplaced.pearsonReducedChiSquared)")
        XCTAssertLessThan(withStep.pearsonReducedChiSquared, misplaced.pearsonReducedChiSquared)
    }

    func testStandardizedResidualStaysFiniteWhereModelIsZero() throws {
        let c = Self.fixture.cases["closedLoop"]!
        var settings = FitSettings(elements: c.elements, resolutionMnKaEV: c.resolutionMnKa, beamEnergy: c.beamEnergy,
                                   background: .none, escapePeaks: false)
        settings.background = .none
        let r = try EDSFit.run(counts: c.data, axis: c.axis, settings: settings)
        XCTAssertTrue(r.standardizedResidual.allSatisfy { $0.isFinite })
        XCTAssertTrue(r.model.contains { $0 < 1e-9 }, "the lines-only model reaches zero far from a line")
        // With model 0 and data 0.002 the floor 1.0 makes r = data - model.
        let i = r.model.firstIndex { $0 < 1e-12 }!
        XCTAssertEqual(r.standardizedResidual[i], r.residual[i] / EDSFitResult.standardizedFloor.squareRoot(), accuracy: 1e-12)
    }

    // MARK: 8. Axis refinement (F4), own Poisson synthetic data

    func testAxisRefinementRecoversPlantedOffsetAndGain() throws {
        let trueAxis = EnergyAxis(offset: 0.003, scale: 0.01, size: 1024)
        let els = ["Mg", "Al", "Si", "K", "Fe", "Cu"]
        let areas = ["Mg_Ka": 12_000.0, "Al_Ka": 20_000, "Si_Ka": 15_000, "K_Ka": 8_000, "Fe_Ka": 18_000, "Cu_Ka": 20_000]
        let e = Self.expected(axis: trueAxis, elements: els, resolution: 129, beam: 200, areas: areas, continuumTotal: 120_000)
        let counts = Self.poissonSpectrum(e, seed: 5)
        let total = counts.reduce(0, +)
        XCTAssertGreaterThan(total, 1e5)
        // The FILE axis is wrong: offset 10 eV too low, gain 0.2 % too high; resolution 8 eV off.
        let fileAxis = EnergyAxis(offset: trueAxis.offset - 0.010, scale: trueAxis.scale * 1.002, size: 1024)
        let settings = FitSettings.standard(elements: els, axis: fileAxis, resolutionMnKaEV: 137, beamEnergy: 200)
        let r = try EnergyAxisRefinement.refine(counts: counts, fileAxis: fileAxis, fileResolutionMnKaEV: 137, settings: settings)
        note("F4: total counts \(total), offset err eV \((r.offset - trueAxis.offset) * 1000), gain err % \((r.scale / trueAxis.scale - 1) * 100), R \(r.resolutionMnKaEV), iterations \(r.iterations), converged \(r.converged), rss \(r.rssFile) -> \(r.rssRefined)")
        XCTAssertLessThan(abs(r.offset - trueAxis.offset) * 1000, 1.0, "offset within 1 eV")
        XCTAssertLessThan(abs(r.scale / trueAxis.scale - 1) * 100, 0.05, "gain within 0.05 %")
        XCTAssertEqual(r.resolutionMnKaEV, 129, accuracy: 3)
        XCTAssertLessThan(r.rssRefined, r.rssFile)
        // The file's values stay beside the refined ones.
        XCTAssertEqual(r.fileOffset, fileAxis.offset); XCTAssertEqual(r.fileScale, fileAxis.scale)
        XCTAssertEqual(r.fileResolutionMnKaEV, 137)
        XCTAssertEqual(r.offsetShiftEV, 10, accuracy: 1.0)
        XCTAssertEqual(r.gainShift, 1 / 1.002 - 1, accuracy: 5e-4)
    }

    // MARK: 9. Escape peaks and reference shapes

    func testEscapePeaksAreFittedAndMgAlSiHaveNone() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let els = ["Mg", "Al", "Si", "K", "Fe", "Cu"]
        let model = EDSLineModel.build(elements: els, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130)
        XCTAssertEqual(EDSLineModel.siKEdge, 1.839, "the Si K edge, keV")
        for g in model.groups {
            let above = g.lines.contains { $0.energy > 1.839 }
            XCTAssertEqual(!g.escapes.isEmpty, above, "\(g.id)")
        }
        // K K-alpha (3.31 keV) is above the edge but below 5 keV: its escape peak sits at 3.31 - 1.74 keV.
        let kEsc = model.groups.first { $0.id == "K_Ka" }!.escapes.first!
        XCTAssertEqual(kEsc.energy, XRayLines.line("K_Ka")!.energy - XRayLines.line("Si_Ka")!.energy, accuracy: 1e-12)
        XCTAssertTrue(model.groups.first { $0.id == "Mg_Ka" }!.escapes.isEmpty)
        XCTAssertTrue(model.groups.first { $0.id == "Al_Ka" }!.escapes.isEmpty)
        XCTAssertTrue(model.groups.first { $0.id == "Si_Ka" }!.escapes.isEmpty)
        // Planted 2 % Fe and Cu escape: recovered; with escapes off the reduced chi2 is worse.
        let areas = ["Fe_Ka": 80_000.0, "Cu_Ka": 60_000, "Al_Ka": 100_000, "Mg_Ka": 10_000, "Si_Ka": 10_000, "K_Ka": 20_000]
        let e = Self.expected(axis: axis, elements: els, resolution: 130, beam: 200, areas: areas, continuumTotal: 100_000, escapeFraction: 0.02)
        let counts = Self.poissonSpectrum(e, seed: 9)
        var s = FitSettings.standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        let on = try EDSFit.run(counts: counts, axis: axis, settings: s)
        s.escapePeaks = false
        let off = try EDSFit.run(counts: counts, axis: axis, settings: s)
        let iFe = on.groupIDs.firstIndex(of: "Fe_Ka")!
        XCTAssertEqual(on.escapeValues[iFe]!, 0.02 * 80_000, accuracy: 0.2 * 0.02 * 80_000)
        XCTAssertNil(on.escapeValues[on.groupIDs.firstIndex(of: "Al_Ka")!])
        XCTAssertLessThan(on.pearsonReducedChiSquared, off.pearsonReducedChiSquared)
        XCTAssertTrue(on.escapeLabel.contains("above the Si K edge"))
    }

    func testReferenceShapeSlotIsEmptyByDefaultAndTiesWork() throws {
        XCTAssertEqual(ReferenceShapes.none.label, "reference shapes: none")
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 600)
        let els = ["Mg", "Al"]
        let model = EDSLineModel.build(elements: els, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130)
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        // A tail profile: exponential below Al Ka, unit sum (what a pure-Al measurement would give).
        var tail = energies.map { $0 < 1.4865 && $0 > 0.3 ? exp(-(1.4865 - $0) / 0.4) : 0 }
        let ts = tail.reduce(0, +); tail = tail.map { $0 / ts }
        let f = 0.04
        let alCol = EDSLineModel.column(of: model.groups.first { $0.id == "Al_Ka" }!.lines, energies: energies, scale: axis.scale)
        let mgCol = EDSLineModel.column(of: model.groups.first { $0.id == "Mg_Ka" }!.lines, energies: energies, scale: axis.scale)
        // Planted: Al 200 000, Mg 8 000, tail f * Al, a flat-ish continuum.
        var e = (0..<axis.size).map { 200_000 * alCol[$0] + 8_000 * mgCol[$0] + 200_000 * f * tail[$0] }
        let bg = energies.map { $0 >= 0.2 ? 60.0 : 0 }
        for i in e.indices { e[i] += bg[i] }
        let counts = Self.poissonSpectrum(e, seed: 21)
        var base = FitSettings(elements: els, resolutionMnKaEV: 130, beamEnergy: 200, fitFrom: 0.5, fitTo: 3.0,
                               background: .polynomial(order: 1), escapePeaks: false)
        let without = try EDSFit.run(counts: counts, axis: axis, settings: base)
        base.referenceShapes = ReferenceShapes([ReferenceShape(name: "Al Ka tail", profile: tail, tie: .lineAmplitude(group: "Al_Ka", fraction: f))])
        let with = try EDSFit.run(counts: counts, axis: axis, settings: base)
        XCTAssertEqual(with.referenceShapesLabel, "reference shapes: Al Ka tail")
        let iMg = with.groupIDs.firstIndex(of: "Mg_Ka")!
        let errWith = abs(with.values[iMg] - 8_000), errWithout = abs(without.values[iMg] - 8_000)
        note("tail tie: Mg error with \(errWith) without \(errWithout), Pearson chi2 \(with.pearsonReducedChiSquared) vs \(without.pearsonReducedChiSquared)")
        XCTAssertLessThan(with.pearsonReducedChiSquared, without.pearsonReducedChiSquared)
        XCTAssertLessThan(errWith, errWithout)

        // Si fluorescence: tied to the counts above 1.84 keV, a known term (not a column).
        let siProfile: [Double] = {
            var p = energies.map { abs($0 - 1.74) < 0.15 ? exp(-pow($0 - 1.74, 2) / (2 * 0.055 * 0.055)) : 0 }
            let s = p.reduce(0, +); p = p.map { $0 / s }; return p
        }()
        let c0 = 0.1
        var e2 = e
        let aboveEdge = e2.indices.filter { energies[$0] >= 1.84 }.reduce(0.0) { $0 + e2[$1] }
        for i in e2.indices { e2[i] += c0 * aboveEdge * siProfile[i] }
        let counts2 = Self.poissonSpectrum(e2, seed: 22)
        // `base` still carries the tail tie; compare the model with and without the Si-fluorescence tie on top of it.
        let tailOnly = try EDSFit.run(counts: counts2, axis: axis, settings: base)
        var s2 = base
        s2.referenceShapes = ReferenceShapes(base.referenceShapes.shapes + [
            ReferenceShape(name: "Si fluorescence", profile: siProfile, tie: .countsAboveEdge(edge: 1.84, fractionPerCount: c0))])
        let both = try EDSFit.run(counts: counts2, axis: axis, settings: s2)
        note("Si tie: Pearson chi2 tail only \(tailOnly.pearsonReducedChiSquared), tail + Si fluorescence \(both.pearsonReducedChiSquared)")
        XCTAssertLessThan(both.pearsonReducedChiSquared, tailOnly.pearsonReducedChiSquared)
        XCTAssertEqual(both.referenceShapesLabel, "reference shapes: Al Ka tail, Si fluorescence")
    }

    // MARK: 10. F2: ML versus LS bias at ~10 counts per pixel (own Poisson synthetic pixels, NOT the simulator)

    /// 1e4 single pixels at ~10 counts per pixel in 0.9-1.9 keV. Variant A: lines only (Mg Ka 4, Al Ka 6 counts/px)
    /// and a lines-only fit. Variant B: Mg Ka 3, Al Ka 4, a flat background of 3 counts/px and a linear background in the fit.
    func testMaximumLikelihoodBiasVersusLeastSquaresAtLowCounts() throws {
        let axis = EnergyAxis(offset: 0.9, scale: 0.01, size: 100)
        let els = ["Mg", "Al"]
        let model = EDSLineModel.build(elements: els, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: false)
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        let mg = EDSLineModel.column(of: model.groups.first { $0.id == "Mg_Ka" }!.lines, energies: energies, scale: axis.scale)
        let al = EDSLineModel.column(of: model.groups.first { $0.id == "Al_Ka" }!.lines, energies: energies, scale: axis.scale)
        let iMg = model.groups.firstIndex { $0.id == "Mg_Ka" }!
        let pixels = 10_000
        for (variant, mgArea, alArea, bgTotal, bgKind) in [("A lines only", 4.0, 6.0, 0.0, FitBackground.none),
                                                           ("B with background", 3.0, 4.0, 3.0, .polynomial(order: 1))] {
            let expected = (0..<axis.size).map { mgArea * mg[$0] + alArea * al[$0] + bgTotal / Double(axis.size) }
            var base = FitSettings(elements: els, resolutionMnKaEV: 130, beamEnergy: 200, background: bgKind, escapePeaks: false)
            let design = LinearDesign.build(model: model, axis: axis, channels: 0..<axis.size, background: bgKind)
            var ls: [Double] = [], ml: [Double] = []
            var stalledPixels = 0
            var rng = SplitMix64(state: 77)
            for _ in 0..<pixels {
                let counts = expected.map { Self.poisson($0, &rng) }
                base.method = .leastSquares
                ls.append(EDSFit.fit(design: design, model: model, counts: counts, settings: base, computeCovariance: false).values[iMg])
                base.method = .poissonML(IRLSSettings())
                let mlFit = EDSFit.fit(design: design, model: model, counts: counts, settings: base, computeCovariance: false)
                if mlFit.converged { ml.append(mlFit.values[iMg]) } else { stalledPixels += 1 }
            }
            func stats(_ v: [Double]) -> (bias: Double, se: Double, sd: Double) {
                let m = v.reduce(0, +) / Double(v.count)
                let sd = (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1)).squareRoot()
                return (m - mgArea, sd / Double(v.count).squareRoot(), sd)
            }
            let l = stats(ls), m = stats(ml)
            note("F2 \(variant): truth Mg \(mgArea)/px; LS bias \(l.bias) (se \(l.se), sd \(l.sd)); ML bias \(m.bias) (se \(m.se), sd \(m.sd)); ML on \(ml.count) converged pixels, \(stalledPixels) stalled (signed background, negative model); LS on all \(ls.count)")
            XCTAssertTrue(l.bias.isFinite && m.bias.isFinite)
            // Variant B's ML subset (converged pixels only, ~49 %) is a selected subset and reads -0.077 (2.9 se): not an
            // unbiased sample, so only variant A (0 stalled) asserts the ML bias.
            if stalledPixels == 0 { XCTAssertLessThan(abs(m.bias), 2 * m.se, "\(variant): ML bias within 2 se of zero") }
            else { XCTAssertGreaterThan(stalledPixels, 1000, "signed background: many ML fits stall at a negative model") }
        }
    }

    // MARK: 11. Round 2: weak-line recovery on two generators, the registered selection, the tail finding

    /// One (form, generator) cell: Mg fitted over `seeds` Poisson draws of each level's expected spectrum.
    private struct Cell { var bias: Double; var se: Double; var sigma: Double }
    private func weakLine(settings: FitSettings, axis: EnergyAxis, expected: [[Double]], truth: [Double], seeds: Int) throws -> [Cell] {
        let iMg = EDSLineModel.build(elements: settings.elements, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130)
            .groups.firstIndex { $0.id == "Mg_Ka" }!
        var out: [Cell] = []
        for (li, e) in expected.enumerated() {
            var vals: [Double] = [], sig = 0.0
            for k in 0..<seeds {
                let c = Self.poissonSpectrum(e, seed: UInt64(7000 + 1000 * li + k))
                let r = try EDSFit.run(counts: c, axis: axis, settings: settings)
                vals.append(r.values[iMg]); sig += r.sigma(at: iMg) / Double(seeds)
            }
            let m = vals.reduce(0, +) / Double(seeds)
            let sd = (vals.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(seeds - 1)).squareRoot()
            out.append(Cell(bias: m - truth[li], se: sd / Double(seeds).squareRoot(), sigma: sig))
        }
        return out
    }

    private static let weakFractions = [0.0, 0.001, 0.003, 0.01, 0.1]

    private func weakLineTable(orders: [Int], efficiency: Bool) throws -> (a: [Cell], s: [Cell]) {
        let axisA = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let elA = ["Mg", "Al", "Si", "Cu"]
        let expA = Self.weakFractions.map { fr in
            Self.expected(axis: axisA, elements: elA, resolution: 130, beam: 200,
                          areas: ["Al_Ka": 300_000, "Mg_Ka": 300_000 * fr, "Si_Ka": 20_000, "Cu_Ka": 40_000],
                          continuumTotal: 400_000, escapeFraction: 0.01)
        }
        var sA = FitSettings.standard(elements: elA, axis: axisA, resolutionMnKaEV: 130, beamEnergy: 200)
        sA.background = .continuum(ContinuumForm(beamEnergy: 200, orders: orders, efficiency: efficiency ? Self.sdd : nil))
        let a = try weakLine(settings: sA, axis: axisA, expected: expA, truth: Self.weakFractions.map { 300_000 * $0 }, seeds: 30)
        let axisS = Self.simPools.axis
        let elS = ["Mg", "Al", "Si", "Cu", "O"]
        var sS = FitSettings.standard(elements: elS, axis: axisS, resolutionMnKaEV: 130, beamEnergy: 200)
        sS.background = .continuum(ContinuumForm(beamEnergy: 200, orders: orders, efficiency: efficiency ? Self.sdd : nil))
        let s = try weakLine(settings: sS, axis: axisS, expected: Self.simPools.levels.map(\.expected),
                             truth: Self.simPools.levels.map(\.mgKa), seeds: 30)
        return (a, s)
    }

    /// The registered criterion (docs: report2.md, written before the runs). Gate 1: no false positive at Mg = 0
    /// (mean <= 0.399 sigma_sandwich + 1 se: NNLS clamps, so an unbiased estimator has mean +0.399 sigma);
    /// selection: smallest max |bias| at 0.3 % and 1 % over both generators; if not <= 1 se at 0.3 % on both, badge.
    func testWeakLineRecoveryRegisteredSelection() throws {
        struct Form { let name: String; let orders: [Int]; let eps: Bool }
        let forms = [Form(name: "kramers (9,5)", orders: [9, 5], eps: false), Form(name: "eps (3,3)", orders: [3, 3], eps: true),
                     Form(name: "eps (4,3)", orders: [4, 3], eps: true), Form(name: "eps (9,5)", orders: [9, 5], eps: true)]
        var scores: [(name: String, score: Double, se: Double, passesGate: Bool)] = []
        var chosen: (a: [Cell], s: [Cell])?
        for f in forms {
            let t = try weakLineTable(orders: f.orders, efficiency: f.eps)
            let gate = [t.a[0], t.s[0]].allSatisfy { $0.bias <= 0.399 * $0.sigma + $0.se }
            let score = [t.a[2], t.a[3], t.s[2], t.s[3]].map { abs($0.bias) }.max()!
            scores.append((f.name, score, [t.a[2], t.a[3], t.s[2], t.s[3]].map(\.se).max()!, gate))
            note("weak-line \(f.name): gate \(gate) score \(score); A " + t.a.map { String(format: "%+.0f±%.0f", $0.bias, $0.se) }.joined(separator: " ")
                 + " | S " + t.s.map { String(format: "%+.0f±%.0f", $0.bias, $0.se) }.joined(separator: " "))
            if f.name == "kramers (9,5)" { chosen = t }
        }
        let winner = scores.filter(\.passesGate).min { $0.score < $1.score }!
        // The rule has no tie clause: the default (Kramers-only, no filler) must be within 1 se of the minimum score.
        let def = scores.first { $0.name == "kramers (9,5)" }!
        XCTAssertTrue(def.passesGate)
        XCTAssertLessThanOrEqual(def.score, winner.score + def.se, "default \(def.score) vs best \(winner.name) \(winner.score), se \(def.se)")
        // Criterion 3: not <= 1 se at 0.3 % on both generators, so the badge must exist and carry the measured numbers.
        let c = chosen!
        XCTAssertGreaterThan(abs(c.a[2].bias), c.a[2].se, "generator A: bias at 0.3 % exceeds 1 se")
        XCTAssertGreaterThan(abs(c.s[2].bias), c.s[2].se, "generator S: bias at 0.3 % exceeds 1 se")
        // The measured band the badge quotes (counts): a deficit of 150-450 on both generators at 0.3 % and 1 %.
        for cell in [c.a[2], c.a[3], c.s[2], c.s[3]] { XCTAssertTrue((-450 ... -150).contains(cell.bias), "bias \(cell.bias)") }
        XCTAssertTrue(ContinuumForm.weakLineBiasNote.contains("eak-line bias measured on synthetic data"))
        // The badge quotes the measured numbers (rounded): the registered table's Kramers (9,5) cells.
        for v in [c.a[2].bias, c.a[3].bias, c.s[2].bias, c.s[3].bias] {
            XCTAssertTrue(ContinuumForm.weakLineBiasNote.contains(String(format: "\u{2212}%.0f \u{00B1}", abs(v))), "badge lacks \(v)")
        }
    }

    /// The finding behind the bias on the simulator: with its Al K-alpha tail supplied as a reference shape the Mg bias
    /// collapses (noise-free fit of the 1 % pool). The slot, not the continuum, is where the owner's pure-Al spectrum helps.
    func testTailReferenceShapeRemovesTheSimulatorWeakLineBias() throws {
        let sim = Self.simPools, axis = sim.axis
        let level = sim.levels[3]
        let els = ["Mg", "Al", "Si", "Cu", "O"]
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        let sig = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: 1.4865)! / EDSLineModel.sigma2fwhm
        var tail = energies.map { e -> Double in e < 1.9865 ? exp((e - 1.4865) / 0.12) * 0.5 * erfc((e - 1.4865) / (sig * 2.0.squareRoot())) : 0 }
        let ts = tail.reduce(0, +); tail = tail.map { $0 / ts }
        var s = FitSettings.standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200, efficiency: Self.sdd)
        s.background = .continuum(ContinuumForm(beamEnergy: 200, orders: [4, 3], efficiency: Self.sdd))
        let iMg = EDSLineModel.build(elements: els, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.firstIndex { $0.id == "Mg_Ka" }!
        let without = try EDSFit.run(counts: level.expected, axis: axis, settings: s).values[iMg] - level.mgKa
        s.referenceShapes = ReferenceShapes([ReferenceShape(name: "Al Ka tail", profile: tail, tie: .lineAmplitude(group: "Al_Ka", fraction: level.alTail / level.alKa))])
        let with = try EDSFit.run(counts: level.expected, axis: axis, settings: s).values[iMg] - level.mgKa
        note("sim 1 % Mg, eps (4,3), noise-free: bias without tail \(without), with the true tail \(with)")
        XCTAssertLessThan(without, -100)
        XCTAssertLessThan(abs(with), 100)
    }

    // MARK: 12. Round 2: covariance of the default continuum, validation, warnings

    /// The default continuum fit (Kramers x eps x Bernstein): predicted sandwich sigma against the scatter of 120 refits.
    func testCovarianceOfTheDefaultContinuumFit() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let els = ["Mg", "Al", "Si", "Cu"]
        let truth = Self.expected(axis: axis, elements: els, resolution: 130, beam: 200,
                                  areas: ["Al_Ka": 300_000, "Mg_Ka": 3_000, "Si_Ka": 20_000, "Cu_Ka": 40_000],
                                  continuumTotal: 400_000, escapeFraction: 0.01)
        let s = FitSettings.standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200, efficiency: Self.sdd)
        let ids = EDSLineModel.build(elements: els, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.map(\.id)
        let reps = 120
        var vals = [String: [Double]](), pred = [String: Double]()
        var kind = ""
        for rep in 0..<reps {
            let r = try EDSFit.run(counts: Self.poissonSpectrum(truth, seed: UInt64(500 + rep)), axis: axis, settings: s)
            kind = r.covarianceKind
            for id in ["Al_Ka", "Si_Ka", "Cu_Ka"] {
                let i = ids.firstIndex(of: id)!
                vals[id, default: []].append(r.values[i]); pred[id, default: 0] += r.sigma(at: i) / Double(reps)
            }
        }
        XCTAssertTrue(kind.contains("unconstrained: bound-active columns counted free"), kind)
        for id in ["Al_Ka", "Si_Ka", "Cu_Ka"] {
            let v = vals[id]!, m = v.reduce(0, +) / Double(reps)
            let sd = (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(reps - 1)).squareRoot()
            note("default-continuum covariance \(id): predicted \(pred[id]!) empirical \(sd) ratio \(pred[id]! / sd)")
            // Stated band: predicted / empirical within 0.80-1.25 (the empirical sd of 120 refits has ~6 % error). Measured: Al Ka 1.20
            // (about 3 se above 1: the strongest line's sigma is over-predicted ~20 %, bound-active columns counted free), Si 0.89, Cu 0.99.
            XCTAssertTrue((0.80 ... 1.25).contains(pred[id]! / sd), "\(id): ratio \(pred[id]! / sd)")
        }
    }

    /// The badge rides on every continuum fit and on no polynomial fit.
    func testWeakLineBadgeAccompaniesContinuumFitsOnly() throws {
        let c = Self.fixture.cases["closedLoop"]!
        let cont = FitSettings.standard(elements: c.elements, axis: c.axis, resolutionMnKaEV: c.resolutionMnKa, beamEnergy: c.beamEnergy)
        XCTAssertTrue(try EDSFit.run(counts: c.data, axis: c.axis, settings: cont).warnings.contains(ContinuumForm.weakLineBiasNote))
        let poly = FitSettings(elements: c.elements, resolutionMnKaEV: c.resolutionMnKa, beamEnergy: c.beamEnergy, background: .polynomial(order: 6))
        XCTAssertFalse(try EDSFit.run(counts: c.data, axis: c.axis, settings: poly).warnings.contains(ContinuumForm.weakLineBiasNote))
        XCTAssertTrue(ContinuumForm.weakLineBiasNote.contains("unmeasured on real data"))
    }

    func testEfficiencyIsComparedByParametersNotName() {
        let a = ContinuumForm(beamEnergy: 200, efficiency: Self.sdd)
        var thick = Self.sdd; thick.siliconMicrons = 300
        XCTAssertNotEqual(a, ContinuumForm(beamEnergy: 200, efficiency: thick))
        XCTAssertEqual(a, ContinuumForm(beamEnergy: 200, efficiency: Self.sdd))
        XCTAssertNotEqual(a, ContinuumForm(beamEnergy: 200))
        // Same name, different values: a parameter the name does not spell out.
        struct Flat: DetectorEfficiency { let k: Double; var sourceName: String { "typed" }; func efficiency(energyKeV: Double) -> Double { k } }
        XCTAssertNotEqual(ContinuumForm(beamEnergy: 200, efficiency: Flat(k: 0.9)), ContinuumForm(beamEnergy: 200, efficiency: Flat(k: 0.8)))
        XCTAssertEqual(ContinuumForm(beamEnergy: 200, efficiency: Flat(k: 0.9)), ContinuumForm(beamEnergy: 200, efficiency: Flat(k: 0.9)))
    }

    func testReferenceShapePreconditionsThrow() throws {
        let c = Self.fixture.cases["closedLoop"]!
        var s = FitSettings(elements: c.elements, resolutionMnKaEV: c.resolutionMnKa, beamEnergy: c.beamEnergy,
                            background: .polynomial(order: 2), escapePeaks: false)
        let ok = [Double](repeating: 1.0 / Double(c.size), count: c.size)
        func run(_ shape: ReferenceShape) throws { s.referenceShapes = ReferenceShapes([shape]); _ = try EDSFit.run(counts: c.data, axis: c.axis, settings: s) }
        XCTAssertThrowsError(try run(ReferenceShape(name: "short", profile: [1, 2, 3], tie: .lineAmplitude(group: "Fe_Ka", fraction: 0.1)))) {
            XCTAssertEqual($0 as? EDSFitError, .referenceShapeLength(name: "short", expected: c.size, got: 3))
        }
        var bad = ok; bad[7] = .nan
        XCTAssertThrowsError(try run(ReferenceShape(name: "nan", profile: bad, tie: .lineAmplitude(group: "Fe_Ka", fraction: 0.1)))) {
            XCTAssertEqual($0 as? EDSFitError, .referenceShapeNotFinite(name: "nan"))
        }
        XCTAssertThrowsError(try run(ReferenceShape(name: "ghost", profile: ok, tie: .lineAmplitude(group: "Zz_Ka", fraction: 0.1)))) {
            XCTAssertEqual($0 as? EDSFitError, .referenceShapeUnknownGroup(name: "ghost", group: "Zz_Ka"))
        }
        XCTAssertNoThrow(try run(ReferenceShape(name: "fine", profile: ok, tie: .lineAmplitude(group: "Fe_Ka", fraction: 0.1))))
    }

    /// A low line on a good detector has no real width under the law: the line is dropped with its reason, never NaN.
    func testLineWithoutARealWidthIsDroppedAndReported() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let counts = [Double](repeating: 5, count: 1024)
        // C K-alpha 0.277 keV: radicand 2.5 (0.277 - 5.8987) 1000 + 100^2 < 0.
        let s = FitSettings(elements: ["C", "Al"], resolutionMnKaEV: 110, beamEnergy: 200, background: .polynomial(order: 2))
        let model = EDSLineModel.build(elements: ["C", "Al"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 110)
        XCTAssertFalse(model.groups.contains { $0.id == "C_Ka" })
        XCTAssertTrue(model.droppedLines.contains { $0.contains("C_Ka") })
        let r = try EDSFit.run(counts: counts, axis: axis, settings: s)
        XCTAssertTrue(r.model.allSatisfy { $0.isFinite }); XCTAssertTrue(r.values.allSatisfy { $0.isFinite })
        XCTAssertTrue(r.warnings.contains { $0.hasPrefix("line dropped") && $0.contains("C_Ka") })
        XCTAssertEqual(r.droppedLines, model.droppedLines)
        // 100 eV drops Al K-alpha too: with no line left the fit is the background alone, not a trap.
        let none = try EDSFit.run(counts: counts, axis: axis, settings: FitSettings(elements: ["C", "Al"], resolutionMnKaEV: 100, beamEnergy: 200, background: .polynomial(order: 2)))
        XCTAssertTrue(none.values.isEmpty); XCTAssertTrue(none.model.allSatisfy { $0.isFinite })
        XCTAssertEqual(none.model[500], 5, accuracy: 1e-6)
    }

    func testWarningsNameTheLargeEscapeRatioAndTheSignedMLBackground() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let els = ["Al", "Fe"]
        // 9 % Fe escape planted: above the 5 % flag.
        let e = Self.expected(axis: axis, elements: els, resolution: 130, beam: 200, areas: ["Fe_Ka": 200_000, "Al_Ka": 100_000],
                              continuumTotal: 60_000, escapeFraction: 0.09)
        let counts = Self.poissonSpectrum(e, seed: 31)
        let r = try EDSFit.run(counts: counts, axis: axis, settings: .standard(elements: els, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200))
        let iFe = r.groupIDs.firstIndex(of: "Fe_Ka")!
        XCTAssertEqual(r.escapeRatios[iFe]!, 0.09, accuracy: 0.015)
        XCTAssertTrue(r.warnings.contains { $0.contains("Fe_Ka") && $0.contains("exceeds 5 %") }, "\(r.warnings)")
        XCTAssertNil(r.escapeRatios[r.groupIDs.firstIndex(of: "Al_Ka")!])
        // Footer labels name the background form.
        XCTAssertTrue(r.backgroundLabel.hasPrefix("continuum: Kramers\u{00D7}Bernstein(9,5), split at 1.5596 keV"), r.backgroundLabel)
        XCTAssertTrue(r.backgroundLabel.hasSuffix("orders chosen on synthetic data"))
        // Poisson ML with an Expert signed polynomial that goes negative is named.
        var s = FitSettings(elements: ["Fe", "Cu"], resolutionMnKaEV: 130, beamEnergy: 200, fitFrom: 5.0, fitTo: 9.5,
                            background: .polynomial(order: 6), escapePeaks: false, method: .poissonML(IRLSSettings()))
        s.background = .polynomial(order: 6)
        let few = Self.poissonSpectrum(Self.expected(axis: EnergyAxis(offset: 0, scale: 0.01, size: 1000), elements: ["Fe", "Cu"], resolution: 130,
                                                    beam: 200, areas: ["Fe_Ka": 60, "Cu_Ka": 40], continuumTotal: 120), seed: 4)
        let ml = try EDSFit.run(counts: few, axis: EnergyAxis(offset: 0, scale: 0.01, size: 1000), settings: s)
        XCTAssertEqual(ml.negativeModelChannels > 0, ml.warnings.contains { $0.contains("Poisson ML with a model below zero") })
        XCTAssertEqual(ml.exit == "converged" || ml.exit.hasPrefix("stationary"), ml.converged)
    }
}
