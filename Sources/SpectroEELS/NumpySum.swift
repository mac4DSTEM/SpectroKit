//
//  NumpySum.swift
//  Role: NumPy's pairwise summation of a contiguous float64 vector, so that I_0 and I_t are the numbers exSpy's
//        `data[:ind].sum()` and `integrate1D` give (HyperSpy `signal.py:5092-5132` sums a binned axis with `.sum`), to the
//        last bit, and not a naive left-to-right sum whose rounding differs.
//
//  Ported from NumPy 2.5.4 `numpy/_core/src/umath/loops_utils.h.src`, `@TYPE@_pairwise_sum` (C source, not shipped in the wheel:
//  transcribed from the source and checked against the sums NumPy returns, AxisRulesTests.testPairwiseSumEqualsNumpysSum, and
//  against exSpy's I_0 and I_t, bit for bit, ThicknessPinsTests): fewer than 8 elements a
//  plain loop; up to 128 (PW_BLOCKSIZE) eight running partial sums combined as ((r0+r1)+(r2+r3))+((r4+r5)+(r6+r7)) and
//  the rest added in order; above 128 the vector splits at n/2 rounded down to a multiple of 8 and the halves are summed
//  recursively. `np.add.reduce` over the contiguous last axis starts from 0 and adds this value once.
//

import Foundation

package nonisolated enum NumpySum {
    package static let blockSize = 128

    package static func pairwise(_ a: UnsafePointer<Double>, count n: Int) -> Double {
        if n < 8 {
            var res = 0.0
            for i in 0..<n { res += a[i] }
            return res
        } else if n <= blockSize {
            var r0 = a[0], r1 = a[1], r2 = a[2], r3 = a[3], r4 = a[4], r5 = a[5], r6 = a[6], r7 = a[7]
            var i = 8
            let blockEnd = n - (n % 8)
            while i < blockEnd {
                r0 += a[i]; r1 += a[i + 1]; r2 += a[i + 2]; r3 += a[i + 3]
                r4 += a[i + 4]; r5 += a[i + 5]; r6 += a[i + 6]; r7 += a[i + 7]
                i += 8
            }
            var res = ((r0 + r1) + (r2 + r3)) + ((r4 + r5) + (r6 + r7))
            while i < n { res += a[i]; i += 1 }
            return res
        } else {
            var n2 = n / 2
            n2 -= n2 % 8
            return pairwise(a, count: n2) + pairwise(a + n2, count: n - n2)
        }
    }

    package static func sum(_ a: [Double]) -> Double {
        a.withUnsafeBufferPointer { b in b.baseAddress.map { pairwise($0, count: b.count) } ?? 0 }
    }
}
