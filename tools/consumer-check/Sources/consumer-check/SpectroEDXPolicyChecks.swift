//
//  SpectroEDXPolicyChecks.swift
//  Role: the policy parameters of SpectroEDX (docs/generality-0.5.0-registration.md) used from outside the package: every
//        type, initialiser, field and entry point a consumer passes must be `public`. One function per family; each checks that
//        the default value changes nothing and that one non-default value moves the result the way the registration predicted.
//        Only public API is named.
//

import Foundation
import SpectroCore
import SpectroEDX

/// Family 1: `WindowRules`.
func windowRulesChecks(_ r: inout Report) {
    let axis = EnergyAxis(offset: 0, scale: 0.005, size: 4000)
    let al = [ElementWindows.Pick(symbol: "Al")]
    let plain = ElementWindows.build(picks: al, axis: axis, beamEnergyKeV: 200)
    r.check("WindowRules.default equals the call without rules",
            plain == ElementWindows.build(picks: al, axis: axis, beamEnergyKeV: 200, rules: .default) && WindowRules.default.isDefault)
    let d = WindowRules.default
    r.check("WindowRules defaults are the values the windows have always used",
            d.integrationWindowsWidth == 2 && d.backgroundGapLeft == 2 && d.backgroundGapRight == 2 && d.backgroundWindowsWidth == 1
            && d.conflictMinimumWeight == 0.01 && d.conflictFlankFWHM == 2 && d.kFamilyLimitKeV == 20 && d.clipOverlappingWindows)
    let narrow = ElementWindows.build(picks: al, axis: axis, beamEnergyKeV: 200, rules: WindowRules(integrationWindowsWidth: 1))
    r.check("a narrower integration window has fewer channels and the same background windows",
            (narrow[0].window?.signal.count ?? 99) < (plain[0].window?.signal.count ?? 0)
            && narrow[0].window?.background?.left == plain[0].window?.background?.left)
    let gap = ElementWindows.build(picks: al, axis: axis, beamEnergyKeV: 200, rules: WindowRules(backgroundGapLeft: 3, backgroundGapRight: 3))
    r.check("a wider gap moves the left window down and the right window up",
            (gap[0].window?.background?.left.upperBound ?? 99_999) < (plain[0].window?.background?.left.upperBound ?? 0)
            && (gap[0].window?.background?.right.lowerBound ?? 0) > (plain[0].window?.background?.right.lowerBound ?? 99_999))
    let wide = ElementWindows.build(picks: al, axis: axis, beamEnergyKeV: 200, rules: WindowRules(backgroundWindowsWidth: 2))
    r.check("twice the background window width gives about twice the channels",
            abs((wide[0].window?.background?.left.count ?? 0) - 2 * (plain[0].window?.background?.left.count ?? 0)) <= 1)
    r.check("the conflict report follows the minimum weight and the flank",
            !plain[0].conflicts.isEmpty
            && ElementWindows.build(picks: al, axis: axis, beamEnergyKeV: 200, rules: WindowRules(conflictMinimumWeight: 0.5))[0].conflicts.isEmpty
            && ElementWindows.build(picks: al, axis: axis, beamEnergyKeV: 200, rules: WindowRules(conflictFlankFWHM: 1))[0].conflicts.isEmpty)
    r.check("the K-family limit decides Zr's default family",
            ElementWindows.defaultFamily(of: "Zr") == .K && ElementWindows.defaultFamily(of: "Zr", rules: WindowRules(kFamilyLimitKeV: 10)) == .L
            && ElementWindows.defaultFamily(of: "Rh") == .L && ElementWindows.defaultFamily(of: "Rh", rules: WindowRules(kFamilyLimitKeV: 25)) == .K)
    let two = [ElementWindows.Pick(symbol: "Al", lines: ["Al_Ka", "Al_Kb"])]
    let clipped = ElementWindows.build(picks: two, axis: axis, beamEnergyKeV: 200)
    let open = ElementWindows.build(picks: two, axis: axis, beamEnergyKeV: 200, rules: WindowRules(clipOverlappingWindows: false))
    r.check("clipping off leaves the two signal windows overlapping",
            (clipped[1].window?.signal.lowerBound ?? 0) == (clipped[0].window?.signal.upperBound ?? 1)
            && (open[1].window?.signal.lowerBound ?? 99_999) < (open[0].window?.signal.upperBound ?? 0))
    let coded = try? JSONDecoder().decode(WindowRules.self, from: JSONEncoder().encode(WindowRules(integrationWindowsWidth: 3)))
    r.check("WindowRules round-trips through JSON", coded == WindowRules(integrationWindowsWidth: 3))
}
