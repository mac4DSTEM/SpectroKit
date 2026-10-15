//
//  EdgePinsTests.swift
//  Role: EELS slice 2, gate 1 and gate 2 (docs/eels-slice-2-registration.md sections 4.1, 4.3, 7): the port against exSpy
//        7185a4d1's pins in Fixtures/edge-pins.json (written by tools/eels-edge/pins.py before the Swift code), and against
//        pyEELSMODEL eed9f072's cross sections.
//
//  Bounds, registered: effective angle relative 1e-14; qint 1e-12; function(E) and sigma_k 1e-10; background indices equal;
//  I1, I2, r, A, the background, I_k, I_b 1e-12; n 1e-10. pyEELSMODEL: within 3 %.
//

import Foundation
import Testing
import SpectroCore
import SpectroEELS

/// edge-pins.json and edge-planted.json as plain dictionaries (the file is large and deep; only what is asserted is read).
enum EdgeFixtures {
    nonisolated(unsafe) static let pins: [String: Any] = load("edge-pins.json")   // read-only after first load
    nonisolated(unsafe) static let planted: [String: Any] = load("edge-planted.json")

    static func load(_ name: String) -> [String: Any] {
        do {
            let data = try Data(contentsOf: EELSFixtures.url(name))
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        } catch { fatalError("\(name): \(error)") }
    }

    static func edge(_ element: String) -> CoreLossEdge {
        CoreLossEdge.bundled.first { $0.element == element }!
    }

    /// A planted core-loss image (3 x 5 pixels, 150 eV + 0.25 eV x 2000).
    static func core(_ file: String) throws -> CoreLossSpectrumImage {
        let ax = planted["coreLossAxis"] as! [String: Any]
        return try CoreLossSpectrumImage(nx: 5, ny: 3, channels: ax["size"] as! Int, counts: EELSFixtures.doubles(file),
                                         energyOffsetEV: ax["offset"] as! Double, energyScaleEV: ax["scale"] as! Double)
    }

    /// A planted low-loss image (slice 1's axis, -10 eV + 0.05 eV x 3400).
    static func low(_ file: String) throws -> LowLossSpectrumImage {
        let ax = planted["lowLossAxis"] as! [String: Any]
        return try LowLossSpectrumImage(nx: 5, ny: 3, channels: ax["size"] as! Int, counts: EELSFixtures.doubles(file),
                                        energyOffsetEV: ax["offset"] as! Double, energyScaleEV: ax["scale"] as! Double)
    }

    static let plantedMicroscope = EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)
}

extension Dictionary where Key == String, Value == Any {
    func d(_ k: String) -> [String: Any] { self[k] as! [String: Any] }
    func a(_ k: String) -> [Double] { (self[k] as! [Any]).map { ($0 as? NSNumber)?.doubleValue ?? .nan } }
    func x(_ k: String) -> Double { (self[k] as! NSNumber).doubleValue }
    func i(_ k: String) -> Int { (self[k] as! NSNumber).intValue }
}

struct EdgePinsTests {

    // Gate 1: the cross section on the whole registered grid (192 edge cases x 3 scales x 4 widths).
    @Test func testCrossSectionEqualsExSpyOnTheGrid() throws {
        let grid = EdgeFixtures.pins["grid"] as! [[String: Any]]
        #expect(grid.count == 192)
        let angle = Worst(), qint = Worst(), fn = Worst(), sig = Worst()
        for g in grid {
            let edge = EdgeFixtures.edge(g["element"] as! String)
            let table = try #require(GOSTable.bundled(edge))
            let xs = try #require(EdgeCrossSection(table: table, beamEnergyKeV: g.x("E0"), convergenceMrad: g.x("alpha"),
                                                    collectionMrad: g.x("beta")))
            let tag = "\(edge) E0 \(g.x("E0")) a \(g.x("alpha")) b \(g.x("beta"))"
            angle.record(relativeDifference(xs.effectiveAngleMrad, g.x("effectiveAngleMrad")), tag)
            #expect(table.energyAxis.map { Double($0) } == g.a("tabulatedEnergies"), "\(tag)")
            for (p, e) in zip(xs.qint, g.a("qint")) { qint.record(relativeDifference(p, e), tag) }
            #expect(isEqual(relativeDifference(xs.powerLawR, g.x("powerLawR")), 0, accuracy: 1e-12), "\(tag)")
            #expect(isEqual(relativeDifference(xs.powerLawA, g.x("powerLawA")), 0, accuracy: 1e-12), "\(tag)")
            for s in g["byScale"] as! [[String: Any]] {
                let scale = s.x("scale"), offset = s.x("offset"), n = s.i("nChannels")
                let energies = (0 ..< n).map { offset + scale * Double($0) }
                let f = xs.differential(energies)
                for (p, e) in zip(f, s.a("function")) { fn.record(relativeDifference(p, e), "\(tag) scale \(scale)") }
                let axis = EnergyAxis(offset: offset, scale: scale, size: n)
                for (delta, v) in s.d("byDelta") {
                    let w = v as! [String: Any]
                    let range = try axis.channelRange(from: edge.onsetEV, to: edge.onsetEV + Double(delta)!)
                    #expect(range == (w.i("i0") ..< w.i("i1")), "\(tag) scale \(scale) Δ \(delta)")
                    let sigma = NumpySum.sum(f[range].map { $0 * scale })
                    sig.record(relativeDifference(sigma, w.x("sigmaK")), "\(tag) scale \(scale) Δ \(delta)")
                }
            }
        }
        print("edge pins: effective angle \(angle.value) at \(angle.where_); qint \(qint.value) at \(qint.where_); "
              + "function \(fn.value) at \(fn.where_); sigma_k \(sig.value) at \(sig.where_)")
        #expect(angle.value <= (1e-14), "\(angle.where_)")
        #expect(qint.value <= (1e-12), "\(qint.where_)")
        #expect(fn.value <= (1e-10), "\(fn.where_)")
        #expect(sig.value <= (1e-10), "\(sig.where_)")
    }

    // Gate 1: the spline itself and the q limits for one setting (the steps that locate a divergence).
    @Test func testSplineAndQLimitsEqualExSpy() throws {
        let s = EdgeFixtures.pins.d("splineC")
        let c = s.d("case")
        let table = try #require(GOSTable.bundled(.carbonK))
        let xs = try #require(EdgeCrossSection(table: table, beamEnergyKeV: c.x("E0"),
                                                convergenceMrad: c.x("alpha"), collectionMrad: c.x("beta")))
        #expect(xs.spline.knots == s.a("knots"))
        let worst = zip(xs.spline.coefficients, s.a("coefficients")).map { relativeDifference($0, $1) }.max()!
        #expect(worst <= (1e-10))
        #expect(isEqual(relativeDifference(xs.powerLawR, s.x("extrapolationR")), 0, accuracy: 1e-12))
        #expect(isEqual(relativeDifference(xs.powerLawA, s.x("extrapolationA")), 0, accuracy: 1e-12))
    }

    // Gate 2: pyEELSMODEL's independent integration of the same GOS within 3 %.
    @Test func testCrossSectionWithinThreePercentOfPyEELSMODEL() throws {
        let p = EdgeFixtures.pins.d("pyEELSMODEL")
        let cases = p["cases"] as! [[String: Any]]
        #expect(cases.count == 72)
        var worst = 0.0
        for c in cases {
            let edge = EdgeFixtures.edge(c["element"] as! String)
            let m = EELSMicroscope(beamEnergyKeV: c.x("E0"), convergenceMrad: c.x("alpha"), collectionMrad: c.x("beta"))
            let scale = c.x("scale"), n = c.i("nChannels")
            let energies = (0 ..< n).map { p.x("axisOffset") + scale * Double($0) }
            let f = try EELSEdgeQuantification.differentialCrossSection(edge: edge, microscope: m, energiesEV: energies).barnPerEV
            let sigma = NumpySum.sum(f[c.i("i0") ..< c.i("i1")].map { $0 * scale })
            #expect(isEqual(relativeDifference(sigma, c.x("sigmaExSpy")), 0, accuracy: 1e-10), "\(c)")
            let rel = abs(sigma / c.x("sigmaPyEELSMODEL") - 1)
            worst = max(worst, rel)
            #expect(rel <= 0.03, "\(c)")
        }
        print("pyEELSMODEL: worst |sigma_port / sigma_pyEELSMODEL - 1| = \(worst)")
    }

    // Gate 1: background, windows, I_k, I_b and n on every planted image, window and width.
    @Test func testRatioMethodEqualsExSpyOnThePlantedImages() throws {
        let planted = EdgeFixtures.pins.d("planted")
        let images = planted["images"] as! [[String: Any]]
        let fit = Worst(), sums = Worst(), dens = Worst()
        var compared = 0
        for im in images {
            let core = try EdgeFixtures.core(im["coreFile"] as! String)
            let low = try EdgeFixtures.low(im["lowFile"] as! String)
            for (wname, wv) in im.d("windows") {
                let w = wv as! [String: Any]
                let range = w.a("valueRangeEV")
                for (delta, dv) in w.d("byDelta") {
                    let dd = dv as! [String: Any]
                    let tag = "\(im["coreFile"]!) \(wname) Δ \(delta)"
                    let map = try EELSEdgeQuantification.ratioMethod(
                        coreLoss: core, edge: .carbonK, microscope: EdgeFixtures.plantedMicroscope,
                        lowLoss: .integratedToWidth(low), backgroundWindowEV: range[0]...range[1],
                        integrationWidthEV: Double(delta)!)
                    #expect(map.edgeChannels == (dd.i("i0") ..< dd.i("i1")), "\(tag)")
                    #expect(map.backgroundWindowEV == w.x("x1")...w.x("x2"), "\(tag)")
                    #expect(isEqual(relativeDifference(map.crossSectionBarn, dd.x("sigmaK")), 0, accuracy: 1e-10), "\(tag)")
                    #expect(map.validation == "none")
                    for (p, px) in map.pixels.enumerated() {
                        fit.record(relativeDifference(px.powerLawR.orFail(), w.a("r")[p]), tag)
                        fit.record(relativeDifference(px.powerLawA.orFail(), w.a("A")[p]), tag)
                        sums.record(relativeDifference(px.edgeCounts.orFail(), dd.a("iK")[p]), tag)
                        sums.record(relativeDifference(px.backgroundCounts.orFail(), dd.a("iB")[p]), tag)
                        #expect(px.lowLossIntensity.orFail() == dd.a("iLow")[p], "\(tag)")
                        dens.record(relativeDifference(px.atomsPerNM2.orFail(), dd.a("n")[p]), tag)
                        compared += 1
                    }
                    // The I_0 route (slice 1's fixed thresholds).
                    for (theta, tv) in dd.d("i0Route") {
                        let t = tv as! [String: Any]
                        let tm = try EELSThickness.logRatio(low, threshold: .fixed(Double(theta)!))
                        let m0 = try EELSEdgeQuantification.ratioMethod(
                            coreLoss: core, edge: .carbonK, microscope: EdgeFixtures.plantedMicroscope,
                            lowLoss: .zeroLoss(tm), backgroundWindowEV: range[0]...range[1], integrationWidthEV: Double(delta)!)
                        for (p, px) in m0.pixels.enumerated() {
                            #expect(px.lowLossIntensity.orFail() == t.a("i0")[p], "\(tag) θ \(theta)")
                            dens.record(relativeDifference(px.atomsPerNM2.orFail(), t.a("n")[p]), "\(tag) θ \(theta)")
                        }
                    }
                }
                // The background window's indices and sums, once per window.
                let core0 = try EdgeFixtures.core(im["coreFile"] as! String)
                let axis = try EELSAxis(offset: core0.energyOffsetEV, scale: core0.energyScaleEV, size: core0.channels)
                let pw = try PowerLawWindow(axis: axis, from: range[0], to: range[1])
                #expect([pw.i1, pw.i2, pw.i3] as [Int] == [w.i("i1"), w.i("i2"), w.i("i3")])
                #expect([pw.x1, pw.x2, pw.x3] as [Double] == [w.x("x1"), w.x("x2"), w.x("x3")])
                let from = w.i("backgroundFromChannel"), nb = w.i("backgroundNChannels")
                let bgPins = w["background"] as! [[Any]]
                try core0.counts.withUnsafeBufferPointer { buf in
                    for p in 0 ..< core0.pixelCount {
                        let s = UnsafeBufferPointer(rebasing: buf[(p * core0.channels) ..< ((p + 1) * core0.channels)])
                        let f = try PowerLawFit.estimate(s, window: pw).get()
                        fit.record(relativeDifference(f.i1Sum, w.a("I1")[p]), "I1")
                        fit.record(relativeDifference(f.i2Sum, w.a("I2")[p]), "I2")
                        for k in 0 ..< nb {
                            let b = f.counts(atEnergy: axis.energy(ofChannel: from + k), scale: core0.energyScaleEV)
                            fit.record(relativeDifference(b, (bgPins[p][k] as! NSNumber).doubleValue), "background")
                        }
                    }
                }
            }
        }
        print("planted vs exSpy (\(compared) pixel results): fit \(fit.value) at \(fit.where_); sums \(sums.value) at "
              + "\(sums.where_); n \(dens.value) at \(dens.where_)")
        #expect(compared > 0)
        #expect(fit.value <= (1e-12), "\(fit.where_)")
        #expect(sums.value <= (1e-12), "\(sums.where_)")
        #expect(dens.value <= (1e-10), "\(dens.where_)")
    }
}
