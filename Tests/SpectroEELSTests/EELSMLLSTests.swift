//
//  EELSMLLSTests.swift
//  Role: SpectroKit 0.10.0, fast target: the multiple linear least squares fit against planted truth (noise-free recovery, the standard
//        errors against the scatter of Poisson realisations, badly scaled columns, given reference shapes), the window, the refusals, masks,
//        singular designs and composition. The HyperSpy pins are in SpectroKitParityTests/MLLSPinsTests. The planted images are the pins
//        script's (Fixtures/eelsrm-*, tools/eels-rl-mlls/pins.py), read here for their truth only.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEELS

struct EELSMLLSTests {

    struct Planted {
        let edges: [CoreLossEdge]
        let masters: [String]
        let microscope: EELSMicroscope
        let core: CoreLossSpectrumImage
        let low: LowLossSpectrumImage?
        let truthA: [Double], truthR: [Double]
        let truthIntensity: [String: [Double]]
    }

    private static let directory = FixtureDirs.fixtures(of: "SpectroEELSTests")
    nonisolated(unsafe) private static let pins: [String: Any] = {
        try! JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("eelsrm-pins.json"))) as! [String: Any]
    }()

    private static func array(_ name: String) -> [Double] {
        let data = try! Data(contentsOf: directory.appendingPathComponent("eelsrm-\(name).f64"))
        return data.withUnsafeBytes { raw in (0 ..< raw.count / 8).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self) } }
    }

    private static func nums(_ any: Any?) -> [Double] { (any as! [Any]).map { ($0 as? NSNumber)?.doubleValue ?? .nan } }

    private func planted(_ key: String, lowLossScale: Double = 1) throws -> Planted {
        let c = (Self.pins["mlls"] as! [String: [String: Any]])[key]!
        let edges = (c["edges"] as! [String]).map { s -> CoreLossEdge in
            let parts = s.split(separator: "_").map(String.init)
            return CoreLossEdge.bundled(parts[0], parts[1] == "K" ? "K1" : parts[1])!
        }
        let mic = Self.nums(c["microscope"])
        let ax = c["axis"] as! [String: Any]
        let nx = c["nx"] as! Int, ny = c["ny"] as! Int
        let core = try CoreLossSpectrumImage(nx: nx, ny: ny, channels: ax["size"] as! Int, counts: Self.array(c["coreFile"] as! String),
                                             energyOffsetEV: (ax["offsetEV"] as! NSNumber).doubleValue, energyScaleEV: (ax["scaleEV"] as! NSNumber).doubleValue)
        var low: LowLossSpectrumImage?
        if let f = c["lowLossFile"] as? String {
            let la = c["lowLossAxis"] as! [String: Any]
            low = try LowLossSpectrumImage(nx: nx, ny: ny, channels: la["size"] as! Int, counts: Self.array(f).map { $0 * lowLossScale },
                                           energyOffsetEV: (la["offsetEV"] as! NSNumber).doubleValue, energyScaleEV: (la["scaleEV"] as! NSNumber).doubleValue)
        }
        let truth = c["truth"] as! [String: Any]
        return Planted(edges: edges, masters: c["masters"] as! [String],
                       microscope: EELSMicroscope(beamEnergyKeV: mic[0], convergenceMrad: mic[1], collectionMrad: mic[2]), core: core, low: low,
                       truthA: Self.nums(truth["A"]), truthR: Self.nums(truth["r"]),
                       truthIntensity: (truth["intensity"] as! [String: Any]).mapValues { Self.nums($0) })
    }

    private func key(_ e: CoreLossEdge) -> String { e.element + "_" + (e.subshell == "K1" ? "K" : e.subshell) }

    /// Noise-free data and the true exponent: A and the intensities come back to rounding, the standard errors are at the noise floor.
    @Test func testRecoversPlantedAmplitudesExactly() throws {
        for name in ["fel-exact.full.given", "cno.full.given", "fecu.full.given", "fel-conv.full.given"] {
            let t = try planted(name)
            let exact = name.hasPrefix("fel-exact")
            let result = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, lowLoss: t.low,
                                          options: EELSMLLSOptions(exponent: .perPixel(t.truthR)))
            #expect(result.validation == "none" && result.convolved == (t.low != nil))
            #expect(result.windowChannels == 0 ... t.core.channels - 1)
            for p in 0 ..< t.core.pixelCount {
                let px = result.pixels[p]
                #expect(px.exponent == t.truthR[p])
                let a = try #require(px.background)
                // the noisy images carry Poisson noise: A and the intensities within 1 % and 1e-3; the exact one to rounding
                #expect(abs(a.value - t.truthA[p]) <= (exact ? 1e-9 : 3e-2) * t.truthA[p], Comment(rawValue: "\(name) pixel \(p): A \(a.value) vs \(t.truthA[p])"))
                for (g, e) in result.edges.enumerated() {
                    let want = t.truthIntensity[key(e)]![p]
                    #expect(abs(px.intensities[g].value - want) <= (exact ? 1e-9 : 1e-3) * want, Comment(rawValue: "\(name) \(key(e)) pixel \(p)"))
                    if exact { #expect(px.intensities[g].standardError! <= 1e-9 * want) }
                }
                #expect(px.degreesOfFreedom == t.core.channels - 1 - result.edges.count)
            }
        }
    }

    /// The standard errors are the scatter of the estimate under the noise they assume: 300 realisations of one exact spectrum with constant-variance
    /// Gaussian noise (sigma 40 counts); the mean reported error of each amplitude is within 12 % of the sample standard deviation (the sample's own
    /// relative error is 4 %), and the means are unbiased. Poisson noise is NOT that (the variance follows the counts, 1e7 at the edge peak): the
    /// unweighted errors, HyperSpy's and these, then overstate the background's by 7x on this spectrum; the notes say so.
    @Test func testStandardErrorsAreTheScatterOfNoisyFits() throws {
        let t = try planted("fel-exact.full.given")
        let n = t.core.channels, reps = 300
        let exactFit = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, options: EELSMLLSOptions(exponent: .perPixel(t.truthR)))
        let curve = try #require(exactFit.modelCurve(pixel: 2))
        var counts = [Double](); counts.reserveCapacity(reps * n)
        for seed in 1 ... reps {
            var rng = Xoshiro256StarStar(seed: UInt64(seed))
            for c in 0 ..< n {
                let u1 = rng.uniform(), u2 = rng.uniform()
                counts.append(curve[c] + 40 * (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2))
            }
        }
        let image = try CoreLossSpectrumImage(nx: reps, ny: 1, channels: n, counts: counts, energyOffsetEV: t.core.energyOffsetEV, energyScaleEV: t.core.energyScaleEV)
        let result = try EELSMLLS.fit(coreLoss: image, edges: t.edges, microscope: t.microscope, options: EELSMLLSOptions(exponent: .given(t.truthR[2])))
        func check(_ what: String, _ amplitudes: [EELSAmplitude], truth: Double) {
            let values = amplitudes.map(\.value)
            let mean = values.reduce(0, +) / Double(reps)
            let sd = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(reps - 1)).squareRoot()
            let reported = amplitudes.map { $0.standardError! }.reduce(0, +) / Double(reps)
            #expect(abs(reported / sd - 1) < 0.12, Comment(rawValue: "\(what): reported \(reported), scatter \(sd)"))
            #expect(abs(mean - truth) < 4 * sd / Double(reps).squareRoot(), Comment(rawValue: "\(what): mean \(mean) vs truth \(truth), sd \(sd)"))
        }
        check("A", result.pixels.map { $0.background! }, truth: t.truthA[2])
        for (g, e) in result.edges.enumerated() { check(key(e), result.pixels.map { $0.intensities[g] }, truth: t.truthIntensity[key(e)]![2]) }
    }

    /// A low loss of area 1e6 makes the edge columns 1e15 times the power law's; numpy's lstsq drops the power law then. Here the columns are scaled:
    /// the fit equals the unit-area one (A unchanged, intensities 1e-6 times).
    @Test func testBadlyScaledColumnsKeepThePowerLaw() throws {
        let unit = try planted("fel-conv.full.given")
        let big = try planted("fel-conv.full.given", lowLossScale: 1e6)
        let options = EELSMLLSOptions(exponent: .perPixel(unit.truthR))
        let a = try EELSMLLS.fit(coreLoss: unit.core, edges: unit.edges, microscope: unit.microscope, lowLoss: unit.low, options: options)
        let b = try EELSMLLS.fit(coreLoss: big.core, edges: big.edges, microscope: big.microscope, lowLoss: big.low, options: options)
        for p in 0 ..< unit.core.pixelCount {
            let x = a.pixels[p], y = b.pixels[p]
            #expect(abs(x.background!.value - y.background!.value) <= 1e-8 * x.background!.value, Comment(rawValue: "pixel \(p): A \(x.background!.value) vs \(y.background!.value)"))
            #expect(abs(x.intensities[0].value - 1e6 * y.intensities[0].value) <= 1e-8 * x.intensities[0].value)
            #expect(abs(x.intensities[0].standardError! - 1e6 * y.intensities[0].standardError!) <= 1e-6 * x.intensities[0].standardError!)
        }
    }

    /// A given reference shape is one more linear amplitude: a planted bump of known height comes back, the others unharmed.
    @Test func testGivenReferenceShapeIsRecovered() throws {
        let t = try planted("fel-exact.full.given")
        let n = t.core.channels, axis = t.core.energyOffsetEV
        let bump = (0 ..< n).map { 50 * exp(-0.5 * pow((axis + 0.5 * Double($0) - 760) / 6, 2)) }
        var counts = t.core.counts
        for p in 0 ..< t.core.pixelCount { for c in 0 ..< n { counts[p * n + c] += 3.0 * bump[c] } }
        let image = try CoreLossSpectrumImage(nx: t.core.nx, ny: t.core.ny, channels: n, counts: counts, energyOffsetEV: t.core.energyOffsetEV, energyScaleEV: t.core.energyScaleEV)
        let result = try EELSMLLS.fit(coreLoss: image, edges: t.edges, microscope: t.microscope,
                                      options: EELSMLLSOptions(exponent: .perPixel(t.truthR), references: [bump]))
        for p in 0 ..< t.core.pixelCount {
            let px = result.pixels[p]
            #expect(abs(px.references[0].value - 3) < 1e-8, Comment(rawValue: "pixel \(p): \(px.references[0].value)"))
            #expect(abs(px.intensities[0].value - t.truthIntensity["Fe_L3"]![p]) <= 1e-9 * t.truthIntensity["Fe_L3"]![p])
        }
        let curve = try #require(result.modelCurve(pixel: 1))
        for c in 0 ..< n { #expect(abs(curve[c] - image.counts[n + c]) <= 1e-6 * max(1, image.counts[n + c])) }
        // two identical references make the design singular: the pixel has no answer (HyperSpy raises LinAlgError)
        let twice = try EELSMLLS.fit(coreLoss: image, edges: t.edges, microscope: t.microscope,
                                     options: EELSMLLSOptions(exponent: .perPixel(t.truthR), references: [bump, bump]))
        #expect(twice.pixels.allSatisfy { $0.unavailable == .fitFailed && $0.background == nil && $0.intensities.isEmpty })
        #expect(twice.modelCurve(pixel: 0) == nil)
    }

    /// The window is HyperSpy's `set_signal_range`: both ends included, an end beyond the axis keeps the last channel.
    @Test func testWindowIncludesBothEnds() throws {
        let t = try planted("fel-exact.full.given")
        let options = { (start: Double?, end: Double?) in EELSMLLSOptions(exponent: .given(2.6), startEnergyEV: start, endEnergyEV: end) }
        let whole = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, options: options(nil, nil))
        let narrow = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, options: options(610, 850))
        let beyond = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, options: options(nil, 1e9))
        #expect(whole.windowChannels == 0 ... 599 && whole.windowEV == 600 ... 899.5)
        #expect(narrow.windowChannels == 20 ... 500 && narrow.windowEV == 610 ... 850)
        #expect(narrow.pixels[0].degreesOfFreedom == 481 - 2)
        #expect(beyond.windowChannels == 0 ... 599)
    }

    @Test func testRefusals() throws {
        let t = try planted("fel-exact.full.given")
        func fit(_ options: EELSMLLSOptions, edges: [CoreLossEdge]? = nil, mask: PixelMask? = nil) throws {
            _ = try EELSMLLS.fit(coreLoss: t.core, edges: edges ?? t.edges, microscope: t.microscope, mask: mask, options: options)
        }
        #expect(throws: EELSMLLSError.invalidExponent) { try fit(EELSMLLSOptions(exponent: .given(.nan))) }
        #expect(throws: EELSMLLSError.invalidExponent) { try fit(EELSMLLSOptions(exponent: .perPixel([Double](repeating: .infinity, count: 6)))) }
        #expect(throws: EELSMLLSError.exponentCountMismatch(expected: 6, got: 2)) { try fit(EELSMLLSOptions(exponent: .perPixel([2, 3]))) }
        #expect(throws: EELSMLLSError.invalidReference(index: 1)) { try fit(EELSMLLSOptions(exponent: .given(2.6), references: [[Double](repeating: 1, count: 600), [1, 2]])) }
        #expect(throws: EELSMLLSError.invalidWindow(startEV: 600, endEV: .infinity)) { try fit(EELSMLLSOptions(exponent: .given(2.6), endEnergyEV: .infinity)) }
        #expect(throws: EELSModelError.self) { try fit(EELSMLLSOptions(exponent: .given(2.6), endEnergyEV: 700)) }          // the edge starts at 708 eV: not inside the window
        #expect(throws: EELSModelError.self) { try fit(EELSMLLSOptions(exponent: .given(2.6)), edges: []) }
        #expect(throws: EELSModelError.maskShapeMismatch(expected: 6, got: 1)) { try fit(EELSMLLSOptions(exponent: .given(2.6)), mask: [true]) }
        // more amplitudes than channels in the window (261 channels, 302 amplitudes)
        #expect(throws: EELSMLLSError.windowTooNarrow(channels: 261, amplitudes: 302)) {
            try fit(EELSMLLSOptions(exponent: .given(2.6), endEnergyEV: 730, references: (0 ..< 300).map { i in (0 ..< 600).map { sin(Double($0 * (i + 1))) } }))
        }
    }

    @Test func testMaskedPixelsAndTwoAreaFailure() throws {
        let t = try planted("fel-exact.full.given")
        var mask = [Bool](repeating: true, count: 6)
        mask[2] = false
        let result = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, mask: mask)
        #expect(result.pixels[2].unavailable == .masked && result.pixels[2].background == nil && result.modelCurve(pixel: 2) == nil)
        #expect(result.pixels[3].unavailable == nil && result.pixels[3].exponent != nil)
        #expect(result.modelCurve(pixel: 99) == nil)
        // a spectrum that is zero over the pre-edge window has no two-area exponent
        var counts = t.core.counts
        for c in 0 ..< 212 { counts[c] = 0 }
        let zeros = try CoreLossSpectrumImage(nx: 6, ny: 1, channels: t.core.channels, counts: Array(counts[0 ..< 600]) + t.core.counts[600 ..< 3600], energyOffsetEV: t.core.energyOffsetEV, energyScaleEV: t.core.energyScaleEV)
        let bad = try EELSMLLS.fit(coreLoss: zeros, edges: t.edges, microscope: t.microscope)
        #expect(bad.pixels[0].unavailable == .fitFailed)
        #expect(bad.pixels[1].unavailable == nil)
    }

    /// at% and wt% from the MLLS intensities equal the ratios of the intensities, with nothing flagged as not detected.
    @Test func testCompositionFromMLLS() throws {
        let t = try planted("fecu.full.given")
        let result = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, options: EELSMLLSOptions(exponent: .perPixel(t.truthR)))
        let comp = try EELSQuantification.composition(result, symbols: ["Fe", "Cu"])
        for p in 0 ..< t.core.pixelCount {
            let fe = result.pixels[p].intensities[0].value, cu = result.pixels[p].intensities[1].value
            let c = comp[p]
            #expect(c.unavailable == nil)
            #expect(abs(c.atomicPercent[0] - 100 * fe / (fe + cu)) < 1e-9 && abs(c.atomicPercent.reduce(0, +) - 100) < 1e-9)
            #expect(abs(c.weightPercent.reduce(0, +) - 100) < 1e-9)
        }
        #expect(throws: EELSModelError.symbolNotFitted("Si")) { try EELSQuantification.composition(result, symbols: ["Si"]) }
        #expect(throws: EELSModelError.self) { try EELSQuantification.composition(result, symbols: ["Fe", "Fe"]) }
        #expect(comp.allSatisfy { $0.notDetected == [false, false] })
    }

    /// An element whose unconstrained MLLS amount is at or below zero is not detected: 0 at% and 0 wt%, flagged in `notDetected`, and the
    /// others are normalised among themselves (as the non-negative model fit gives such an element 0). The pixel keeps its composition.
    /// Pixels with every amount positive are unchanged to the bit.
    ///
    /// The image: the planted C, N and O image with its N amplitude moved to +-1.5 % of C's by linearity. With H_CO the hat matrix of the
    /// fit without N (power law, C, O), the CNO fit of Y - k (H_CNO Y - H_CO Y) has N amplitude (1 - k) N(Y), because H_CO Y lies in the
    /// CNO design's span with no N part (C and O move towards the fit without N; only the sign of N matters here).
    @Test func testCompositionWithNegativeAbsentElementKeepsTheOthers() throws {
        let t = try planted("cno.full.given")
        let options = EELSMLLSOptions(exponent: .perPixel(t.truthR))
        let all = try EELSMLLS.fit(coreLoss: t.core, edges: t.edges, microscope: t.microscope, options: options)
        let co = try EELSMLLS.fit(coreLoss: t.core, edges: [t.edges[0], t.edges[2]], microscope: t.microscope, options: options)
        #expect(all.edges.map(\.element) == ["C", "N", "O"])
        let n = t.core.channels
        var counts = t.core.counts
        for p in 0 ..< t.core.pixelCount {
            let c = all.pixels[p].intensities[0].value, nk = all.pixels[p].intensities[1].value
            let target = (p % 2 == 0 ? 0.015 : -0.015) * c
            let k = 1 - target / nk
            let full = try #require(all.modelCurve(pixel: p)), without = try #require(co.modelCurve(pixel: p))
            for ch in 0 ..< n { counts[p * n + ch] -= k * (full[ch] - without[ch]) }
        }
        let image = try CoreLossSpectrumImage(nx: t.core.nx, ny: t.core.ny, channels: n, counts: counts,
                                              energyOffsetEV: t.core.energyOffsetEV, energyScaleEV: t.core.energyScaleEV)
        let result = try EELSMLLS.fit(coreLoss: image, edges: t.edges, microscope: t.microscope, options: options)
        let comp = try EELSQuantification.composition(result, symbols: ["C", "N", "O"])
        let masses = ["C", "N", "O"].map { EELSQuantification.atomicMasses[$0]! }
        for p in 0 ..< t.core.pixelCount {
            let a = result.pixels[p].intensities.map(\.value), c = comp[p]
            #expect(c.unavailable == nil, Comment(rawValue: "pixel \(p)"))
            if p % 2 == 0 {
                #expect(a[1] > 0, Comment(rawValue: "pixel \(p): N \(a[1])"))
                // the old rule, exactly
                let atoms = a.reduce(0, +), weights = zip(a, masses).map { $0 * $1 }.reduce(0, +)
                #expect(c.atomicPercent == a.map { 100 * $0 / atoms })
                #expect(c.weightPercent == zip(a, masses).map { 100 * $0 * $1 / weights })
                #expect(c.notDetected == [false, false, false])
            } else {
                #expect(a[1] < 0, Comment(rawValue: "pixel \(p): N \(a[1])"))
                #expect(c.notDetected == [false, true, false])
                #expect(c.atomicPercent[1] == 0 && c.weightPercent[1] == 0)
                #expect(abs(c.atomicPercent[0] - 100 * a[0] / (a[0] + a[2])) < 1e-9)
                #expect(abs(c.weightPercent[2] - 100 * a[2] * masses[2] / (a[0] * masses[0] + a[2] * masses[2])) < 1e-9)
                #expect(abs(c.atomicPercent.reduce(0, +) - 100) < 1e-9 && abs(c.weightPercent.reduce(0, +) - 100) < 1e-9)
            }
        }
        // every element at or below zero: no composition
        let none = try EELSQuantification.composition(result, symbols: ["N"])
        #expect(none[1].unavailable == .noComposition && none[1].atomicPercent.isEmpty)
        #expect(none[0].unavailable == nil && none[0].atomicPercent == [100])
    }
}
