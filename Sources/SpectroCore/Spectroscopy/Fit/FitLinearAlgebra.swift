//
//  FitLinearAlgebra.swift
//  Role: The few dense linear-algebra operations the spectrum fit needs, on Accelerate's
//        LAPACK (column-major, double precision): a minimum-norm least-squares solve that
//        tolerates rank deficiency (`dgelsy_`), and the covariance of a linear estimator
//        through a QR factorisation (`dgeqrf_`, `dorgqr_`, `dtrtri_`), so no normal
//        equations are ever formed (a 6th-order polynomial beside Gaussian lines is
//        ill-conditioned enough squared).
//
//  The routines are reached through `CSpectroLAPACK`, plain-C wrappers over Accelerate's
//  non-deprecated `__LAPACK_int` interface (SpectroKit S3): the wrappers take values and
//  return `info`, and this file imports no Accelerate, so no `-DACCELERATE_NEW_LAPACK` flag.
//

internal import CSpectroLAPACK
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
        var jpvt = [Int32](repeating: 0, count: n)
        let mm = Int32(m), nn = Int32(n), nr = Int32(nrhs)
        let lda = Int32(m), ldbb = Int32(ldb)
        var rank = Int32(0)
        var query = [Double](repeating: 0, count: 1)
        var info = sk_dgelsy(mm, nn, nr, &aBuf, lda, &bBuf, ldbb, &jpvt, rcond, &rank, &query, -1)
        guard info == 0, query[0].isFinite, query[0] >= 1 else { return nil }
        let lwork = Int32(query[0])
        var work = [Double](repeating: 0, count: Int(lwork))
        info = sk_dgelsy(mm, nn, nr, &aBuf, lda, &bBuf, ldbb, &jpvt, rcond, &rank, &work, lwork)
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
        let mm = Int32(m), nn = Int32(n), lda = Int32(m)
        var tau = [Double](repeating: 0, count: n)
        var query = [Double](repeating: 0, count: 1)
        var info = sk_dgeqrf(mm, nn, &buf, lda, &tau, &query, -1)
        guard info == 0 else { return nil }
        var lwork = max(Int32(query[0]), Int32(n))
        var work = [Double](repeating: 0, count: Int(lwork))
        info = sk_dgeqrf(mm, nn, &buf, lda, &tau, &work, lwork)
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
        info = sk_dorgqr(mm, nn, nn, &q, lda, &tau, &query, -1)
        guard info == 0 else { return nil }
        lwork = max(Int32(query[0]), Int32(n))
        work = [Double](repeating: 0, count: Int(lwork))
        info = sk_dorgqr(mm, nn, nn, &q, lda, &tau, &work, lwork)
        guard info == 0 else { return nil }
        // R^-1 in place.
        info = sk_dtrtri(CChar(UInt8(ascii: "U")), CChar(UInt8(ascii: "N")), nn, &r, Int32(n))
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
