//
//  CheckedConversion.swift
//  SpectroCore
//
//  The conversions from a Double that trap on NaN, infinity or a value out of range (`Int(_:)`), made total, and the JSON encoder
//  that cannot throw on a non-finite Double. A NaN from a caller's or a file's number is refused or skipped by the caller in words,
//  never a crash (macEMSuite/SpectroKit#103).
//

import Foundation

package nonisolated enum CheckedConversion {
    /// `Int(value)` (truncation toward zero) when `value` is finite and fits an Int; nil otherwise.
    @inline(__always)
    package static func int(_ value: Double) -> Int? {
        value.isFinite ? Int(exactly: value.rounded(.towardZero)) : nil
    }

    /// `value` clamped to ±`limit`, NaN as 0: a coordinate that must become an Int and may be any number.
    @inline(__always)
    package static func clamped(_ value: Double, to limit: Double = 1e15) -> Double {
        value.isNaN ? 0 : min(max(value, -limit), limit)
    }

    /// A sorted-key JSON encoder whose non-finite Doubles are the strings "nan", "inf" and "-inf" (JSONEncoder throws on them
    /// otherwise): a method or policy holding a NaN still has a canonical form, so its hash and footer never trap.
    package static func canonicalEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }
}
