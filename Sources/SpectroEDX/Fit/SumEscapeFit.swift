//
//  SumEscapeFit.swift
//  Role: Two optional components of the EDS fit, both OFF unless asked for (a fit that does not ask runs the code it always ran,
//        bit for bit): SUM (pile-up) peaks and a COMMON Si-ESCAPE FRACTION.
//
//  There is no Python reference. eXSpy's `EDSModel` has `add_family_lines` and no sum or escape model, and HyperSpy has none, so
//  nothing here is pinned: it is tested against planted truth only, and every result says `validation: "none"`.
//
//  THE MODEL (all parameters are stated in `SumEscapeResult.parameters`)
//   * Sum peak. Two photons that reach the detector within its pulse-resolving time are read as one photon of the summed energy.
//     For the alpha lines i and j of two fitted line groups with fitted areas A_i and A_j (counts), the pile-up peak is a unit-area
//     Gaussian at E_i + E_j (width from the detector's line-width law at the summed energy; the quadrature sum of the two parents'
//     widths where the law has no real width there) with area
//         S_ij = c * m_ij * A_i * A_j,     m_ij = 1 for i = j (a photon met by a second of its own kind),
//                                          m_ij = 2 for i != j (either one arriving first).
//     c is the pile-up coefficient, c = tau / T (pulse-resolving time over live time: dimensionless, A_i A_j c is in counts). It is
//     ONE number for the whole spectrum, estimated by least squares (or fixed by the caller). The parents are the `parentCount`
//     groups with the largest baseline areas; pairs whose energy is at or above the beam energy, or outside the fitted range, are
//     left out.
//   * Escape peak. A photon of energy E above the Si K edge (1.839 keV) can leave the detector with the Si K-alpha (1.7400 keV) it
//     excited, and be read at E - 1.7400 keV. The escape copy of a line group is the same lines shifted down by Si K-alpha with an
//     area f times the parent group's area, f one COMMON fraction (estimated or fixed) instead of the default fit's own free
//     escape area per group. The default fit's escape columns are removed when this model is on.
//
//  THE SOLVER. Both terms are tied to the line areas, so the fit is not linear. It is solved by alternation: given c and f, the
//  line areas are the (non-negative) linear fit of the design whose group columns carry the Gauss-Newton linearisation of the tied
//  terms (column_g + c dS/dA_g + f * escape_g, and the offset -c * S(A0), exact for the degree-two sum term and for the degree-one
//  escape term); given the areas, c and f are the one-dimensional least squares of the residual on the two terms' shapes (weighted
//  by 1 / model under Poisson ML), clipped at 0. Each step lowers the objective; the loop stops when c, f and the areas move by
//  less than `tolerance` relative, or at `maxIterations` (then `converged` is false and a warning says so).
//
//  SIGMA. `sumCoefficientSigma` is the first-order (sandwich) sigma of c with Var(data) = model: the residual of the term's shape
//  after projecting out the fit's other columns, q_perp, gives Var(c) = sum(mu q_perp^2) / (q_perp . q_perp)^2. It ignores the
//  dependence of the term's shape on the areas (second order, c * A_j is of the order of the sum fraction). The line areas'
//  covariance is the fit's own on the linearised design.
//
//  DEVIATIONS: the degrees of freedom count the design's columns, not the one or two extra coefficients (a change of 1 or 2 in
//  hundreds of channels); the sum term uses the ALPHA line of a group only (a family's weaker lines are not parents).
//

import Foundation
import SpectroCore

/// What to switch on. The default value is "nothing": `EDSSumEscapeFit.run` with it returns the baseline fit.
public nonisolated struct SumEscapeModel: Sendable, Equatable {
    /// Model pile-up (sum) peaks of the strongest alpha lines.
    public var sumPeaks: Bool
    /// How many groups (the largest baseline areas) are parents of sum peaks.
    public var parentCount: Int
    /// The pile-up coefficient c = tau / T, fixed; nil estimates it.
    public var sumCoefficient: Double?
    /// Replace the default fit's free escape area per group by one common escape fraction f.
    public var commonEscapeFraction: Bool
    /// The common escape fraction, fixed (0 to 1); nil estimates it.
    public var escapeFraction: Double?
    public var maxIterations: Int
    public var tolerance: Double

    public init(sumPeaks: Bool = false, parentCount: Int = 4, sumCoefficient: Double? = nil,
                commonEscapeFraction: Bool = false, escapeFraction: Double? = nil,
                maxIterations: Int = 300, tolerance: Double = 1e-9) {
        self.sumPeaks = sumPeaks; self.parentCount = parentCount; self.sumCoefficient = sumCoefficient
        self.commonEscapeFraction = commonEscapeFraction; self.escapeFraction = escapeFraction
        self.maxIterations = maxIterations; self.tolerance = tolerance
    }

    /// Both components on, both coefficients estimated.
    public static let both = SumEscapeModel(sumPeaks: true, commonEscapeFraction: true)
    public var isOff: Bool { !sumPeaks && !commonEscapeFraction }
}

public nonisolated enum SumEscapeError: Error, Equatable, LocalizedError {
    case invalidParentCount(Int)
    case invalidCoefficient(String)
    public var errorDescription: String? {
        switch self {
        case .invalidParentCount(let n): return "The sum-peak model needs at least one parent line group; \(n) was given."
        case .invalidCoefficient(let s): return s
        }
    }
}

/// One fitted pile-up peak.
public nonisolated struct SumPeakComponent: Sendable, Equatable {
    /// "Fe_Ka + Cu_Ka".
    public var label: String
    public var firstGroup: String
    public var secondGroup: String
    public var energyKeV: Double
    /// c * m * A_i * A_j, counts.
    public var area: Double
}

/// One fitted escape copy.
public nonisolated struct EscapeComponent: Sendable, Equatable {
    public var group: String
    /// f * the parent group's area, counts.
    public var area: Double
}

public nonisolated struct SumEscapeResult: Sendable {
    /// The fit with the components on: `values` are the line areas, `model` includes the sum and escape peaks.
    public var fit: EDSFitResult
    /// The default fit of the same settings without the components, for comparison.
    public var baseline: EDSFitResult
    public var sumCoefficient: Double?
    public var sumCoefficientSigma: Double?
    /// True when c was clipped at 0 (no sum peak supported by the data).
    public var sumCoefficientAtBound: Bool
    public var sumPeaks: [SumPeakComponent]
    public var escapeFraction: Double?
    public var escapeFractionSigma: Double?
    public var escapePeaks: [EscapeComponent]
    /// The fitted sum and escape peaks together, counts per channel of `fit.channels` (c S(A) + f E(A) at the reported areas): what
    /// the model explains beyond the line and continuum columns. The element proposer takes it as a fixed part of its model, so a
    /// peak this model covers is not proposed as an element. All zeros when the model is off. It is the exact sum term at the
    /// reported areas; `fit.model` holds its linearisation at the previous iterate, which differs by c times the squared area step
    /// (nothing at convergence; the warnings say when the alternation did not converge).
    public var componentCounts: [Double]
    public var iterations: Int
    public var converged: Bool
    /// The parameters of the model as run, one sentence each.
    public var parameters: [String]
    /// Always "none": there is no reference and no standard.
    public var validation: String
}

public nonisolated enum EDSSumEscapeFit {
    public static let validation = "none"

    public static func run(counts: [Double], axis: EnergyAxis, settings: FitSettings, model: SumEscapeModel,
                           channels explicit: Range<Int>? = nil,
                           escapeRatioWarning: Double = FitPolicy.default.escapeRatioWarning) throws -> SumEscapeResult {
        if model.sumPeaks, model.parentCount < 1 { throw SumEscapeError.invalidParentCount(model.parentCount) }
        if let c = model.sumCoefficient, !(c.isFinite && c >= 0) {
            throw SumEscapeError.invalidCoefficient("The pile-up coefficient must be finite and not negative; \(c) was given.")
        }
        if let f = model.escapeFraction, !(f.isFinite && f >= 0 && f <= 1) {
            throw SumEscapeError.invalidCoefficient("The escape fraction must lie in 0...1; \(f) was given.")
        }
        let baseline = try EDSFit.run(counts: counts, axis: axis, settings: settings, channels: explicit, escapeRatioWarning: escapeRatioWarning)
        if model.isOff {
            return SumEscapeResult(fit: baseline, baseline: baseline, sumCoefficient: nil, sumCoefficientSigma: nil,
                                   sumCoefficientAtBound: false, sumPeaks: [], escapeFraction: nil, escapeFractionSigma: nil,
                                   escapePeaks: [], componentCounts: [Double](repeating: 0, count: baseline.channels.count),
                                   iterations: 0, converged: true,
                                   parameters: ["sum and escape model: off (the default fit)"], validation: validation)
        }

        let channels = explicit ?? axis.fitChannels(from: settings.fitFrom, to: settings.fitTo)
        var s = settings
        if model.commonEscapeFraction { s.escapePeaks = true }   // the line model needs the escape lists; the free columns are removed below
        let lineModel = EDSLineModel.build(elements: s.elements, axis: axis, beamEnergy: s.beamEnergy,
                                           resolutionMnKaEV: s.resolutionMnKaEV, escapePeaks: s.escapePeaks, lineTail: s.lineTail)
        var design = LinearDesign.build(model: lineModel, axis: axis, channels: channels, background: s.background,
                                        shapes: s.referenceShapes, counts: counts)
        if model.commonEscapeFraction {
            design.areaColumns.removeAll { if case .escape = $0.kind { return true } else { return false } }
        }
        var fitSettings = s
        fitSettings.escapePeaks = false   // the footer's own escape label is replaced below
        let energies = design.energies
        let n = channels.count
        let y = channels.map { counts[$0] }
        let groups = lineModel.groups
        let g = groups.count
        let isML: Bool = { if case .poissonML = settings.method { return true } else { return false } }()

        // Parents and pair columns.
        struct Pair { var i: Int; var j: Int; var mult: Double; var energy: Double; var column: [Double] }
        var pairs: [Pair] = []
        if model.sumPeaks {
            let eligible = (0..<g).filter { baseline.supported[$0] && baseline.values[$0] > 0 }
                .sorted { baseline.values[$0] > baseline.values[$1] }.prefix(model.parentCount).sorted()
            for a in 0..<eligible.count { for b in a..<eligible.count {
                let i = eligible[a], j = eligible[b]
                let la = groups[i].lines[0], lb = groups[j].lines[0]
                let e = la.energy + lb.energy
                guard e < s.beamEnergy else { continue }
                let w = XRayLines.fwhm(resolutionMnKaEV: s.resolutionMnKaEV, atEnergy: e)
                    ?? (la.fwhm * la.fwhm + lb.fwhm * lb.fwhm).squareRoot()
                let col = EDSLineModel.column(of: [FitLine(id: "sum", energy: e, weight: 1, fwhm: w)], energies: energies, scale: axis.scale, tail: s.lineTail)
                guard (col.max() ?? 0) >= 1e-8 else { continue }
                pairs.append(Pair(i: i, j: j, mult: i == j ? 1 : 2, energy: e, column: col))
            } }
        }
        var escColumns = [[Double]?](repeating: nil, count: g)
        if model.commonEscapeFraction {
            for (gi, grp) in groups.enumerated() where !grp.escapes.isEmpty && baseline.supported[gi] {
                let col = EDSLineModel.column(of: grp.escapes, energies: energies, scale: axis.scale, tail: s.lineTail)
                if (col.max() ?? 0) >= 1e-8 { escColumns[gi] = col }
            }
        }

        func sumShape(_ a: [Double]) -> [Double] {
            var q = [Double](repeating: 0, count: n)
            for p in pairs {
                let amp = p.mult * a[p.i] * a[p.j]
                if amp == 0 { continue }
                for k in 0..<n { q[k] += amp * p.column[k] }
            }
            return q
        }
        func escShape(_ a: [Double]) -> [Double] {
            var q = [Double](repeating: 0, count: n)
            for gi in 0..<g { if let col = escColumns[gi], a[gi] != 0 { for k in 0..<n { q[k] += a[gi] * col[k] } } }
            return q
        }

        let estimateC = model.sumPeaks && model.sumCoefficient == nil
        let estimateF = model.commonEscapeFraction && model.escapeFraction == nil
        var c = model.sumPeaks ? (model.sumCoefficient ?? 0) : 0
        var f = model.commonEscapeFraction ? (model.escapeFraction ?? 0) : 0
        var area = baseline.values
        var cAtBound = false

        func linearised(_ design0: LinearDesign, c: Double, f: Double, area a0: [Double]) -> LinearDesign {
            var d = design0
            if c != 0 {
                let q0 = sumShape(a0)
                for k in 0..<n { d.offset[k] -= c * q0[k] }
                for p in pairs {
                    if p.i == p.j {
                        let w = c * p.mult * 2 * a0[p.i]
                        for k in 0..<n { d.areaColumns[p.i].values[k] += w * p.column[k] }
                    } else {
                        let wi = c * p.mult * a0[p.j], wj = c * p.mult * a0[p.i]
                        for k in 0..<n {
                            d.areaColumns[p.i].values[k] += wi * p.column[k]
                            d.areaColumns[p.j].values[k] += wj * p.column[k]
                        }
                    }
                }
            }
            if f != 0 {
                for gi in 0..<g { if let col = escColumns[gi] { for k in 0..<n { d.areaColumns[gi].values[k] += f * col[k] } } }
            }
            return d
        }

        func oneD(_ r: [Double], _ q: [Double], weights w: [Double]?) -> Double {
            var num = 0.0, den = 0.0
            for k in 0..<n { let wk = w?[k] ?? 1; num += wk * r[k] * q[k]; den += wk * q[k] * q[k] }
            return den > 0 ? num / den : 0
        }

        var iterations = 0, converged = false
        let maxIt = max(model.maxIterations, 1)
        while iterations < maxIt {
            iterations += 1
            let d = linearised(design, c: c, f: f, area: area)
            let r = EDSFit.fit(design: d, model: lineModel, counts: counts, settings: fitSettings, computeCovariance: false)
            let aNew = r.values
            var mu = r.model
            let w: [Double]? = isML ? mu.map { 1 / max($0, 1e-6) } : nil
            var cNew = c, fNew = f
            if estimateC {
                let q = sumShape(aNew)
                // The model holds c * q(A) (to second order in the area change): take it out, regress, put the new one in.
                let res = (0..<n).map { y[$0] - mu[$0] + c * q[$0] }
                cNew = max(oneD(res, q, weights: w), 0)
                for k in 0..<n { mu[k] += (cNew - c) * q[k] }
            }
            if estimateF {
                let q = escShape(aNew)
                let res = (0..<n).map { y[$0] - mu[$0] + f * q[$0] }
                fNew = min(max(oneD(res, q, weights: w), 0), 1)
            }
            let dc = abs(cNew - c) / max(abs(cNew), 1e-300), df = abs(fNew - f) / max(abs(fNew), 1e-300)
            var da = 0.0
            let scale = max(aNew.map(abs).max() ?? 0, 1)
            for i in 0..<g { da = max(da, abs(aNew[i] - area[i]) / scale) }
            area = aNew; c = cNew; f = fNew
            let cDone = !estimateC || dc < model.tolerance
            let fDone = !estimateF || df < model.tolerance
            if cDone && fDone && da < model.tolerance { converged = true; break }
        }
        cAtBound = estimateC && c == 0

        // Final fit with covariance on the linearised design at the converged point.
        let dFinal = linearised(design, c: c, f: f, area: area)
        var fit = EDSFit.fit(design: dFinal, model: lineModel, counts: counts, settings: fitSettings, computeCovariance: true,
                            escapeRatioWarning: escapeRatioWarning)
        area = fit.values

        // Components as run.
        var sumComponents: [SumPeakComponent] = []
        for p in pairs {
            sumComponents.append(SumPeakComponent(label: groups[p.i].id + " + " + groups[p.j].id, firstGroup: groups[p.i].id,
                                                  secondGroup: groups[p.j].id, energyKeV: p.energy,
                                                  area: c * p.mult * area[p.i] * area[p.j]))
        }
        var escComponents: [EscapeComponent] = []
        for gi in 0..<g where escColumns[gi] != nil { escComponents.append(EscapeComponent(group: groups[gi].id, area: f * area[gi])) }
        var componentCounts = [Double](repeating: 0, count: n)
        if c != 0 { let q = sumShape(area); for k in 0..<n { componentCounts[k] += c * q[k] } }
        if f != 0 { let q = escShape(area); for k in 0..<n { componentCounts[k] += f * q[k] } }

        // Sigma of c and f: the term's shape with the fit's other columns projected out.
        func sigmaOf(_ q: [Double]) -> Double? {
            let nn = dFinal.nonNegative, ff = dFinal.free
            let keep = (0..<nn.cols).filter { $0 >= dFinal.areaColumns.count || dFinal.areaColumns[$0].supported }
            var cols: [[Double]] = keep.map { Array(nn.column($0)) }
            for j in 0..<ff.cols { cols.append(Array(ff.column(j))) }
            var qp = q
            if !cols.isEmpty, let sol = FitLinearAlgebra.leastSquares(ColumnMatrix(columns: cols), ColumnMatrix(columns: [q])) {
                let proj = ColumnMatrix(columns: cols).times(Array(sol.x.data))
                for k in 0..<n { qp[k] -= proj[k] }
            }
            let nrm = qp.reduce(0) { $0 + $1 * $1 }
            guard nrm > 1e-12 else { return nil }
            if isML {
                let fisher = (0..<n).reduce(0.0) { $0 + qp[$1] * qp[$1] / max(fit.model[$1], 1e-6) }
                return fisher > 0 ? (1 / fisher).squareRoot() : nil
            }
            var v = 0.0
            for k in 0..<n { v += max(fit.model[k], 0) * qp[k] * qp[k] }
            return v.squareRoot() / nrm
        }
        let cSigma: Double? = model.sumPeaks && !pairs.isEmpty ? sigmaOf(sumShape(area)) : nil
        let fSigma: Double? = model.commonEscapeFraction && escColumns.contains(where: { $0 != nil }) ? sigmaOf(escShape(area)) : nil

        var params: [String] = []
        if model.sumPeaks {
            let how = model.sumCoefficient == nil ? "estimated" : "fixed"
            let cs = String(format: "%.4g", c)
            params.append("sum peaks: \(pairs.count) pair\(pairs.count == 1 ? "" : "s") of the \(model.parentCount) strongest alpha lines; area = c m A_i A_j, m = 1 (same line) or 2 (two lines); c = tau/T = \(cs) (\(how))" + (cAtBound ? ", held at 0: no sum peak in the data" : ""))
        }
        if model.commonEscapeFraction {
            let how = model.escapeFraction == nil ? "estimated" : "fixed"
            params.append(String(format: "escape peaks: one common fraction f = %.4g (%@) of each parent group's area, shifted down by Si K-alpha (%.4f keV), for %d group%@",
                                 f, how, XRayLines.line("Si_Ka")!.energy, escComponents.count, escComponents.count == 1 ? "" : "s"))
        }
        params.append("solver: alternating Gauss-Newton on the line areas and least squares on the coefficients, \(iterations) iteration\(iterations == 1 ? "" : "s"), " + (converged ? "converged" : "NOT converged"))
        params.append("no reference implementation; planted-truth tests only")
        fit.escapeLabel = params.filter { $0.hasPrefix("sum peaks") || $0.hasPrefix("escape peaks") }.joined(separator: "; ")
        if fit.escapeLabel.isEmpty { fit.escapeLabel = baseline.escapeLabel }
        if !converged { fit.warnings.append("sum/escape model: the alternation did not converge in \(maxIt) iterations") }
        fit.warnings.append("sum/escape model (sum peaks c m A_i A_j, one common escape fraction; no reference implementation, planted-truth tests only): the line areas are conditional on its coefficients")

        return SumEscapeResult(fit: fit, baseline: baseline, sumCoefficient: model.sumPeaks ? c : nil, sumCoefficientSigma: cSigma,
                               sumCoefficientAtBound: cAtBound, sumPeaks: sumComponents,
                               escapeFraction: model.commonEscapeFraction ? f : nil, escapeFractionSigma: fSigma,
                               escapePeaks: escComponents, componentCounts: componentCounts, iterations: iterations, converged: converged,
                               parameters: params, validation: validation)
    }
}
