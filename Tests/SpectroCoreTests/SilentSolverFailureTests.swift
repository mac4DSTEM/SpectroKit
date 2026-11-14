//
//  SilentSolverFailureTests.swift
//  Role: SpectroKit#104. The incomplete gamma at large counts and the least-squares solvers say when they have no answer.
//        Red before: P(1e5, x) near x = a stopped the series at 500 terms (11 % low at the mode, 62 % at 1e6); a NaN count gave
//        converged zeros from `LeastSquaresFit` and a "stationary" exit from `PoissonMLFit`.
//

import Foundation
import Testing
import SpectroCore

struct SilentSolverFailureTests {

    /// Values from a 40-digit mpmath series (SciPy `gammainc` agrees to 1e-15 up to a = 1e5; at a = 1e6, 6 sigma below the mode,
    /// SciPy itself is 6e-7 off the 40-digit value, so the pin there is mpmath).
    @Test func testTheIncompleteGammaHoldsAtLargeCounts() {
        let cases: [(a: Double, x: Double, p: Double)] = [
            (1e4, 9_700, 0.001234175584468492),
            (1e5, 99_052, 0.0013221954066057287),
            (1e5, 100_000, 0.50042052211036518),
            (1e5, 100_948, 0.99860269675648225),
            (1e6, 994_000, 9.1789002623020234e-10),
        ]
        for c in cases {
            let got = IncompleteGamma.lowerRegularized(a: c.a, x: c.x)
            #expect(abs(got - c.p) <= 1e-10 * c.p, Comment(rawValue: "a \(c.a) x \(c.x): \(got) vs \(c.p)"))
        }
        // The quantile inherits it: the median of a gamma of shape 1e5 sits just below a (a - 1/3 + ...).
        let median = IncompleteGamma.gammaQuantile(p: 0.5, shape: 1e5)
        #expect(abs(median - (1e5 - 1.0 / 3)) < 0.01, Comment(rawValue: "\(median)"))
    }

    @Test func testTheIterationCapGrowsWithTheShape() {
        #expect(IncompleteGamma.iterationCap(a: 1) >= IncompleteGamma.maximumIterations)
        #expect(IncompleteGamma.iterationCap(a: 1e6) >= 12_000)
    }

    @Test func testALeastSquaresFitOnANaNCountIsNotConverged() {
        let design = ColumnMatrix(columns: [[1, 1, 1, 1]])
        let free = ColumnMatrix(columns: [[0, 1, 2, 3]])
        let good = LeastSquaresFit.solve(nonNegative: design, free: free, y: [1, 2, 3, 4])
        #expect(good.converged && good.answered)
        let bad = LeastSquaresFit.solve(nonNegative: design, free: free, y: [1, .nan, 3, 4])
        #expect(!bad.converged && !bad.answered)
        let badWeight = LeastSquaresFit.solve(nonNegative: design, y: [1, 2, 3, 4], rowWeights: [1, .infinity, 1, 1])
        #expect(!badWeight.converged)
    }

    @Test func testAPoissonFitOnANaNCountIsNotConverged() {
        let design = ColumnMatrix(columns: [[1, 1, 1, 1], [0, 1, 0, 1]])
        let good = PoissonMLFit.solve(nonNegative: design, y: [3, 5, 3, 5])
        #expect(good.converged)
        let bad = PoissonMLFit.solve(nonNegative: design, y: [3, .nan, 3, 5])
        #expect(!bad.converged && bad.exit == .notFinite, Comment(rawValue: bad.exit.rawValue))
    }
}
