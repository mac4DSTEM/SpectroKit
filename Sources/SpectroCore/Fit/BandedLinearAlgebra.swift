//
//  BandedLinearAlgebra.swift
//  Role: A general banded linear solve on Accelerate's LAPACK `dgbsv_` (LU with partial pivoting), the routine SciPy 1.18.1's
//        `make_interp_spline` calls for its collocation system (`interpolate/_bsplines.py:1898-1909`). For SpectroEELS's
//        interpolating spline (EELS slice 2); SpectroEDX does not use it.
//

internal import CSpectroLAPACK
import Foundation

package nonisolated enum BandedLinearAlgebra {

    /// Solves `A x = b` for an `n x n` matrix with `kl` sub- and `ku` super-diagonals.
    ///
    /// - Parameters:
    ///   - ab: LAPACK band storage, column-major, `ldab = 2 kl + ku + 1` rows per column: `A[i][j]` (0-based) at
    ///     `ab[j * ldab + kl + ku + i - j]`; the first `kl` rows are workspace for the fill-in.
    ///   - b: the right-hand side, length `n` (one column).
    /// - Returns: x, or nil when LAPACK reports a singular matrix or an illegal argument (`info != 0`).
    package static func solve(n: Int, kl: Int, ku: Int, ab: [Double], b: [Double]) -> [Double]? {
        let ldab = 2 * kl + ku + 1
        guard n > 0, kl >= 0, ku >= 0, ab.count == ldab * n, b.count == n,
              let n32 = Int32(exactly: n), let kl32 = Int32(exactly: kl), let ku32 = Int32(exactly: ku),
              let ld32 = Int32(exactly: ldab) else { return nil }
        var a = ab, x = b
        var ipiv = [Int32](repeating: 0, count: n)
        let info = sk_dgbsv(n32, kl32, ku32, 1, &a, ld32, &ipiv, &x, n32)
        return info == 0 ? x : nil
    }
}
