//
//  EDXQuantificationSigma.swift
//  Role: sigma on the composition of one spectrum or one region's pooled spectrum, for every method of `EDXQuantification`
//        (Cliff-Lorimer, zeta, cross section; with or without absorption): first-order propagation of the counting sigma of the net
//        counts and of the relative sigma of the factors (typed k, zeta or cross section) to wt% and at%.
//
//  There is no Python counterpart (eXSpy and HyperSpy report no sigma on a composition), so nothing is pinned: the tests compare the
//  propagated sigma with the standard deviation of the quantification over many Poisson realisations of a planted case.
//  The result says `validation: "none"` as every quantification does.
//
//  THE FORMULA. With net intensities I (n of them), their covariance C (counting statistics: diagonal, C_ii = I_i for raw counts; for
//  fitted areas the fit's own covariance) and a composition Y(I, f) (wt% or at% of one element, or the mass thickness) that depends
//  on the factors f_j (k, zeta or cross section) with relative one-sigma s_j (independent):
//
//      var(Y) = J C J^T  +  sum_j ( dY / d ln f_j  s_j )^2          J_i = dY / dI_i
//
//  J and dY/d ln f_j are central finite differences of the kit's own quantification (step 1e-5 relative for I, 1e-4 for ln f; the
//  intensities are clamped at 0 on the low side). When the absorption correction is on, the differences are taken with the loop run to
//  1e-10 percentage points, never the caller's coarser criterion, so the stop of the loop does not enter the sigma.
//  The two terms are returned separately, so a report can show "counting" and "k" as the pooled quantification does.
//
//  WHAT IS NOT IN IT: the thickness (absorption), the dose (beam current and live time) and the detector are taken as exact; the
//  absorption model spread is not an uncertainty; a first-order sigma is a poor guide where the composition is strongly nonlinear in
//  I (a line near the 0.1 floor, a few counts): the Monte Carlo test is at a few hundred to a few thousand counts per line.
//

import Foundation

public nonisolated struct EDXQuantificationSigma: Sendable, Equatable {
    /// The composition at the given intensities, as `EDXQuantification.quantify` returns it.
    public var pixel: EDXQuantificationPixel
    public var weightSigma: [Double]
    public var atomicSigma: [Double]
    /// The share of the counting statistics alone (the factors exact).
    public var weightCountingSigma: [Double]
    public var atomicCountingSigma: [Double]
    /// The share of the factors alone (the counts exact).
    public var weightFactorSigma: [Double]
    public var atomicFactorSigma: [Double]
    /// kg/m^2, where the method gives a mass thickness.
    public var massThicknessSigma: Double?
    /// The formula in words, for a report.
    public var formula: String
    public var validation: String
}

extension EDXQuantification {
    public static let sigmaFormula = "first-order propagation: var(Y) = J C J^T + sum_j (dY/dln f_j s_j)^2 on the net counts' covariance C and the factors' relative sigma; thickness, dose and detector exact"

    /// Quantifies one spectrum (or one region's pooled spectrum) and propagates the counting sigma of the net counts, and the
    /// factors' relative sigma, to wt% and at%.
    /// - intensityCovariance: row-major n x n covariance of the intensities (a fit's `covariance` restricted to the quantified lines).
    /// - intensitySigmas: independent one-sigma per intensity. With neither given, the counting statistics of raw counts: variance = I.
    /// - factorRelativeSigmas: relative one-sigma per factor, in the order of `setup.elements` (0.2 = 20 %); nil = the factors are exact.
    public static func quantifyWithSigma(intensities: [Double], intensityCovariance: [Double]? = nil, intensitySigmas: [Double]? = nil,
                                         factorRelativeSigmas: [Double]? = nil, setup: EDXQuantificationSetup,
                                         liveTimeSeconds: Double? = nil) throws -> EDXQuantificationSigma {
        let n = intensities.count
        let base = try quantify(intensities: intensities, setup: setup, liveTimeSeconds: liveTimeSeconds)
        var cov = [Double](repeating: 0, count: n * n)
        if let c = intensityCovariance {
            guard c.count == n * n, c.allSatisfy(\.isFinite) else { throw QuantError.countMismatch("The intensity covariance must hold n x n finite values.") }
            cov = c
        } else if let s = intensitySigmas {
            guard s.count == n, s.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw QuantError.countMismatch("One non-negative sigma per intensity.") }
            for i in 0..<n { cov[i * n + i] = s[i] * s[i] }
        } else {
            for i in 0..<n { cov[i * n + i] = max(intensities[i], 0) }
        }
        if let f = factorRelativeSigmas {
            guard f.count == n, f.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw QuantError.countMismatch("One non-negative relative sigma per factor.") }
        }

        var tight = setup
        if var a = tight.absorption { a.convergencePercent = 1e-10; a.maxIterations = max(a.maxIterations, 500); tight.absorption = a }

        func outputs(_ I: [Double], _ s: EDXQuantificationSetup) throws -> (w: [Double], a: [Double], m: Double?) {
            let p = try quantify(intensities: I, setup: s, liveTimeSeconds: liveTimeSeconds)
            return (p.weightPercent, p.atomicPercent, p.massThickness)
        }
        let hasMass = base.massThickness != nil

        // Counting: J C J^T by central differences on each intensity.
        var jW = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)   // [output][input]
        var jA = jW
        var jM = [Double](repeating: 0, count: n)
        for j in 0..<n {
            let h = 1e-5 * max(intensities[j], 1)
            var lo = intensities, hi = intensities
            lo[j] = max(intensities[j] - h, 0); hi[j] = intensities[j] + h
            let a: (w: [Double], a: [Double], m: Double?), b: (w: [Double], a: [Double], m: Double?)
            do { a = try outputs(hi, tight); b = try outputs(lo, tight) }
            catch { throw QuantError.invalid("The sigma could not be propagated: the composition is not defined next to these intensities (\((error as? LocalizedError)?.errorDescription ?? "\(error)")).") }
            let d = hi[j] - lo[j]
            for i in 0..<n {
                jW[i][j] = (a.w[i] - b.w[i]) / d
                jA[i][j] = (a.a[i] - b.a[i]) / d
            }
            if hasMass, let ma = a.m, let mb = b.m { jM[j] = (ma - mb) / d }
        }
        func quad(_ J: [Double]) -> Double {
            var s = 0.0
            for a in 0..<n { for b in 0..<n { s += J[a] * cov[a * n + b] * J[b] } }
            return max(s, 0)
        }
        let wCount = (0..<n).map { quad(jW[$0]) }, aCount = (0..<n).map { quad(jA[$0]) }
        let mCount = quad(jM)

        // Factors: d/d ln f_j by central differences, times the relative sigma, in quadrature.
        var wFac = [Double](repeating: 0, count: n), aFac = wFac
        var mFac = 0.0
        if let rel = factorRelativeSigmas {
            for j in 0..<n where rel[j] > 0 {
                let d = 1e-4
                let up = scaled(tight, factor: j, by: exp(d)), dn = scaled(tight, factor: j, by: exp(-d))
                let a = try outputs(intensities, up), b = try outputs(intensities, dn)
                for i in 0..<n {
                    wFac[i] += pow((a.w[i] - b.w[i]) / (2 * d) * rel[j], 2)
                    aFac[i] += pow((a.a[i] - b.a[i]) / (2 * d) * rel[j], 2)
                }
                if let ma = a.m, let mb = b.m { mFac += pow((ma - mb) / (2 * d) * rel[j], 2) }
            }
        }
        return EDXQuantificationSigma(
            pixel: base,
            weightSigma: zip(wCount, wFac).map { ($0 + $1).squareRoot() }, atomicSigma: zip(aCount, aFac).map { ($0 + $1).squareRoot() },
            weightCountingSigma: wCount.map { $0.squareRoot() }, atomicCountingSigma: aCount.map { $0.squareRoot() },
            weightFactorSigma: wFac.map { $0.squareRoot() }, atomicFactorSigma: aFac.map { $0.squareRoot() },
            massThicknessSigma: hasMass ? (mCount + mFac).squareRoot() : nil,
            formula: sigmaFormula, validation: validation)
    }

    /// `setup` with factor `j` multiplied by `m`.
    private static func scaled(_ setup: EDXQuantificationSetup, factor j: Int, by m: Double) -> EDXQuantificationSetup {
        var s = setup
        switch setup.method {
        case .cliffLorimer(var k, let t): k[j] *= m; s.method = .cliffLorimer(kFactors: k, thicknessNm: t)
        case .zeta(var z): z[j] *= m; s.method = .zeta(zetaFactors: z)
        case .crossSection(var c, let area): c[j] *= m; s.method = .crossSection(sectionsBarn: c, probeAreaNm2: area)
        }
        return s
    }
}
