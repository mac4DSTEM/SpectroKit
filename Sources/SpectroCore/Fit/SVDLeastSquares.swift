//
//  SVDLeastSquares.swift
//  Role: Minimum-norm least squares by LAPACK `dgelsd_` (the SVD, divide and conquer) - the driver `scipy.linalg.lstsq` uses by
//        default. `FitLinearAlgebra.leastSquares` (`dgelsy_`) is a different algorithm and differs from it at the 1e-15 level;
//        SpectroEELS' Savitzky-Golay derivative needs SciPy's bits, so it solves with this one. `dgelsy`'s behaviour, and so
//        SpectroEDX's numbers, is untouched.
//
//  The workspace is queried with `lwork = -1` and the optimal size used, as SciPy does; the query depends on the number of
//  right-hand sides, so a problem is created for the number it will be solved with.
//

internal import CSpectroLAPACK
import Foundation

/// One matrix `A` (m x n, column-major) to be solved against right-hand sides, with the workspace sizes fixed once.
package nonisolated struct SVDLeastSquaresProblem: Sendable {
    package let a: ColumnMatrix
    package let rcond: Double
    package let nrhs: Int
    private let lwork: Int
    private let liwork: Int

    /// nil when LAPACK's workspace query fails.
    package init?(_ a: ColumnMatrix, rhsCount nrhs: Int, rcond: Double) {
        precondition(a.rows > 0 && a.cols > 0 && nrhs > 0)
        self.a = a; self.rcond = rcond; self.nrhs = nrhs
        let m = a.rows, n = a.cols
        var aBuf = a.data
        let ldb = max(m, n)
        var bBuf = [Double](repeating: 0, count: ldb * nrhs)
        var s = [Double](repeating: 0, count: min(m, n))
        var rank = Int32(0)
        var query = [Double](repeating: 0, count: 1)
        var iq = [Int32](repeating: 0, count: 1)
        let info = sk_dgelsd(Int32(m), Int32(n), Int32(nrhs), &aBuf, Int32(m), &bBuf, Int32(ldb), &s, rcond, &rank, &query, -1, &iq)
        guard info == 0, query[0].isFinite, query[0] >= 1 else { return nil }
        self.lwork = Int(query[0])
        // LIWORK >= max(1, 3 * minmn * nlvl + 11 * minmn), nlvl = max(0, int(log2(minmn / (smlsiz + 1))) + 1), smlsiz = 25
        // (dgelsd's documentation). One level more than the formula, so that the bound never falls short.
        let minmn = min(m, n)
        let nlvl = max(0, Int(log2(Double(minmn) / 26.0)) + 1) + 1
        self.liwork = max(1, 3 * minmn * nlvl + 11 * minmn)
    }

    /// X (n x nrhs, column-major in an array) for B (m x nrhs, column-major), and the rank; nil when LAPACK fails.
    package func solve(_ b: [Double]) -> (x: [Double], rank: Int)? {
        let m = a.rows, n = a.cols
        precondition(b.count == m * nrhs)
        var aBuf = a.data
        let ldb = max(m, n)
        var bBuf = [Double](repeating: 0, count: ldb * nrhs)
        for c in 0..<nrhs { for i in 0..<m { bBuf[c * ldb + i] = b[c * m + i] } }
        var s = [Double](repeating: 0, count: min(m, n))
        var work = [Double](repeating: 0, count: lwork)
        var iwork = [Int32](repeating: 0, count: liwork)
        var rank = Int32(0)
        let info = sk_dgelsd(Int32(m), Int32(n), Int32(nrhs), &aBuf, Int32(m), &bBuf, Int32(ldb), &s, rcond, &rank,
                             &work, Int32(lwork), &iwork)
        guard info == 0 else { return nil }
        var x = [Double](repeating: 0, count: n * nrhs)
        for c in 0..<nrhs { for i in 0..<n { x[c * n + i] = bBuf[c * ldb + i] } }
        return (x, Int(rank))
    }
}

extension FitLinearAlgebra {
    /// Minimum-norm least squares `min || A X - B ||` through `dgelsd_` (the SVD; SciPy's default). Singular values at or
    /// below `rcond` times the largest are treated as zero. X is n x nrhs; nil when LAPACK reports failure.
    package static func leastSquaresSVD(_ a: ColumnMatrix, _ b: ColumnMatrix, rcond: Double)
        -> (x: ColumnMatrix, rank: Int)? {
        precondition(a.rows == b.rows)
        if a.cols == 0 { return (ColumnMatrix(rows: 0, cols: b.cols), 0) }
        if a.rows == 0 || b.cols == 0 { return (ColumnMatrix(rows: a.cols, cols: b.cols), 0) }
        guard let problem = SVDLeastSquaresProblem(a, rhsCount: b.cols, rcond: rcond),
              let solved = problem.solve(b.data) else { return nil }
        return (ColumnMatrix(rows: a.cols, cols: b.cols, data: solved.x), solved.rank)
    }
}
