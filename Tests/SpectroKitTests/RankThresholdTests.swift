//
//  RankThresholdTests.swift
//  Role: The rank threshold of SpectroCore's least squares (`FitLinearAlgebra.leastSquares`, LAPACK `dgelsy_` with
//        rcond = 1e-12). S3 found that no fixture's design is near rank-deficient, so rcond x1e9 (1e-12 -> 1e-3) stayed green.
//        Two three-row designs with columns 1 and 1 + (0, δ, −δ) have a condition number of about 3/δ: δ = 1e-6 (about 3e6)
//        is full rank under 1e-12 but not under 1e-3; δ = 1e-14 (about 3e14) is rank 1 under 1e-12 but rank 2 under 1e-20.
//

import Foundation
import Testing
import SpectroCore

struct RankThresholdTests {

    func design(_ delta: Double) -> ColumnMatrix {
        ColumnMatrix(columns: [[1, 1, 1], [1, 1 + delta, 1 - delta]])
    }

    @Test func testWellConditionedDesignIsFullRankAndExact() throws {
        let a = design(1e-6)
        // b = A (2, 3): an exact system, recovered at full rank.
        let b = ColumnMatrix(columns: [a.times([2, 3])])
        let r = try #require(FitLinearAlgebra.leastSquares(a, b))
        #expect(r.rank == 2)
        #expect(isEqual(r.x.data[0], 2, accuracy: 1e-6))
        #expect(isEqual(r.x.data[1], 3, accuracy: 1e-6))
    }

    @Test func testNearlyCollinearDesignIsCutToRankOneMinimumNorm() throws {
        let a = design(1e-14)
        let b = ColumnMatrix(columns: [[5, 5, 5]])
        let r = try #require(FitLinearAlgebra.leastSquares(a, b))
        #expect(r.rank == 1)
        // Rank 1: the minimum-norm solution splits the weight equally, 2.5 and 2.5 (a rank-2 solve gives anything).
        #expect(isEqual(r.x.data[0], 2.5, accuracy: 1e-9))
        #expect(isEqual(r.x.data[1], 2.5, accuracy: 1e-9))
    }
}
