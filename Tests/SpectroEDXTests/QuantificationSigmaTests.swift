//
//  QuantificationSigmaTests.swift
//  Role: sigma on wt% and at% (SpectroKit 0.10.0). No Python counterpart: the propagated first-order sigma is compared with the
//        standard deviation of the quantification over many seeded Poisson realisations of a planted case, within 5 %, for
//        Cliff-Lorimer (plain, with typed-k sigma, with absorption), zeta and cross section, and against hand-derived values for
//        a two-element Cliff-Lorimer case.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEDX

struct QuantificationSigmaTests {

    private static let elements = ["Al", "Cr", "Ni"]
    private static let truth: [Double] = [2000, 1500, 800]

    private struct Rng {
        var x = Xoshiro256StarStar(seed: 20261022)
        mutating func poisson(_ l: Double) -> Double { x.poisson(l) }
        mutating func normal() -> Double { (-2 * log(x.uniform())).squareRoot() * cos(2 * Double.pi * x.uniform()) }
    }

    private static func monteCarlo(setup: EDXQuantificationSetup, truth I: [Double], kRelSigma: [Double]? = nil, draws: Int,
                                   factorsOf make: ((_ factorScale: [Double]) -> EDXQuantificationSetup)? = nil) throws -> (wSD: [Double], aSD: [Double], mSD: Double?) {
        var rng = Rng()
        var w: [[Double]] = [], a: [[Double]] = [], m: [Double] = []
        for _ in 0..<draws {
            let y = I.map { rng.poisson($0) }
            var s = setup
            if let rel = kRelSigma, let make { s = make(rel.map { max(1 + $0 * rng.normal(), 0.05) }) }
            let p = try EDXQuantification.quantify(intensities: y, setup: s)
            w.append(p.weightPercent); a.append(p.atomicPercent); if let mt = p.massThickness { m.append(mt) }
        }
        func sd(_ v: [Double]) -> Double {
            let mean = v.reduce(0, +) / Double(v.count)
            return (v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count - 1)).squareRoot()
        }
        let n = I.count
        return ((0..<n).map { i in sd(w.map { $0[i] }) }, (0..<n).map { i in sd(a.map { $0[i] }) }, m.isEmpty ? nil : sd(m))
    }

    private static func expectClose(_ got: [Double], _ mc: [Double], _ what: String, tol: Double = 0.05) {
        for (i, (g, e)) in zip(got, mc).enumerated() {
            #expect(abs(g / e - 1) < tol, "\(what)[\(i)]: propagated \(g) against Monte Carlo \(e)")
        }
    }

    @Test func cliffLorimerCountingSigmaMatchesMonteCarlo() throws {
        let setup = EDXQuantificationSetup(elements: Self.elements, method: .cliffLorimer(kFactors: [1.0, 1.47, 1.72], thicknessNm: nil))
        let s = try EDXQuantification.quantifyWithSigma(intensities: Self.truth, setup: setup)
        let mc = try Self.monteCarlo(setup: setup, truth: Self.truth, draws: 20000)
        Self.expectClose(s.weightSigma, mc.wSD, "wt%")
        Self.expectClose(s.atomicSigma, mc.aSD, "at%")
        #expect(s.weightFactorSigma == [0, 0, 0] && s.validation == "none")
    }

    @Test func typedKSigmaIsAddedInQuadratureAndMatchesMonteCarlo() throws {
        let k = [1.0, 1.47, 1.72]
        let rel = [0.0, 0.05, 0.05]
        let setup = EDXQuantificationSetup(elements: Self.elements, method: .cliffLorimer(kFactors: k, thicknessNm: nil))
        let s = try EDXQuantification.quantifyWithSigma(intensities: Self.truth, factorRelativeSigmas: rel, setup: setup)
        let mc = try Self.monteCarlo(setup: setup, truth: Self.truth, kRelSigma: rel, draws: 20000) { scale in
            EDXQuantificationSetup(elements: Self.elements, method: .cliffLorimer(kFactors: zip(k, scale).map { $0 * $1 }, thicknessNm: nil))
        }
        Self.expectClose(s.weightSigma, mc.wSD, "wt%")
        Self.expectClose(s.atomicSigma, mc.aSD, "at%")
        for i in 0..<3 { #expect(abs(s.weightSigma[i] * s.weightSigma[i] - s.weightCountingSigma[i] * s.weightCountingSigma[i] - s.weightFactorSigma[i] * s.weightFactorSigma[i]) < 1e-12) }
        #expect(s.weightFactorSigma.allSatisfy { $0 > 0 })
    }

    @Test func twoElementCliffLorimerAgainstTheHandDerivedSigma() throws {
        // C_A/C_B = (kA/kB)(IA/IB); w_A = r/(1+r), r = kA IA/(kB IB). var(w_A) = (dw/dr)^2 var(r); var(r)/r^2 = 1/IA + 1/IB (Poisson).
        let (kA, kB, iA, iB) = (1.0, 1.9, 3000.0, 1200.0)
        let setup = EDXQuantificationSetup(elements: ["Al", "Zn"], method: .cliffLorimer(kFactors: [kA, kB], thicknessNm: nil))
        let s = try EDXQuantification.quantifyWithSigma(intensities: [iA, iB], setup: setup)
        let r = kA * iA / (kB * iB)
        let sigmaR = r * (1 / iA + 1 / iB).squareRoot()
        let sigmaW = 100 * sigmaR / pow(1 + r, 2)
        #expect(abs(s.weightSigma[0] - sigmaW) < 1e-6 * sigmaW)
        #expect(abs(s.weightSigma[1] - sigmaW) < 1e-6 * sigmaW)
        // With the k of the second element 10 % uncertain: dw_A/dln kB = r/(1+r)^2 -> 100 r/(1+r)^2 * 0.1.
        let t = try EDXQuantification.quantifyWithSigma(intensities: [iA, iB], factorRelativeSigmas: [0, 0.1], setup: setup)
        let kTerm = 100 * r / pow(1 + r, 2) * 0.1
        #expect(abs(t.weightFactorSigma[0] - kTerm) < 1e-6 * kTerm)
        #expect(abs(t.weightSigma[0] - (sigmaW * sigmaW + kTerm * kTerm).squareRoot()) < 1e-6)
    }

    @Test func givenCovarianceReplacesTheCountingDefault() throws {
        let setup = EDXQuantificationSetup(elements: ["Al", "Zn"], method: .cliffLorimer(kFactors: [1.0, 1.9], thicknessNm: nil))
        let plain = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], setup: setup)
        let same = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], intensityCovariance: [3000, 0, 0, 1200], setup: setup)
        #expect(abs(plain.weightSigma[0] - same.weightSigma[0]) < 1e-12)
        let inflated = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], intensitySigmas: [2 * 3000.0.squareRoot(), 2 * 1200.0.squareRoot()], setup: setup)
        #expect(abs(inflated.weightSigma[0] / plain.weightSigma[0] - 2) < 1e-6)
        // Positively correlated net counts (a common factor) leave the ratio, and so the composition, less uncertain.
        let corr = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], intensityCovariance: [3000, 0.9 * (3000.0 * 1200).squareRoot(), 0.9 * (3000.0 * 1200).squareRoot(), 1200], setup: setup)
        #expect(corr.weightSigma[0] < plain.weightSigma[0])
    }

    @Test func absorptionIsPropagatedWithTheLoopRunTight() throws {
        var abs = EDXAbsorptionSetting(takeOffDegrees: 20, lineEnergiesKeV: [1.4867, 5.4147, 7.4781])
        abs.convergencePercent = 1e-10; abs.maxIterations = 500
        let setup = EDXQuantificationSetup(elements: Self.elements, method: .cliffLorimer(kFactors: [1.0, 1.47, 1.72], thicknessNm: 150), absorption: abs)
        let s = try EDXQuantification.quantifyWithSigma(intensities: Self.truth, setup: setup)
        let mc = try Self.monteCarlo(setup: setup, truth: Self.truth, draws: 8000)
        Self.expectClose(s.weightSigma, mc.wSD, "wt% with absorption")
        Self.expectClose(s.atomicSigma, mc.aSD, "at% with absorption")
        // The caller's coarse criterion does not enter the sigma.
        var coarse = setup
        coarse.absorption!.convergencePercent = 0.5
        let c = try EDXQuantification.quantifyWithSigma(intensities: Self.truth, setup: coarse)
        for i in 0..<3 { #expect(Swift.abs(c.weightSigma[i] - s.weightSigma[i]) < 1e-9) }
    }

    @Test func zetaAndCrossSectionMatchMonteCarlo() throws {
        let zeta = EDXQuantificationSetup(elements: Self.elements, method: .zeta(zetaFactors: [20, 40, 60]), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)
        let z = try EDXQuantification.quantifyWithSigma(intensities: Self.truth, factorRelativeSigmas: nil, setup: zeta)
        let mcz = try Self.monteCarlo(setup: zeta, truth: Self.truth, draws: 15000)
        Self.expectClose(z.weightSigma, mcz.wSD, "zeta wt%")
        Self.expectClose(z.atomicSigma, mcz.aSD, "zeta at%")
        let mz = try #require(z.massThicknessSigma), mmz = try #require(mcz.mSD)
        #expect(Swift.abs(mz / mmz - 1) < 0.05, "zeta mass thickness \(mz) against \(mmz)")

        let cross = EDXQuantificationSetup(elements: Self.elements, method: .crossSection(sectionsBarn: [3, 4, 5], probeAreaNm2: 1.0), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)
        let c = try EDXQuantification.quantifyWithSigma(intensities: Self.truth, setup: cross)
        let mcc = try Self.monteCarlo(setup: cross, truth: Self.truth, draws: 15000)
        Self.expectClose(c.weightSigma, mcc.wSD, "cross-section wt%")
        Self.expectClose(c.atomicSigma, mcc.aSD, "cross-section at%")
    }

    @Test func refusals() {
        let setup = EDXQuantificationSetup(elements: ["Al", "Zn"], method: .cliffLorimer(kFactors: [1.0, 1.9], thicknessNm: nil))
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], intensityCovariance: [1, 2, 3], setup: setup) }
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], intensitySigmas: [1], setup: setup) }
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 1200], factorRelativeSigmas: [0.1], setup: setup) }
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, -1], setup: setup) }
        // One line above the floor: Cliff-Lorimer refuses, so there is no composition to put a sigma on.
        #expect(throws: QuantError.self) { _ = try EDXQuantification.quantifyWithSigma(intensities: [3000, 0], setup: setup) }
    }
}
