//
//  EELSMLLS.swift
//  Role: the multiple linear least squares (MLLS) fit of an EELS spectrum image: HyperSpy's `Model1D.fit(optimizer="lstsq")` on exSpy's EELS model
//        with the power-law exponent fixed. The model is then linear in the power law's amplitude A and in each edge's intensity, so the
//        amplitudes come from ONE least-squares solve per pixel, with their standard errors from `hyperspy.misc.model_tools._calculate_covariance`:
//        covariance = RSS / (n - k) x inv(F^T F), perror = |x| sqrt(diag(covariance)), where F's columns are the components times their
//        coefficients; that is the textbook s sqrt(diag(inv(X^T X))) of ordinary least squares, which is what is computed here.
//
//  The columns are the existing edge machinery's (`EELSEdgeBasis`: the dft GOS cross sections summed over the shells of a master, or
//  convolved with the pixel's low loss), the power law E^-r x channel width, and any given reference shapes. The fit window is HyperSpy's
//  `set_signal_range(start, end)`: `value_range_to_indices` and both ends included (`i2 + 1`), so an `endEnergyEV` of nil keeps the last channel
//  (the smart fit of `EELSModelFit` leaves it out; that is exSpy's `smart_fit` stage, not this).
//
//  DEVIATIONS (HyperSpy): (1) the unconstrained fit has no bounds: an intensity can come out negative on noise, as `lstsq` gives it.
//  (2) `numpy.linalg.lstsq(rcond=None)` drops every singular direction below eps x max(M, N) of the largest; with unscaled columns (a low loss of
//  area 1e6 puts the edge columns 1e15 above the power law's) it silently sets the power law to zero. The columns are scaled to unit length here
//  before the QR solve, which changes nothing mathematically and keeps that direction; the pins use unit-area low losses, where HyperSpy is sound.
//  (3) a rank-deficient or singular design (a column of zeros, two columns equal) is a pixel with `.fitFailed`; HyperSpy raises `LinAlgError`
//  for its covariance. CPU float64 only: one small QR per pixel.
//

import Foundation
import SpectroCore

/// Where the power-law exponent r comes from. The fit is linear only for a given r.
public enum EELSBackgroundExponent: Sendable, Equatable {
    /// The same r at every pixel.
    case given(Double)
    /// One r per pixel (row-major, `nx * ny` values).
    case perPixel([Double])
    /// exSpy's `two_area_background_estimation()` at each pixel: over `[start, first edge - preEdgeSafeWindowEV]`.
    /// A pixel the estimate fails at is unavailable.
    case twoArea
}

/// What to fit and where.
public struct EELSMLLSOptions: Sendable, Equatable {
    public var exponent: EELSBackgroundExponent
    /// The first energy of the fit window (HyperSpy `set_signal_range(start, ...)`); nil is the axis start.
    public var startEnergyEV: Double?
    /// The last energy of the fit window, included; nil is the axis end.
    public var endEnergyEV: Double?
    /// exSpy `_preedge_safe_window_width`: the two-area window ends this far below the first edge.
    public var preEdgeSafeWindowEV: Double
    /// Extra fixed shapes to fit besides the background and the edges (for example a measured edge fine structure): each one value per
    /// channel of the core-loss axis, in counts per channel. They enter the fit as one more linear amplitude each.
    public var references: [[Double]]

    public init(exponent: EELSBackgroundExponent = .twoArea, startEnergyEV: Double? = nil, endEnergyEV: Double? = nil,
                preEdgeSafeWindowEV: Double = 2, references: [[Double]] = []) {
        self.exponent = exponent; self.startEnergyEV = startEnergyEV; self.endEnergyEV = endEnergyEV
        self.preEdgeSafeWindowEV = preEdgeSafeWindowEV; self.references = references
    }
}

/// One fitted amplitude and its standard error (`Parameter.std` of HyperSpy).
public struct EELSAmplitude: Sendable, Equatable {
    public let value: Double
    /// nil when the window has no degrees of freedom left (as many channels as amplitudes).
    public let standardError: Double?
}

/// One pixel's MLLS answer. A pixel with no answer has a reason and no numbers.
public struct EELSMLLSPixel: Sendable, Equatable {
    /// The power law's A (per eV, as exSpy: a channel holds A x E^-r x channel width).
    public let background: EELSAmplitude?
    /// The exponent used at this pixel.
    public let exponent: Double?
    /// One per master, in `EELSMLLSResult.edges` order (exSpy's `intensity.value`).
    public let intensities: [EELSAmplitude]
    /// One per entry of `EELSMLLSOptions.references`.
    public let references: [EELSAmplitude]
    public let residualSumOfSquares: Double?
    public let degreesOfFreedom: Int
    public let unavailable: EELSUnavailable?
}

public nonisolated enum EELSMLLSError: Error, Equatable, Sendable {
    /// The exponent list does not hold one value per pixel.
    case exponentCountMismatch(expected: Int, got: Int)
    case invalidExponent
    /// A reference shape does not have the core-loss axis's number of channels, or holds a value that is not finite.
    case invalidReference(index: Int)
    /// The fit window holds no more channels than there are amplitudes to fit.
    case windowTooNarrow(channels: Int, amplitudes: Int)
    case invalidWindow(startEV: Double, endEV: Double)
}

/// The fit of an image: per pixel the amplitudes of the background, the edges and the references, with standard errors.
public struct EELSMLLSResult: Sendable {
    public let nx: Int
    public let ny: Int
    /// The masters, in onset order; each stands for every shell of its element and family (`shells`).
    public let edges: [CoreLossEdge]
    public let shells: [[CoreLossEdge]]
    /// `pixels[pixel]`.
    public let pixels: [EELSMLLSPixel]
    /// The energies of the first and last channel of the fit window.
    public let windowEV: ClosedRange<Double>
    /// The channels of the fit window, `first ... last`.
    public let windowChannels: ClosedRange<Int>
    public let convolved: Bool
    public let methodName: String
    /// "none": unvalidated against a standard of known composition.
    public let validation: String
    fileprivate let basis: EELSEdgeBasis
    fileprivate let references: [[Double]]

    /// The fitted model at one pixel over the whole core-loss axis (power law, edges with the low-loss convolution when one was given, and the
    /// references), as exSpy's `as_signal()`. nil where the pixel has no answer.
    public func modelCurve(pixel: Int) -> [Double]? {
        guard pixel >= 0, pixel < pixels.count else { return nil }
        let px = pixels[pixel]
        guard let bg = px.background, let r = px.exponent else { return nil }
        var curve = [Double](repeating: 0, count: basis.channels)
        for k in 0 ..< basis.channels where basis.energies[k] > 0 { curve[k] = bg.value * Libm.pow(basis.energies[k], -r) * basis.scale }
        for g in 0 ..< edges.count {
            let column = basis.column(group: g, pixel: pixel, rows: 0 ..< basis.channels)
            for k in 0 ..< basis.channels { curve[k] += px.intensities[g].value * column[k] }
        }
        for (i, ref) in references.enumerated() { for k in 0 ..< basis.channels { curve[k] += px.references[i].value * ref[k] } }
        return curve
    }
}

public enum EELSMLLS {
    public static let methodName = "EELS multiple linear least squares: power law (fixed exponent) + dft GOS edges, QR solve"

    /// The MLLS fit of every pixel not masked out (`mask[p] == true` fits, false skips).
    /// - Throws: `EELSModelError` as the model fit does (edges, microscope, low loss, mask, the pre-edge window), `EELSMLLSError` for the
    ///   exponent, the references and the window.
    public static func fit(
        coreLoss: CoreLossSpectrumImage, edges: [CoreLossEdge], microscope: EELSMicroscope, lowLoss: LowLossSpectrumImage? = nil,
        mask: PixelMask? = nil, options: EELSMLLSOptions = .init(),
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> EELSMLLSResult {
        let np = coreLoss.pixelCount, n = coreLoss.channels
        let modelOptions = EELSModelOptions(startEnergyEV: options.startEnergyEV, preEdgeSafeWindowEV: options.preEdgeSafeWindowEV)
        let setup = try EELSModelFit.prepare(coreLoss: coreLoss, edges: edges, options: modelOptions, mask: mask, lowLoss: lowLoss)
        let axis = setup.axis
        // The window: HyperSpy set_signal_range(start, end), both ends included.
        let startEV = options.startEnergyEV ?? axis.lowValue, endEV = options.endEnergyEV ?? axis.highValue
        guard startEV.isFinite, endEV.isFinite, startEV <= endEV else { throw EELSMLLSError.invalidWindow(startEV: startEV, endEV: endEV) }
        let (first, last) = try axis.valueRangeToIndices(startEV, endEV)
        let window = first ..< (last + 1)
        guard window.lowerBound == setup.start else { throw EELSMLLSError.invalidWindow(startEV: startEV, endEV: endEV) }
        let all = setup.groups.flatMap(\.shells)
        for shell in all where shell.onsetEV > axis.energy(ofChannel: last) {
            throw EELSModelError.noEdgeInRange(fromEV: axis.energy(ofChannel: first), toEV: axis.energy(ofChannel: last))
        }
        for (i, ref) in options.references.enumerated() where ref.count != n || !ref.allSatisfy(\.isFinite) {
            throw EELSMLLSError.invalidReference(index: i)
        }
        let m = setup.groups.count, k = 1 + m + options.references.count
        guard window.count > k else { throw EELSMLLSError.windowTooNarrow(channels: window.count, amplitudes: k) }

        let exponents: [Double?]
        switch options.exponent {
        case .given(let r):
            guard r.isFinite else { throw EELSMLLSError.invalidExponent }
            exponents = [Double?](repeating: r, count: np)
        case .perPixel(let list):
            guard list.count == np else { throw EELSMLLSError.exponentCountMismatch(expected: np, got: list.count) }
            guard list.allSatisfy(\.isFinite) else { throw EELSMLLSError.invalidExponent }
            exponents = list
        case .twoArea:
            let estimate = try EELSModelFit.twoAreaBackground(coreLoss: coreLoss, edges: edges, options: modelOptions, mask: mask)
            exponents = estimate.map { $0?.r }
        }

        let basis = try EELSEdgeBasis(axis: axis, groups: setup.groups.map(\.shells), microscope: microscope, lowLoss: lowLoss)
        let logE = window.map { log(basis.energies[$0]) }
        let refColumns = options.references.map { Array($0[window]) }
        let slots = EELSSlots<EELSMLLSPixel?>(count: np, initial: nil)
        try coreLoss.counts.withUnsafeBufferPointer { counts in
            nonisolated(unsafe) let input = counts
            try EELSParallel.forEachPixel(count: np, cancelled: cancelled, progress: progress) { p in
                if let mask, !mask[p] { slots.set(p, failed(.masked, references: options.references.count, edges: m)); return }
                guard let r = exponents[p] else { slots.set(p, failed(.fitFailed, references: options.references.count, edges: m)); return }
                let y = Array(UnsafeBufferPointer(start: input.baseAddress! + p * n + window.lowerBound, count: window.count))
                var columns: [[Double]] = [logE.map { exp(-r * $0) * basis.scale }]
                for g in 0 ..< m { columns.append(basis.column(group: g, pixel: p, rows: window)) }
                columns.append(contentsOf: refColumns)
                guard let s = solve(columns: columns, y: y) else {
                    slots.set(p, failed(.fitFailed, references: options.references.count, edges: m)); return
                }
                let dof = window.count - k
                func amplitude(_ j: Int) -> EELSAmplitude { EELSAmplitude(value: s.x[j], standardError: s.standardError[j]) }
                slots.set(p, EELSMLLSPixel(
                    background: amplitude(0), exponent: r, intensities: (0 ..< m).map { amplitude(1 + $0) },
                    references: (0 ..< options.references.count).map { amplitude(1 + m + $0) },
                    residualSumOfSquares: s.rss, degreesOfFreedom: dof, unavailable: nil))
            }
        }
        return EELSMLLSResult(
            nx: coreLoss.nx, ny: coreLoss.ny, edges: setup.groups.map(\.master), shells: setup.groups.map(\.shells), pixels: slots.values.map { $0! },
            windowEV: axis.energy(ofChannel: first) ... axis.energy(ofChannel: last), windowChannels: first ... last,
            convolved: basis.convolved, methodName: methodName, validation: "none", basis: basis, references: options.references)
    }

    private static func failed(_ why: EELSUnavailable, references: Int, edges: Int) -> EELSMLLSPixel {
        EELSMLLSPixel(background: nil, exponent: nil, intensities: [], references: [], residualSumOfSquares: nil, degreesOfFreedom: 0, unavailable: why)
    }

    /// Ordinary least squares `min |y - X x|^2` for the columns `columns` (each one window long): the coefficients, their standard errors
    /// `s sqrt(diag((X^T X)^-1))` with `s^2 = RSS / (n - k)` (HyperSpy's `_calculate_covariance`), and the residual sum of squares.
    /// The columns are scaled to unit length for the QR (see the file header); nil for a design that is not of full numerical rank, or
    /// with a column that is zero or not finite.
    static func solve(columns: [[Double]], y: [Double]) -> (x: [Double], standardError: [Double?], rss: Double)? {
        let rows = y.count, k = columns.count
        guard rows > k, y.allSatisfy(\.isFinite) else { return nil }
        var norms = [Double](repeating: 0, count: k)
        var scaled = columns
        for j in 0 ..< k {
            var sum = 0.0
            for v in columns[j] { sum += v * v }
            let norm = sum.squareRoot()
            guard norm.isFinite, norm > 0 else { return nil }
            norms[j] = norm
            for i in 0 ..< rows { scaled[j][i] = columns[j][i] / norm }
        }
        guard let inverse = FitLinearAlgebra.pseudoInverse(ColumnMatrix(columns: scaled)) else { return nil }
        // x_j (scaled) = sum_i K[j, i] y[i]; K is k x rows, column-major (element (j, i) at i * k + j)
        var xs = [Double](repeating: 0, count: k)
        inverse.k.data.withUnsafeBufferPointer { kd in
            for i in 0 ..< rows { let yi = y[i]; for j in 0 ..< k { xs[j] += kd[i * k + j] * yi } }
        }
        var rss = 0.0
        for i in 0 ..< rows {
            var model = 0.0
            for j in 0 ..< k { model += scaled[j][i] * xs[j] }
            let d = y[i] - model
            rss += d * d
        }
        guard rss.isFinite else { return nil }
        let x = (0 ..< k).map { xs[$0] / norms[$0] }
        guard x.allSatisfy(\.isFinite) else { return nil }
        let dof = rows - k
        let variance = rss / Double(dof)
        let errors: [Double?] = (0 ..< k).map { j in
            let v = variance * inverse.gramInverse[j, j] / (norms[j] * norms[j])
            return v >= 0 && v.isFinite ? v.squareRoot() : nil
        }
        return (x, errors, rss)
    }
}

extension EELSQuantification {
    /// at% and wt% of `symbols` at every pixel of an MLLS `result`, as `composition(_: EELSModelResult, symbols:)` does for the model fit: an
    /// element's amount is its master edge's intensity (the first independent edge in fit order when an element has K and L). The fit is
    /// unconstrained, so an absent element's amount scatters around zero: an amount at or below zero is not detected (`notDetected`), counts
    /// as 0 at% and 0 wt%, and the others are normalised among themselves (kit decision, consistent with the non-negative model fit, which
    /// gives an absent element 0; exSpy has no EELS composition, and its EDS Cliff-Lorimer passes a negative line through as a negative
    /// fraction). `notDetected == false` only means the amount is above zero, not above a detection limit. Clamping per pixel biases an
    /// average of pixel compositions upward for an absent element: quantify a summed region instead. The pixel is unavailable
    /// (`noComposition`) only when no amount is above zero. No uncertainty on the percentages (open item).
    public static func composition(_ result: EELSMLLSResult, symbols: [String]) throws -> [EELSCompositionPixel] {
        var columns: [Int] = []
        if let dup = symbols.enumerated().first(where: { i, s in symbols[..<i].contains(s) })?.element { throw EELSModelError.symbolNotFitted(dup + " (listed twice)") }
        for s in symbols {
            guard let g = result.edges.firstIndex(where: { $0.element == s }), atomicMasses[s] != nil else { throw EELSModelError.symbolNotFitted(s) }
            columns.append(g)
        }
        let masses = symbols.map { atomicMasses[$0]! }
        return result.pixels.map { pixel in
            guard pixel.unavailable == nil else {
                return EELSCompositionPixel(atomicPercent: [], weightPercent: [], unavailable: pixel.unavailable)
            }
            let fitted = columns.map { pixel.intensities[$0].value }
            // An amount at or below zero is not detected and counts as 0, as the non-negative model fit gives an absent element.
            let notDetected = fitted.map { !($0 > 0) }
            let amounts = fitted.map { $0 > 0 ? $0 : 0 }
            let atoms = amounts.reduce(0, +)
            let weights = zip(amounts, masses).map { $0 * $1 }.reduce(0, +)
            guard atoms > 0, weights > 0 else {
                return EELSCompositionPixel(atomicPercent: [], weightPercent: [], unavailable: .noComposition)
            }
            return EELSCompositionPixel(atomicPercent: amounts.map { 100 * $0 / atoms },
                                        weightPercent: zip(amounts, masses).map { 100 * $0 * $1 / weights }, unavailable: nil,
                                        notDetected: notDetected)
        }
    }
}
