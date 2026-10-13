//
//  FitLinearAlgebra.swift
//  Role: The few dense linear-algebra operations the spectrum fit needs, on Accelerate's
//        LAPACK (column-major, double precision): a minimum-norm least-squares solve that
//        tolerates rank deficiency (`dgelsy_`), and the covariance of a linear estimator
//        through a QR factorisation (`dgeqrf_`, `dorgqr_`, `dtrtri_`), so no normal
//        equations are ever formed (a 6th-order polynomial beside Gaussian lines is
//        ill-conditioned enough squared).
//
//  The non-deprecated `__LAPACK_int` declarations are behind -DACCELERATE_NEW_LAPACK
//  (Package.swift and the Xcode project's OTHER_SWIFT_FLAGS), as in DiffractionEmbedding.
//

import Accelerate
import Foundation

/// A dense column-major matrix of doubles.
package nonisolated struct ColumnMatrix: Sendable, Equatable {
    package let rows: Int
    package let cols: Int
    package var data: [Double]

    package init(rows: Int, cols: Int, data: [Double]? = nil) {
        precondition(rows >= 0 && cols >= 0)
        self.rows = rows; self.cols = cols
        self.data = data ?? [Double](repeating: 0, count: rows * cols)
        precondition(self.data.count == rows * cols)
    }

    package init(columns: [[Double]]) {
        let m = columns.first?.count ?? 0
        precondition(columns.allSatisfy { $0.count == m })
        self.init(rows: m, cols: columns.count, data: columns.flatMap { $0 })
    }

    package func column(_ j: Int) -> ArraySlice<Double> { data[(j * rows)..<((j + 1) * rows)] }

    package subscript(i: Int, j: Int) -> Double {
        get { data[j * rows + i] }
        set { data[j * rows + i] = newValue }
    }

    /// The columns `js` as a new matrix.
    package func selecting(_ js: [Int]) -> ColumnMatrix {
        var out = [Double](); out.reserveCapacity(rows * js.count)
        for j in js { out.append(contentsOf: column(j)) }
        return ColumnMatrix(rows: rows, cols: js.count, data: out)
    }

    /// Row `i` multiplied by `s[i]`.
    package func scalingRows(_ s: [Double]) -> ColumnMatrix {
        precondition(s.count == rows)
        var out = data
        for j in 0..<cols { for i in 0..<rows { out[j * rows + i] *= s[i] } }
        return ColumnMatrix(rows: rows, cols: cols, data: out)
    }

    package func times(_ x: [Double]) -> [Double] {
        precondition(x.count == cols)
        var y = [Double](repeating: 0, count: rows)
        for j in 0..<cols where x[j] != 0 {
            let xj = x[j]
            for i in 0..<rows { y[i] += data[j * rows + i] * xj }
        }
        return y
    }

    package func transposeTimes(_ v: [Double]) -> [Double] {
        precondition(v.count == rows)
        return (0..<cols).map { j in
            var s = 0.0
            for i in 0..<rows { s += data[j * rows + i] * v[i] }
            return s
        }
    }
}

package nonisolated enum FitLinearAlgebra {

    /// Minimum-norm least squares `min || A X - B ||` for `A` (m x n) and `B` (m x nrhs), through
    /// LAPACK `dgelsy_` (complete orthogonal factorisation with column pivoting). `rcond` decides the
    /// numerical rank. Returns X (n x nrhs) and the rank, nil when LAPACK reports failure.
    package static func leastSquares(_ a: ColumnMatrix, _ b: ColumnMatrix, rcond: Double = 1e-12)
        -> (x: ColumnMatrix, rank: Int)? {
        precondition(a.rows == b.rows)
        let m = a.rows, n = a.cols, nrhs = b.cols
        if n == 0 { return (ColumnMatrix(rows: 0, cols: nrhs), 0) }
        if m == 0 { return (ColumnMatrix(rows: n, cols: nrhs), 0) }
        var aBuf = a.data
        let ldb = max(m, n)
        var bBuf = [Double](repeating: 0, count: ldb * nrhs)
        for c in 0..<nrhs { for i in 0..<m { bBuf[c * ldb + i] = b.data[c * m + i] } }
        var jpvt = [__LAPACK_int](repeating: 0, count: n)
        var mm = __LAPACK_int(m), nn = __LAPACK_int(n), nr = __LAPACK_int(nrhs)
        var lda = __LAPACK_int(m), ldbb = __LAPACK_int(ldb)
        var rc = rcond
        var rank = __LAPACK_int(0)
        var info = __LAPACK_int(0)
        var lwork = __LAPACK_int(-1)
        var query = [Double](repeating: 0, count: 1)
        dgelsy_(&mm, &nn, &nr, &aBuf, &lda, &bBuf, &ldbb, &jpvt, &rc, &rank, &query, &lwork, &info)
        guard info == 0, query[0].isFinite, query[0] >= 1 else { return nil }
        lwork = __LAPACK_int(query[0])
        var work = [Double](repeating: 0, count: Int(lwork))
        dgelsy_(&mm, &nn, &nr, &aBuf, &lda, &bBuf, &ldbb, &jpvt, &rc, &rank, &work, &lwork, &info)
        guard info == 0 else { return nil }
        var x = [Double](repeating: 0, count: n * nrhs)
        for c in 0..<nrhs { for i in 0..<n { x[c * n + i] = bBuf[c * ldb + i] } }
        return (ColumnMatrix(rows: n, cols: nrhs, data: x), Int(rank))
    }

    /// `(A^T A)^-1` for a full-column-rank `A` (m x k, m >= k), as `R^-1 R^-T` from the QR factorisation
    /// `A = Q R` (never forming `A^T A`), plus `K = (A^T A)^-1 A^T` = `R^-1 Q^T` (k x m, column-major),
    /// which the sandwich covariance needs. nil when `A` is numerically rank deficient
    /// (smallest |R_ii| below 1e-10 of the largest) or LAPACK fails.
    package static func pseudoInverse(_ a: ColumnMatrix) -> (gramInverse: ColumnMatrix, k: ColumnMatrix)? {
        let m = a.rows, n = a.cols
        guard n > 0, m >= n else { return nil }
        var buf = a.data
        var mm = __LAPACK_int(m), nn = __LAPACK_int(n), lda = __LAPACK_int(m)
        var info = __LAPACK_int(0)
        var tau = [Double](repeating: 0, count: n)
        var lwork = __LAPACK_int(-1)
        var query = [Double](repeating: 0, count: 1)
        dgeqrf_(&mm, &nn, &buf, &lda, &tau, &query, &lwork, &info)
        guard info == 0 else { return nil }
        lwork = max(__LAPACK_int(query[0]), __LAPACK_int(n))
        var work = [Double](repeating: 0, count: Int(lwork))
        dgeqrf_(&mm, &nn, &buf, &lda, &tau, &work, &lwork, &info)
        guard info == 0 else { return nil }
        // R (upper triangle of the n x n block) and its conditioning.
        var r = [Double](repeating: 0, count: n * n)
        var dmin = Double.infinity, dmax = 0.0
        for j in 0..<n {
            for i in 0...j { r[j * n + i] = buf[j * m + i] }
            let d = abs(r[j * n + j]); dmin = min(dmin, d); dmax = max(dmax, d)
        }
        guard dmax > 0, dmin / dmax > 1e-10 else { return nil }
        // Q (m x n explicit) from the reflectors.
        var q = buf
        lwork = -1
        dorgqr_(&mm, &nn, &nn, &q, &lda, &tau, &query, &lwork, &info)
        guard info == 0 else { return nil }
        lwork = max(__LAPACK_int(query[0]), __LAPACK_int(n))
        work = [Double](repeating: 0, count: Int(lwork))
        dorgqr_(&mm, &nn, &nn, &q, &lda, &tau, &work, &lwork, &info)
        guard info == 0 else { return nil }
        // R^-1 in place.
        var uplo = Int8(UInt8(ascii: "U")), diag = Int8(UInt8(ascii: "N"))
        var ldr = __LAPACK_int(n)
        dtrtri_(&uplo, &diag, &nn, &r, &ldr, &info)
        guard info == 0 else { return nil }
        // gram^-1 = R^-1 R^-T (upper-triangular R^-1).
        var gi = [Double](repeating: 0, count: n * n)
        for i in 0..<n { for j in 0..<n {
            var s = 0.0
            for t in max(i, j)..<n { s += r[t * n + i] * r[t * n + j] }
            gi[j * n + i] = s
        } }
        // K = R^-1 Q^T  (n x m).
        var k = [Double](repeating: 0, count: n * m)
        for i in 0..<m { for a_ in 0..<n {
            var s = 0.0
            for t in a_..<n { s += r[t * n + a_] * q[t * m + i] }
            k[i * n + a_] = s
        } }
        return (ColumnMatrix(rows: n, cols: n, data: gi), ColumnMatrix(rows: n, cols: m, data: k))
    }
}
