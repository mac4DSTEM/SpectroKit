//
//  SeededPoissonTests.swift
//  Role: The test-side Poisson sampler (SeededPoisson.swift) is itself tested before the noise tests rely on it: mean,
//        variance and P(0) on three lambda (one per branch, and one large like the zero-loss peak's channels), determinism per
//        seed, and different streams for different seeds.
//

import Foundation
import Testing
import SpectroTestSupport

struct SeededPoissonTests {

    /// 400 000 draws per lambda; the mean within 5 standard errors sqrt(lambda/n); the variance within 5 standard errors
    /// sqrt((lambda + 2 lambda^2)/n) (the variance of a sample variance of a Poisson); P(0) within 5 binomial standard errors.
    @Test func testMeanVarianceAndZeroProbabilityOnThreeLambda() {
        let n = 400_000
        for (lambda, seed) in [(0.4, UInt64(11)), (35.0, UInt64(12)), (7.5e4, UInt64(13))] {
            var g = Xoshiro256StarStar(seed: seed)
            var sum = 0.0, sumSquares = 0.0, zeros = 0
            for _ in 0..<n {
                let x = g.poisson(lambda)
                #expect(x >= 0); #expect(x == x.rounded(), "an integer")
                sum += x; sumSquares += x * x
                if x == 0 { zeros += 1 }
            }
            let mean = sum / Double(n)
            let variance = (sumSquares - Double(n) * mean * mean) / Double(n - 1)
            let meanBound = 5 * (lambda / Double(n)).squareRoot()
            let varBound = 5 * ((lambda + 2 * lambda * lambda) / Double(n)).squareRoot()
            print("EELS-REPORT Poisson sampler lambda \(lambda): mean \(mean) (|diff| \(abs(mean - lambda)) <= \(meanBound)), variance \(variance) (|diff| \(abs(variance - lambda)) <= \(varBound))")
            #expect(isEqual(mean, lambda, accuracy: meanBound), "mean, lambda \(lambda)")
            #expect(isEqual(variance, lambda, accuracy: varBound), "variance, lambda \(lambda)")
            let p0 = exp(-lambda)
            #expect(isEqual(Double(zeros) / Double(n), p0, accuracy: 5 * (p0 * (1 - p0) / Double(n)).squareRoot() + 1e-12), "P(0), lambda \(lambda)")
        }
    }

    @Test func testStreamsAreDeterministicPerSeedAndDifferAcrossSeeds() {
        var a = Xoshiro256StarStar(seed: 7), b = Xoshiro256StarStar(seed: 7), c = Xoshiro256StarStar(seed: 8)
        var same = true, differ = false
        for _ in 0..<1000 {
            let x = a.poisson(50), y = b.poisson(50), z = c.poisson(50)
            if x != y { same = false }
            if x != z { differ = true }
        }
        #expect(same); #expect(differ)
    }

    @Test func testLogFactorialAgreesWithTheExactValue() {
        var exact = 0.0
        for k in 1...60 {
            exact += log(Double(k))
            #expect(isEqual(Xoshiro256StarStar.logFactorial(Double(k)), exact, accuracy: 1e-11), "ln \(k)!")
        }
    }
}
