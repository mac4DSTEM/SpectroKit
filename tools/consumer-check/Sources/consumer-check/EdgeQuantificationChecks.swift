//
//  EdgeQuantificationChecks.swift
//  Role: the public surface of EELS slice 2 (the C K areal density by the ratio method) used from outside the package:
//        `EELSEdgeQuantification` (`ratioMethod` with every parameter and both `LowLossIntensity` routes,
//        `differentialCrossSection`, `methodName`, `defaultBackgroundWindow`), `CoreLossSpectrumImage` (both initialisers, every
//        field, `pixelCount`), `EELSMicroscope`, `LowLossIntensity`, `CoreLossEdge`, `ArealDensityMap`, `ArealDensityPixel`,
//        `EdgeUnavailable`, `EELSEdgeError`.
//        Values: the committed pins of Tests/SpectroEELSTests/Fixtures/edge-pins.json (exSpy 7185a4d1 / HyperSpy 2.4.0's
//        answers, never truth) on the planted images (set R and the registered set), and exSpy's cross section on the grid.
//        The resource bundle: the GOS tables are SpectroEELS's `Bundle.module` resources; a cross section for C K, N K and
//        O K that succeeds can only have come from the bundle the Debug consumer loaded (run.sh also requires the bundle
//        directory next to the binary).
//

import Foundation
import SpectroCore
import SpectroEELS

private func raw(_ url: URL) throws -> [Double] {
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { b in
        (0..<(data.count / 8)).map { Double(bitPattern: UInt64(littleEndian: b.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) }
    }
}

private func json(_ url: URL) throws -> [String: Any] {
    guard let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CheckError("\(url.lastPathComponent): not an object") }
    return o
}

private extension Dictionary where Key == String, Value == Any {
    func d(_ k: String) -> [String: Any] { self[k] as! [String: Any] }
    func a(_ k: String) -> [Double] { (self[k] as! [Any]).map { ($0 as? NSNumber)?.doubleValue ?? .nan } }
    func x(_ k: String) -> Double { (self[k] as! NSNumber).doubleValue }
    func i(_ k: String) -> Int { (self[k] as! NSNumber).intValue }
}

private func rel(_ a: Double, _ b: Double) -> Double {
    if a == b { return 0 }
    return Swift.abs(a - b) / max(Swift.abs(a), Swift.abs(b))
}

func edgeQuantificationChecks(_ r: inout Report, _ eelsFixtures: URL) throws {
    let pins = try json(eelsFixtures.appendingPathComponent("edge-pins.json"))
    let planted = try json(eelsFixtures.appendingPathComponent("edge-planted.json"))
    let coreAxis = planted.d("coreLossAxis"), lowAxis = planted.d("lowLossAxis")
    let scope = EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)

    func core(_ file: String) throws -> CoreLossSpectrumImage {
        try CoreLossSpectrumImage(nx: 5, ny: 3, channels: coreAxis.i("size"), counts: raw(eelsFixtures.appendingPathComponent(file)),
                                  energyOffsetEV: coreAxis.x("offset"), energyScaleEV: coreAxis.x("scale"))
    }
    func low(_ file: String) throws -> LowLossSpectrumImage {
        try LowLossSpectrumImage(nx: 5, ny: 3, channels: lowAxis.i("size"), counts: raw(eelsFixtures.appendingPathComponent(file)),
                                 energyOffsetEV: lowAxis.x("offset"), energyScaleEV: lowAxis.x("scale"))
    }

    // MARK: 1. Types without a fixture: CoreLossSpectrumImage, EELSMicroscope, CoreLossEdge, the arithmetic constants.
    let exact: [Double] = [1, 2, 3, 4, 5, 6]
    let cd = try CoreLossSpectrumImage(nx: 2, ny: 1, channels: 3, counts: exact, energyOffsetEV: 280, energyScaleEV: 0.5)
    r.check("CoreLossSpectrumImage .nx .ny .channels .counts .energyOffsetEV .energyScaleEV .pixelCount as given",
            cd.nx == 2 && cd.ny == 1 && cd.channels == 3 && cd.counts == exact && cd.energyOffsetEV == 280 && cd.energyScaleEV == 0.5 && cd.pixelCount == 2)
    let cf = try CoreLossSpectrumImage(nx: 2, ny: 1, channels: 3, counts: exact.map { Float($0) }, energyOffsetEV: 280, energyScaleEV: 0.5)
    r.check("CoreLossSpectrumImage.init(... counts: [Float] ...) widens exactly to Double", cf.counts == exact && cf.pixelCount == 2)
    let m3 = EELSMicroscope(beamEnergyKeV: 300, convergenceMrad: 0, collectionMrad: 25)
    r.check("EELSMicroscope .beamEnergyKeV .convergenceMrad .collectionMrad as given; Equatable",
            m3.beamEnergyKeV == 300 && m3.convergenceMrad == 0 && m3.collectionMrad == 25 && m3 == EELSMicroscope(beamEnergyKeV: 300, convergenceMrad: 0, collectionMrad: 25)
            && m3 != scope)
    r.check("CoreLossEdge .carbonK .nitrogenK .oxygenK: element, subshell K1, onset 284 / 401 / 532 eV",
            [CoreLossEdge.carbonK, .nitrogenK, .oxygenK].map { [$0.element, $0.subshell, String($0.onsetEV)] }
            == [["C", "K1", "284.0"], ["N", "K1", "401.0"], ["O", "K1", "532.0"]])
    r.check("CoreLossEdge.bundled starts with [C K, N K, O K] (20 edges since 0.9.0); Equatable distinguishes them; .description is \"<element> K\"",
            CoreLossEdge.bundled.prefix(3) == [.carbonK, .nitrogenK, .oxygenK] && CoreLossEdge.carbonK != .oxygenK
            && CoreLossEdge.bundled.prefix(3).map { $0.description } == ["C K", "N K", "O K"] && "\(CoreLossEdge.nitrogenK)" == "N K"
            && "\(CoreLossEdge.ironL3)" == "Fe L3")
    r.equal("EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284) is [E_k - 50, E_k - 5] = 234...279",
            EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284), 234...279)
    r.check("EELSEdgeQuantification.methodName names the power law, the ratio method and exSpy's dft GOS",
            EELSEdgeQuantification.methodName.contains("power law") && EELSEdgeQuantification.methodName.contains("Egerton eq. 4.65/4.66")
            && EELSEdgeQuantification.methodName.contains("exSpy 7185a4d1 dft GOS"))

    // MARK: 2. The resource bundle and exSpy's cross section. C, N and O K load their GOS tables from SpectroEELS's Bundle.module
    // (the only source of the tables); the differential cross section equals exSpy's `EELSCLEdge.function` on the pinned grid.
    var worstFn = 0.0, worstAngle = 0.0, worstSigma = 0.0
    var gridCount = 0, sigmaCount = 0
    let grid = pins["grid"] as! [[String: Any]]
    r.equal("edge-pins.json grid has 192 cases (C, N, O x E0 x alpha x beta)", grid.count, 192)
    var loaded = Set<String>()
    let onesLow = try LowLossSpectrumImage(nx: 1, ny: 1, channels: lowAxis.i("size"), counts: [Double](repeating: 1, count: lowAxis.i("size")),
                                           energyOffsetEV: lowAxis.x("offset"), energyScaleEV: lowAxis.x("scale"))
    for (index, g) in grid.enumerated() {
        let element = g["element"] as! String
        let edge = CoreLossEdge.bundled.first { $0.element == element }!
        let microscope = EELSMicroscope(beamEnergyKeV: g.x("E0"), convergenceMrad: g.x("alpha"), collectionMrad: g.x("beta"))
        let scales = g["byScale"] as! [[String: Any]]
        for (si, s) in scales.enumerated() where index % 4 == 0 || si == 0 {
            let offset = s.x("offset"), scale = s.x("scale"), n = s.i("nChannels")
            let energies = (0..<n).map { offset + scale * Double($0) }
            let result = try EELSEdgeQuantification.differentialCrossSection(edge: edge, microscope: microscope, energiesEV: energies)
            loaded.insert(element)
            worstAngle = max(worstAngle, rel(result.effectiveCollectionMrad, g.x("effectiveAngleMrad")))
            for (p, e) in zip(result.barnPerEV, s.a("function")) { worstFn = max(worstFn, rel(p, e)) }
            gridCount += 1
            // The same cross section through ratioMethod: sigma_k over the edge window, on a flat image with this axis.
            guard index % 8 == 0 else { continue }
            let flat = try CoreLossSpectrumImage(nx: 1, ny: 1, channels: n, counts: [Double](repeating: 1, count: n), energyOffsetEV: offset, energyScaleEV: scale)
            for (delta, dv) in s.d("byDelta") {
                let w = dv as! [String: Any]
                let map = try EELSEdgeQuantification.ratioMethod(coreLoss: flat, edge: edge, microscope: microscope, lowLoss: .integratedToWidth(onesLow),
                                                                  backgroundWindowEV: (offset + 2)...(offset + 8), integrationWidthEV: Double(delta)!)
                worstSigma = max(worstSigma, rel(map.crossSectionBarn, w.x("sigmaK")))
                if map.edgeChannels != w.i("i0")..<w.i("i1") { worstSigma = .infinity }
                sigmaCount += 1
            }
        }
    }
    r.equal("Bundle.module: the GOS tables of C K, N K and O K all load (a cross section was computed for each)", loaded, ["C", "N", "O"])
    r.check("differentialCrossSection equals exSpy's EELSCLEdge.function on \(gridCount) grid axes (worst relative \(worstFn), allowed 1e-10)", gridCount > 60 && worstFn <= 1e-10)
    r.check("differentialCrossSection .effectiveCollectionMrad equals exSpy's (worst relative \(worstAngle), allowed 1e-14)", worstAngle <= 1e-14)
    r.check("ArealDensityMap.crossSectionBarn / .edgeChannels equal exSpy's sigma_k and window on \(sigmaCount) grid cases, N and O included (worst \(worstSigma), allowed 1e-10)",
            sigmaCount > 20 && worstSigma <= 1e-10)
    let below = try EELSEdgeQuantification.differentialCrossSection(edge: .carbonK, microscope: scope, energiesEV: [283.99, 284.0, 2500, 5000])
    r.check("differentialCrossSection: 0 below the onset, positive at and beyond it (power law past the table)",
            below.barnPerEV[0] == 0 && below.barnPerEV[1] > 0 && below.barnPerEV[2] > below.barnPerEV[3] && below.barnPerEV[3] > 0)

    // MARK: 3. The planted images against the pins (set R and the registered set; noiseless and noisy; both I_low routes).
    var worst = (n: 0.0, sums: 0.0, fit: 0.0, sigma: 0.0, low: 0.0, i0n: 0.0, sigmaK: 0.0)
    var structural = true, compared = 0, i0Compared = 0
    for setKey in ["planted", "plantedR"] {
        let set = pins.d(setKey)
        let effective = set.x("effectiveAngleMrad")
        for im in set["images"] as! [[String: Any]] {
            let c = try core(im["coreFile"] as! String), l = try low(im["lowFile"] as! String)
            for (wname, wv) in im.d("windows") {
                let w = wv as! [String: Any]
                let range = w.a("valueRangeEV")
                for (delta, dv) in w.d("byDelta") {
                    let dd = dv as! [String: Any]
                    let map = try EELSEdgeQuantification.ratioMethod(coreLoss: c, edge: .carbonK, microscope: scope, lowLoss: .integratedToWidth(l),
                                                                      backgroundWindowEV: range[0]...range[1], edgeOnsetEV: nil,
                                                                      integrationWidthEV: Double(delta)!, coreLossToLowLossDose: 1,
                                                                      cancelled: { false })
                    structural = structural && map.edgeChannels == dd.i("i0")..<dd.i("i1") && map.backgroundWindowEV == w.x("x1")...w.x("x2")
                        && map.validation == "none" && map.caveat == nil && map.nx == 5 && map.ny == 3 && map.pixels.count == 15
                        && map.edge == .carbonK && map.microscope == scope && map.coreLossToLowLossDose == 1
                        && map.edgeWindowEV == 284..<(284 + Double(delta)!) && rel(map.effectiveCollectionMrad, effective) <= 1e-14
                    worst.sigmaK = max(worst.sigmaK, rel(map.crossSectionBarn, dd.x("sigmaK")))
                    for (p, px) in map.pixels.enumerated() {
                        worst.n = max(worst.n, rel(px.atomsPerNM2 ?? .nan, dd.a("n")[p]))
                        worst.sums = max(worst.sums, rel(px.edgeCounts ?? .nan, dd.a("iK")[p]), rel(px.backgroundCounts ?? .nan, dd.a("iB")[p]))
                        worst.fit = max(worst.fit, rel(px.powerLawR ?? .nan, w.a("r")[p]), rel(px.powerLawA ?? .nan, w.a("A")[p]))
                        worst.sigma = max(worst.sigma, rel(px.sigmaCounting ?? .nan, dd.a("sigmaN")[p]))
                        worst.low = max(worst.low, (px.lowLossIntensity ?? .nan) == dd.a("iLow")[p] ? 0 : 1)
                        structural = structural && px.unavailable == nil
                        compared += 1
                    }
                    // The I_0 route: slice 1's fixed-threshold thickness map as the low-loss intensity (Egerton eq. 4.65).
                    for (theta, tv) in dd.d("i0Route") {
                        let t = tv as! [String: Any]
                        let tm = try EELSThickness.logRatio(l, threshold: .fixed(Double(theta)!))
                        let m0 = try EELSEdgeQuantification.ratioMethod(coreLoss: c, microscope: scope, lowLoss: .zeroLoss(tm),
                                                                         backgroundWindowEV: range[0]...range[1], integrationWidthEV: Double(delta)!)
                        structural = structural && m0.lowLossRoute.contains("4.65") && m0.lowLossRoute != map.lowLossRoute
                        for (p, px) in m0.pixels.enumerated() {
                            worst.low = max(worst.low, (px.lowLossIntensity ?? .nan) == t.a("i0")[p] ? 0 : 1)
                            worst.i0n = max(worst.i0n, rel(px.atomsPerNM2 ?? .nan, t.a("n")[p]))
                            i0Compared += 1
                        }
                    }
                }
                _ = wname
            }
        }
    }
    r.check("ratioMethod, I_low(Δ) route, 16 planted images x 3 windows x 4 widths: .atomsPerNM2 equals exSpy/HyperSpy's n (\(compared) pixels, worst relative \(worst.n), allowed 1e-10)",
            compared == 16 * 3 * 4 * 15 && worst.n <= 1e-10)
    r.check("ratioMethod: .edgeCounts, .backgroundCounts equal the pins (worst relative \(worst.sums), allowed 1e-12); .powerLawR, .powerLawA (worst \(worst.fit), allowed 1e-12)",
            worst.sums <= 1e-12 && worst.fit <= 1e-12)
    r.check("ratioMethod: .sigmaCounting equals the registered sigma_n (worst relative \(worst.sigma), allowed 1e-9)", worst.sigma <= 1e-9)
    r.check("ratioMethod: .lowLossIntensity equals the pins' I_low and I_0 exactly, on both routes", worst.low == 0)
    r.check("ratioMethod: .crossSectionBarn equals the pins' sigma_k (worst relative \(worst.sigmaK), allowed 1e-10)", worst.sigmaK <= 1e-10)
    r.check("ratioMethod, I_0 route (.zeroLoss(ThicknessMap)), \(i0Compared) pixels: .atomsPerNM2 equals the pins' n (worst relative \(worst.i0n), allowed 1e-10)",
            i0Compared > 0 && worst.i0n <= 1e-10)
    r.check("ArealDensityMap .nx .ny .pixels .edge .microscope .effectiveCollectionMrad .edgeWindowEV .edgeChannels .backgroundWindowEV .validation .caveat .coreLossToLowLossDose; no pixel unavailable",
            structural)

    // MARK: 4. One planted image in detail: the map's own statements, every parameter, the other edges.
    let cR = try core("edge-core-R-ss-noiseless.f64"), lR = try low("edge-low-R-ss-noiseless.f64")
    let base = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, microscope: scope, lowLoss: .integratedToWidth(lR))
    r.check("ratioMethod defaults: edge C K, window 234...279, Δ 50 (edge 284..<334, channels 536..<736), dose 1, method, validation \"none\", no caveat",
            base.edge == .carbonK && base.backgroundWindowEV == 234...279 && base.edgeWindowEV == 284..<334 && base.edgeChannels == 536..<736
            && base.coreLossToLowLossDose == 1 && base.method == EELSEdgeQuantification.methodName && base.validation == "none" && base.caveat == nil)
    r.check("ArealDensityMap.lowLossRoute names Egerton eq. 4.66 for .integratedToWidth", base.lowLossRoute.contains("4.66") && base.lowLossRoute.contains("50"))
    let rPlanted = pins.d("plantedR")
    let rImage = (rPlanted["images"] as! [[String: Any]]).first { ($0["coreFile"] as! String) == "edge-core-R-ss-noiseless.f64" }!
    let nR = rImage.d("windows").d("default").d("byDelta").d("50").a("n")
    r.check("planted set R, single scattering, default window, Δ 50: the 15 densities equal the pins' (relative 1e-10) and the truth 200 ... within 2 % [method bias]",
            zip(base.pixels, nR).allSatisfy { rel($0.atomsPerNM2 ?? .nan, $1) <= 1e-10 } && base.pixels[0].atomsPerNM2.map { Swift.abs($0 / 200 - 1) <= 0.02 } == true)
    let px0 = base.pixels[0], px1 = base.pixels[1]
    r.check("ArealDensityPixel: every field present on an answered pixel; Equatable compares them",
            px0.atomsPerNM2 != nil && px0.sigmaCounting != nil && px0.edgeCounts != nil && px0.backgroundCounts != nil && px0.powerLawR != nil
            && px0.powerLawA != nil && px0.lowLossIntensity != nil && px0.unavailable == nil && px0 == base.pixels[0] && px0 != px1)

    let dose2 = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, microscope: scope, lowLoss: .integratedToWidth(lR), coreLossToLowLossDose: 2)
    r.check("coreLossToLowLossDose: 2 doubles .lowLossIntensity, halves .atomsPerNM2 and .sigmaCounting, and is reported",
            dose2.coreLossToLowLossDose == 2 && zip(base.pixels, dose2.pixels).allSatisfy {
                $1.lowLossIntensity == 2 * $0.lowLossIntensity! && $1.atomsPerNM2 == $0.atomsPerNM2! / 2 && $1.sigmaCounting == $0.sigmaCounting! / 2 })
    let onset = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, microscope: scope, lowLoss: .integratedToWidth(lR), edgeOnsetEV: 290)
    r.check("edgeOnsetEV: 290 moves the edge window to 290..<340 (channels 560..<760) and the default background window to 240...285",
            onset.edgeWindowEV == 290..<340 && onset.edgeChannels == 560..<760 && onset.backgroundWindowEV == 240...285)
    let nitrogen = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, edge: .nitrogenK, microscope: scope, lowLoss: .integratedToWidth(lR))
    let oxygen = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, edge: .oxygenK, microscope: scope, lowLoss: .integratedToWidth(lR))
    r.check("edge: .nitrogenK / .oxygenK: edge window from 401 / 532 eV, a caveat naming the preceding edge's tail, validation \"none\"; C K has none",
            nitrogen.edge == .nitrogenK && nitrogen.edgeWindowEV == 401..<451 && nitrogen.backgroundWindowEV == 351...396
            && oxygen.edge == .oxygenK && oxygen.edgeWindowEV == 532..<582 && oxygen.backgroundWindowEV == 482...527
            && nitrogen.caveat?.contains("preceding edge's tail") == true && oxygen.caveat?.contains("preceding edge's tail") == true
            && nitrogen.validation == "none" && oxygen.validation == "none" && base.caveat == nil
            && nitrogen.crossSectionBarn > 0 && oxygen.crossSectionBarn > 0 && nitrogen.crossSectionBarn != base.crossSectionBarn)
    let wide = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, microscope: scope, lowLoss: .integratedToWidth(lR),
                                                      backgroundWindowEV: 200...279, integrationWidthEV: 100)
    r.check("backgroundWindowEV: 200...279 and integrationWidthEV: 100 are used (edge 284..<384, 400 channels, window as given)",
            wide.edgeWindowEV == 284..<384 && wide.edgeChannels.count == 400 && wide.backgroundWindowEV == 200...279)
    let microscopeSeen = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, microscope: m3, lowLoss: .integratedToWidth(lR))
    r.check("microscope: a different EELSMicroscope changes the effective angle and the cross section, and is reported",
            microscopeSeen.microscope == m3 && microscopeSeen.effectiveCollectionMrad != base.effectiveCollectionMrad
            && microscopeSeen.crossSectionBarn != base.crossSectionBarn)
    let floatCore = try CoreLossSpectrumImage(nx: 5, ny: 3, channels: cR.channels, counts: cR.counts.map { Float($0) },
                                              energyOffsetEV: cR.energyOffsetEV, energyScaleEV: cR.energyScaleEV)
    let viaFloat = try EELSEdgeQuantification.ratioMethod(coreLoss: floatCore, microscope: scope, lowLoss: .integratedToWidth(lR))
    r.check("a core-loss image built from Float counts runs through ratioMethod and gives n within 1e-3 of the Double image's (Float rounding)",
            zip(base.pixels, viaFloat.pixels).allSatisfy { rel($0.atomsPerNM2 ?? .nan, $1.atomsPerNM2 ?? .nan) <= 1e-3 })
    do { _ = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, microscope: scope, lowLoss: .integratedToWidth(lR), cancelled: { true })
        r.check("cancelled: { true } stops ratioMethod", false, "completed") }
    catch is SpectroCancelled { r.check("cancelled: { true } throws SpectroCancelled (SpectroCore's)", true) }
    catch { r.check("cancelled: { true } throws SpectroCancelled", false, "\(error)") }

    // MARK: 5. Why a pixel has no answer: every EdgeUnavailable case, by an input that causes it.
    let channelsC = cR.channels, channelsL = lR.channels
    var counts = cR.counts, lowCounts = lR.counts
    for c in 336..<426 { counts[c] = 0 }                                                    // pixel 0: first window half empty
    for c in 0..<channelsL { lowCounts[channelsL + c] = 0 }                                 // pixel 1: low loss all zero
    for c in 0..<channelsL { lowCounts[3 * channelsL + c] = -1 }                            // pixel 3: low loss negative
    for c in 336..<426 { counts[4 * channelsC + c] = 1e300 }                                // pixel 4: r, A overflow
    for c in 426..<516 { counts[4 * channelsC + c] = 1e-300 }
    let core2 = try CoreLossSpectrumImage(nx: 5, ny: 3, channels: channelsC, counts: counts, energyOffsetEV: cR.energyOffsetEV, energyScaleEV: cR.energyScaleEV)
    let low2 = try LowLossSpectrumImage(nx: 5, ny: 3, channels: channelsL, counts: lowCounts, energyOffsetEV: lR.energyOffsetEV, energyScaleEV: lR.energyScaleEV)
    let bad = try EELSEdgeQuantification.ratioMethod(coreLoss: core2, microscope: scope, lowLoss: .integratedToWidth(low2))
    r.check("EdgeUnavailable.backgroundSumNotPositive (pixel 0): n, sigma, counts nil; reason set",
            bad.pixels[0].unavailable == .backgroundSumNotPositive && bad.pixels[0].atomsPerNM2 == nil && bad.pixels[0].sigmaCounting == nil
            && bad.pixels[0].edgeCounts == nil && bad.pixels[0].backgroundCounts == nil && bad.pixels[0].lowLossIntensity == nil)
    r.check("EdgeUnavailable.lowLossNotPositive (pixels 1 and 3: I_low = 0 and < 0): n nil, the power law's r and A still reported",
            bad.pixels[1].unavailable == .lowLossNotPositive && bad.pixels[3].unavailable == .lowLossNotPositive
            && bad.pixels[1].atomsPerNM2 == nil && bad.pixels[1].powerLawR != nil && bad.pixels[1].powerLawA != nil)
    r.check("EdgeUnavailable.backgroundNotFinite (pixel 4: window sums 9e301 and 9e-299): r and A overflow, reason set",
            bad.pixels[4].unavailable == .backgroundNotFinite && bad.pixels[4].atomsPerNM2 == nil, "\(bad.pixels[4])")
    r.check("a pixel nothing is wrong with (pixel 2) answers beside the refused ones",
            bad.pixels[2].unavailable == nil && bad.pixels[2].atomsPerNM2 != nil)
    var thresholds = [Double](repeating: 4.5, count: 15)
    thresholds[1] = .nan
    let tmNaN = try EELSThickness.logRatio(lR, threshold: .perPixel(thresholds))
    let viaI0 = try EELSEdgeQuantification.ratioMethod(coreLoss: cR, microscope: scope, lowLoss: .zeroLoss(tmNaN))
    r.check("EdgeUnavailable.lowLossUnavailable (the thickness map has no I_0 at pixel 1); other pixels answer",
            viaI0.pixels[1].unavailable == .lowLossUnavailable && viaI0.pixels[1].atomsPerNM2 == nil && viaI0.pixels[0].unavailable == nil
            && viaI0.pixels[0].atomsPerNM2 != nil)
    let allReasons: [EdgeUnavailable] = [.backgroundSumNotPositive, .backgroundNotFinite, .lowLossNotPositive, .lowLossUnavailable]
    r.check("EdgeUnavailable: .rawValue and .description are the same non-empty text, distinct per case; an Error; Equatable",
            allReasons.allSatisfy { !$0.rawValue.isEmpty && $0.description == $0.rawValue && EdgeUnavailable(rawValue: $0.rawValue) == $0 && ($0 as Error) is EdgeUnavailable }
            && Set(allReasons.map { $0.rawValue }).count == 4)

    // MARK: 6. What the call refuses (EELSEdgeError, Equatable).
    func refuses(_ name: String, _ want: EELSEdgeError, _ body: () throws -> Void) {
        do { try body(); r.check("EELSEdgeError.\(name)", false, "did not throw") }
        catch let e as EELSEdgeError { r.check("EELSEdgeError.\(name)", e == want, "threw \(e)") }
        catch { r.check("EELSEdgeError.\(name)", false, "threw \(error)") }
    }
    func run(_ c: CoreLossSpectrumImage? = nil, _ m: EELSMicroscope? = nil, low: LowLossIntensity? = nil, edge: CoreLossEdge = .carbonK,
             window: ClosedRange<Double>? = nil, onset: Double? = nil, width: Double = 50, dose: Double = 1) throws {
        _ = try EELSEdgeQuantification.ratioMethod(coreLoss: c ?? cR, edge: edge, microscope: m ?? scope, lowLoss: low ?? .integratedToWidth(lR),
                                                   backgroundWindowEV: window, edgeOnsetEV: onset, integrationWidthEV: width, coreLossToLowLossDose: dose)
    }
    refuses("invalidShape(nx: 2, ny: 1, channels: 3, counts: 4)", .invalidShape(nx: 2, ny: 1, channels: 3, counts: 4)) {
        _ = try CoreLossSpectrumImage(nx: 2, ny: 1, channels: 3, counts: [1, 2, 3, 4] as [Double], energyOffsetEV: 0, energyScaleEV: 1)
    }
    refuses("invalidShape (the Float initialiser)", .invalidShape(nx: 0, ny: 1, channels: 1, counts: 1)) {
        _ = try CoreLossSpectrumImage(nx: 0, ny: 1, channels: 1, counts: [1] as [Float], energyOffsetEV: 0, energyScaleEV: 1)
    }
    refuses("invalidEnergyAxis(offsetEV: 0, scaleEV: 0)", .invalidEnergyAxis(offsetEV: 0, scaleEV: 0)) {
        _ = try CoreLossSpectrumImage(nx: 1, ny: 1, channels: 2, counts: [1, 2] as [Double], energyOffsetEV: 0, energyScaleEV: 0)
    }
    refuses("nonFiniteCounts(pixel: 1)", .nonFiniteCounts(pixel: 1)) {
        _ = try CoreLossSpectrumImage(nx: 2, ny: 1, channels: 2, counts: [1, 2, 3, Double.nan], energyOffsetEV: 0, energyScaleEV: 1)
    }
    refuses("invalidIntegrationWidth(0)", .invalidIntegrationWidth(0)) { try run(width: 0) }
    refuses("invalidDoseRatio(-1)", .invalidDoseRatio(-1)) { try run(dose: -1) }
    refuses("invalidMicroscope (collection angle 0)", .invalidMicroscope) { try run(nil, EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 0)) }
    refuses("backgroundWindowOutsideAxis(fromEV: 100, toEV: 140, axisFromEV: 150, axisToEV: 649.75)",
            .backgroundWindowOutsideAxis(fromEV: 100, toEV: 140, axisFromEV: 150, axisToEV: 649.75)) { try run(window: 100...140) }
    refuses("edgeWindowOutsideAxis(fromEV: 700, toEV: 750)", .edgeWindowOutsideAxis(fromEV: 700, toEV: 750)) { try run(window: 234...279, onset: 700) }
    refuses("crossSectionZero(edgeWindowFromEV: 210, toEV: 260)", .crossSectionZero(edgeWindowFromEV: 210, toEV: 260)) {
        try run(window: 160...200, onset: 210)
    }
    refuses("lowLossShapeMismatch(expected: 15, got: 1)  [.integratedToWidth]", .lowLossShapeMismatch(expected: 15, got: 1)) {
        try run(low: .integratedToWidth(LowLossSpectrumImage(nx: 1, ny: 1, channels: channelsL, counts: Array(lR.counts[0..<channelsL]),
                                                              energyOffsetEV: lR.energyOffsetEV, energyScaleEV: lR.energyScaleEV)))
    }
    let oneTM = try EELSThickness.logRatio(LowLossSpectrumImage(nx: 1, ny: 1, channels: 8, counts: [1, 2, 4, 8, 4, 2, 1, 1] as [Double], energyOffsetEV: -2, energyScaleEV: 1),
                                           threshold: .fixed(1))
    refuses("lowLossShapeMismatch(expected: 15, got: 1)  [.zeroLoss]", .lowLossShapeMismatch(expected: 15, got: 1)) { try run(low: .zeroLoss(oneTM)) }
    refuses("backgroundWindowNotPositive(fromEV: -50)  [a core-loss axis from -100 eV]", .backgroundWindowNotPositive(fromEV: -50)) {
        let negative = try CoreLossSpectrumImage(nx: 1, ny: 1, channels: 600, counts: [Double](repeating: 1, count: 600), energyOffsetEV: -100, energyScaleEV: 1)
        try run(negative, low: .integratedToWidth(onesLow), window: -50 ... -10)
    }
    refuses("backgroundWindowTooNarrow(fromEV: 649.75, toEV: 649.75)  [a window at the last channel]", .backgroundWindowTooNarrow(fromEV: 649.75, toEV: 649.75)) {
        try run(window: 649.75...649.75)
    }
    do { try run(width: .nan); r.check("EELSEdgeError.invalidIntegrationWidth(NaN)", false, "did not throw") }
    catch let e as EELSEdgeError { if case .invalidIntegrationWidth(let w) = e { r.check("EELSEdgeError.invalidIntegrationWidth(NaN)", w.isNaN) } else { r.check("EELSEdgeError.invalidIntegrationWidth(NaN)", false, "\(e)") } }
    catch { r.check("EELSEdgeError.invalidIntegrationWidth(NaN)", false, "\(error)") }
    r.check("EELSEdgeError: Equatable distinguishes cases and payloads", EELSEdgeError.invalidDoseRatio(1) != .invalidDoseRatio(2)
            && EELSEdgeError.invalidMicroscope != .crossSectionFailed && EELSEdgeError.noBundledCrossSection(element: "C", subshell: "K1")
            != .noBundledCrossSection(element: "N", subshell: "K1") && EELSEdgeError.backgroundWindowTooNarrow(fromEV: 1, toEV: 2) == .backgroundWindowTooNarrow(fromEV: 1, toEV: 2))
}
