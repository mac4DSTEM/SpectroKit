import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// The pooled quantification against PLANTED TRUTH ON SYNTHETIC DATA: five pools of the public AlMgSi demo set (mac4DSTEM `demo-edx`,
/// `tools/demo-edx/sim_edx.py` v2.0; `tools/edx-sim/demo_pools.py` wrote `edx-demo-pools.json`) and the kit's own
/// `eds-absorption-truth.json` pool. The truth is the simulation recipe, not a measurement, so every number here stays
/// `validation: "none"`.
///
/// The generator plants what a real detector does and exSpy's line model leaves out: sum (pile-up) peaks whose parents lose the
/// photons, a 1.5 % Al K-alpha tail (0.12 keV), Si escape, Si internal fluorescence and stray Cu K. Each pool is fitted on the
/// generator's noise-free expected spectrum x100 (the fit's bias without noise) and, where said, on its Poisson counts. Setup as the
/// apps run it: true axis locked, the generator's true k typed (weight convention, relative to the first quantified element), the
/// truth geometry and thickness, absorption on. Cu and O are Fit only: the demo's Cu is a stray grid line (the test's choice).
///
/// Si planted counts include the Si internal-fluorescence peak at the same energy (the kit's convention, `SpectroscopyAbsorptionTruthTests`).
///
/// What the bounds are: MEASURED regression bounds on fixed inputs, not derived limits. The fit with the default sum peaks reads
/// noise-free Si K-alpha -0.0 to -4.0 % on the pools at up to 300 counts/px and -7.9 % on L5 (the highest rate, where the
/// generator's pile-up takes 11 % of the Al K-alpha photons); the bound is 5 % (10 % on L5). The fit without sum peaks read -8 to
/// -57 % on the same pools: the Al+Al sum peak (2.97 keV) pulls the continuum segment above the Al K edge and Si K-alpha with it.
struct DemoEDXPoolTests {
    static let tables = try! QuantificationTables(directory: EDXFixtures.repoRoot.appendingPathComponent("Sources/SpectroEDX/Resources/Spectroscopy"))

    private struct Axis: Decodable { let offset: Double; let scale: Double }
    private struct DemoPool: Decodable {
        let name: String; let npix: Int
        let thicknessNm: Double
        let truthAt: [String: Double]
        let axisTrue: Axis
        let counts: [Int]; let expected: [Double]; let planted: [String: Double]
        enum CodingKeys: String, CodingKey {
            case name, npix, counts, expected, planted
            case thicknessNm = "thickness_nm", truthAt = "truth_at", axisTrue = "axis_true"
        }
    }
    private struct DemoDoc: Decodable {
        let trueK: [String: Double]; let mass: [String: Double]; let pools: [DemoPool]
        enum CodingKeys: String, CodingKey { case pools; case trueK = "true_k_counts_per_atom_nm2"; case mass = "atomic_mass" }
    }
    private static let demo = try! JSONDecoder().decode(DemoDoc.self, from: Data(contentsOf: EDXFixtures.url("edx-demo-pools.json")))

    /// One pool in the form the tests use.
    struct Case {
        let name: String
        let axis: EnergyAxis
        let npix: Int
        let thicknessNm: Double
        let quantified: [String]
        let trueK: [String: Double]
        let expected: [Double]
        let counts: [Int]?
        /// Planted Mg K-alpha, Si K-alpha (+ internal fluorescence) and Cu K-alpha (stray + sample), counts; nil when not planted or not known.
        let mg: Double, si: Double, cu: Double?
    }

    static let cases: [Case] = {
        var out: [Case] = demo.pools.map { p in
            Case(name: p.name, axis: EnergyAxis(offset: p.axisTrue.offset, scale: p.axisTrue.scale, size: p.expected.count), npix: p.npix,
                 thicknessNm: p.thicknessNm, quantified: p.truthAt["Al"] == nil ? ["Mg", "Si"] : ["Al", "Mg", "Si"], trueK: demo.trueK,
                 expected: p.expected, counts: p.counts, mg: p.planted["Mg_Ka"]!, si: p.planted["Si_Ka"]! + p.planted["Si_Ka_internal"]!,
                 cu: p.planted["Cu_Ka"]! + p.planted["Cu_Ka_stray"]!)
        }
        let fx = EDXFixtures.jsonObject("eds-absorption-truth.json")
        let e = fx["expected"] as! [Double]
        let with = fx["areas_with_absorption"] as! [String: Double]
        out.append(Case(name: "absorption-truth", axis: EnergyAxis(offset: fx["offset"] as! Double, scale: fx["scale"] as! Double, size: e.count),
                        npix: fx["npix"] as! Int, thicknessNm: fx["thickness_nm"] as! Double, quantified: ["Al", "Mg", "Si"],
                        trueK: fx["true_k_counts_per_atom_nm2"] as! [String: Double], expected: e, counts: nil,
                        mg: with["Mg_Ka"]!, si: with["Si_Ka"]! + (fx["area_si_ka_internal"] as! Double), cu: nil))
        return out
    }()

    static func named(_ prefix: String) -> Case { cases.first { $0.name.hasPrefix(prefix) }! }

    static func input(_ c: Case, noiseFree: Bool, policy: QuantificationPolicy = .default) -> PooledQuantificationInput {
        let counts = noiseFree ? c.expected.map { UInt64(($0 * 100).rounded()) } : c.counts!.map { UInt64($0) }
        var m = QuantificationMethod()
        var roles: [(String, QuantificationMethod.ElementRole)] = c.quantified.map { ($0, .quantify) }
        if !c.quantified.contains("Al") { roles.append(("Al", .fitOnly)) }
        roles += [("Cu", .fitOnly), ("O", .fitOnly)]
        m.elements = roles.map { .init(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = true
        m.kFactorSource = .typed
        m.kSource = "demo generator true k (Gp x s x eps), weight convention"; m.kDate = "2026-10-31"; m.kReference = c.quantified[0]
        let mass = demo.mass
        let w = c.quantified.map { mass[$0]! / c.trueK[$0]! }
        m.typedK = zip(c.quantified, w).map { .init(element: $0.0, k: $0.1 / w[0], relativeSigma: 0) }
        m.thickness = .init(nanometres: c.thicknessNm, sigmaNanometres: 0)
        m.absorptionCorrection = true
        var meta = SpectrumImageMetadata(fileName: c.name, filePath: c.name, scanWidth: 1, scanHeight: 1, channelCount: counts.count,
                                         energyOffsetEV: c.axis.offset * 1000, energyDispersionEV: c.axis.scale * 1000)
        meta.origin = .veloxEMD
        meta.alphaTiltDegrees = -16.87; meta.betaTiltDegrees = 0
        meta.detectors = zip([45.0, 135, 225, 315], [0.4, 0.2, 0.1, 0.3]).enumerated().map { i, a in
            SpectrumDetectorSegment(name: "SuperXG1\(i + 1)", azimuthDegrees: a.0, elevationDegrees: 22, solidAngle: a.1)
        }
        return PooledQuantificationInput(counts: counts, axis: c.axis, method: m, metadata: meta, regionName: c.name, pixelCount: c.npix,
                                         resolutionMnKaEV: 130, policy: policy)
    }

    static var withoutSumPeaks: QuantificationPolicy { QuantificationPolicy(fit: .exspyEquivalent) }

    static func net(_ q: PooledQuantification, _ group: String) -> Double { q.fit.groupIDs.firstIndex(of: group).map { q.fit.values[$0] } ?? .nan }
    static func say(_ s: String) { FileHandle.standardError.write(Data(("DEMO " + s + "\n").utf8)) }

    /// Red before sum peaks were the default: Si K-alpha read 8-57 % low noise-free. Now within 5 % (10 % at L5's rate), and the
    /// footer names the decision with its number.
    @Test(arguments: cases.map(\.name))
    func defaultFitRecoversSiKAlphaNoiseFree(_ name: String) throws {
        let c = Self.named(name)
        let q = try PooledQuantifier.run(Self.input(c, noiseFree: true), tables: Self.tables)
        let off = try PooledQuantifier.run(Self.input(c, noiseFree: true, policy: Self.withoutSumPeaks), tables: Self.tables)
        let si = Self.net(q, "Si_Ka") / 100 / c.si - 1, siOff = Self.net(off, "Si_Ka") / 100 / c.si - 1
        Self.say(String(format: "%@ Si %+.4f (without sum peaks %+.4f) | %@", name, si, siOff, q.footerLines.first { $0.hasPrefix("sum peaks") } ?? "-"))
        #expect(abs(si) <= (name.hasPrefix("L5") ? 0.10 : 0.05), "\(name): Si K-alpha \(si)")
        #expect(q.appliedSumEscape == SumEscapeModel(sumPeaks: true))
        #expect(q.footerLines.contains { $0.hasPrefix("sum peaks kept") })
        #expect(off.appliedSumEscape == nil)
        #expect(off.footerLines.contains("policy (non-default): fit.sumPeaks = off"))
        #expect(abs(si) < abs(siOff) || abs(siOff) < 0.01, "\(name): the default is not closer than the fit without sum peaks")
        #expect(q.quality < off.quality, "\(name): the fit with sum peaks fits worse")
    }

    /// Cu K-alpha at high rate: the fit without sum peaks held it at 0 (L6) or read 40 % of it (L5, L7), noise-free; the default
    /// reads 92-97 %. At the map pools' low rate both fits read it within 5 %.
    @Test func cuKAlphaIsRecoveredAtHighRate() throws {
        for c in Self.cases where c.cu != nil {
            let q = try PooledQuantifier.run(Self.input(c, noiseFree: true), tables: Self.tables)
            let off = try PooledQuantifier.run(Self.input(c, noiseFree: true, policy: Self.withoutSumPeaks), tables: Self.tables)
            let cu = Self.net(q, "Cu_Ka") / 100 / c.cu!, cuOff = Self.net(off, "Cu_Ka") / 100 / c.cu!
            Self.say(String(format: "%@ Cu read %.3f of planted (without sum peaks %.3f)", c.name, cu, cuOff))
            if c.name.hasPrefix("L") {
                #expect(cu >= 0.85, "\(c.name): Cu \(cu)")
                #expect(cuOff <= 0.45, "\(c.name): without sum peaks Cu \(cuOff)")
            } else {
                #expect(abs(cu - 1) <= 0.05 && abs(cuOff - 1) <= 0.05, "\(c.name): Cu \(cu), without sum peaks \(cuOff)")
            }
        }
        // On the Poisson counts of L6 (300 counts/px): 123 counts of stray Cu above the window background.
        let l6 = Self.named("L6")
        let q = try PooledQuantifier.run(Self.input(l6, noiseFree: false), tables: Self.tables)
        let off = try PooledQuantifier.run(Self.input(l6, noiseFree: false, policy: Self.withoutSumPeaks), tables: Self.tables)
        #expect(Self.net(q, "Cu_Ka") / l6.cu! >= 0.85)
        #expect(Self.net(off, "Cu_Ka") / l6.cu! <= 0.05)
    }

    /// The Poisson counts of every demo pool: the fit without sum peaks has a reduced chi2 of 2.1-31; with them 0.7-1.1.
    @Test func reducedChiSquareOnThePoissonCounts() throws {
        for c in Self.cases where c.counts != nil {
            let q = try PooledQuantifier.run(Self.input(c, noiseFree: false), tables: Self.tables)
            let off = try PooledQuantifier.run(Self.input(c, noiseFree: false, policy: Self.withoutSumPeaks), tables: Self.tables)
            Self.say(String(format: "%@ chi2_red %.3f (without sum peaks %.3f) | %@", c.name, q.quality, off.quality,
                            q.footerLines.first { $0.hasPrefix("sum peaks") } ?? "-"))
            #expect(q.appliedSumEscape == SumEscapeModel(sumPeaks: true), "\(c.name): the self pair did not pass on the Poisson counts")
            #expect(q.quality <= 1.2, "\(c.name): \(q.quality)")
            #expect(off.quality >= 2, "\(c.name): \(off.quality)")
        }
    }

    /// The Al K-alpha tail is a detector calibration, not part of the default. Measured once on a high-count spectrum of the same
    /// detector (the absorption-truth pool, 1e4 px) with `TailEstimate`, then typed into `FitPolicy.lineTail`, it takes the noise-free
    /// Mg K-alpha bias next to Al K-alpha (-22 % on L5, -32 % on recipe A, -45 % on the matrix map) to within 5 % on L5 and recipe A,
    /// and to -15 % on the matrix map (which
    /// pools seven recipes and thicknesses; not explained). Without it the default fit leaves Mg where it was (the tail is not a sum peak).
    @Test func aCalibratedTailTakesTheMgBiasOut() throws {
        let fx = Self.named("absorption-truth")
        var s = FitSettings.standard(elements: ["Al", "Mg", "Si", "Cu", "O"], axis: fx.axis, resolutionMnKaEV: 130, beamEnergy: 200)
        s.method = .leastSquares
        let tail = try TailEstimate.measure(counts: fx.expected.map { $0.rounded() }, axis: fx.axis, settings: s, elements: ["Al", "Mg", "Si", "Cu", "O"]).tail
        Self.say(String(format: "tail measured on the absorption-truth pool: f %.4f, slope %.3f keV (planted 0.015, 0.12)", tail.fraction, tail.slopeKeV))
        #expect(tail.fraction > 0.005 && tail.fraction < 0.02)
        var calibrated = QuantificationPolicy.default
        calibrated.fit.lineTail = tail
        for (name, bound) in [("L5", 0.05), ("L6", 0.05), ("L7", 0.05), ("M_A", 0.05), ("M_matrix", 0.16)] {
            let c = Self.named(name)
            let q = try PooledQuantifier.run(Self.input(c, noiseFree: true, policy: calibrated), tables: Self.tables)
            let plain = try PooledQuantifier.run(Self.input(c, noiseFree: true), tables: Self.tables)
            let off = try PooledQuantifier.run(Self.input(c, noiseFree: true, policy: Self.withoutSumPeaks), tables: Self.tables)
            let mg = Self.net(q, "Mg_Ka") / 100 / c.mg - 1, mgPlain = Self.net(plain, "Mg_Ka") / 100 / c.mg - 1
            let mgOff = Self.net(off, "Mg_Ka") / 100 / c.mg - 1
            Self.say(String(format: "%@ Mg with the calibrated tail %+.4f, default %+.4f, without sum peaks %+.4f", name, mg, mgPlain, mgOff))
            #expect(abs(mg) <= bound, "\(name): Mg \(mg)")
            #expect(abs(mgPlain - mgOff) <= 0.03, "\(name): sum peaks moved Mg from \(mgOff) to \(mgPlain)")
        }
    }

    /// The unlisted-line check on the Poisson counts of the Al-rich pools: without sum peaks the Al+Al sum (2.973 keV) is left in
    /// the residual (Ar K-alpha 2.957 keV, Ag L-alpha 2.984 keV); with the default it is a modelled sum peak, explained to the proposer,
    /// and neither Ar nor Ag is named.
    @Test(arguments: ["L5", "M_A", "M_matrix"])
    func theAlAlSumIsNotNamedAsArOrAg(_ name: String) throws {
        let c = Self.named(name)
        let input = Self.input(c, noiseFree: false)
        let q = try PooledQuantifier.run(input, tables: Self.tables)
        let proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q)
        let check = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q)
        Self.say("\(name) unlisted check, default: \(check.summary)")
        #expect(!check.names.contains("Ar") && !check.names.contains("Ag"), "\(name): \(check.summary)")
        // The other side of the same coin: a real Ar or Ag line there would be read as pile-up, and the result says so.
        #expect(q.warnings.contains { $0.contains("Ar_Ka") && $0.contains("read as pile-up") }, "\(name): \(q.warnings)")
        #expect(q.footerLines.contains { $0.contains("Ar_Ka") }, "\(name): \(q.footerLines)")
    }

    /// `.off` is the fit as it ran before, bit for bit: the same as a caller's explicit `SumEscapeModel()` (both off).
    @Test func theSwitchGivesTheFitWithoutSumPeaksBitForBit() throws {
        let c = Self.named("L6")
        let off = try PooledQuantifier.run(Self.input(c, noiseFree: false, policy: Self.withoutSumPeaks), tables: Self.tables)
        var explicit = Self.input(c, noiseFree: false)
        explicit.sumEscape = SumEscapeModel()
        let e = try PooledQuantifier.run(explicit, tables: Self.tables)
        #expect(off.fit.values == e.fit.values)
        #expect(off.fit.model == e.fit.model)
        #expect(off.rows == e.rows)
        #expect(FitPolicy.exspyEquivalent.sumPeaks == .off)
        #expect(FitPolicy.default.sumPeaks == .whenSignificant)
    }

    /// A policy stored before `sumPeaks` existed reads `.off` (the fit it was stored with); the new fields round-trip.
    @Test func aStoredPolicyWithoutTheFieldReadsOff() throws {
        var o = try #require(try JSONSerialization.jsonObject(with: Data(QuantificationPolicy.default.canonicalJSON.utf8)) as? [String: Any])
        var fit = try #require(o["fit"] as? [String: Any])
        #expect(fit["sumPeaks"] as? String == "whenSignificant")
        fit.removeValue(forKey: "sumPeaks"); fit.removeValue(forKey: "sumPeakSignificance")
        o["fit"] = fit
        let old = try JSONDecoder().decode(QuantificationPolicy.self, from: JSONSerialization.data(withJSONObject: o))
        #expect(old.fit.sumPeaks == .off)
        #expect(old.fit.sumPeakSignificance == 3)
        var p = QuantificationPolicy.default
        p.fit.sumPeaks = .always; p.fit.sumPeakSignificance = 5
        #expect(try JSONDecoder().decode(QuantificationPolicy.self, from: Data(p.canonicalJSON.utf8)) == p)
        p.fit.sumPeakSignificance = -1
        #expect(p.problem != nil)
    }

    /// No pile-up planted (`eds-unlisted-sim.json`, noise-free, the one such spectrum tested): the default keeps the fit without sum
    /// peaks bit for bit, and says so. With Cu, Ga
    /// and Ge left out of the list the four-parent model would keep c at 48 sigma (Ni K-alpha + O K-alpha lies on Cu K-alpha); the
    /// self-pair test (Si + Si) reads 0, so nothing is kept.
    @Test(arguments: [false, true])
    func noPileUpKeepsTheDefaultFit(incompleteList: Bool) throws {
        let o = EDXFixtures.jsonObject("eds-unlisted-sim.json")
        let e = o["expected"] as! [Double]
        let axis = EnergyAxis(offset: o["offset"] as! Double, scale: o["scale"] as! Double, size: e.count)
        var m = QuantificationMethod()
        let listed = incompleteList ? ["O", "Si", "Ti", "Ni"] : ["O", "Si", "Ti", "Ni", "Ge", "Cu", "Ga"]
        m.elements = listed.map { .init(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200
        m.absorptionCorrection = false
        m.lockEnergyAxis = true
        let meta = SpectrumImageMetadata(fileName: "eds-unlisted-sim.json", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: e.count,
                                         energyOffsetEV: axis.offset * 1000, energyDispersionEV: axis.scale * 1000)
        var input = PooledQuantificationInput(counts: e.map { UInt64($0.rounded()) }, axis: axis, method: m, metadata: meta,
                                              regionName: "synthetic", pixelCount: 1)
        let q = try PooledQuantifier.run(input, tables: Self.tables)
        input.policy = Self.withoutSumPeaks
        let off = try PooledQuantifier.run(input, tables: Self.tables)
        #expect(q.appliedSumEscape == nil)
        #expect(q.fit.values == off.fit.values)
        #expect(q.rows == off.rows)
        #expect(q.footerLines.contains { $0.hasPrefix("sum peaks tested, not kept: Si_Ka + Si_Ka alone") }, "\(q.footerLines)")
    }
}
