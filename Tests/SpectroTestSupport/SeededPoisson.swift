//
//  SeededPoisson.swift
//  Role: A seeded Poisson sampler for the noise tests (registration section 7 gate 3: 200 realisations, seeds 1 to 200,
//        generated in the test, not stored). Written here, not NumPy's stream: the realisations differ from the ones
//        tools/eels-thickness/pins.py drew, and the claim tested (standard deviation of t/lambda against sigma_counting) does
//        not depend on which stream.
//
//  Algorithm:
//   * generator: xoshiro256** (Blackman and Vigna 2018), its 256-bit state filled from the seed by SplitMix64; a uniform in the
//     open interval (0, 1) is (top 53 bits + 0.5) / 2^53;
//   * lambda < 10: Knuth's multiplication method (multiply uniforms until the product falls to exp(-lambda) or below; the
//     number of factors minus one is the sample);
//   * lambda >= 10: PTRS, Hormann's transformed rejection with squeeze (W. Hormann, "The transformed rejection method for
//     generating Poisson random variables", Insurance: Mathematics and Economics 12 (1993) 39-45), with the constants b = 0.931
//     + 2.53 sqrt(lambda), a = -0.059 + 0.02483 b, 1/alpha = 1.1239 + 1.1328/(b - 3.4), v_r = 0.9277 - 3.6224/(b - 2) of the
//     paper; ln k! by the exact sum below 20 and Stirling's series above.
//  `SeededPoissonTests` checks its mean, variance and P(0) on three lambda.
//

import Foundation

package struct SplitMix64 {
    package var state: UInt64
    package mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

package struct Xoshiro256StarStar {
    private var s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64

    package init(seed: UInt64) {
        var sm = SplitMix64(state: seed)
        s0 = sm.next(); s1 = sm.next(); s2 = sm.next(); s3 = sm.next()
    }

    private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }

    package mutating func next() -> UInt64 {
        let result = Self.rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3
        s2 ^= t
        s3 = Self.rotl(s3, 45)
        return result
    }

    /// Uniform on the open interval (0, 1).
    package mutating func uniform() -> Double { (Double(next() >> 11) + 0.5) * 0x1.0p-53 }

    /// A Poisson variate with mean `lambda` (0 for lambda <= 0).
    package mutating func poisson(_ lambda: Double) -> Double {
        if !(lambda > 0) { return 0 }
        if lambda < 10 {
            let limit = exp(-lambda)
            var k = 0
            var product = 1.0
            repeat { k += 1; product *= uniform() } while product > limit
            return Double(k - 1)
        }
        let slam = lambda.squareRoot(), loglam = log(lambda)
        let b = 0.931 + 2.53 * slam
        let a = -0.059 + 0.02483 * b
        let invalpha = 1.1239 + 1.1328 / (b - 3.4)
        let vr = 0.9277 - 3.6224 / (b - 2)
        while true {
            let u = uniform() - 0.5
            let v = uniform()
            let us = 0.5 - abs(u)
            let k = ((2 * a / us + b) * u + lambda + 0.43).rounded(.down)
            if us >= 0.07 && v <= vr { return k }
            if k < 0 || (us < 0.013 && v > us) { continue }
            if log(v) + log(invalpha) - log(a / (us * us) + b) <= -lambda + k * loglam - Self.logFactorial(k) { return k }
        }
    }

    /// ln k! : the exact sum of logs for k < 20, Stirling's series (three correction terms, error below 5e-13 from k = 20) above.
    package static func logFactorial(_ k: Double) -> Double {
        if k < 20 {
            var s = 0.0
            if k >= 2 { for i in 2...Int(k) { s += log(Double(i)) } }
            return s
        }
        let inv = 1 / k
        return k * log(k) - k + 0.5 * log(2 * Double.pi * k) + inv / 12 - inv * inv * inv / 360 + inv * inv * inv * inv * inv / 1260
    }
}
