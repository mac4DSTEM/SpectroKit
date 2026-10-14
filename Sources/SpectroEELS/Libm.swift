//
//  Libm.swift
//  Role: The C library's `pow` and `powf`, called as Python and NumPy call them. A Python float's `**`, a NumPy scalar's `**` and
//        NumPy's `power` with a non-special exponent all call libm, whose `pow(x, 2)` and `powf(x, 2)` are not always the
//        correctly rounded x*x on this platform (measured 2026-10-14: 0.13 % of doubles and 0.4 % of floats differ). Swift's
//        optimiser rewrites `pow(x, 2)` as `x * x`, so a literal exponent would not give exSpy's number. These wrappers are
//        compiled without optimisation and never inlined, so the call reaches libm. (NumPy arrays and 0-d arrays square by
//        x * x instead: those places write `x * x`.)
//

import Foundation

package nonisolated enum Libm {
    @_optimize(none) @inline(never)
    package static func pow(_ x: Double, _ y: Double) -> Double { Foundation.pow(x, y) }

    @_optimize(none) @inline(never)
    package static func powf(_ x: Float, _ y: Float) -> Float { Foundation.powf(x, y) }
}
