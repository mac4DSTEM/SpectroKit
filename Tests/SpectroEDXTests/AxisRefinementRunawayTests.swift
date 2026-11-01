//
//  AxisRefinementRunawayTests.swift
//  Role: The pooled energy-axis refinement on a synthetic spectrum with one strong line (Al K-alpha; Mg and Si K-alpha planted
//        weak, both fitted at 0) on a 0-10.24 keV axis, 4322 counts in all. Under the broadened continuum edge step the
//        refinement walked to gain +444 %, offset -6.6 keV and the 500 eV width bound and said converged; under the sharp step it
//        stopped at gain +32.7 %, offset -484 eV. The file axis is the truth (the lines were planted on it).
//
//  Cause: one line fixes two numbers (its channel and its width in channels), the refinement has three. Along the valley that
//  keeps Al K-alpha at channel 148.6 and 9 channels wide the residual changes by under 5 % from gain 0 to +444 % (`valley`), so
//  the step form only decides where on the valley the simplex stops. Refuting check run first: holding the continuum on the
//  file axis and width left the broadened result bit-identical, so the continuum following the axis is not the cause.
//

import Foundation
import Testing
import SpectroCore
@testable import SpectroEDX

enum DemoSpectrum {
    /// The pooled sum of a synthetic 32 x 32 x 1024 spectrum image (a deterministic LCG; offset 0, 10 eV/channel): a weak decaying
    /// background and three Gaussian lines at 1.254, 1.487 and 1.740 keV (sigma^2 = 0.0035 keV^2), stronger inside a central
    /// disc. Each pixel's channel value is truncated to an integer, then summed. Synthetic; the same generator as an app's demo
    /// spectrum image.
    static func pooled() -> [UInt64] {
        let ny = 32, nx = 32, channels = 1024
        var sum = [UInt64](repeating: 0, count: channels)
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 40) / Double(1 << 24)
        }
        let peaks: [(keV: Double, matrix: Double, blob: Double)] = [(1.487, 40, 12), (1.254, 0.4, 14), (1.740, 0.4, 16)]
        for y in 0..<ny { for x in 0..<nx {
            let inBlob = pow(Double(x) - 16, 2) + pow(Double(y) - 16, 2) < 64
            for c in 0..<channels {
                let e = Double(c) * 0.01
                var mean = 0.4 * exp(-e / 3)
                for p in peaks { mean += (inBlob ? p.blob : p.matrix) * exp(-pow(e - p.keV, 2) / (2 * 0.0035)) * 0.02 }
                sum[c] += UInt64(UInt32(max(0, mean + (next() - 0.5) * sqrt(max(mean, 0.01)))))
            }
        } }
        return sum
    }

    static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)

    static func input(policy: QuantificationPolicy = .default, locked: Bool = false) -> PooledQuantificationInput {
        var m = QuantificationMethod()
        m.elements = ["Al", "Mg", "Si"].map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = locked
        let meta = SpectrumImageMetadata(fileName: "demo", filePath: "", scanWidth: 32, scanHeight: 32, channelCount: 1024,
                                         energyOffsetEV: 0, energyDispersionEV: 10)
        var i = PooledQuantificationInput(counts: pooled(), axis: axis, method: m, metadata: meta, regionName: "Whole map",
                                          pixelCount: 1024)
        i.policy = policy
        return i
    }
}

struct AxisRefinementRunawayTests {

    private static func sharp() -> QuantificationPolicy {
        var p = QuantificationPolicy.default; p.fit.continuumEdgeStep = .sharp; return p
    }

    /// The fixture is the one the issue was reported on: 4322 counts.
    @Test func fixtureIsTheReportedSpectrum() {
        #expect(DemoSpectrum.pooled().reduce(0, +) == 4322)
    }

    /// Under either edge step the spectrum does not determine the axis: the refinement stops at a bound, says so, is not
    /// converged, and the fit runs on the file axis and width, number for number the locked-axis fit.
    @Test(arguments: ["broadened", "sharp"])
    func oneLineSpectrumRefusesTheRefinedAxisWithANamedReason(_ step: String) throws {
        let policy = step == "sharp" ? Self.sharp() : QuantificationPolicy.default
        let q = try PooledQuantifier.run(DemoSpectrum.input(policy: policy), tables: nil)
        let r = try #require(q.refinement)
        #expect(!r.converged, "\(step): \(r.offsetShiftEV) eV, \(r.gainShift), \(r.resolutionMnKaEV) eV")
        #expect(!r.parametersAtBound.isEmpty)
        #expect(abs(r.gainShift) <= 0.05 + 1e-12 && abs(r.offsetShiftEV) <= 200 + 1e-9 && r.resolutionMnKaEV < 500)
        #expect(q.usedAxis == DemoSpectrum.axis)
        #expect(q.warnings.contains { $0.contains("stopped at its bound") && $0.contains("the file's axis is used") }, "\(q.warnings)")
        #expect(q.footerLines.contains { $0.hasPrefix("energy axis:") && $0.contains("NOT used (stopped at its bound:") }, "\(q.footerLines)")

        let locked = try PooledQuantifier.run(DemoSpectrum.input(policy: policy, locked: true), tables: nil)
        #expect(q.rows.map(\.net) == locked.rows.map(\.net))
        #expect(q.rows.map(\.sigma) == locked.rows.map(\.sigma))
    }

    /// The refinement objective at (d keV, g, R), on the file channels, as `EnergyAxisRefinement` computes it.
    private static func rss(_ counts: [Double], step: ContinuumEdgeStep, d: Double, g: Double, r: Double) -> Double {
        var fp = FitPolicy.default; fp.continuumEdgeStep = step
        let file = DemoSpectrum.axis
        let s = FitSettings.standard(elements: ["Al", "Mg", "Si"], axis: file, resolutionMnKaEV: 130, beamEnergy: 200, policy: fp)
        let channels = file.fitChannels(from: s.fitFrom, to: s.fitTo)
        let axis = EnergyAxis(offset: file.offset + d, scale: file.scale * (1 + g), size: file.size)
        let model = EDSLineModel.build(elements: s.elements, axis: axis, beamEnergy: 200, resolutionMnKaEV: r, escapePeaks: s.escapePeaks)
        let design = LinearDesign.build(model: model, axis: axis, channels: channels, background: s.background)
        let y = channels.map { counts[$0] }
        let sol = LeastSquaresFit.solve(nonNegative: design.nonNegative, free: design.free, y: y)
        let mu = design.nonNegative.times(sol.nonNegative)
        return y.indices.reduce(0) { $0 + (y[$1] - mu[$1]) * (y[$1] - mu[$1]) }
    }

    /// The diagnosis: hold Al K-alpha (1.4865 keV) at channel 148.6 and its FWHM at 9.0 channels while the gain walks from 0 to
    /// +444 %; the residual moves by under 5 % and, under the broadened step, falls all the way to the width bound.
    @Test func oneLineValleyIsFlat() {
        let counts = DemoSpectrum.pooled().map { Double($0) }
        let gains = [0.0, 0.327, 1.5, 4.44]
        var values: [Double] = []
        for g in gains {
            let scale = 0.01 * (1 + g)
            let fwhm = 9.0 * scale * 1000
            let r = (fwhm * fwhm - 2.5 * (1486.5 - 5898.7)).squareRoot()   // the kit width law, FWHM^2 = R^2 + 2.5 (E - E_MnKa) eV^2
            values.append(Self.rss(counts, step: .broadened, d: 1.4865 - scale * 148.6, g: g, r: r))
        }
        #expect((values.max()! - values.min()!) / values.max()! < 0.05, "\(values)")
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 > $1 }, "\(values)")
    }
}
