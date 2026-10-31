//
//  DetectorAndMapSigmaTests.swift
//  Role: the detector term of the sigma on wt% and at% (`quantifyWithSigma(takeOffSigmaDegrees:)`) and the per-pixel sigma maps
//        (`quantifyMapsWithSigma`). No Python counterpart (eXSpy reports no sigma on a composition). Coverage on planted cases, as
//        QuantificationSigmaCoverageTests: the truth is the noise-free quantification at the true take-off angle; each draw adds Poisson
//        noise to the counts and draws the measured angle with its sigma. Red before the change: neither the argument nor the maps existed.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEDX

struct DetectorAndMapSigmaTests {

    private static let elements = ["Al", "Cr", "Ni"]
    private static let base: [Double] = [2000, 1500, 800]
    private static let energies = [1.4867, 5.4147, 7.4781]
    private static let k = [1.0, 1.47, 1.72]

    private struct Rng {
        var x = Xoshiro256StarStar(seed: 20261031)
        mutating func poisson(_ l: Double) -> Double { x.poisson(l) }
        mutating func normal() -> Double { (-2 * log(x.uniform())).squareRoot() * cos(2 * Double.pi * x.uniform()) }
    }

    private static func absorption(takeOff: Double = 20) -> EDXAbsorptionSetting {
        var a = EDXAbsorptionSetting(takeOffDegrees: takeOff, lineEnergiesKeV: energies)
        a.convergencePercent = 1e-8; a.maxIterations = 500
        return a
    }

    private static func setup(thickness t: Double, takeOff: Double = 20) -> EDXQuantificationSetup {
        EDXQuantificationSetup(elements: elements, method: .cliffLorimer(kFactors: k, thicknessNm: t), absorption: absorption(takeOff: takeOff))
    }

    /// Fractions within 1 and 2 sigma of the truth: [wt% 1, wt% 2, at% 1, at% 2] per element.
    private static func coverage(draws: Int, intensities I: [Double], truth: EDXQuantificationPixel, angleSigma: Double, setup: EDXQuantificationSetup,
                                 sigma: ([Double], EDXQuantificationSetup) throws -> EDXQuantificationSigma) throws -> [[Double]] {
        var rng = Rng()
        var c = [[Double]](repeating: [0, 0, 0, 0], count: I.count)
        for _ in 0..<draws {
            let y = I.map { rng.poisson($0) }
            var s = setup
            s.absorption?.takeOffDegrees = 20 + angleSigma * rng.normal()
            let r = try sigma(y, s)
            for i in I.indices {
                let dw = abs(r.pixel.weightPercent[i] - truth.weightPercent[i]), da = abs(r.pixel.atomicPercent[i] - truth.atomicPercent[i])
                if dw <= r.weightSigma[i] { c[i][0] += 1 }
                if dw <= 2 * r.weightSigma[i] { c[i][1] += 1 }
                if da <= r.atomicSigma[i] { c[i][2] += 1 }
                if da <= 2 * r.atomicSigma[i] { c[i][3] += 1 }
            }
        }
        return c.map { $0.map { $0 / Double(draws) } }
    }

    private static func expectNominal(_ c: [[Double]], _ what: String) {
        for (i, e) in c.enumerated() {
            for j in [0, 2] { #expect(e[j] > 0.61 && e[j] < 0.75, "\(what) [\(i)][\(j)] within 1 sigma: \(e[j])") }
            for j in [1, 3] { #expect(e[j] > 0.92 && e[j] < 0.98, "\(what) [\(i)][\(j)] within 2 sigma: \(e[j])") }
        }
    }

    /// 400 nm with absorption, a 20 degree take-off read with a 2 degree sigma (a holder tilt off the stage), 54 000 Al counts: the
    /// angle term dominates the counting term on Al K alpha, the most absorbed line.
    @Test func takeOffSigmaRestoresCoverageOfCliffLorimerWithAbsorption() throws {
        let truthSetup = Self.setup(thickness: 400)
        let I = Self.base.map { $0 * 27 }
        let truth = try EDXQuantification.quantify(intensities: I, setup: truthSetup)
        let countingOnly = try Self.coverage(draws: 1000, intensities: I, truth: truth, angleSigma: 2, setup: truthSetup) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, setup: s)
        }
        #expect(countingOnly[0][0] < 0.4 && countingOnly[0][2] < 0.4, "the counting sigma alone under-covers: \(countingOnly)")
        let full = try Self.coverage(draws: 1000, intensities: I, truth: truth, angleSigma: 2, setup: truthSetup) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, takeOffSigmaDegrees: 2, setup: s)
        }
        Self.expectNominal(full, "CL take-off")
    }

    @Test func theDetectorTermVanishesWithoutAbsorptionAndAddsInQuadrature() throws {
        var plain = Self.setup(thickness: 120); plain.absorption = nil
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: Self.base, takeOffSigmaDegrees: 2, setup: plain) }
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: Self.base, takeOffSigmaDegrees: -1, setup: Self.setup(thickness: 120)) }
        let a = try EDXQuantification.quantifyWithSigma(intensities: Self.base, thicknessSigmaNm: 12, takeOffSigmaDegrees: 2, setup: Self.setup(thickness: 120))
        let a0 = try EDXQuantification.quantifyWithSigma(intensities: Self.base, thicknessSigmaNm: 12, setup: Self.setup(thickness: 120))
        #expect(a.weightDetectorSigma.allSatisfy { $0 > 0 } && a0.weightDetectorSigma == [0, 0, 0])
        for i in 0..<3 {
            let q = [a.weightCountingSigma[i], a.weightThicknessSigma[i], a.weightDetectorSigma[i]].reduce(0) { $0 + $1 * $1 }.squareRoot()
            #expect(abs(a.weightSigma[i] - q) < 1e-12)
        }
        // Against a hand difference of the quantification: dY/dalpha x sigma at a 0.01 degree step.
        let up = try EDXQuantification.quantify(intensities: Self.base, setup: Self.setup(thickness: 120, takeOff: 20.01))
        let dn = try EDXQuantification.quantify(intensities: Self.base, setup: Self.setup(thickness: 120, takeOff: 19.99))
        for i in 0..<3 {
            let hand = abs(up.weightPercent[i] - dn.weightPercent[i]) / 0.02 * 2
            #expect(abs(a.weightDetectorSigma[i] - hand) < 1e-3 * hand + 1e-9, "\(i): \(a.weightDetectorSigma[i]) against \(hand)")
        }
    }

    // MARK: - Maps

    private static let rows = 16, columns = 16

    /// A planted wedge: the take-off angle runs from 15 to 25 degrees across the columns (a curved specimen), the counts from 0.5 to 1.5 times
    /// `base` down the rows.
    private static func planted() -> (I: [[Double]], angles: [Double]) {
        let pixels = rows * columns
        var I = [[Double]](repeating: [Double](repeating: 0, count: pixels), count: 3)
        var angles = [Double](repeating: 0, count: pixels)
        for r in 0..<rows { for c in 0..<columns {
            let p = r * columns + c
            for e in 0..<3 { I[e][p] = base[e] * (0.5 + Double(r) / Double(rows - 1)) }
            angles[p] = 15 + 10 * Double(c) / Double(columns - 1)
        } }
        return (I, angles)
    }

    @Test func theMapsAreQuantifyMapsAndEachPixelIsQuantifyWithSigma() throws {
        let (I, angles) = Self.planted()
        var mask = [Bool](repeating: false, count: Self.rows * Self.columns); mask[5] = true
        var bad = I; bad[0][7] = -1; bad[1][7] = -1; bad[2][7] = -1   // all-negative intensities: the composition fails there
        let s = Self.setup(thickness: 200)
        let m = try EDXQuantification.quantifyMapsWithSigma(intensityMaps: bad, rows: Self.rows, columns: Self.columns, setup: s,
                                                            thicknessSigmaNm: 20, takeOffSigmaDegrees: 1, navigationMask: mask,
                                                            takeOffDegreesPerPixel: angles)
        let plain = try EDXQuantification.quantifyMaps(intensityMaps: bad, rows: Self.rows, columns: Self.columns, setup: s, navigationMask: mask,
                                                       takeOffDegreesPerPixel: angles)
        // Equal to quantifyMaps (NaN on the failed pixel compares as equal here).
        func same(_ a: [Double], _ b: [Double]) -> Bool { zip(a, b).allSatisfy { $0 == $1 || ($0.isNaN && $1.isNaN) } }
        #expect(zip(m.maps.weightPercent, plain.weightPercent).allSatisfy(same) && zip(m.maps.atomicPercent, plain.atomicPercent).allSatisfy(same))
        #expect(same(m.maps.massThickness ?? [], plain.massThickness ?? []) && m.maps.failures == plain.failures && m.maps.iterations == plain.iterations)
        #expect(plain.failures[7] != nil && m.validation == "none")
        #expect(m.weightSigma.allSatisfy { $0[5] == 0 } && m.atomicSigma.allSatisfy { $0[5] == 0 })
        #expect(m.weightSigma.allSatisfy { $0[7].isNaN } && m.atomicSigma.allSatisfy { $0[7].isNaN } && m.massThicknessSigma?[7].isNaN == true)
        for p in [0, 17, 100, 255] {
            var sp = s; sp.absorption?.takeOffDegrees = angles[p]
            let one = try EDXQuantification.quantifyWithSigma(intensities: (0..<3).map { bad[$0][p] }, thicknessSigmaNm: 20, takeOffSigmaDegrees: 1, setup: sp)
            for e in 0..<3 {
                #expect(m.weightSigma[e][p] == one.weightSigma[e] && m.atomicSigma[e][p] == one.atomicSigma[e], "pixel \(p) element \(e)")
                #expect(abs(m.maps.weightPercent[e][p] - one.pixel.weightPercent[e]) <= 1e-9 * max(one.pixel.weightPercent[e], 1))
            }
            #expect(m.massThicknessSigma?[p] == one.massThicknessSigma)
        }
        #expect(m.sigmaFailures.allSatisfy { $0 == nil })
    }

    /// Coverage per pixel on the planted wedge: 8 Poisson realisations of the 256-pixel map (2048 pixel draws) with the counting sigma of each
    /// pixel's own counts (1000 to 3000 Al counts) must hold about 68 and 95 % of the pixels within 1 and 2 sigma of the noise-free map.
    @Test func theCountingSigmaMapCoversThePlantedWedge() throws {
        let (I, angles) = Self.planted()
        let s = Self.setup(thickness: 200)
        let truth = try EDXQuantification.quantifyMaps(intensityMaps: I, rows: Self.rows, columns: Self.columns, setup: s, takeOffDegreesPerPixel: angles)
        var rng = Rng()
        var w1 = [Double](repeating: 0, count: 3), w2 = w1, a1 = w1, a2 = w1
        let realisations = 8, pixels = Self.rows * Self.columns
        for _ in 0..<realisations {
            let y = I.map { $0.map { rng.poisson($0) } }
            let m = try EDXQuantification.quantifyMapsWithSigma(intensityMaps: y, rows: Self.rows, columns: Self.columns, setup: s, takeOffDegreesPerPixel: angles)
            for e in 0..<3 { for p in 0..<pixels {
                let dw = abs(m.maps.weightPercent[e][p] - truth.weightPercent[e][p]), da = abs(m.maps.atomicPercent[e][p] - truth.atomicPercent[e][p])
                if dw <= m.weightSigma[e][p] { w1[e] += 1 }
                if dw <= 2 * m.weightSigma[e][p] { w2[e] += 1 }
                if da <= m.atomicSigma[e][p] { a1[e] += 1 }
                if da <= 2 * m.atomicSigma[e][p] { a2[e] += 1 }
            } }
        }
        let d = Double(realisations * pixels)
        for e in 0..<3 {
            for (name, one, two) in [("wt%", w1[e] / d, w2[e] / d), ("at%", a1[e] / d, a2[e] / d)] {
                #expect(one > 0.63 && one < 0.73, "\(name)[\(e)] within 1 sigma: \(one)")
                #expect(two > 0.93 && two < 0.97, "\(name)[\(e)] within 2 sigma: \(two)")
            }
        }
    }

    @Test func mapRefusals() {
        let (I, _) = Self.planted()
        let s = Self.setup(thickness: 200)
        #expect(throws: QuantError.self) {
            _ = try EDXQuantification.quantifyMapsWithSigma(intensityMaps: I, rows: Self.rows, columns: Self.columns, setup: s, intensitySigmaMaps: [[1]])
        }
        // A bad shared argument is refused once, not per pixel.
        var plain = s; plain.absorption = nil
        #expect(throws: QuantError.self) {
            _ = try EDXQuantification.quantifyMapsWithSigma(intensityMaps: I, rows: Self.rows, columns: Self.columns, setup: plain, takeOffSigmaDegrees: 1)
        }
        #expect(throws: QuantError.self) {
            _ = try EDXQuantification.quantifyMapsWithSigma(intensityMaps: I, rows: Self.rows, columns: Self.columns, setup: s, thicknessSigmaNm: -1)
        }
    }

    /// A pixel whose sigma alone cannot be propagated (a NaN in its sigma map) reads NaN sigma with its reason; its composition stands.
    @Test func aPixelWhoseSigmaFailsKeepsItsComposition() throws {
        let (I, _) = Self.planted()
        let s = Self.setup(thickness: 200)
        var sm = I.map { $0.map { $0.squareRoot() } }
        sm[1][9] = .nan
        let m = try EDXQuantification.quantifyMapsWithSigma(intensityMaps: I, rows: Self.rows, columns: Self.columns, setup: s, intensitySigmaMaps: sm)
        #expect(m.sigmaFailures[9] != nil && m.sigmaFailures.enumerated().allSatisfy { $0.offset == 9 || $0.element == nil })
        #expect(m.weightSigma.allSatisfy { $0[9].isNaN } && m.atomicSigma.allSatisfy { $0[9].isNaN } && m.massThicknessSigma?[9].isNaN == true)
        #expect(m.maps.failures[9] == nil && m.maps.weightPercent.allSatisfy { $0[9].isFinite && $0[9] > 0 })
        // Elsewhere the given sigmas are the Poisson ones, so the map equals the default counting sigma there.
        let d = try EDXQuantification.quantifyMapsWithSigma(intensityMaps: I, rows: Self.rows, columns: Self.columns, setup: s)
        #expect(abs(m.weightSigma[0][10] - d.weightSigma[0][10]) <= 1e-12 * d.weightSigma[0][10])
    }
}
