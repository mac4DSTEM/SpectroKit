//
//  EdgeWindowsTests.swift
//  Role: per-edge background and signal windows in the EELS model fit: the default rules, the unchanged joint fit, a planted C K, N K, O K
//        spectrum on a steep tail (windows against the one-range fit), the power-law preview, and the refusals.
//

import Foundation
import Testing
import SpectroCore
import SpectroEELS

struct EdgeWindowsTests {
    private let axis = EnergyAxis(offset: 150, scale: 0.75, size: 2020)

    private func planted(curved: Bool, backgroundScale: Double = 1, ratio: [Double] = [3.0, 1.0, 2.0]) throws -> (core: CoreLossSpectrumImage, mic: EELSMicroscope, truth: [Double]) {
        let mic = EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)
        let energies = (0 ..< axis.size).map { axis.energy(ofChannel: $0) }
        // the r = 3 plasmon tail; `curved` adds a shallower power law (E^-1, equal to the tail at 300 eV) that takes over higher up,
        // so no single power law fits 150 to 1664 eV, as on the real files
        let tail = 3.0e10 / pow(300.0, 3)
        var counts = energies.map { e in backgroundScale * (3.0e10 * pow(e, -3) + (curved ? tail * 300 / e : 0)) }
        let edges: [CoreLossEdge] = [.carbonK, .nitrogenK, .oxygenK]
        // the kit's own cross sections, so the planted amplitudes are the fitted quantity (2000 counts per channel for C at 30 eV above its onset)
        var unit = 0.0
        for (g, edge) in edges.enumerated() {
            let xs = EdgeCrossSection(table: GOSTable.bundled(edge)!, beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)!
            let col = xs.differential(energies).map { $0 * axis.scale }
            if g == 0 { unit = 2000 / (ratio[0] * col[Int((edge.onsetEV + 30 - 150) / 0.75)]) }
            for k in 0 ..< axis.size { counts[k] += ratio[g] * unit * col[k] }
        }
        _ = mic
        let core = try CoreLossSpectrumImage(nx: 1, ny: 1, channels: axis.size, counts: counts, energyOffsetEV: 150, energyScaleEV: 0.75)
        return (core, mic, ratio)
    }

    private func defaultWindows() -> [EdgeWindows] {
        let c = EdgeWindows.defaults(onsetEV: 284, family: "K", precedingSignalEndEV: nil, nextOnsetEV: 401, axis: axis)
        let n = EdgeWindows.defaults(onsetEV: 401, family: "K", precedingSignalEndEV: c.signalEV.upperBound, nextOnsetEV: 532, axis: axis)
        let o = EdgeWindows.defaults(onsetEV: 532, family: "K", precedingSignalEndEV: n.signalEV.upperBound, nextOnsetEV: nil, axis: axis)
        return [c, n, o]
    }

    @Test func testDefaultRules() {
        let w = defaultWindows()
        func close(_ r: ClosedRange<Double>, _ lo: Double, _ hi: Double) -> Bool { abs(r.lowerBound - lo) < 1e-9 && abs(r.upperBound - hi) < 1e-9 }
        // C K: background 20 % of 284 = 56.8 eV wide ending at 279; signal 284 to 284 + max(28.4, 30)
        #expect(close(w[0].backgroundEV, 279 - 56.8, 279), Comment(rawValue: "\(w[0])"))
        #expect(close(w[0].signalEV, 284, 314))
        // N K: 80.2 eV wide ending 396 would start at 315.8, cut 5 eV above C's signal end (314) to 319; signal 401 to 441.1
        #expect(close(w[1].backgroundEV, 319, 396), Comment(rawValue: "\(w[1])"))
        #expect(close(w[1].signalEV, 401, 441.1))
        // O K: 106.4 clamps to 100 (527 - 100 = 427), cut at 441.1 + 5; signal 532 to 532 + 53.2
        #expect(close(w[2].backgroundEV, 446.1, 527), Comment(rawValue: "\(w[2])"))
        #expect(close(w[2].signalEV, 532, 585.2))
        // clamps: a 50 eV onset gives the 20 eV background floor, a 2000 eV one the 100 eV ceiling and the 150 eV signal ceiling
        let lowOnset = EdgeWindows.defaults(onsetEV: 100, family: "L", precedingSignalEndEV: nil, nextOnsetEV: nil, axis: axis)
        #expect(close(lowOnset.backgroundEV, 150, 150) && lowOnset.signalEV.lowerBound == 150)   // 75 to 95 eV and 120 to 150 eV lie below the axis start 150: clipped to it
        let mid = EdgeWindows.defaults(onsetEV: 200, family: "L", precedingSignalEndEV: nil, nextOnsetEV: nil, axis: axis)
        #expect(close(mid.backgroundEV, 155, 195) && close(mid.signalEV, 220, 250), Comment(rawValue: "\(mid)"))   // delayed: onset + 20; 20 eV -> 30 eV floor
        let high = EdgeWindows.defaults(onsetEV: 1400, family: "K", precedingSignalEndEV: nil, nextOnsetEV: nil, axis: axis)
        #expect(close(high.backgroundEV, 1295, 1395) && close(high.signalEV, 1400, 1540))
        // the axis end clips the signal window
        let edge = EdgeWindows.defaults(onsetEV: 1600, family: "K", precedingSignalEndEV: nil, nextOnsetEV: nil, axis: axis)
        #expect(edge.signalEV.upperBound <= 150 + 0.75 * 2019 + 1e-9)
        // the next onset cuts the signal window 5 eV below it
        let cut = EdgeWindows.defaults(onsetEV: 284, family: "K", precedingSignalEndEV: nil, nextOnsetEV: 300, axis: axis)
        #expect(close(cut.signalEV, 284, 295))
    }

    @Test func testWindowsAreCodable() throws {
        let w = EdgeWindows(backgroundEV: 200 ... 250, signalEV: 260 ... 300, secondBackgroundEV: 400 ... 420)
        let back = try JSONDecoder().decode(EdgeWindows.self, from: JSONEncoder().encode(w))
        #expect(back == w)
    }

    /// Without windows the joint fit is the one it was: the bits recorded from the code before `edgeWindows` existed.
    @Test func testFitWithoutWindowsIsUnchanged() throws {
        let all = ModelFixtures.pins["cases"] as! [String: [String: Any]]
        let c = try ModelFixtures.make("fel", all["fel"]!)
        let a = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope)
        let b = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope, edgeWindows: nil)
        #expect(a.pixels == b.pixels && a.backgrounds == b.backgrounds && a.residualSumOfSquares == b.residualSumOfSquares)
        #expect(a.edgeWindows == nil && a.fitRangeEV == nil && a.edgeBackgrounds == nil)
        let recorded: [UInt64] = [0x41286a2cbb917b26, 0x412d4c1e4b6979d8, 0x41311731d63b4f29, 0x413387d3d451918f, 0x4135f90b32d7e1fc, 0x41386a15123b16ed]
        #expect(a.pixels.prefix(recorded.count).map { $0[0].intensity!.bitPattern } == recorded)
    }

    @Test func testWindowsRecoverThePlantedRatioAndTheGlobalFitDoesNot() throws {
        let (core, mic, ratio) = try planted(curved: true)
        let edges: [CoreLossEdge] = [.carbonK, .nitrogenK, .oxygenK]
        let w = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, edgeWindows: defaultWindows())
        let g = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic)
        let iw = w.pixels[0].map { $0.intensity ?? .nan }, ig = g.pixels[0].map { $0.intensity ?? .nan }
        print("planted ratio 3:1:2 | per-edge windows: \(iw.map { $0 / iw[1] }) | global fit: \(ig.map { $0 / max(ig[1], 1e-300) }) intensities \(ig)")
        print("exponents per edge: \((0 ..< 3).map { w.exponent(pixel: 0, edge: $0)! })  fit ranges: \(w.fitRangeEV!)")
        for k in 0 ..< 3 { #expect(abs(iw[k] / iw[1] - ratio[k] / ratio[1]) <= 0.05 * ratio[k] / ratio[1], Comment(rawValue: "edge \(k): \(iw)")) }
        let globalOK = (0 ..< 3).allSatisfy { ig[1] > 0 && abs(ig[$0] / ig[1] - ratio[$0] / ratio[1]) <= 0.05 * ratio[$0] / ratio[1] }
        #expect(!globalOK, Comment(rawValue: "global \(ig)"))
        #expect(w.edgeWindows == defaultWindows() && w.fitRangeEV!.count == 3)
        #expect(w.modelCurve(pixel: 0)?.count == 2020)
        #expect((1.5 ... 4).contains(w.exponent(pixel: 0, edge: 0)!))   // between the tail (3) and the shallower part (1)
    }


    /// The real-file case: the N K default background window (319 to 396 eV) lies in the tail of C K, which dominates a weak background.
    @Test func testStrippingRecoversNKInsideTheCTail() throws {
        let (core, mic, ratio) = try planted(curved: true, backgroundScale: 0.02, ratio: [100, 1, 2])
        let edges: [CoreLossEdge] = [.carbonK, .nitrogenK, .oxygenK]
        let w = defaultWindows()
        // the C K tail under the N signal window against the N signal itself
        let energies = (0 ..< axis.size).map { axis.energy(ofChannel: $0) }
        func column(_ e: CoreLossEdge) -> [Double] {
            EdgeCrossSection(table: GOSTable.bundled(e)!, beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)!.differential(energies).map { $0 * axis.scale }
        }
        let cc = column(.carbonK), nn = column(.nitrogenK)
        let rows = EdgeWindows.rows(w[1].signalEV, offset: 150, scale: 0.75, size: axis.size)
        let tailShare = rows.reduce(0.0) { $0 + ratio[0] * cc[$1] } / rows.reduce(0.0) { $0 + ratio[1] * nn[$1] }
        #expect(tailShare >= 0.10, Comment(rawValue: "C tail / N signal = \(tailShare)"))
        let s = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, options: EELSModelOptions(stripPrecedingEdges: true), edgeWindows: w)
        // without stripping (the default): the same fit of N K and O K alone, the C K edge left in the data
        let n = try EELSModelFit.fit(coreLoss: core, edges: [.nitrogenK, .oxygenK], microscope: mic, edgeWindows: [w[1], w[2]])
        let d = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, edgeWindows: w)
        #expect(d.pixels[0][1].intensity == n.pixels[0][0].intensity && d.pixels[0][2].intensity == n.pixels[0][1].intensity, "the default does not strip")
        #expect(!d.strippedPrecedingEdges && s.strippedPrecedingEdges && !d.methodName.contains("stripped") && s.methodName.contains("stripped"))
        let iS = s.pixels[0].map { $0.intensity ?? .nan }, iN = n.pixels[0].map { $0.intensity ?? .nan }
        print("C tail / N signal \(tailShare) | N K without stripping \(iN[0]) (planted-unit N \(iS[1])), O/N \(iN[1] / max(iN[0], 1e-300)) | with stripping C:N:O \(iS.map { $0 / iS[1] })")
        for k in 0 ..< 3 { #expect(abs(iS[k] / iS[1] - ratio[k] / ratio[1]) <= 0.05 * ratio[k] / ratio[1], Comment(rawValue: "edge \(k): \(iS)")) }
        #expect(abs(iN[0] / iS[1] - 1) > 0.2, Comment(rawValue: "unstripped N \(iN[0]) vs stripped \(iS[1])"))
    }

    /// Two edges 85 eV apart (Fe L1 846 and Cu L3 931 eV): the second default background window is empty by the first rule, so rule 2 applies.
    @Test func testCloseEdgesShareAWindowAndAreRecovered() throws {
        let fe = EdgeWindows.defaults(onsetEV: 846, family: "L", precedingSignalEndEV: nil, nextOnsetEV: 931, axis: axis)
        let plain = EdgeWindows.defaults(onsetEV: 931, family: "L", precedingSignalEndEV: fe.signalEV.upperBound, nextOnsetEV: nil, axis: axis)
        #expect(plain.backgroundEV.upperBound - plain.backgroundEV.lowerBound < 20 && plain.note == nil)
        let cu = EdgeWindows.defaults(onsetEV: 931, family: "L", precedingSignalEndEV: fe.signalEV.upperBound, nextOnsetEV: nil, axis: axis,
                                      precedingOnsetEV: 846, precedingBackgroundEV: fe.backgroundEV, precedingName: "Fe L")
        #expect(cu.backgroundEV == 846 ... 926 && cu.note == "background between Fe L's onset and this one: edges 85 eV apart", Comment(rawValue: "\(cu)"))
        // the stretch too short: the preceding edge's own window is reused
        let tight = EdgeWindows.defaults(onsetEV: 931, family: "L", precedingSignalEndEV: 915, nextOnsetEV: nil, axis: axis,
                                         precedingOnsetEV: 920, precedingBackgroundEV: fe.backgroundEV, precedingName: "Fe L")
        #expect(tight.backgroundEV == fe.backgroundEV && tight.note == "background shares Fe L's window: edges 11 eV apart", Comment(rawValue: "\(tight)"))
        // no fallback given: still empty, the fit refuses it
        #expect(plain.backgroundEV.upperBound - plain.backgroundEV.lowerBound < 20)

        let edges: [CoreLossEdge] = [.ironL1, .copperL3]
        let energies = (0 ..< axis.size).map { axis.energy(ofChannel: $0) }
        var counts = energies.map { 4.0e9 * pow($0, -2.5) }
        let planted = [1.0, 0.6]
        var peak = 0.0
        for (g, e) in edges.enumerated() {
            let col = EdgeCrossSection(table: GOSTable.bundled(e)!, beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)!.differential(energies).map { $0 * axis.scale }
            if g == 0 { peak = 300 / col[Int((e.onsetEV + 40 - 150) / 0.75)] }
            for k in 0 ..< axis.size { counts[k] += planted[g] * peak * col[k] }
        }
        let core = try CoreLossSpectrumImage(nx: 1, ny: 1, channels: axis.size, counts: counts, energyOffsetEV: 150, energyScaleEV: 0.75)
        let mic = EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)
        let r = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, options: EELSModelOptions(stripPrecedingEdges: true), edgeWindows: [fe, cu])
        let i = r.pixels[0].map { $0.intensity ?? .nan }
        print("close edges: windows \(fe.backgroundEV) / \(cu.backgroundEV) note \(cu.note ?? "-") | Cu/Fe \(i[1] / i[0]) planted \(planted[1] / planted[0])")
        #expect(i[1] > 0 && abs(i[1] / i[0] - planted[1] / planted[0]) <= 0.10 * planted[1] / planted[0], Comment(rawValue: "\(i)"))
        #expect(r.edgeWindows?[1].note == cu.note)
    }

    @Test func testDefaultNotesAreNilInTheEasyCase() {
        #expect(defaultWindows().allSatisfy { $0.note == nil })
        let c = EdgeWindows.defaults(onsetEV: 284, family: "K", precedingSignalEndEV: nil, nextOnsetEV: 401, axis: axis,
                                     precedingOnsetEV: 100, precedingBackgroundEV: 150 ... 200, precedingName: "X")
        #expect(c.note == nil)
        let back = try? JSONDecoder().decode(EdgeWindows.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func testPreviewRecoversThePlantedExponent() throws {
        let energies = (0 ..< axis.size).map { axis.energy(ofChannel: $0) }
        let counts = energies.map { 3.0e10 * pow($0, -3) * axis.scale }
        let p = try EELSBackground.preview(counts: counts, axis: axis, window: 222.2 ... 279, extrapolateTo: 200 ... 320)
        #expect(abs(p.parameters.r - 3) <= 0.03, Comment(rawValue: "r = \(p.parameters.r)"))
        #expect(p.curve.count == p.channels.count && p.channels.lowerBound == Int(ceil((200 - 150) / 0.75)))
        let k = p.channels.lowerBound + 100
        #expect(abs(p.curve[100] / counts[k] - 1) <= 0.01)
        #expect(throws: (any Error).self) { _ = try EELSBackground.preview(counts: counts, axis: axis, window: 100 ... 200, extrapolateTo: 200 ... 320) }
    }

    @Test func testRefusals() throws {
        let (core, mic, _) = try planted(curved: false)
        let edges: [CoreLossEdge] = [.carbonK, .nitrogenK, .oxygenK]
        var w = defaultWindows()
        #expect(throws: EELSModelError.edgeWindowCountMismatch(expected: 3, got: 2)) {
            _ = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, edgeWindows: Array(w.prefix(2)))
        }
        w[1].signalEV = 300 ... 450                                   // runs into C's 284 to 314
        #expect(throws: EELSModelError.overlappingSignalWindows("C K", "N K")) {
            _ = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, edgeWindows: w)
        }
        w = defaultWindows(); w[2].signalEV = 1600 ... 1700           // beyond the axis end
        #expect(throws: EELSModelError.self) { _ = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, edgeWindows: w) }
        w = defaultWindows(); w[0].backgroundEV = 250 ... 251         // two channels
        #expect(throws: EELSModelError.self) { _ = try EELSModelFit.fit(coreLoss: core, edges: edges, microscope: mic, edgeWindows: w) }
    }
}
