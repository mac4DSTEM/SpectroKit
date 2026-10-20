//
//  AxisRulesTests.swift
//  Role: The HyperSpy 2.4.0 rules the thickness map stands on, and NumPy's pairwise sum, each pinned by a case that fails if the
//        rule changes: value2index's rounding (README "value -> channel"), value_range_to_indices (axes.py:648-691), the stop of
//        isig[:threshold] (axes.py:401-471), and the sums I_0 and I_t (numpy 2.5.4).
//

import Foundation
import Testing
import SpectroEELS

struct AxisRulesTests {

    private func planted() throws -> EELSAxis { try EELSAxis(offset: -10, scale: 0.05, size: 3400) }
    private func lineScan() throws -> EELSAxis { try EELSAxis(offset: -100, scale: 0.5, size: 1024) }

    // MARK: value2index (through the fixed threshold's stop)

    /// A value exactly half-way between two channels goes DOWN for a non-negative energy (round half towards zero) and UP for a
    /// negative one (half away from zero); nothing here is round-half-up or half-even. Scale 0.5 makes the halves exact.
    @Test func testHalfWayEnergiesRoundTowardsZeroForNonNegativeAndAwayForNegative() throws {
        let axis = try lineScan()
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.75)) == 209)     // q = 209.5
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.76)) == 210)
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.74)) == 209)
        #expect((try axis.zeroLossStop(forFixedThreshold: 0.25)) == 200)     // q = 200.5
        #expect((try axis.zeroLossStop(forFixedThreshold: -4.75)) == 191)    // q = 190.5, value < 0: up
        #expect((try axis.zeroLossStop(forFixedThreshold: -4.74)) == 191)
        #expect((try axis.zeroLossStop(forFixedThreshold: -4.76)) == 190)
        #expect((try axis.zeroLossStop(forFixedThreshold: 0)) == 200)        // value >= 0 includes zero
    }

    /// The index is truncated at 1e-12 channels first, so a value 1e-13 channels above a half-way point still counts as exactly
    /// half-way (and goes down); plain rounding would give 210.
    @Test func testTruncationAtTwelveDecimalsMakesNearlyHalfWayAnExactHalf() throws {
        let axis = try lineScan()
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.75 + 5e-14)) == 209)
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.75 + 5e-12)) == 210)    // 1e-11 channels above: a real 210
    }

    /// README finding 6: 4.52 eV and 4.5 eV are the same channel (290) on the planted axis; a floor or truncation would differ.
    @Test func testAThresholdOffTheChannelCentreIsRoundedNotFloored() throws {
        let axis = try planted()
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.5)) == 290)
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.52)) == 290)
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.48)) == 290)
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.53)) == 291)
        #expect((try axis.zeroLossStop(forFixedThreshold: 4.47)) == 289)
        #expect([2.5, 4.5, 6.0].map { try? axis.zeroLossStop(forFixedThreshold: $0) } == [250, 290, 320])
    }

    /// Above the last energy the slice runs to the end (I_0 = I_t); below the first it is an IndexError; NaN is refused.
    @Test func testFixedThresholdBeyondTheAxis() throws {
        let axis = try planted()
        #expect((try axis.zeroLossStop(forFixedThreshold: 159.95)) == 3399)      // exactly the last energy: stop = size - 1
        #expect((try axis.zeroLossStop(forFixedThreshold: 159.97)) == 3399)      // within half a channel: rounds to the last channel
        #expect((try axis.zeroLossStop(forFixedThreshold: 160.0)) == 3400)       // a channel beyond: value2index raises, the slice runs to the end
        #expect((try axis.zeroLossStop(forFixedThreshold: 1e6)) == 3400)
        #expect((try axis.zeroLossStop(forFixedThreshold: -10.0)) == 0)
        #expect((try axis.zeroLossStop(forFixedThreshold: -10.02)) == 0)         // rounds to channel 0: in range
        if let error = #expect(throws: (any Error).self, performing: { try axis.zeroLossStop(forFixedThreshold: -10.2) }) { #expect((error as? EELSThicknessError) == .invalidFixedThreshold(-10.2)) }
        #expect(throws: (any Error).self) { try axis.zeroLossStop(forFixedThreshold: .nan) }
    }

    // MARK: value_range_to_indices

    @Test func testValueRangeToIndicesFollowsHyperSpysFourConditions() throws {
        let axis = try planted()                    // low -10, high 159.95, size 3400
        func range(_ a: Double, _ b: Double) throws -> [Int] { let r = try axis.valueRangeToIndices(a, b); return [r.first, r.last] }
        #expect((try range(1, 11)) == [220, 420])                    // the defaults
        #expect((try range(-10, 11)) == [0, 420])                    // v1 == low: `low < v1` is false: 0
        #expect((try range(-20, 11)) == [0, 420])
        #expect((try range(170, 180)) == [0, 3399])                  // v1 above the axis: 0 (!); v2 above: size - 1
        #expect((try range(1, axis.highValue)) == [220, 3399])       // v2 == high: `high > v2` is false: size - 1
        #expect((try range(1, 159.9)) == [220, 3398])
        #expect((try range(axis.highValue, 170)) == [3399, 3399])    // v1 == high is allowed (`<= high`): channel 3399, not 0
        #expect((try range(axis.lowValue, 11)) == [0, 420])
        #expect((try range(-30, -20)) == [0, 3399])                  // v2 below low: size - 1 (!)
        #expect((try range(-20, -10)) == [0, 0])                     // v2 == low is allowed (`>= low`): channel 0, not size - 1
        #expect((try range(2, 2)) == [240, 240])
        #expect(throws: (any Error).self) { try axis.valueRangeToIndices(5, 4) }
        #expect(throws: (any Error).self) { try axis.valueRangeToIndices(.nan, 4) }
    }

    // MARK: I_0 and I_t sums

    /// NumPy's pairwise sum, asserted bit for bit today (D12 allows a tolerance; the summation order is the point), on arrays where it differs from a left-to-right sum (expected values from NumPy 2.5.4:
    /// `np.array([((i * 7919) % 10007) / 7.0 for i in range(n)]).sum()`).
    @Test func testPairwiseSumEqualsNumpysSum() {
        let expected: [(Int, Double)] = [
            (3, 1964.2857142857142), (7, 5172.571428571428), (8, 5943.714285714285), (9, 6416.571428571428),
            (100, 71711.57142857143), (127, 90863.28571428571), (128, 91579.42857142858), (129, 91997.28571428571),
            (250, 178190.42857142858), (1000, 715294.4285714286), (3400, 2431594.5714285714),
        ]
        var naiveDiffers = 0
        for (n, want) in expected {
            let x = (0..<n).map { Double(($0 * 7919) % 10007) / 7.0 }
            #expect(NumpySum.sum(x).bitPattern == want.bitPattern, "n = \(n)")
            var naive = 0.0
            for v in x { naive += v }
            if naive != want { naiveDiffers += 1 }
        }
        #expect(naiveDiffers >= 4, "the arrays must distinguish pairwise from naive summation")
        #expect(NumpySum.sum([]) == 0)
    }

    /// I_t is the sum of every channel and I_0 the sum of channels [0, stop): the channel AT the threshold is not in I_0.
    @Test func testZeroLossSumStopsBeforeTheThresholdChannel() throws {
        let counts = (0..<40).map { Double($0 + 1) }                          // 1, 2, ..., 40
        let image = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 40, counts: counts, energyOffsetEV: -10, energyScaleEV: 0.5)
        let map = try EELSThickness.logRatio(image, threshold: .fixed(0.0))   // channel 20: I_0 = 1 + ... + 20
        #expect(map.pixels[0].thresholdChannel == 20)
        #expect(map.pixels[0].i0 == 210)
        #expect(map.pixels[0].iTotal == 820)
        #expect(isEqual(map.pixels[0].tOverLambda.orFail(), log(820.0 / 210.0), accuracy: 1e-15))
    }
}
