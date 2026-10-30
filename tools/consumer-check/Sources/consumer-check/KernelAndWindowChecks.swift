//
//  KernelAndWindowChecks.swift
//  Role: policy family 4 (0.5.0) used from outside the package: `SmoothingKernel` with
//        `MapSmoothing.apply(_:width:height:kernel:)` (SpectroCore) and the ratio method's default pre-edge window offsets
//        (SpectroEELS). Only public API is named.
//

import Foundation
import SpectroCore
import SpectroEELS

func kernelAndWindowChecks(_ r: inout Report) {
    var m = [Double](repeating: 0, count: 15 * 15)
    m[7 * 15 + 7] = 49
    r.check("a menu entry is its kernel bit for bit",
            MapSmoothing.box3.apply(m, width: 15, height: 15) == MapSmoothing.apply(m, width: 15, height: 15, kernel: .box(width: 3))
            && MapSmoothing.gaussian2.smoothingKernel == .gaussian(sigma: 2, truncation: 2) && MapSmoothing.none.smoothingKernel == nil)
    let s = MapSmoothing.apply(m, width: 15, height: 15, kernel: .box(width: 7))
    r.check("a box of seven spreads an impulse over seven by seven", abs(s[7 * 15 + 7] - 1) < 1e-12 && abs(s[3 * 15 + 3]) < 1e-12 && abs(s[4 * 15 + 4] - 1) < 1e-12)
    r.check("a Gaussian's truncation sets its taps", SmoothingKernel.gaussian(sigma: 1.5, truncation: 3).taps.count == 11
            && SmoothingKernel.gaussian(sigma: 1.5).taps.count == 7)
    r.check("an invalid kernel leaves the map alone", MapSmoothing.apply(m, width: 15, height: 15, kernel: .box(width: 4)) == m
            && !SmoothingKernel.gaussian(sigma: 0).isValid)
    r.check("the default pre-edge window is [E_k - 50, E_k - 5] and its offsets are parameters",
            EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284) == 234...279
            && EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284, belowOnsetEV: 80, gapEV: 10) == 204...274)
}
