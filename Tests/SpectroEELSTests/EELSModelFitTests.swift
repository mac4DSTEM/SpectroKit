//
//  EELSModelFitTests.swift
//  Role: Task 16 step 5, fast target: the edge model against planted truth (Fixtures/eels16-model-*), its refusals, the twin rule, masks,
//        composition and the summed region. The exSpy pins are in SpectroKitParityTests/ModelPinsTests.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEELS

struct EELSModelFitTests {

    private func planted(_ name: String) throws -> ModelCase {
        let all = ModelFixtures.pins["cases"] as! [String: [String: Any]]
        return try ModelFixtures.make(name, all[name]!)
    }

    /// The fitted intensities equal the planted ones within 5e-4 on the Poisson-noisy images (counts in the 1e5 range) and 1e-9 on the exact one;
    /// the background of the exact image is recovered to 1e-6.
    @Test func testFitRecoversPlantedIntensities() throws {
        for name in ["fel-exact", "fel", "cno", "fecu", "fel-conv"] {
            let c = try planted(name)
            let result = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope, lowLoss: c.low)
            #expect(result.convolved == (c.low != nil))
            let truth = c.record["truth"] as! [String: Any]
            let intensity = truth["intensity"] as! [String: Any]
            for (g, edge) in result.edges.enumerated() {
                let key = edge.element + "_" + (edge.subshell == "K1" ? "K" : edge.subshell)
                let want = ModelFixtures.nums(intensity[key])
                for p in 0 ..< want.count {
                    let got = try #require(result.pixels[p][g].intensity, Comment(rawValue: "\(name) \(p)"))
                    let tol = name == "fel-exact" ? 1e-9 : 5e-4
                    #expect(abs(got - want[p]) <= tol * want[p], Comment(rawValue: "\(name) \(key) pixel \(p): \(got) vs \(want[p])"))
                    if c.low != nil { #expect(result.pixels[p][g].arealDensityPerNM2 == got * 1e10) } else { #expect(result.pixels[p][g].arealDensityPerNM2 == nil) }
                }
            }
            if name == "fel-exact" {
                let a = ModelFixtures.nums(truth["A"]), r = ModelFixtures.nums(truth["r"])
                for p in 0 ..< a.count {
                    let bg = try #require(result.backgrounds[p])
                    #expect(abs(bg.a - a[p]) <= 1e-6 * a[p] && abs(bg.r - r[p]) <= 1e-6, Comment(rawValue: "pixel \(p): \(bg)"))
                    #expect(result.residualSumOfSquares[p]! < 1e-3)
                }
            }
        }
    }

    /// The shells of one element and family share one intensity: one master (the last name), the others ride on it.
    @Test func testTwinsShareTheMastersIntensity() throws {
        let c = try planted("fel")
        let one = try EELSModelFit.fit(coreLoss: c.core, edges: [.ironL3], microscope: c.microscope)
        let two = try EELSModelFit.fit(coreLoss: c.core, edges: [.ironL2, .ironL3], microscope: c.microscope)
        let swapped = try EELSModelFit.fit(coreLoss: c.core, edges: [.ironL3, .ironL2], microscope: c.microscope)
        #expect(two.edges == [.ironL3] && two.shells == [[.ironL2, .ironL3]])
        #expect(swapped.edges == two.edges && swapped.pixels == two.pixels)
        #expect(one.pixels[0][0].intensity != two.pixels[0][0].intensity)               // the L2 shape is in the model, so L3 alone cannot give the same amount
        // K and L of one element are independent edges
        let both = try EELSModelFit.fit(coreLoss: try ModelFixtures.wide(c.core), edges: [.ironL3, .ironL2, .copperL3, .copperL2], microscope: c.microscope)
        #expect(both.edges == [.ironL3, .copperL3])
    }

    @Test func testRefusals() throws {
        let c = try planted("fel")
        func fit(_ edges: [CoreLossEdge], mask: PixelMask? = nil, low: LowLossSpectrumImage? = nil, options: EELSModelOptions = .init(),
                 microscope: EELSMicroscope? = nil) throws {
            _ = try EELSModelFit.fit(coreLoss: c.core, edges: edges, microscope: microscope ?? c.microscope, lowLoss: low, mask: mask, options: options)
        }
        #expect(throws: EELSModelError.self) { try fit([]) }
        #expect(throws: EELSModelError.duplicateEdge("Fe L3")) { try fit([.ironL3, .ironL3]) }
        #expect(throws: EELSModelError.edgeNotBundled("Fe M3")) { try fit([CoreLossEdge(element: "Fe", subshell: "M3", onsetEV: 54)]) }
        #expect(throws: EELSModelError.self) { try fit([.carbonK] ) }                       // onset below the axis
        #expect(throws: EELSModelError.self) { try fit([.copperL3] ) }                      // onset beyond the axis end
        #expect(throws: EELSModelError.maskShapeMismatch(expected: 6, got: 2)) { try fit([.ironL3], mask: [true, false]) }
        #expect(throws: EELSModelError.invalidExponentRange) { try fit([.ironL3], options: EELSModelOptions(exponentRange: 3 ... 3)) }
        #expect(throws: EELSModelError.invalidMicroscope) { try fit([.ironL3], microscope: EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 0)) }
        #expect(throws: EELSModelError.self) { try fit([.ironL3], options: EELSModelOptions(startEnergyEV: 1e6)) }
        #expect(throws: EELSModelError.self) { try fit([.ironL3], options: EELSModelOptions(startEnergyEV: 706)) }       // the pre-edge window is too narrow
        let cn = try planted("fel-conv")
        let ll = try #require(cn.low)
        let wrongScale = try LowLossSpectrumImage(nx: 3, ny: 2, channels: ll.channels, counts: ll.counts, energyOffsetEV: ll.energyOffsetEV, energyScaleEV: 0.4)
        #expect(throws: EELSModelError.lowLossScaleMismatch(coreEV: 0.5, lowEV: 0.4)) { try fit([.ironL3], low: wrongScale) }
        let noZero = try LowLossSpectrumImage(nx: 3, ny: 2, channels: ll.channels, counts: ll.counts, energyOffsetEV: 10, energyScaleEV: 0.5)
        #expect(throws: EELSModelError.lowLossAxisHasNoZero) { try fit([.ironL3], low: noZero) }
        let wrongShape = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 120, counts: Array(ll.counts[0 ..< 120]), energyOffsetEV: -20, energyScaleEV: 0.5)
        #expect(throws: EELSModelError.lowLossShapeMismatch(expected: 6, got: 1)) { try fit([.ironL3], low: wrongShape) }
    }

    @Test func testMaskedPixelsAreSkipped() throws {
        let c = try planted("fel")
        var mask = [Bool](repeating: true, count: 6)
        mask[2] = false
        let result = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope, mask: mask)
        #expect(result.pixels[2][0].unavailable == .masked && result.pixels[2][0].intensity == nil)
        #expect(result.backgrounds[2] == nil && result.modelCurve(pixel: 2) == nil)
        #expect(result.pixels[3][0].intensity != nil)
        let curve = try #require(result.modelCurve(pixel: 3))
        #expect(curve.count == c.core.channels && curve.allSatisfy { $0.isFinite })
        #expect(result.modelCurve(pixel: 99) == nil)
    }

    /// An exponent outside the search range is reported at the bound rather than hidden.
    @Test func testExponentAtBoundIsFlagged() throws {
        let c = try planted("fel-exact")
        let result = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope, options: EELSModelOptions(exponentRange: 0 ... 2))
        #expect(result.exponentAtBound.allSatisfy { $0 })
        #expect(result.backgrounds.allSatisfy { $0.map { abs($0.r - 2) < 1e-6 } ?? false })
    }

    @Test func testFitBackgroundAndTwoAreaShapes() throws {
        let c = try planted("fel-exact")
        let two = try EELSModelFit.twoAreaBackground(coreLoss: c.core, edges: c.edges)
        let bg = try EELSModelFit.fitBackground(coreLoss: c.core, edges: c.edges)
        #expect(two.count == 6 && bg.count == 6 && bg.allSatisfy { $0 != nil })
        var mask = [Bool](repeating: true, count: 6); mask[0] = false
        #expect(try EELSModelFit.fitBackground(coreLoss: c.core, edges: c.edges, mask: mask)[0] == nil)
        #expect(try EELSModelFit.twoAreaBackground(coreLoss: c.core, edges: c.edges, mask: mask)[0] == nil)
        // a start energy inside the axis moves the pre-edge window, not the answer on a pure power law
        let moved = try EELSModelFit.fitBackground(coreLoss: c.core, edges: c.edges, options: EELSModelOptions(startEnergyEV: 650))
        for p in 0 ..< 6 { #expect(abs(moved[p]!.r - bg[p]!.r) < 1e-6) }
    }

    @Test func testCompositionFromFittedIntensities() throws {
        let c = try planted("fecu")
        let result = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope)
        let comp = try EELSQuantification.composition(result, symbols: ["Fe", "Cu"])
        #expect(comp.count == 6)
        let intensity = ModelFixtures.nums((c.record["truth"] as! [String: Any])["intensity"].flatMap { ($0 as! [String: Any])["Fe_L3"] })
        let cu = ModelFixtures.nums((c.record["truth"] as! [String: Any])["intensity"].flatMap { ($0 as! [String: Any])["Cu_L3"] })
        for p in 0 ..< 6 {
            let px = comp[p]
            #expect(px.unavailable == nil && px.atomicPercent.count == 2)
            let atFe = 100 * intensity[p] / (intensity[p] + cu[p])
            #expect(abs(px.atomicPercent[0] - atFe) < 0.05, Comment(rawValue: "pixel \(p): \(px.atomicPercent) vs \(atFe)"))
            #expect(abs(px.atomicPercent.reduce(0, +) - 100) < 1e-9 && abs(px.weightPercent.reduce(0, +) - 100) < 1e-9)
            let wtFe = 100 * intensity[p] * 55.845 / (intensity[p] * 55.845 + cu[p] * 63.546)
            #expect(abs(px.weightPercent[0] - wtFe) < 0.05)
        }
        #expect(throws: EELSModelError.symbolNotFitted("Al")) { try EELSQuantification.composition(result, symbols: ["Fe", "Al"]) }
        // masked pixel: no composition, with the mask's reason
        var mask = [Bool](repeating: true, count: 6); mask[1] = false
        let masked = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope, mask: mask)
        let m = try EELSQuantification.composition(masked, symbols: ["Fe"])
        #expect(m[1].unavailable == .masked && m[1].atomicPercent.isEmpty)
        #expect(abs(m[0].atomicPercent[0] - 100) < 1e-12 && abs(m[0].weightPercent[0] - 100) < 1e-12)
    }

    @Test func testRegionSumAndItsFit() throws {
        let c = try planted("fel")
        var mask = [Bool](repeating: false, count: 6)
        mask[1] = true; mask[4] = true
        let sum = try c.core.sum(mask: mask)
        #expect(sum.nx == 1 && sum.ny == 1 && sum.channels == c.core.channels && sum.energyOffsetEV == c.core.energyOffsetEV)
        let n = c.core.channels
        for k in [0, 100, n - 1] { #expect(sum.counts[k] == c.core.counts[n + k] + c.core.counts[4 * n + k]) }
        let low = try planted("fel-conv").low!
        let lsum = try low.sum(mask: mask)
        #expect(lsum.counts[10] == low.counts[low.channels + 10] + low.counts[4 * low.channels + 10])
        #expect(throws: EELSModelError.emptyMask) { try c.core.sum(mask: [Bool](repeating: false, count: 6)) }
        #expect(throws: EELSModelError.maskShapeMismatch(expected: 6, got: 5)) { try c.core.sum(mask: [Bool](repeating: true, count: 5)) }
        // a one-pixel region result works like an image: its composition is the intensity ratio of the summed spectrum
        let result = try EELSModelFit.fit(coreLoss: sum, edges: c.edges, microscope: c.microscope)
        #expect(result.pixels.count == 1 && result.pixels[0][0].intensity != nil)
        #expect(abs(try EELSQuantification.composition(result, symbols: ["Fe"])[0].atomicPercent[0] - 100) < 1e-12)
    }
}

/// The pins file of `tools/eels-chain/model.py`, shared by the fast and the parity targets.
struct ModelCase {
    let edges: [CoreLossEdge]
    let microscope: EELSMicroscope
    let core: CoreLossSpectrumImage
    let low: LowLossSpectrumImage?
    let record: [String: Any]
}

enum ModelFixtures {
    nonisolated(unsafe) static let pins: [String: Any] = {
        let url = FixtureDirs.fixtures(of: "SpectroEELSTests").appendingPathComponent("eels16-model-pins.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static func nums(_ any: Any?) -> [Double] { (any as! [NSNumber]).map(\.doubleValue) }

    static func array(_ name: String) -> [Double] {
        let data = try! Data(contentsOf: FixtureDirs.fixtures(of: "SpectroEELSTests").appendingPathComponent("eels16-model-\(name).f64"))
        return data.withUnsafeBytes { raw in (0 ..< raw.count / 8).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self) } }
    }

    static func make(_ name: String, _ c: [String: Any]) throws -> ModelCase {
        let edges = (c["edges"] as! [String]).map { s -> CoreLossEdge in
            let parts = s.split(separator: "_").map(String.init)
            return CoreLossEdge.bundled(parts[0], parts[1] == "K" ? "K1" : parts[1])!
        }
        let mic = nums(c["microscope"])
        let ax = c["axis"] as! [String: Any]
        let core = try CoreLossSpectrumImage(nx: c["nx"] as! Int, ny: c["ny"] as! Int, channels: ax["size"] as! Int, counts: array(c["coreFile"] as! String),
                                             energyOffsetEV: (ax["offsetEV"] as! NSNumber).doubleValue, energyScaleEV: (ax["scaleEV"] as! NSNumber).doubleValue)
        var low: LowLossSpectrumImage?
        if let f = c["lowLossFile"] as? String {
            let la = c["lowLossAxis"] as! [String: Any]
            low = try LowLossSpectrumImage(nx: c["nx"] as! Int, ny: c["ny"] as! Int, channels: la["size"] as! Int, counts: array(f),
                                           energyOffsetEV: (la["offsetEV"] as! NSNumber).doubleValue, energyScaleEV: (la["scaleEV"] as! NSNumber).doubleValue)
        }
        return ModelCase(edges: edges, microscope: EELSMicroscope(beamEnergyKeV: mic[0], convergenceMrad: mic[1], collectionMrad: mic[2]), core: core, low: low, record: c)
    }

    /// The Fe-only image read as if it reached 1500 eV, so a Cu edge has an onset inside the axis (zeros appended).
    static func wide(_ core: CoreLossSpectrumImage) throws -> CoreLossSpectrumImage {
        let extra = 1000
        var counts = [Double]()
        for p in 0 ..< core.pixelCount { counts += core.counts[p * core.channels ..< (p + 1) * core.channels] + [Double](repeating: 1, count: extra) }
        return try CoreLossSpectrumImage(nx: core.nx, ny: core.ny, channels: core.channels + extra, counts: counts, energyOffsetEV: core.energyOffsetEV, energyScaleEV: core.energyScaleEV)
    }
}
