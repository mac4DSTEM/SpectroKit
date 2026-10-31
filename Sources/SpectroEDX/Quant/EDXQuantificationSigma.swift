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
//  THICKNESS AND DOSE (the measured inputs). The typed film thickness t (Cliff-Lorimer) and the dose D = live time x beam current / e
//  (zeta, cross section) are measurements with their own one-sigma, independent of the counts and of the factors. Each enters as one
//  more independent term of the same form as a factor:
//
//      var(Y) += ( dY / d ln t  sigma_t / t )^2  +  ( dY / d ln D  s_D )^2
//
//  with dY/d ln t and dY/d ln D central differences of the kit's own quantification (step 1e-4 in ln t, ln D; the dose is scaled through
//  the beam current, so a per-call live time keeps working), the absorption loop run tight as for the counts. Where they act:
//   * Cliff-Lorimer without absorption: wt% and at% do not depend on t (only k ratios enter); the mass thickness is proportional to t,
//     so its relative sigma is sigma_t / t.
//   * Cliff-Lorimer with absorption: t sets the mass thickness the transmission is taken at, so wt% and at% move with t; the term grows
//     with t (the absorption grows) and with the counts (the counting term shrinks): at 150 nm with a 10 % thickness sigma it is already
//     larger than the counting term at about 10^4 counts on the absorbed line.
//   * Zeta and cross section without absorption: the dose cancels in wt% and at% (C_i = zeta_i I_i / sum zeta_j I_j); the mass
//     thickness (and the atoms) go as 1/D, so their relative sigma is s_D.
//   * Zeta and cross section with absorption: the mass thickness rho t = sum zeta_i I_i / D sets the transmission, so a dose error moves
//     wt% and at% through the correction.
//  eXSpy has no uncertainty on any of these (no sigma on a composition at all), so there is no formula to match: the term is the
//  first-order propagation above, tested by Monte Carlo coverage on planted cases where t or D is drawn with its sigma.
//
//  THE DETECTOR. The quantification's only detector input is the take-off angle alpha of the absorption correction (the detector's
//  efficiency and window are inside the typed k, zeta or cross-section factors, so their sigma is the factors' term). With absorption on,
//  the transmission goes as exp(-chi rho t) with chi = mu / sin(alpha) (eXSpy's absorption correction), so an error in alpha (the
//  holder tilt read off the stage, the detector elevation) moves wt% and at% as a thick or tilted specimen grows:
//
//      var(Y) += ( dY / d alpha  sigma_alpha )^2
//
//  with dY/d alpha a central difference of the kit's own quantification (step 1e-3 degree), the loop run tight. Without absorption
//  the angle does not enter and the term is zero.
//
//  WHAT IS NOT IN IT: the detector's efficiency and window are inside the factors' term; the absorption model spread is not an
//  uncertainty; a first-order sigma is a poor guide where the composition is strongly nonlinear in I (a line near the 0.1 floor, a few
//  counts) or in t: the Monte Carlo tests are at a few hundred to a few tens of thousands of counts per line and a 10 % thickness sigma.
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
    /// The share of the typed thickness sigma alone (Cliff-Lorimer; zeros when no thickness sigma is given).
    public var weightThicknessSigma: [Double]
    public var atomicThicknessSigma: [Double]
    /// The share of the dose sigma alone (zeta and cross section; zeros when no dose sigma is given).
    public var weightDoseSigma: [Double]
    public var atomicDoseSigma: [Double]
    /// The share of the take-off angle sigma alone (with absorption; zeros when no angle sigma is given or absorption is off).
    public var weightDetectorSigma: [Double]
    public var atomicDetectorSigma: [Double]
    /// kg/m^2, where the method gives a mass thickness (every term included).
    public var massThicknessSigma: Double?
    /// The formula in words, for a report.
    public var formula: String
    public var validation: String
}

/// Per-pixel sigma maps beside the composition maps (`EDXQuantification.quantifyMapsWithSigma`).
public nonisolated struct EDXQuantificationSigmaMaps: Sendable, Equatable {
    /// The composition maps, exactly as `quantifyMaps` returns them.
    public var maps: EDXQuantificationMaps
    /// One map per element: the one-sigma of wt% and at% at each pixel, every term included (0 on masked pixels, NaN on failed ones).
    public var weightSigma: [[Double]]
    public var atomicSigma: [[Double]]
    /// kg/m^2, where the method gives a mass thickness.
    public var massThicknessSigma: [Double]?
    /// Why the sigma could not be propagated at a pixel whose composition was found (its sigma reads NaN); nil elsewhere.
    public var sigmaFailures: [String?]
    public var formula: String
    public var validation: String
}

extension EDXQuantification {
    public static let sigmaFormula = "first-order propagation: var(Y) = J C J^T + sum_j (dY/dln f_j s_j)^2 + (dY/dln t sigma_t/t)^2 + (dY/dln D s_D)^2 + (dY/dalpha sigma_alpha)^2 on the net counts' covariance C, the factors' relative sigma, the typed thickness sigma, the dose relative sigma and the take-off angle sigma; detector efficiency inside the factors"

    /// Quantifies one spectrum (or one region's pooled spectrum) and propagates the counting sigma of the net counts, the
    /// factors' relative sigma, the thickness sigma and the dose sigma to wt% and at%.
    /// - intensityCovariance: row-major n x n covariance of the intensities (a fit's `covariance` restricted to the quantified lines).
    /// - intensitySigmas: independent one-sigma per intensity. With neither given, the counting statistics of raw counts: variance = I.
    /// - factorRelativeSigmas: relative one-sigma per factor, in the order of `setup.elements` (0.2 = 20 %); nil = the factors are exact.
    /// - thicknessSigmaNm: one-sigma of the typed film thickness in nm (Cliff-Lorimer with a thickness only); nil = exact.
    /// - doseRelativeSigma: relative one-sigma of the dose, live time x beam current (zeta and cross section only; 0.05 = 5 %,
    ///   in practice the beam current's); nil = exact.
    /// - takeOffSigmaDegrees: one-sigma of the take-off angle in degrees (with an absorption setting only); nil = exact.
    public static func quantifyWithSigma(intensities: [Double], intensityCovariance: [Double]? = nil, intensitySigmas: [Double]? = nil,
                                         factorRelativeSigmas: [Double]? = nil, thicknessSigmaNm: Double? = nil,
                                         doseRelativeSigma: Double? = nil, takeOffSigmaDegrees: Double? = nil, setup: EDXQuantificationSetup,
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
        let typedThickness = try validateSigmaArguments(count: n, setup: setup, factorRelativeSigmas: factorRelativeSigmas,
                                                        thicknessSigmaNm: thicknessSigmaNm, doseRelativeSigma: doseRelativeSigma,
                                                        takeOffSigmaDegrees: takeOffSigmaDegrees)

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

        // Thickness and dose: one more ln-derivative each, times the relative sigma (variances, per output).
        func lnTerm(_ up: EDXQuantificationSetup, _ dn: EDXQuantificationSetup, rel: Double) throws -> (w: [Double], a: [Double], m: Double) {
            let d = 1e-4
            let a: (w: [Double], a: [Double], m: Double?), b: (w: [Double], a: [Double], m: Double?)
            do { a = try outputs(intensities, up); b = try outputs(intensities, dn) }
            catch { throw QuantError.invalid("The sigma could not be propagated: the composition is not defined next to this thickness or dose (\((error as? LocalizedError)?.errorDescription ?? "\(error)")).") }
            let w = (0..<n).map { pow((a.w[$0] - b.w[$0]) / (2 * d) * rel, 2) }
            let at = (0..<n).map { pow((a.a[$0] - b.a[$0]) / (2 * d) * rel, 2) }
            var m = 0.0
            if let ma = a.m, let mb = b.m { m = pow((ma - mb) / (2 * d) * rel, 2) }
            return (w, at, m)
        }
        let zeros = [Double](repeating: 0, count: n)
        var wThick = zeros, aThick = zeros, mThick = 0.0
        if let st = thicknessSigmaNm, st > 0, let t = typedThickness, case .cliffLorimer(let k, _) = tight.method {
            var up = tight, dn = tight
            up.method = .cliffLorimer(kFactors: k, thicknessNm: t * exp(1e-4))
            dn.method = .cliffLorimer(kFactors: k, thicknessNm: t * exp(-1e-4))
            (wThick, aThick, mThick) = try lnTerm(up, dn, rel: st / t)
        }
        var wDose = zeros, aDose = zeros, mDose = 0.0
        if let sd = doseRelativeSigma, sd > 0 {
            guard let current = tight.beamCurrentNA else { throw QuantError.invalid("The dose needs a positive beam current and live time.") }
            var up = tight, dn = tight
            up.beamCurrentNA = current * exp(1e-4); dn.beamCurrentNA = current * exp(-1e-4)
            (wDose, aDose, mDose) = try lnTerm(up, dn, rel: sd)
        }
        var wDet = zeros, aDet = zeros, mDet = 0.0
        if let sa = takeOffSigmaDegrees, sa > 0, let a = tight.absorption {
            // lnTerm divides by 2 x 1e-4; a step of 1e-3 degree with rel = sigma x 1e-4 / 1e-3 gives dY/dalpha x sigma.
            let h = 1e-3
            guard a.takeOffDegrees - h > 0, a.takeOffDegrees + h <= 90 else { throw QuantError.invalid("The take-off angle sigma needs the angle at least 0.001 degree inside (0, 90) degrees (the central difference steps that far).") }
            var up = tight, dn = tight
            up.absorption?.takeOffDegrees = a.takeOffDegrees + h; dn.absorption?.takeOffDegrees = a.takeOffDegrees - h
            (wDet, aDet, mDet) = try lnTerm(up, dn, rel: sa * 1e-4 / h)
        }

        func total(_ terms: [Double]...) -> [Double] { (0..<n).map { i in terms.reduce(0) { $0 + $1[i] }.squareRoot() } }
        return EDXQuantificationSigma(
            pixel: base,
            weightSigma: total(wCount, wFac, wThick, wDose, wDet), atomicSigma: total(aCount, aFac, aThick, aDose, aDet),
            weightCountingSigma: wCount.map { $0.squareRoot() }, atomicCountingSigma: aCount.map { $0.squareRoot() },
            weightFactorSigma: wFac.map { $0.squareRoot() }, atomicFactorSigma: aFac.map { $0.squareRoot() },
            weightThicknessSigma: wThick.map { $0.squareRoot() }, atomicThicknessSigma: aThick.map { $0.squareRoot() },
            weightDoseSigma: wDose.map { $0.squareRoot() }, atomicDoseSigma: aDose.map { $0.squareRoot() },
            weightDetectorSigma: wDet.map { $0.squareRoot() }, atomicDetectorSigma: aDet.map { $0.squareRoot() },
            massThicknessSigma: hasMass ? (mCount + mFac + mThick + mDose + mDet).squareRoot() : nil,
            formula: sigmaFormula, validation: validation)
    }

    /// Per-pixel sigma maps: `quantifyWithSigma` at every pixel of `quantifyMaps`' input, with the same mask, live times and take-off
    /// angles per pixel. `intensitySigmaMaps[e][pixel]` is the one-sigma of element e's intensity at a pixel (a fit's per-pixel sigma);
    /// nil = the counting statistics of raw counts (variance = I). The factor, thickness, dose and take-off sigmas are shared by every
    /// pixel. A masked pixel reads 0 (as in `quantifyMaps`); a pixel whose composition failed reads NaN (its reason in `maps.failures`),
    /// and one whose sigma alone could not be propagated reads NaN with its reason in `sigmaFailures`.
    public static func quantifyMapsWithSigma(intensityMaps: [[Double]], rows: Int, columns: Int, setup: EDXQuantificationSetup,
                                             intensitySigmaMaps: [[Double]]? = nil, factorRelativeSigmas: [Double]? = nil,
                                             thicknessSigmaNm: Double? = nil, doseRelativeSigma: Double? = nil,
                                             takeOffSigmaDegrees: Double? = nil, navigationMask: [Bool]? = nil,
                                             liveTimesSeconds: [Double]? = nil, takeOffDegreesPerPixel: [Double]? = nil) throws -> EDXQuantificationSigmaMaps {
        let n = intensityMaps.count
        let pixels = rows * columns
        // The composition maps (and every refusal of their inputs) are `quantifyMaps`' own.
        _ = try validateSigmaArguments(count: n, setup: setup, factorRelativeSigmas: factorRelativeSigmas, thicknessSigmaNm: thicknessSigmaNm,
                                       doseRelativeSigma: doseRelativeSigma, takeOffSigmaDegrees: takeOffSigmaDegrees)
        if let sm = intensitySigmaMaps {
            guard sm.count == n, sm.allSatisfy({ $0.count == pixels }) else { throw QuantError.countMismatch("One sigma map of rows x columns values per intensity map.") }
        }
        let maps = try quantifyMaps(intensityMaps: intensityMaps, rows: rows, columns: columns, setup: setup, navigationMask: navigationMask,
                                    liveTimesSeconds: liveTimesSeconds, takeOffDegreesPerPixel: takeOffDegreesPerPixel)
        var wS = [[Double]](repeating: [Double](repeating: 0, count: pixels), count: n), aS = wS
        var mS: [Double]? = maps.massThickness.map { _ in [Double](repeating: 0, count: pixels) }
        var sigmaFailures = [String?](repeating: nil, count: pixels)

        enum Outcome { case skipped, ok(EDXQuantificationSigma), failed(String) }
        final class Slots: @unchecked Sendable { var outcomes: [Outcome]; init(_ n: Int) { outcomes = [Outcome](repeating: .skipped, count: n) } }
        let slots = Slots(pixels)
        let chunk = 256
        let chunks = (pixels + chunk - 1) / chunk
        slots.outcomes.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let out = buffer
            DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                for p in (ci * chunk)..<min(pixels, (ci + 1) * chunk) {
                    if navigationMask?[p] == true || maps.failures[p] != nil { continue }
                    var s = setup
                    if let a = takeOffDegreesPerPixel?[p] { s.absorption?.takeOffDegrees = a }
                    do {
                        out[p] = .ok(try quantifyWithSigma(
                            intensities: (0..<n).map { intensityMaps[$0][p] }, intensitySigmas: intensitySigmaMaps.map { m in (0..<n).map { m[$0][p] } },
                            factorRelativeSigmas: factorRelativeSigmas, thicknessSigmaNm: thicknessSigmaNm, doseRelativeSigma: doseRelativeSigma,
                            takeOffSigmaDegrees: takeOffSigmaDegrees, setup: s, liveTimeSeconds: liveTimesSeconds?[p] ?? setup.liveTimeSeconds))
                    } catch {
                        out[p] = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
                    }
                }
            }
        }
        for p in 0..<pixels {
            switch slots.outcomes[p] {
            case .skipped:
                if maps.failures[p] != nil {
                    for e in 0..<n { wS[e][p] = .nan; aS[e][p] = .nan }
                    mS?[p] = .nan
                }
            case .ok(let r):
                for e in 0..<n { wS[e][p] = r.weightSigma[e]; aS[e][p] = r.atomicSigma[e] }
                if let m = r.massThicknessSigma { mS?[p] = m }
            case .failed(let why):
                for e in 0..<n { wS[e][p] = .nan; aS[e][p] = .nan }
                mS?[p] = .nan
                sigmaFailures[p] = why
            }
        }
        return EDXQuantificationSigmaMaps(maps: maps, weightSigma: wS, atomicSigma: aS, massThicknessSigma: mS,
                                          sigmaFailures: sigmaFailures, formula: sigmaFormula, validation: validation)
    }

    /// The refusals of the shared sigma arguments; returns the typed thickness when a thickness sigma is given.
    private static func validateSigmaArguments(count n: Int, setup: EDXQuantificationSetup, factorRelativeSigmas: [Double]?, thicknessSigmaNm: Double?,
                                               doseRelativeSigma: Double?, takeOffSigmaDegrees: Double?) throws -> Double? {
        if let f = factorRelativeSigmas {
            guard f.count == n, f.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw QuantError.countMismatch("One non-negative relative sigma per factor.") }
        }
        var typedThickness: Double? = nil
        if let st = thicknessSigmaNm {
            guard st.isFinite, st >= 0 else { throw QuantError.invalid("The thickness sigma must be finite and not negative.") }
            guard case .cliffLorimer(_, let t?) = setup.method else {
                throw QuantError.invalid("A thickness sigma needs Cliff-Lorimer with a typed thickness (zeta and cross section derive the mass thickness from the dose).")
            }
            typedThickness = t
        }
        if let sd = doseRelativeSigma {
            guard sd.isFinite, sd >= 0 else { throw QuantError.invalid("The dose sigma must be finite and not negative.") }
            if case .cliffLorimer = setup.method { throw QuantError.invalid("A dose sigma needs the zeta or cross-section method (Cliff-Lorimer takes no dose).") }
        }
        if let sa = takeOffSigmaDegrees {
            guard sa.isFinite, sa >= 0 else { throw QuantError.invalid("The take-off angle sigma must be finite and not negative.") }
            guard setup.absorption != nil else { throw QuantError.invalid("A take-off angle sigma needs an absorption setting (without it the angle does not enter).") }
        }
        return typedThickness
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
