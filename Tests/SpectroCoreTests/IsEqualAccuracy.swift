//
//  IsEqualAccuracy.swift
//  Role: XCTest's `XCTAssertEqual(_:_:accuracy:)` rule, for `#expect(isEqual(a, b, accuracy: c))` after the Swift Testing
//        migration (0.4.0): equal values pass first (so two equal infinities pass), then |a - b| <= |accuracy|; a NaN on either
//        side fails. One copy per test target (a test target cannot share another's sources).
//

func isEqual<T: FloatingPoint>(_ a: T, _ b: T, accuracy: T) -> Bool {
    if a == b { return true }
    let difference = a.magnitude > b.magnitude ? a - b : b - a
    return difference.magnitude <= accuracy.magnitude
}
