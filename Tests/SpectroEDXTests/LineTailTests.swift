//
//  LineTailTests.swift
//  Role: The opt-in low-energy tail of the line shape (`LineTail`): off is exactly the Gaussian column, on keeps the line's total area,
//        a planted tail biases a Gaussian-only fit and is recovered by the tail model and by `TailEstimate.measure`. Noise-free planted spectra.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct LineTailTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.005, size: 1600)   // 0 to 7.995 keV
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
    private static let planted = LineTail(fraction: 0.03, slopeKeV: 0.3, source: "planted")

    private static func lines(_ id: String) -> [FitLine] {
        EDSLineModel.build(elements: [String(id.prefix { $0 != "_" })], axis: axis, beamEnergy: 20, resolutionMnKaEV: 130)
            .groups.first { $0.id == id }!.lines
    }

    private static let kramers: @Sendable (Double) -> Double = { e in
        let x = max(e, 0.05)
        return 60 * max(20 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5
    }

    /// Continuum + Al K area 2e6 + Mg K area 2e5, lines shaped with `tail`.
    private static func spectrum(tail: LineTail?) -> [Double] {
        var out = energies.map { $0 >= 0.2 ? kramers($0) : 0 }
        let al = EDSLineModel.column(of: lines("Al_Ka"), energies: energies, scale: axis.scale, tail: tail)
        let mg = EDSLineModel.column(of: lines("Mg_Ka"), energies: energies, scale: axis.scale, tail: tail)
        for i in out.indices { out[i] += 2e6 * al[i] + 2e5 * mg[i] }
        return out
    }

    private static func settings(tail: LineTail?) -> FitSettings {
        var s = FitSettings.standard(elements: ["Al", "Mg"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 20)
        s.lineTail = tail
        return s
    }

    @Test func testNilTailIsTheGaussianColumnExactly() {
        let l = Self.lines("Al_Ka")
        let a = EDSLineModel.column(of: l, energies: Self.energies, scale: Self.axis.scale)
        let b = EDSLineModel.column(of: l, energies: Self.energies, scale: Self.axis.scale, tail: nil)
        #expect(a == b)
    }

    @Test func testTheTailKeepsTheTotalAreaAndLiesBelowTheLine() {
        let l = Self.lines("Fe_Ka")   // high enough that the tail is not cut off at 0 keV
        let g = EDSLineModel.column(of: l, energies: Self.energies, scale: Self.axis.scale, tail: nil)
        let t = EDSLineModel.column(of: l, energies: Self.energies, scale: Self.axis.scale, tail: Self.planted)
        let sg = g.reduce(0, +), st = t.reduce(0, +)
        #expect(abs(st - sg) / sg < 1e-6, "\(st) vs \(sg)")
        let e0 = l[0].energy
        let single = EDSLineModel.column(of: [l[0]], energies: Self.energies, scale: Self.axis.scale, tail: Self.planted)
        let below = zip(Self.energies, single).filter { $0.0 < e0 }.reduce(0) { $0 + $1.1 }
        let above = zip(Self.energies, single).filter { $0.0 >= e0 }.reduce(0) { $0 + $1.1 }
        #expect(below > above)
        let gSingle = EDSLineModel.column(of: [l[0]], energies: Self.energies, scale: Self.axis.scale, tail: nil)
        let belowG = zip(Self.energies, gSingle).filter { $0.0 < e0 }.reduce(0) { $0 + $1.1 }
        #expect(below > belowG)
    }

    @Test func testAPlantedTailBiasesAGaussianFitAndTheTailModelRecoversIt() throws {
        let counts = Self.spectrum(tail: Self.planted)
        let truth = 2e5
        let without = try EDSFit.run(counts: counts, axis: Self.axis, settings: Self.settings(tail: nil), computeCovariance: false)
        let with = try EDSFit.run(counts: counts, axis: Self.axis, settings: Self.settings(tail: Self.planted), computeCovariance: false)
        let iMg = try #require(without.groupIDs.firstIndex(of: "Mg_Ka"))
        let biasWithout = without.values[iMg] / truth - 1, biasWith = with.values[iMg] / truth - 1
        print("LINETAIL (c) Mg without tail: \(biasWithout * 100) %, with planted tail: \(biasWith * 100) %")
        #expect(abs(biasWith) < abs(biasWithout), "the tail model reads Mg closer than the Gaussian: \(biasWithout) vs \(biasWith)")
        #expect(abs(biasWith) < 0.01, "\(biasWith)")
    }

    /// A beta far below sigma must not poison the column (exp overflow against an underflowed erfc): finite everywhere, and a tail of fraction 0 is the Gaussian.
    @Test func testASmallSlopeStaysFiniteAndAZeroFractionIsTheGaussian() {
        let l = EDSLineModel.build(elements: ["Fe"], axis: Self.axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == "Fe_Ka" }!.lines
        let tiny = EDSLineModel.column(of: l, energies: Self.energies, scale: Self.axis.scale, tail: LineTail(fraction: 0.05, slopeKeV: 0.0005, source: "test"))
        #expect(tiny.allSatisfy { $0.isFinite })
        let zero = EDSLineModel.column(of: l, energies: Self.energies, scale: Self.axis.scale, tail: LineTail(fraction: 0, slopeKeV: 0.3, source: "test"))
        #expect(zero == EDSLineModel.column(of: l, energies: Self.energies, scale: Self.axis.scale, tail: nil))
        #expect(LineTail(fraction: -1, slopeKeV: 0, source: "").fraction == 0 && LineTail(fraction: -1, slopeKeV: 0, source: "").slopeKeV == 0.001)
    }

    @Test func testMeasureFindsThePlantedTail() throws {
        let counts = Self.spectrum(tail: Self.planted)
        let m = try TailEstimate.measure(counts: counts, axis: Self.axis, settings: Self.settings(tail: nil), elements: ["Al", "Mg"])
        print("LINETAIL (d) f \(m.tail.fraction) beta \(m.tail.slopeKeV) residual \(m.residualNormWithout) -> \(m.residualNorm); \(m.tail.source)")
        #expect(abs(m.tail.fraction - 0.03) < 0.01)
        #expect(abs(m.tail.slopeKeV - 0.3) / 0.3 < 0.3)
        #expect(m.residualNorm < m.residualNormWithout)
        #expect(m.tail.source.hasPrefix("measured on"))
    }

    @Test func testTheFooterNamesTheLineShape() throws {
        let counts = Self.spectrum(tail: nil)
        let off = try EDSFit.run(counts: counts, axis: Self.axis, settings: Self.settings(tail: nil), computeCovariance: false)
        #expect(off.lineShapeLabel == "line shape: Gaussian")
        let on = try EDSFit.run(counts: counts, axis: Self.axis, settings: Self.settings(tail: Self.planted), computeCovariance: false)
        #expect(on.lineShapeLabel.hasPrefix("line shape: Gaussian + tail (f 0.03"))
        #expect(on.lineShapeLabel.contains("0.3 keV") && on.lineShapeLabel.contains("planted"))
        let policy = FitPolicy(lineTail: Self.planted)
        let st = FitSettings.standard(elements: ["Al"], axis: Self.axis, resolutionMnKaEV: 130, beamEnergy: 20, policy: policy)
        #expect(st.lineTail == Self.planted)
    }
}
