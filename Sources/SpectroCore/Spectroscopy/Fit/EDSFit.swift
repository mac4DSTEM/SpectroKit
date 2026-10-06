//
//  EDSFit.swift
//  Role: The spectrum fit as one call: line model + background + method -> areas, their
//        covariance, the model, and the fit-quality numbers, with every setting that shaped them
//        named in the result (the footer's source of truth).
//

import Foundation

package nonisolated enum FitMethod: Sendable, Equatable {
    /// The named default: unweighted least squares, non-negative areas.
    case leastSquares
    case poissonML(IRLSSettings)
}

package nonisolated struct FitSettings: Sendable, Equatable {
    package var elements: [String]
    package var resolutionMnKaEV: Double
    package var beamEnergy: Double
    /// Fitted energy range in keV; nil bound = the axis end.
    package var fitFrom: Double?
    package var fitTo: Double?
    package var background: FitBackground
    package var escapePeaks: Bool = true
    package var referenceShapes: ReferenceShapes = .none
    package var method: FitMethod = .leastSquares

    package init(elements: [String], resolutionMnKaEV: Double, beamEnergy: Double,
                 fitFrom: Double? = nil, fitTo: Double? = nil, background: FitBackground,
                 escapePeaks: Bool = true, referenceShapes: ReferenceShapes = .none,
                 method: FitMethod = .leastSquares) {
        self.elements = elements; self.resolutionMnKaEV = resolutionMnKaEV; self.beamEnergy = beamEnergy
        self.fitFrom = fitFrom; self.fitTo = fitTo; self.background = background
        self.escapePeaks = escapePeaks; self.referenceShapes = referenceShapes; self.method = method
    }

    /// The app's default: continuum with the Al K step, 0.2 keV to the beam energy or the axis end,
    /// escape peaks on, no reference shapes, unweighted least squares. The 0.2 keV start keeps the
    /// zero-energy noise peak out (a stated choice, not a measurement).
    /// `efficiency`: the detector model of the continuum (`SDDEfficiency` for the registered default, see
    /// `ContinuumForm.weakLineBiasNote`); nil gives the Kramers-only form, which IS the default: the registered selection (report2) had no tie
    /// clause, 397 (with eps) vs 402 (without) counts at se ~33 is unresolved, so the no-filler rule decides: eps would add a generic EPQ SDD
    /// model to every footer for zero measured gain. eps stays an option.
    package static func standard(elements: [String], axis: EnergyAxis, resolutionMnKaEV: Double,
                                 beamEnergy: Double, efficiency: (any DetectorEfficiency)? = nil) -> FitSettings {
        FitSettings(elements: elements, resolutionMnKaEV: resolutionMnKaEV, beamEnergy: beamEnergy,
                    fitFrom: 0.2, fitTo: min(axis.highValue, beamEnergy),
                    background: .continuum(ContinuumForm(beamEnergy: beamEnergy, efficiency: efficiency)))
    }
}

/// Conforms to `FittedAmplitudes` (Statistics/SigmaTerms.swift): `values`, row-major `covariance`.
package nonisolated struct EDSFitResult: FittedAmplitudes, Sendable {
    package var groupIDs: [String]
    /// Line areas in counts, one per group (alpha line + its tied family), >= 0.
    package var values: [Double]
    /// Covariance of `values`, row-major (see `covarianceKind`).
    package var covariance: [Double]
    package var covarianceKind: String
    /// False for a group with no support in the fitted range (its area is reported 0, variance 0).
    package var supported: [Bool]
    /// True where the area is held at 0 by the non-negativity constraint.
    package var atBound: [Bool]
    /// Si-escape areas per group; nil where the group has no line above the Si K edge.
    package var escapeValues: [Double?]
    package var backgroundNames: [String]
    package var backgroundCoefficients: [Double]

    package var channels: Range<Int>
    package var model: [Double]
    package var residual: [Double]
    /// (data - model) / sqrt(max(model, `standardizedFloor`)); the floor keeps r finite as model -> 0.
    package var standardizedResidual: [Double]
    package static let standardizedFloor = 1.0
    package var negativeModelChannels: Int

    package var degreesOfFreedom: Int
    /// RSS / dof with unit variance, as hyperspy's `red_chisq` (unweighted).
    /// DEVIATION (hyperspy): hyperspy divides by (n - p - 1) (`model.py:1723`, `chisq / (-dof + n - 1)` with its
    /// `dof` = the parameter count p); this divides by the textbook n - p. The RSS is identical; the FePt pin
    /// 921.3672657 is reproduced as RSS / (n - p - 1) in the tests.
    package var reducedChiSquared: Double
    /// Pearson chi^2 with the model as variance / dof.
    package var pearsonReducedChiSquared: Double
    package var deviance: Double
    package var reducedDeviance: Double

    // Settings as run, for the footer.
    package var methodLabel: String
    package var referenceShapesLabel: String
    package var escapeLabel: String
    /// The background as run, named (the continuum form and orders, or the parity polynomial).
    package var backgroundLabel: String
    /// How the solver ended: "converged", "stationary (no deviance decrease, KKT satisfied)", "cap reached", "stalled (KKT violated)".
    package var exit: String
    /// Everything a footer must say that is not a number: dropped lines, ML with a negative model, a large escape ratio, a cap.
    package var warnings: [String]
    /// Lines the model could not place (see `EDSLineModel.droppedLines`).
    package var droppedLines: [String]
    /// Si-escape area / parent area per group; nil where there is no escape column. Above 0.05 is flagged in `warnings`.
    package var escapeRatios: [Double?]
    package var iterations: Int
    package var converged: Bool
    package var irls: IRLSSettings?
    package var devianceHistory: [Double]

    package var count: Int { values.count }
    package func sigma(at i: Int) -> Double { max(covariance[i * count + i], 0).squareRoot() }
}

package nonisolated enum EDSFitError: Error, Equatable {
    case noChannels
    case lengthMismatch
    /// A reference profile does not have one value per channel of the axis.
    case referenceShapeLength(name: String, expected: Int, got: Int)
    case referenceShapeNotFinite(name: String)
    /// A `.lineAmplitude` tie names a group the model does not have.
    case referenceShapeUnknownGroup(name: String, group: String)
}

package nonisolated enum EDSFit {

    package static func run(counts: [Double], axis: EnergyAxis, settings: FitSettings,
                            channels explicit: Range<Int>? = nil, computeCovariance: Bool = true) throws -> EDSFitResult {
        guard counts.count == axis.size else { throw EDSFitError.lengthMismatch }
        let channels = explicit ?? axis.fitChannels(from: settings.fitFrom, to: settings.fitTo)
        guard !channels.isEmpty else { throw EDSFitError.noChannels }
        let model = EDSLineModel.build(elements: settings.elements, axis: axis, beamEnergy: settings.beamEnergy,
                                       resolutionMnKaEV: settings.resolutionMnKaEV, escapePeaks: settings.escapePeaks)
        try validate(settings.referenceShapes, axis: axis, model: model)
        let design = LinearDesign.build(model: model, axis: axis, channels: channels, background: settings.background,
                                        shapes: settings.referenceShapes, counts: counts)
        return fit(design: design, model: model, counts: counts, settings: settings, computeCovariance: computeCovariance)
    }

    /// The reference-shape preconditions, as errors rather than traps in `LinearDesign.build`.
    package static func validate(_ shapes: ReferenceShapes, axis: EnergyAxis, model: EDSLineModel) throws {
        for s in shapes.shapes {
            guard s.profile.count == axis.size else {
                throw EDSFitError.referenceShapeLength(name: s.name, expected: axis.size, got: s.profile.count)
            }
            guard s.profile.allSatisfy(\.isFinite) else { throw EDSFitError.referenceShapeNotFinite(name: s.name) }
            if case .lineAmplitude(let group, _) = s.tie, !model.groups.contains(where: { $0.id == group }) {
                throw EDSFitError.referenceShapeUnknownGroup(name: s.name, group: group)
            }
        }
    }

    /// Fits a prebuilt design (the refinement builds many).
    package static func fit(design: LinearDesign, model: EDSLineModel, counts: [Double], settings: FitSettings,
                            computeCovariance: Bool = true) -> EDSFitResult {
        let channels = design.channels
        let y = channels.map { counts[$0] }
        let n = y.count
        let nn = design.nonNegative, ff = design.free
        let target = (0..<n).map { y[$0] - design.offset[$0] }

        var x: [Double], b: [Double]
        var iterations = 0, converged = true
        var exit = "converged"
        var irls: IRLSSettings?
        var history: [Double] = []
        let label: String
        switch settings.method {
        case .leastSquares:
            let s = LeastSquaresFit.solve(nonNegative: nn, free: ff, y: target)
            x = s.nonNegative; b = s.free; iterations = s.iterations; converged = s.converged
            exit = s.converged ? "converged" : "cap reached"
            label = LeastSquaresFit.label
        case .poissonML(let ir):
            let s = PoissonMLFit.solve(nonNegative: nn, free: ff, y: y, offset: design.offset, settings: ir)
            x = s.nonNegative; b = s.free; iterations = s.iterations; converged = s.converged
            exit = s.exit.rawValue
            irls = ir; history = s.devianceHistory
            label = PoissonMLFit.label(ir)
        }

        var mu = nn.times(x)
        if ff.cols > 0 { let g = ff.times(b); for i in 0..<n { mu[i] += g[i] } }
        for i in 0..<n { mu[i] += design.offset[i] }
        let residual = (0..<n).map { y[$0] - mu[$0] }
        let std = (0..<n).map { residual[$0] / max(mu[$0], EDSFitResult.standardizedFloor).squareRoot() }
        let rss = residual.reduce(0) { $0 + $1 * $1 }
        let pearson = (0..<n).reduce(0.0) { $0 + residual[$1] * residual[$1] / max(mu[$1], EDSFitResult.standardizedFloor) }
        let floor = irls?.muFloor ?? 1e-6
        let dev = PoissonMLFit.deviance(y: y, mu: mu, floor: floor)
        let dof = n - design.parameterCount
        let dofD = dof > 0 ? Double(dof) : Double.nan

        // Split coefficients back to groups / escapes.
        let g = model.groups.count
        var values = [Double](repeating: 0, count: g)
        var esc = [Double?](repeating: nil, count: g)
        var supported = [Bool](repeating: true, count: g)
        var atBound = [Bool](repeating: false, count: g)
        var colOfGroup = [Int](repeating: -1, count: g)
        for (k, c) in design.areaColumns.enumerated() {
            switch c.kind {
            case .line(let gi):
                values[gi] = x[k]; supported[gi] = c.supported; colOfGroup[gi] = k
                atBound[gi] = c.supported && x[k] <= 0
            case .escape(let gi): esc[gi] = c.supported ? x[k] : 0
            case .background: break
            }
        }

        // Covariance of the line areas.
        var cov = [Double](repeating: .nan, count: g * g)
        var covKind = "not computed"
        if computeCovariance {
            // Covariance columns: the supported area columns, then every background column (all of
            // `nn` after the areas, then the free ones). Index j below is an index into `nn` columns.
            let supportedCols = nn.cols > 0 ? (0..<nn.cols).filter { $0 >= design.areaColumns.count || design.areaColumns[$0].supported } : []
            let k = supportedCols.count + ff.cols
            if k > 0, n >= k {
                var cols: [[Double]] = supportedCols.map { Array(nn.column($0)) }
                for j in 0..<ff.cols { cols.append(Array(ff.column(j))) }
                // Unit-norm columns for conditioning.
                let norms = cols.map { c in max(c.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-300) }
                var scaled = ColumnMatrix(columns: cols.enumerated().map { (j, c) in c.map { $0 / norms[j] } })
                var fullCov: ColumnMatrix?
                switch settings.method {
                case .leastSquares:
                    // Sandwich: Var(y_i) = mu_i (Poisson), estimator theta = D^+ y.
                    if let (_, kmat) = FitLinearAlgebra.pseudoInverse(scaled) {
                        var c = ColumnMatrix(rows: k, cols: k)
                        for i in 0..<n {
                            let v = max(mu[i], 0)
                            if v == 0 { continue }
                            for a in 0..<k { let ka = kmat.data[i * k + a] * v
                                for bb in 0..<k { c.data[bb * k + a] += ka * kmat.data[i * k + bb] } }
                        }
                        fullCov = c
                    }
                    covKind = "sandwich covariance of unweighted least squares, Var(data) = model (Poisson); unconstrained: bound-active columns counted free"
                case .poissonML(let ir):
                    let w = mu.map { 1 / max($0, ir.muFloor).squareRoot() }
                    scaled = scaled.scalingRows(w)
                    fullCov = FitLinearAlgebra.pseudoInverse(scaled)?.gramInverse
                    covKind = "inverse expected Fisher information (Poisson); unconstrained: bound-active columns counted free"
                }
                if fullCov == nil { covKind = "not computed (the design is numerically rank deficient)" }
                if let c = fullCov {
                    for (ia, ja) in supportedCols.enumerated() {
                        guard ja < design.areaColumns.count, case .line(let gi) = design.areaColumns[ja].kind else { continue }
                        for (ib, jb) in supportedCols.enumerated() {
                            guard jb < design.areaColumns.count, case .line(let gj) = design.areaColumns[jb].kind else { continue }
                            cov[gi * g + gj] = c.data[ib * k + ia] / (norms[ia] * norms[ib])
                        }
                    }
                }
            }
            for gi in 0..<g where !supported[gi] { for gj in 0..<g { cov[gi * g + gj] = 0; cov[gj * g + gi] = 0 } }
        }

        let escLabel: String
        if !settings.escapePeaks { escLabel = "escape peaks: off (eXSpy parity)" }
        else {
            let n = model.groups.filter { !$0.escapes.isEmpty }.count
            escLabel = n == 0
                ? "escape peaks: none (no line above the Si K edge, 1.839 keV)"
                : "escape peaks: fitted for \(n) line group\(n == 1 ? "" : "s") above the Si K edge (1.839 keV)"
        }
        var escRatios = [Double?](repeating: nil, count: g)
        var warnings: [String] = model.droppedLines.map { "line dropped: " + $0 }
        for gi in 0..<g {
            if let e = esc[gi], values[gi] > 0 {
                escRatios[gi] = e / values[gi]
                if e / values[gi] > 0.05 {
                    warnings.append("\(model.groups[gi].id): Si-escape/parent ratio \(String(format: "%.1f", 100 * e / values[gi])) % exceeds 5 %: an unmodelled line near the escape energy is likely (the 5 % flag is a sanity bound; the SDD Si escape is about 1 % at Cu K\u{03B1})")
                }
            }
        }
        let negMu = mu.reduce(0) { $0 + ($1 < 0 ? 1 : 0) }
        if irls != nil, negMu > 0 {
            warnings.append("Poisson ML with a model below zero in \(negMu) channels (a signed background); the deviance clamps them at \(irls!.muFloor), so the maximum is not the likelihood's")
        }
        if !converged { warnings.append("solver exit: " + exit) }
        let bgLabel: String
        switch settings.background {
        case .continuum(let form):
            bgLabel = form.label
            warnings.append(ContinuumForm.weakLineBiasNote)
        case .polynomial(let o): bgLabel = "background: polynomial order \(o) over the fitted range, signed coefficients (eXSpy parity)"
        case .none: bgLabel = "background: none"
        }
        return EDSFitResult(
            groupIDs: design.groupIDs, values: values, covariance: cov, covarianceKind: covKind,
            supported: supported, atBound: atBound, escapeValues: esc,
            backgroundNames: design.backgroundColumns.map(\.name),
            backgroundCoefficients: design.backgroundCoefficients(nonNegative: x, free: b),
            channels: channels, model: mu, residual: residual, standardizedResidual: std,
            negativeModelChannels: mu.reduce(0) { $0 + ($1 < 0 ? 1 : 0) },
            degreesOfFreedom: dof, reducedChiSquared: rss / dofD, pearsonReducedChiSquared: pearson / dofD,
            deviance: dev, reducedDeviance: dev / dofD,
            methodLabel: label, referenceShapesLabel: settings.referenceShapes.label, escapeLabel: escLabel,
            backgroundLabel: bgLabel, exit: exit, warnings: warnings, droppedLines: model.droppedLines, escapeRatios: escRatios,
            iterations: iterations, converged: converged, irls: irls, devianceHistory: history)
    }
}
