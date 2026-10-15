import Foundation
import Testing
@testable import SpectroCore

/// `MapSmoothing`: count conservation, identity for none and for a flat map, a symmetric spread, no loss at the border.
struct MapSmoothingTests {
    @Test func testNoneIsIdentityAndAShapeMismatchIsLeftAlone() {
        let m = [1.0, 2, 3, 4, 5, 6]
        #expect(MapSmoothing.none.apply(m, width: 3, height: 2) == m)
        #expect(MapSmoothing.box3.apply(m, width: 4, height: 2) == m, "a shape mismatch returns the input")
    }

    @Test func testEveryKernelConservesTheTotalOfAnInteriorFeatureIncludingNegatives() {
        var m = [Double](repeating: 0, count: 21 * 21)
        m[10 * 21 + 10] = 9; m[10 * 21 + 11] = -3; m[11 * 21 + 10] = 2.5   // ≥ 2 radii (8 px) from every edge: every receiver's window is inside
        for k in MapSmoothing.allCases {
            let s = k.apply(m, width: 21, height: 21)
            #expect(isEqual(s.reduce(0, +), m.reduce(0, +), accuracy: 1e-9), "\(k) must conserve the total away from the border")
            #expect(s.count == m.count)
        }
    }

    @Test func testTheBorderKeepsTheMeanNotADarkRim() {
        var m = [Double](repeating: 2, count: 8 * 8)
        m[0] = 10                                        // a corner feature
        let s = MapSmoothing.box3.apply(m, width: 8, height: 8)
        #expect(isEqual(s[0], (10 + 2 + 2 + 2) / 4, accuracy: 1e-12), "a corner averages its four in-bounds taps")
        #expect(isEqual(s[63], 2, accuracy: 1e-12), "a flat corner stays at its value")
    }

    @Test func testAFlatMapStaysFlat() {
        let m = [Double](repeating: 4, count: 6 * 6)
        for k in MapSmoothing.allCases {
            let s = k.apply(m, width: 6, height: 6)
            #expect(s.allSatisfy { abs($0 - 4) < 1e-9 }, "\(k): a flat map is its own smoothing (renormalised border)")
        }
    }

    @Test func testBox3SpreadsAnInteriorDeltaEvenly() {
        var m = [Double](repeating: 0, count: 5 * 5)
        m[12] = 9
        let s = MapSmoothing.box3.apply(m, width: 5, height: 5)
        for y in 1...3 { for x in 1...3 { #expect(isEqual(s[y * 5 + x], 1, accuracy: 1e-12)) } }
        #expect(s[0] == 0); #expect(s[4] == 0)
    }

    @Test func testGaussianIsSymmetricAndPeakedAtTheSource() {
        var m = [Double](repeating: 0, count: 9 * 9)
        m[40] = 1
        let s = MapSmoothing.gaussian1.apply(m, width: 9, height: 9)
        #expect(isEqual(s[40 - 1], s[40 + 1], accuracy: 1e-12))
        #expect(isEqual(s[40 - 9], s[40 + 9], accuracy: 1e-12))
        #expect(s[40] > s[41])
        #expect(s[41] > s[42])
    }

    @Test func testLabelsNameTheKernelAndNoneIsSilent() {
        #expect(MapSmoothing.none.label == "")
        #expect(MapSmoothing.box3.label == "3 \u{00D7} 3")
        #expect(MapSmoothing.gaussian2.fileTag == "s2px")
        #expect(MapSmoothing.gaussian1.kernel.count == 5)
    }
}
