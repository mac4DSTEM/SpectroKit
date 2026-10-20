//
//  WindowRulesTests.swift
//  Role: docs/generality-0.5.0-registration.md, family 1 (W1-W7): the window rules as one value. The default reproduces what
//        `ElementWindows.build` has always built (equality with the call that names no rules; asserted exactly today as D12's quick check); each non-default
//        field moves the windows or the counts as the registration's section 5 predicted before the code was written. Planted,
//        noise-free spectra (Gaussian lines at the detector's line width on a stated continuum, rounded to integer counts).
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct WindowRulesTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.005, size: 4000)   // 0 to 20 keV
    /// 1 eV channels, for the test whose prediction is a continuous Gaussian fraction: with 5 eV channels the whole-channel windows
    /// move the ratio by 1.1 % (0.764 against 0.775), the registration's +-0.01 being too tight for that axis (amendment).
    private static let fineAxis = EnergyAxis(offset: 0, scale: 0.001, size: 20000)
    private static let resolution = 130.0

    /// Integer counts: `continuum(E)` per channel plus a Gaussian of the given area (counts) at each line, width from the
    /// detector law at that energy (the width `SpectralLine` gives the window).
    private static func spectrum(lines: [(id: String, area: Double)], continuum: (Double) -> Double, axis: EnergyAxis = axis) -> [UInt64] {
        var mu = (0..<axis.size).map { continuum(axis.energy(ofChannel: $0)) }
        for l in lines {
            let sl = try! SpectralLine(id: l.id, resolutionMnKaEV: resolution)
            let sigma = sl.fwhm / (2 * (2 * log(2.0)).squareRoot())
            for i in 0..<axis.size {
                let d = axis.energy(ofChannel: i) - sl.energy
                if abs(d) < 12 * sigma { mu[i] += l.area * axis.scale * exp(-d * d / (2 * sigma * sigma)) / (sigma * (2 * Double.pi).squareRoot()) }
            }
        }
        return mu.map { UInt64($0.rounded()) }
    }

    private static func net(_ rules: WindowRules, _ counts: [UInt64], picks: [ElementWindows.Pick] = [.init(symbol: "Al")],
                            axis: EnergyAxis = axis) -> [Double] {
        let w = ElementWindows.build(picks: picks, axis: axis, resolutionMnKaEV: resolution, beamEnergyKeV: 200, rules: rules)
        return ElementWindows.netCounts(spectrum: counts, windows: w).map { $0!.net }
    }

    private static let flat: @Sendable (Double) -> Double = { _ in 1000 }
    /// Convex and decreasing: a symmetric pair of background windows reads high at the line, more so the farther out they sit.
    private static let convex: @Sendable (Double) -> Double = { e in 20000 * exp(-(e - 1) / 0.3) + 200 }

    // MARK: The default is the old behaviour

    @Test func testDefaultRulesEqualTheCallWithoutRules() {
        let counts = Self.spectrum(lines: [("Al_Ka", 5e6), ("Si_Ka", 2e6), ("Mg_Ka", 1e6)], continuum: Self.convex)
        let picks: [ElementWindows.Pick] = [.init(symbol: "Al"), .init(symbol: "Si"), .init(symbol: "Mg"), .init(symbol: "Zr"),
                                            .init(symbol: "Al", lines: ["Al_Ka", "Al_Kb"])]
        let a = ElementWindows.build(picks: picks, axis: Self.axis, resolutionMnKaEV: Self.resolution, beamEnergyKeV: 200)
        let b = ElementWindows.build(picks: picks, axis: Self.axis, resolutionMnKaEV: Self.resolution, beamEnergyKeV: 200, rules: .default)
        #expect(a == b)
        let na = ElementWindows.netCounts(spectrum: counts, windows: a), nb = ElementWindows.netCounts(spectrum: counts, windows: b)
        #expect(na == nb)
        #expect(WindowRules.default.isDefault)
        #expect(!WindowRules(integrationWindowsWidth: 2.1).isDefault)
        for s in ["Al", "Zr", "Rh", "Hf", "Cu", "O"] {
            #expect(ElementWindows.defaultFamily(of: s) == ElementWindows.defaultFamily(of: s, rules: .default))
        }
        // The values the windows have always used.
        let d = WindowRules.default
        #expect(d.integrationWindowsWidth == 2.0 && d.backgroundGapLeft == 2 && d.backgroundGapRight == 2
                && d.backgroundWindowsWidth == 1 && d.conflictMinimumWeight == 0.01 && d.conflictFlankFWHM == 2
                && d.kFamilyLimitKeV == 20 && d.clipOverlappingWindows)
        let data = try! JSONEncoder().encode(WindowRules(integrationWindowsWidth: 3, clipOverlappingWindows: false))
        #expect(try! JSONDecoder().decode(WindowRules.self, from: data) == WindowRules(integrationWindowsWidth: 3, clipOverlappingWindows: false))
    }

    // MARK: W1 integration width

    /// A Gaussian holds erf(1.177 / sqrt 2) = 0.7612 of its area within +-F/2 and erf(2.355 / sqrt 2) = 0.9817 within +-F.
    @Test func testNarrowerIntegrationWindowKeepsTheGaussianFraction() {
        let counts = Self.spectrum(lines: [("Al_Ka", 5e8)], continuum: Self.flat, axis: Self.fineAxis)
        let wide = Self.net(.default, counts, axis: Self.fineAxis)[0]
        let narrow = Self.net(WindowRules(integrationWindowsWidth: 1), counts, axis: Self.fineAxis)[0]
        #expect(abs(narrow / wide - 0.7612 / 0.9817) < 0.01, "ratio \(narrow / wide), predicted \(0.7612 / 0.9817)")
        #expect(abs(wide / 5e8 - 0.9817) < 0.005)
        // On the 5 eV axis the windows are whole channels and the ratio is 0.764 (within 0.015 of the continuous value).
        let coarse = Self.spectrum(lines: [("Al_Ka", 5e8)], continuum: Self.flat)
        #expect(abs(Self.net(WindowRules(integrationWindowsWidth: 1), coarse)[0] / Self.net(.default, coarse)[0] - 0.7612 / 0.9817) < 0.015)
        let w2 = ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200, rules: WindowRules(integrationWindowsWidth: 1))[0].window!
        let w1 = ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200)[0].window!
        #expect(w2.signal.count < w1.signal.count)
        #expect(w2.background!.left == w1.background!.left && w2.background!.right == w1.background!.right)   // anchored to W2, W3
    }

    // MARK: W2 background gap

    @Test func testWiderBackgroundGapMovesTheWindowsOutAndLowersTheNetOnAConvexContinuum() {
        let counts = Self.spectrum(lines: [("Al_Ka", 5e6)], continuum: Self.convex)
        let a = ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200)[0]
        let b = ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200,
                                     rules: WindowRules(backgroundGapLeft: 3, backgroundGapRight: 3))[0]
        // Exactly F further out on each side, within one channel of rounding: F = 76.6 eV = 15.3 channels.
        let f = a.fwhm / Self.axis.scale
        #expect(abs(Double(a.window!.background!.left.upperBound - b.window!.background!.left.upperBound) - f) <= 1)
        #expect(abs(Double(b.window!.background!.right.lowerBound - a.window!.background!.right.lowerBound) - f) <= 1)
        let netDefault = ElementWindows.netCounts(spectrum: counts, windows: [a])[0]!.net
        let netWide = ElementWindows.netCounts(spectrum: counts, windows: [b])[0]!.net
        #expect(netWide < netDefault)
        // One side only: the left edge moves, the right does not.
        let l = ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200,
                                     rules: WindowRules(backgroundGapLeft: 3))[0].window!.background!
        #expect(l.right == a.window!.background!.right && l.left != a.window!.background!.left)
    }

    // MARK: W3 background window width

    @Test func testWiderBackgroundWindowsDoubleTheChannelsAndCatchANeighbour() {
        let a = ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200)[0].window!
        let b = ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200,
                                     rules: WindowRules(backgroundWindowsWidth: 2))[0].window!
        #expect(abs(b.background!.left.count - 2 * a.background!.left.count) <= 1)
        #expect(abs(b.background!.right.count - 2 * a.background!.right.count) <= 1)
        #expect(abs(b.background!.scale - a.background!.scale / 2) < 0.02 * a.background!.scale)
        // Flat continuum, no line: the net is zero for either width (the scale is the channel ratio).
        let empty = Self.spectrum(lines: [], continuum: Self.flat)
        for r in [WindowRules.default, WindowRules(backgroundWindowsWidth: 2)] { #expect(abs(Self.net(r, empty)[0]) < 1e-6) }
        // A peak 4 F above Al K-alpha: the default right window ends at 3 F (the peak's near tail only), the wider one at 4 F
        // (half the peak): the net falls by about half the peak times the scale.
        let f = try! SpectralLine(id: "Al_Ka", resolutionMnKaEV: Self.resolution).fwhm
        let e = 1.4865 + 4 * f
        var mu = (0..<Self.axis.size).map { _ in 1000.0 }
        let sigma = f / (2 * (2 * log(2.0)).squareRoot())
        for i in 0..<Self.axis.size {
            let d = Self.axis.energy(ofChannel: i) - e
            if abs(d) < 12 * sigma { mu[i] += 1e6 * Self.axis.scale * exp(-d * d / (2 * sigma * sigma)) / (sigma * (2 * Double.pi).squareRoot()) }
        }
        let counts = mu.map { UInt64($0.rounded()) }
        #expect(Self.net(WindowRules(backgroundWindowsWidth: 2), counts)[0] < Self.net(.default, counts)[0] - 1000)
    }

    // MARK: W4 and W5 the conflict report

    @Test func testConflictReportFollowsTheMinimumWeightAndTheFlank() {
        func conflicts(_ r: WindowRules) -> [WindowConflict] {
            ElementWindows.build(picks: [.init(symbol: "Al")], axis: Self.axis, beamEnergyKeV: 200, rules: r)[0].conflicts
        }
        // Al K-beta (weight 0.0132) lies on Al K-alpha's right background window by default.
        #expect(conflicts(.default).contains { $0.other == "Al_Kb" })
        #expect(conflicts(WindowRules(conflictMinimumWeight: 0.5)).isEmpty)
        #expect(conflicts(WindowRules(conflictMinimumWeight: 0.01)).contains { $0.other == "Al_Kb" })
        // Flank 2 F reaches the window, 1 F stops 2 eV short of it.
        #expect(conflicts(WindowRules(conflictFlankFWHM: 1)).isEmpty)
        #expect(conflicts(WindowRules(conflictFlankFWHM: 3)).contains { $0.other == "Al_Kb" })
        // The counts are untouched by either field.
        let counts = Self.spectrum(lines: [("Al_Ka", 5e6)], continuum: Self.convex)
        #expect(Self.net(WindowRules(conflictMinimumWeight: 0.5, conflictFlankFWHM: 1), counts) == Self.net(.default, counts))
    }

    // MARK: W6 the K-family limit

    @Test func testKFamilyLimit() {
        #expect(ElementWindows.defaultFamily(of: "Zr") == .K)                                       // Kα 15.78 keV
        #expect(ElementWindows.defaultFamily(of: "Zr", rules: WindowRules(kFamilyLimitKeV: 10)) == .L)
        #expect(ElementWindows.defaultFamily(of: "Rh") == .L)                                       // Kα 20.22 keV
        #expect(ElementWindows.defaultFamily(of: "Rh", rules: WindowRules(kFamilyLimitKeV: 25)) == .K)
        // It reaches the windows: Zr's default line is Zr_Ka, or Zr_La at a limit of 10 keV.
        #expect(ElementWindows.build(picks: [.init(symbol: "Zr")], axis: Self.axis, beamEnergyKeV: 200)[0].id == "Zr_Ka")
        #expect(ElementWindows.build(picks: [.init(symbol: "Zr")], axis: Self.axis, beamEnergyKeV: 200,
                                     rules: WindowRules(kFamilyLimitKeV: 10))[0].id == "Zr_La")
    }

    // MARK: W7 clipping

    @Test func testUnclippedWindowsCountTheSharedChannelsTwice() {
        let picks: [ElementWindows.Pick] = [.init(symbol: "Al", lines: ["Al_Ka", "Al_Kb"])]
        let counts = Self.spectrum(lines: [("Al_Ka", 5e6), ("Al_Kb", 5e4)], continuum: Self.flat)
        let clipped = ElementWindows.build(picks: picks, axis: Self.axis, beamEnergyKeV: 200)
        let open = ElementWindows.build(picks: picks, axis: Self.axis, beamEnergyKeV: 200, rules: WindowRules(clipOverlappingWindows: false))
        #expect(clipped[1].window!.signal.lowerBound == clipped[0].window!.signal.upperBound)       // the later window starts where the earlier ends
        #expect(open[1].window!.signal.lowerBound < open[0].window!.signal.upperBound)               // overlapping
        #expect(open[0].window == clipped[0].window)
        let sumClipped = ElementWindows.netCounts(spectrum: counts, windows: clipped).map { $0!.net }.reduce(0, +)
        let sumOpen = ElementWindows.netCounts(spectrum: counts, windows: open).map { $0!.net }.reduce(0, +)
        #expect(sumOpen > sumClipped)
    }
}
