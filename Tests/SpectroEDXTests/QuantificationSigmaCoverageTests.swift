//
//  QuantificationSigmaCoverageTests.swift
//  Role: the thickness and dose terms of the sigma on wt% and at% (`quantifyWithSigma(thicknessSigmaNm:doseRelativeSigma:)`).
//        No Python counterpart (eXSpy reports no sigma on a composition). Coverage on planted cases: the truth is the noise-free
//        quantification at the true thickness and dose; each draw adds Poisson noise to the counts AND draws the measured thickness
//        (10 %) or dose (5 %) with its sigma; the reported sigma must then hold about 68 % of the draws within 1 sigma and about 95 %
//        within 2 sigma, where the counting sigma alone holds far fewer (the diagnosis of the missing terms).
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEDX

struct QuantificationSigmaCoverageTests {

    private static let elements = ["Al", "Cr", "Ni"]
    private static let base: [Double] = [2000, 1500, 800]
    private static let energies = [1.4867, 5.4147, 7.4781]

    private struct Rng {
        var x = Xoshiro256StarStar(seed: 20261031)
        mutating func poisson(_ l: Double) -> Double { x.poisson(l) }
        mutating func normal() -> Double { (-2 * log(x.uniform())).squareRoot() * cos(2 * Double.pi * x.uniform()) }
    }

    private struct Coverage { var w1: [Double]; var w2: [Double]; var a1: [Double]; var a2: [Double] }

    /// Fraction of draws whose wt% and at% lie within 1 and 2 reported sigma of the truth, per element.
    private static func coverage(truthSetup: EDXQuantificationSetup, intensities I: [Double], draws: Int,
                                 measured: (inout Rng) -> EDXQuantificationSetup,
                                 sigma: ([Double], EDXQuantificationSetup) throws -> EDXQuantificationSigma) throws -> Coverage {
        let truth = try EDXQuantification.quantify(intensities: I, setup: truthSetup)
        var rng = Rng()
        let n = I.count
        var w1 = [Double](repeating: 0, count: n), w2 = w1, a1 = w1, a2 = w1
        for _ in 0..<draws {
            let y = I.map { rng.poisson($0) }
            let s = measured(&rng)
            let r = try sigma(y, s)
            for i in 0..<n {
                let dw = abs(r.pixel.weightPercent[i] - truth.weightPercent[i]), da = abs(r.pixel.atomicPercent[i] - truth.atomicPercent[i])
                if dw <= r.weightSigma[i] { w1[i] += 1 }
                if dw <= 2 * r.weightSigma[i] { w2[i] += 1 }
                if da <= r.atomicSigma[i] { a1[i] += 1 }
                if da <= 2 * r.atomicSigma[i] { a2[i] += 1 }
            }
        }
        let d = Double(draws)
        return Coverage(w1: w1.map { $0 / d }, w2: w2.map { $0 / d }, a1: a1.map { $0 / d }, a2: a2.map { $0 / d })
    }

    /// About 68 % within 1 sigma and 95 % within 2 sigma (1000 draws: binomial sd 1.5 and 0.7 points).
    private static func expectNominal(_ c: Coverage, _ what: String) {
        for (name, one, two) in [("wt%", c.w1, c.w2), ("at%", c.a1, c.a2)] {
            for i in 0..<one.count {
                #expect(one[i] > 0.61 && one[i] < 0.75, "\(what) \(name)[\(i)] within 1 sigma: \(one[i])")
                #expect(two[i] > 0.92 && two[i] < 0.98, "\(what) \(name)[\(i)] within 2 sigma: \(two[i])")
            }
        }
    }

    private static func absorption() -> EDXAbsorptionSetting {
        var a = EDXAbsorptionSetting(takeOffDegrees: 20, lineEnergiesKeV: energies)
        a.convergencePercent = 1e-8; a.maxIterations = 500
        return a
    }

    @Test func thicknessSigmaRestoresCoverageOfCliffLorimerWithAbsorption() throws {
        // 400 nm, 10 % thickness sigma, 54 000 / 40 500 / 21 600 counts: the thickness term dominates the counting term.
        let t = 400.0, k = [1.0, 1.47, 1.72]
        let I = Self.base.map { $0 * 27 }
        let truthSetup = EDXQuantificationSetup(elements: Self.elements, method: .cliffLorimer(kFactors: k, thicknessNm: t), absorption: Self.absorption())
        let measured: (inout Rng) -> EDXQuantificationSetup = { rng in
            var s = truthSetup
            s.method = .cliffLorimer(kFactors: k, thicknessNm: t * max(1 + 0.10 * rng.normal(), 0.2))
            return s
        }
        func typed(_ s: EDXQuantificationSetup) -> Double { if case .cliffLorimer(_, let tm?) = s.method { return tm }; return .nan }
        let countingOnly = try Self.coverage(truthSetup: truthSetup, intensities: I, draws: 1000, measured: measured) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, setup: s)
        }
        #expect(countingOnly.w1[0] < 0.4 && countingOnly.a1[0] < 0.4, "the counting sigma alone under-covers: \(countingOnly.w1)")
        let full = try Self.coverage(truthSetup: truthSetup, intensities: I, draws: 1000, measured: measured) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, thicknessSigmaNm: 0.10 * typed(s), setup: s)
        }
        Self.expectNominal(full, "CL 400 nm")
    }

    @Test func doseSigmaRestoresCoverageOfZetaWithAbsorption() throws {
        // Zeta with absorption at a mass thickness of 2.4e-3 kg/m^2, 5 % dose sigma, 200 000 / 150 000 / 80 000 counts.
        let I = Self.base.map { $0 * 100 }
        let truthSetup = EDXQuantificationSetup(elements: Self.elements, method: .zeta(zetaFactors: [20, 40, 60]), absorption: Self.absorption(),
                                                beamCurrentNA: 0.5, liveTimeSeconds: 2.5)
        let measured: (inout Rng) -> EDXQuantificationSetup = { rng in
            var s = truthSetup
            s.beamCurrentNA = 0.5 * max(1 + 0.05 * rng.normal(), 0.2)
            return s
        }
        let countingOnly = try Self.coverage(truthSetup: truthSetup, intensities: I, draws: 1000, measured: measured) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, setup: s)
        }
        #expect(countingOnly.w1[0] < 0.4 && countingOnly.a1[0] < 0.4, "the counting sigma alone under-covers: \(countingOnly.w1)")
        let full = try Self.coverage(truthSetup: truthSetup, intensities: I, draws: 1000, measured: measured) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, doseRelativeSigma: 0.05, setup: s)
        }
        Self.expectNominal(full, "zeta dose")
    }

    @Test func doseSigmaRestoresCoverageOfCrossSectionWithAbsorption() throws {
        // Sections and current chosen for a mass thickness of a few 1e-3 kg/m^2 (a film of a few hundred nm), as the zeta case.
        let I = Self.base.map { $0 * 100 }
        let truthSetup = EDXQuantificationSetup(elements: Self.elements, method: .crossSection(sectionsBarn: [30, 40, 50], probeAreaNm2: 1.0),
                                                absorption: Self.absorption(), beamCurrentNA: 0.25, liveTimeSeconds: 2.5)
        let m = try #require(try EDXQuantification.quantify(intensities: I, setup: truthSetup).massThickness)
        #expect(m > 5e-4 && m < 1e-2, "planted mass thickness \(m) kg/m^2")
        let measured: (inout Rng) -> EDXQuantificationSetup = { rng in
            var s = truthSetup
            s.beamCurrentNA = 0.25 * max(1 + 0.05 * rng.normal(), 0.2)
            return s
        }
        let countingOnly = try Self.coverage(truthSetup: truthSetup, intensities: I, draws: 1000, measured: measured) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, setup: s)
        }
        #expect(countingOnly.a1[0] < 0.55, "the counting sigma alone under-covers: \(countingOnly.a1)")
        let full = try Self.coverage(truthSetup: truthSetup, intensities: I, draws: 1000, measured: measured) { y, s in
            try EDXQuantification.quantifyWithSigma(intensities: y, doseRelativeSigma: 0.05, setup: s)
        }
        Self.expectNominal(full, "cross-section dose")
    }

    @Test func whereTheTermsVanishAndWhereTheyAreExact() throws {
        // CL without absorption: wt% does not depend on the thickness; the mass thickness is proportional to it.
        let cl = EDXQuantificationSetup(elements: Self.elements, method: .cliffLorimer(kFactors: [1.0, 1.47, 1.72], thicknessNm: 120))
        let c = try EDXQuantification.quantifyWithSigma(intensities: Self.base, thicknessSigmaNm: 12, setup: cl)
        let c0 = try EDXQuantification.quantifyWithSigma(intensities: Self.base, setup: cl)
        #expect(c.weightThicknessSigma.allSatisfy { $0 < 1e-9 } && c.atomicThicknessSigma.allSatisfy { $0 < 1e-9 })
        let m = try #require(c.pixel.massThickness), ms = try #require(c.massThicknessSigma), ms0 = try #require(c0.massThicknessSigma)
        // (the counting term moves the mass thickness too, through the density mean over wt%: the thickness term is the rest)
        #expect(abs((ms * ms - ms0 * ms0).squareRoot() - 0.10 * m) < 1e-6 * m)
        #expect(c.weightSigma == c0.weightSigma && c.weightDoseSigma == [0, 0, 0])

        // Zeta without absorption: the dose cancels in wt% and at%; the mass thickness goes as 1/D (relative sigma s_D).
        let z = EDXQuantificationSetup(elements: Self.elements, method: .zeta(zetaFactors: [20, 40, 60]), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)
        let zs = try EDXQuantification.quantifyWithSigma(intensities: Self.base, doseRelativeSigma: 0.05, setup: z)
        let zs0 = try EDXQuantification.quantifyWithSigma(intensities: Self.base, setup: z)
        #expect(zs.weightDoseSigma.allSatisfy { $0 < 1e-9 } && zs.atomicDoseSigma.allSatisfy { $0 < 1e-9 })
        let zm = try #require(zs.pixel.massThickness), zms = try #require(zs.massThicknessSigma), zms0 = try #require(zs0.massThicknessSigma)
        #expect(abs((zms * zms - zms0 * zms0).squareRoot() - 0.05 * zm) < 1e-6 * zm)

        // With absorption the terms are positive and add in quadrature with the counting term.
        var absorbed = cl; absorbed.absorption = Self.absorption()
        let a = try EDXQuantification.quantifyWithSigma(intensities: Self.base, thicknessSigmaNm: 12, setup: absorbed)
        #expect(a.weightThicknessSigma.allSatisfy { $0 > 0 } && a.validation == "none")
        for i in 0..<3 {
            let q = (a.weightCountingSigma[i] * a.weightCountingSigma[i] + a.weightThicknessSigma[i] * a.weightThicknessSigma[i]).squareRoot()
            #expect(Swift.abs(a.weightSigma[i] - q) < 1e-12)
        }
    }

    @Test func refusals() {
        let cl = EDXQuantificationSetup(elements: ["Al", "Zn"], method: .cliffLorimer(kFactors: [1.0, 1.9], thicknessNm: nil))
        let z = EDXQuantificationSetup(elements: ["Al", "Zn"], method: .zeta(zetaFactors: [20, 40]), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)
        // No typed thickness, or a method without one; a dose sigma on Cliff-Lorimer; negative sigmas.
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], thicknessSigmaNm: 5, setup: cl) }
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], thicknessSigmaNm: 5, setup: z) }
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], doseRelativeSigma: 0.05, setup: cl) }
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], doseRelativeSigma: -0.05, setup: z) }
    }
}
