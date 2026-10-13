import XCTest
@testable import DSTEMCore

/// `MapSmoothing`: count conservation, identity for none and for a flat map, a symmetric spread, no loss at the border.
final class MapSmoothingTests: XCTestCase {
    func testNoneIsIdentityAndAShapeMismatchIsLeftAlone() {
        let m = [1.0, 2, 3, 4, 5, 6]
        XCTAssertEqual(MapSmoothing.none.apply(m, width: 3, height: 2), m)
        XCTAssertEqual(MapSmoothing.box3.apply(m, width: 4, height: 2), m, "a shape mismatch returns the input")
    }

    func testEveryKernelConservesTheTotalOfAnInteriorFeatureIncludingNegatives() {
        var m = [Double](repeating: 0, count: 21 * 21)
        m[10 * 21 + 10] = 9; m[10 * 21 + 11] = -3; m[11 * 21 + 10] = 2.5   // ≥ 2 radii (8 px) from every edge: every receiver's window is inside
        for k in MapSmoothing.allCases {
            let s = k.apply(m, width: 21, height: 21)
            XCTAssertEqual(s.reduce(0, +), m.reduce(0, +), accuracy: 1e-9, "\(k) must conserve the total away from the border")
            XCTAssertEqual(s.count, m.count)
        }
    }

    func testTheBorderKeepsTheMeanNotADarkRim() {
        var m = [Double](repeating: 2, count: 8 * 8)
        m[0] = 10                                        // a corner feature
        let s = MapSmoothing.box3.apply(m, width: 8, height: 8)
        XCTAssertEqual(s[0], (10 + 2 + 2 + 2) / 4, accuracy: 1e-12, "a corner averages its four in-bounds taps")
        XCTAssertEqual(s[63], 2, accuracy: 1e-12, "a flat corner stays at its value")
    }

    func testAFlatMapStaysFlat() {
        let m = [Double](repeating: 4, count: 6 * 6)
        for k in MapSmoothing.allCases {
            let s = k.apply(m, width: 6, height: 6)
            XCTAssert(s.allSatisfy { abs($0 - 4) < 1e-9 }, "\(k): a flat map is its own smoothing (renormalised border)")
        }
    }

    func testBox3SpreadsAnInteriorDeltaEvenly() {
        var m = [Double](repeating: 0, count: 5 * 5)
        m[12] = 9
        let s = MapSmoothing.box3.apply(m, width: 5, height: 5)
        for y in 1...3 { for x in 1...3 { XCTAssertEqual(s[y * 5 + x], 1, accuracy: 1e-12) } }
        XCTAssertEqual(s[0], 0); XCTAssertEqual(s[4], 0)
    }

    func testGaussianIsSymmetricAndPeakedAtTheSource() {
        var m = [Double](repeating: 0, count: 9 * 9)
        m[40] = 1
        let s = MapSmoothing.gaussian1.apply(m, width: 9, height: 9)
        XCTAssertEqual(s[40 - 1], s[40 + 1], accuracy: 1e-12)
        XCTAssertEqual(s[40 - 9], s[40 + 9], accuracy: 1e-12)
        XCTAssertGreaterThan(s[40], s[41])
        XCTAssertGreaterThan(s[41], s[42])
    }

    func testLabelsNameTheKernelAndNoneIsSilent() {
        XCTAssertEqual(MapSmoothing.none.label, "")
        XCTAssertEqual(MapSmoothing.box3.label, "3 \u{00D7} 3")
        XCTAssertEqual(MapSmoothing.gaussian2.fileTag, "s2px")
        XCTAssertEqual(MapSmoothing.gaussian1.kernel.count, 5)
    }
}
