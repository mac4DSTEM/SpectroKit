//
//  Libm.swift
//  Role: libm's `pow` / `powf` exactly as called, never rewritten by the optimiser (a literal `pow(x, 2)` is folded to `x * x`,
//        which differs from this Mac's libm in 0.13 % of doubles; Python floats and NumPy's non-special exponents call libm).
//

import Foundation

package nonisolated enum Libm {
    @_optimize(none) @inline(never) package static func pow(_ x: Double, _ y: Double) -> Double { Foundation.pow(x, y) }
    @_optimize(none) @inline(never) package static func powf(_ x: Float, _ y: Float) -> Float { Foundation.powf(x, y) }
}
