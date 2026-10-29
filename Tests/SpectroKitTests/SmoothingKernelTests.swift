//
//  SmoothingKernelTests.swift
//  Role: `SmoothingKernel`, any box width or Gaussian sigma and truncation.
//        The menu entries are the same kernels as before (asserted bit for bit today, D12's quick check); a non-default kernel spreads an impulse as predicted.
//

import Foundation
import Testing
import SpectroCore

struct SmoothingKernelTests {

    @Test func testMenuEntriesAreTheirKernelsBitForBit() {
        var m = [Double](repeating: 0, count: 13 * 11)
        var state: UInt64 = 20261015
        for i in m.indices { state = state &* 6364136223846793005 &+ 1442695040888963407; m[i] = Double(state >> 40) / 1000 - 8000 }
        for entry in MapSmoothing.allCases {
            guard let k = entry.smoothingKernel else { #expect(entry == .none); continue }
            let a = entry.apply(m, width: 13, height: 11), b = MapSmoothing.apply(m, width: 13, height: 11, kernel: k)
            #expect(a.map(\.bitPattern) == b.map(\.bitPattern), "\(entry)")
            #expect(entry.kernel == k.taps)
        }
        #expect(MapSmoothing.box3.smoothingKernel == .box(width: 3) && MapSmoothing.gaussian2.smoothingKernel == .gaussian(sigma: 2, truncation: 2))
        #expect(SmoothingKernel.gaussian(sigma: 1) == .gaussian(sigma: 1, truncation: 2))
        #expect(MapSmoothing.gaussian1.kernel.count == 5 && MapSmoothing.gaussian2.kernel.count == 9)
    }

    @Test func testABoxOfSevenSpreadsAnImpulseOverSevenBySeven() {
        var m = [Double](repeating: 0, count: 15 * 15)
        m[7 * 15 + 7] = 49
        let s = MapSmoothing.apply(m, width: 15, height: 15, kernel: .box(width: 7))
        for y in 0..<15 { for x in 0..<15 {
            let inside = (4...10).contains(x) && (4...10).contains(y)
            #expect(abs(s[y * 15 + x] - (inside ? 1 : 0)) < 1e-12, "(\(x), \(y))")
        } }
        #expect(abs(s.reduce(0, +) - 49) < 1e-9)
    }

    @Test func testAWiderGaussianTruncationKeepsMoreTapsAndTheTotal() {
        let k = SmoothingKernel.gaussian(sigma: 1.5, truncation: 3)
        #expect(k.taps.count == 11)                                  // 2 * ceil(4.5) + 1
        #expect(SmoothingKernel.gaussian(sigma: 1.5).taps.count == 7) // 2 * ceil(3) + 1
        #expect(k.taps == k.taps.reversed())
        var m = [Double](repeating: 0, count: 31 * 31)
        m[15 * 31 + 15] = 5; m[15 * 31 + 16] = -2
        let s = MapSmoothing.apply(m, width: 31, height: 31, kernel: k)
        #expect(abs(s.reduce(0, +) - 3) < 1e-12)
        // Five pixels from the impulse: inside the truncation of 3 sigma (5 taps out), outside the default 2 sigma (3 taps out).
        let narrow = MapSmoothing.apply(m, width: 31, height: 31, kernel: .gaussian(sigma: 1.5))
        #expect(s[15 * 31 + 20] != 0 && narrow[15 * 31 + 20] == 0)
    }

    @Test func testInvalidKernelsLeaveTheMapAloneAndKernelsRoundTrip() throws {
        let m = [1.0, 2, 3, 4, 5, 6, 7, 8, 9]
        for bad in [SmoothingKernel.box(width: 4), .box(width: 0), .gaussian(sigma: 0), .gaussian(sigma: 1, truncation: 0), .gaussian(sigma: .nan)] {
            #expect(!bad.isValid && bad.taps.isEmpty)
            #expect(MapSmoothing.apply(m, width: 3, height: 3, kernel: bad) == m)
        }
        for k in [SmoothingKernel.box(width: 7), .gaussian(sigma: 1.5, truncation: 3), .gaussian(sigma: 1)] {
            #expect(try JSONDecoder().decode(SmoothingKernel.self, from: JSONEncoder().encode(k)) == k)
        }
    }
}
