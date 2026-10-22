//
//  EELSModelFit.swift
//  Role: exSpy's EELS model (`exspy/models/eelsmodel.py` at 7185a4d1) on the dft GOS tables: a power-law background plus the cross sections of
//        the requested edges, fitted per pixel (docs/design/eels-task-16.md section 6.2). `two_area_background_estimation`,
//        `fit_background`, `smart_fit` and the low-loss convolution of the edge components are ported; `quantify` is `EELSModelResult.quantifyText`.
//
//  DEVIATION (exSpy): `Model1D.fit` is an unbounded Levenberg-Marquardt that stops short of the minimum (the EDX precedent, `LeastSquaresFit`:
//  1e-4 relative). The model is linear in the background amplitude A and the edge intensities for a fixed exponent r, so each pixel is solved
//  by variable projection: non-negative least squares for A and the intensities at each r, a grid over `exponentRange` and Brent's minimiser
//  for r. The cascade of `smart_fit` (background, then edges one at a time) only seeds LM; its last stage is the whole model over the whole
//  range, which is the one minimum solved here (the last channel is left out, as exSpy's `value_range_to_indices(start, axis end)` does).
//  Shells of one element and one family (K, L) share one intensity: exSpy's twins, the lexicographically last name the master.
//

import Accelerate
import Foundation
import SpectroCore

/// What to fit and where.
public struct EELSModelOptions: Sendable, Equatable {
    /// exSpy `start_energy`: the first energy of the fit; nil is the axis start.
    public var startEnergyEV: Double? = nil
    /// exSpy `_preedge_safe_window_width`: the pre-edge window ends this far below the first edge.
    public var preEdgeSafeWindowEV: Double = 2
    /// The power-law exponent r is searched in this range. exSpy's is unbounded; a fit that ends on a bound is flagged (`exponentAtBound`).
    public var exponentRange: ClosedRange<Double> = 0 ... 10
    /// Per-edge windows only: each fitted edge (amplitude times its cross section on every channel) is subtracted from the spectrum before the
    /// next edge's background and amplitude are fitted. Off by default: on the owner's real GMS maps the convolved C K model, fitted on its
    /// 30 eV signal window, overshoots the data 150 eV further up and leaves O K nothing to fit (2026-10-23); the planted tests hold the on case.
    public var stripPrecedingEdges: Bool = false
    public init(startEnergyEV: Double? = nil, preEdgeSafeWindowEV: Double = 2, exponentRange: ClosedRange<Double> = 0 ... 10, stripPrecedingEdges: Bool = false) {
        self.startEnergyEV = startEnergyEV; self.preEdgeSafeWindowEV = preEdgeSafeWindowEV; self.exponentRange = exponentRange
        self.stripPrecedingEdges = stripPrecedingEdges
    }
}

/// One edge's amount at one pixel.
public struct EdgeIntensityPixel: Sendable, Equatable {
    /// exSpy's `intensity.value`: the factor on the cross section (barn per eV) in the model; counts per channel are `intensity` x the cross
    /// section x the channel width, times the low-loss counts convolved in when a low loss is given. nil with `unavailable`.
    public let intensity: Double?
    /// Atoms per nm^2: with a low loss the intensity is the areal density in atoms per barn (the low-loss counts carry the dose), and 1 barn is
    /// 1e-10 nm^2. nil without a low loss (the dose is unknown).
    public let arealDensityPerNM2: Double?
    public let unavailable: EELSUnavailable?
}

/// The fit of an image: per pixel and edge.
public struct EELSModelResult: Sendable {
    public let nx: Int
    public let ny: Int
    /// The masters, in onset order; each stands for every shell of its element and family (`shells`).
    public let edges: [CoreLossEdge]
    public let shells: [[CoreLossEdge]]
    /// `pixels[pixel][edge]`.
    public let pixels: [[EdgeIntensityPixel]]
    /// The fitted power law per pixel (A in exSpy's units: per eV, so a channel holds A x E^-r x channel width); nil where the fit failed.
    public let backgrounds: [PowerLawParameters?]
    /// True where the exponent ended on a bound of `exponentRange`.
    public let exponentAtBound: [Bool]
    /// The sum of squared residuals over the fit window, per pixel.
    public let residualSumOfSquares: [Double?]
    /// The energies the fit used, and the pre-edge window `fitBackground` used.
    public let windowEV: ClosedRange<Double>
    public let preEdgeWindowEV: ClosedRange<Double>
    public let convolved: Bool
    public let methodName: String
    public let validation: String
    fileprivate let basis: EELSEdgeBasis
    /// Set by a fit with per-edge windows (`EELSModelFit.fit(edgeWindows:)`), nil for the one-range joint fit. One entry per `edges`.
    public internal(set) var edgeWindows: [EdgeWindows]? = nil
    /// The signal window each edge was fitted on, as the channels it holds (eV); nil without per-edge windows.
    public internal(set) var fitRangeEV: [ClosedRange<Double>]? = nil
    /// `edgeBackgrounds[pixel][edge]`: the power law fitted on each edge's own background window(s); nil without per-edge windows
    /// (`backgrounds` then holds the first edge's).
    public internal(set) var edgeBackgrounds: [[PowerLawParameters?]]? = nil
    /// Per-edge windows: whether each edge was stripped before the next (`EELSModelOptions.stripPrecedingEdges`).
    public internal(set) var strippedPrecedingEdges = false
    fileprivate var signalRows: [Range<Int>] = []

    /// The background exponent r of one edge at one pixel; nil without per-edge windows or where the fit failed.
    public func exponent(pixel: Int, edge: Int) -> Double? {
        guard let eb = edgeBackgrounds, pixel >= 0, pixel < eb.count, edge >= 0, edge < eb[pixel].count else { return nil }
        return eb[pixel][edge]?.r
    }

    /// exSpy's `quantify()` text for one pixel's masters: `Elem.\tIntensity`, element symbols (and `Element_Shell` where one element has several
    /// independent edges), six decimals.
    public func quantifyText(pixel: Int) -> String {
        guard pixel >= 0, pixel < pixels.count else { return "\nAbsolute quantification:\nElem.\tIntensity\n" }
        var perElement: [(element: String, labels: [(String, Double)])] = []
        for (g, edge) in edges.enumerated() {
            guard let v = pixels[pixel][g].intensity else { continue }
            let label = edge.element + "_" + edge.subshell
            if let i = perElement.firstIndex(where: { $0.element == edge.element }) { perElement[i].labels.append((label, v)) }
            else { perElement.append((edge.element, [(label, v)])) }
        }
        var text = "\nAbsolute quantification:\nElem.\tIntensity\n"
        for e in perElement {
            if e.labels.count == 1 { text += "\(e.element)\t\(String(format: "%f", e.labels[0].1))\n" }
            else { for l in e.labels { text += "\(l.0)\t\(String(format: "%f", l.1))\n" } }
        }
        return text
    }

    /// The fitted model at one pixel over the whole core-loss axis (background plus every edge, with the low-loss convolution when one was given),
    /// as exSpy's `as_signal()`. nil where the fit failed.
    public func modelCurve(pixel: Int) -> [Double]? {
        guard pixel >= 0, pixel < pixels.count, let bg = backgrounds[pixel] else { return nil }
        if let eb = edgeBackgrounds {
            // per-edge windows: each edge's background plus its amplitude, inside its own signal window; zero elsewhere
            var curve = [Double](repeating: 0, count: basis.channels)
            for g in 0 ..< edges.count {
                guard let intensity = pixels[pixel][g].intensity, let b = eb[pixel][g] else { return nil }
                let rows = signalRows[g]
                let column = basis.column(group: g, pixel: pixel, rows: rows)
                for (i, k) in rows.enumerated() { curve[k] = b.a * Libm.pow(basis.energies[k], -b.r) * basis.scale + intensity * column[i] }
                for h in 0 ..< g where strippedPrecedingEdges {                 // the earlier edges' tails under this window (the background was fitted without them)
                    guard let ih = pixels[pixel][h].intensity, ih > 0 else { continue }
                    let tail = basis.column(group: h, pixel: pixel, rows: rows)
                    for (i, k) in rows.enumerated() { curve[k] += ih * tail[i] }
                }
            }
            return curve
        }
        var curve = [Double](repeating: 0, count: basis.channels)
        for k in 0 ..< basis.channels where basis.energies[k] > 0 { curve[k] = bg.a * Libm.pow(basis.energies[k], -bg.r) * basis.scale }   // PowerLaw is 0 at E <= 0 (left_cutoff)
        for g in 0 ..< edges.count {
            guard let intensity = pixels[pixel][g].intensity else { return nil }
            let column = basis.column(group: g, pixel: pixel, rows: 0 ..< basis.channels)
            for k in 0 ..< basis.channels { curve[k] += intensity * column[k] }
        }
        return curve
    }
}

/// The edge columns of a model: the cross sections summed over a group's shells, on the core-loss axis (direct) or convolved with a pixel's low loss.
struct EELSEdgeBasis: Sendable {
    let channels: Int
    let scale: Double
    let energies: [Double]
    let groups: Int
    let direct: [[Double]]                  // [group][channel], times the channel width; empty when convolved
    let kernels: [[Double]]                 // [group][convolution channel]; empty when direct
    let lowLossChannels: Int
    let reversedLowLoss: [Double]           // pixel-major, reversed per pixel
    let lowLossPixels: Int

    init(axis: EELSAxis, groups: [[CoreLossEdge]], microscope: EELSMicroscope, lowLoss: LowLossSpectrumImage?) throws {
        guard microscope.beamEnergyKeV > 0, microscope.collectionMrad > 0, microscope.convergenceMrad >= 0,
              microscope.beamEnergyKeV.isFinite, microscope.collectionMrad.isFinite, microscope.convergenceMrad.isFinite else {
            throw EELSModelError.invalidMicroscope
        }
        channels = axis.size; scale = axis.scale; self.groups = groups.count
        let n = axis.size
        let localEnergies = (0 ..< n).map { axis.energy(ofChannel: $0) }
        energies = localEnergies
        var sections: [[EdgeCrossSection]] = []
        for shells in groups {
            var row: [EdgeCrossSection] = []
            for shell in shells {
                guard let table = GOSTable.bundled(shell) else { throw EELSModelError.edgeNotBundled(shell.description) }
                guard let xs = EdgeCrossSection(table: table, beamEnergyKeV: microscope.beamEnergyKeV, convergenceMrad: microscope.convergenceMrad,
                                                collectionMrad: microscope.collectionMrad) else {
                    throw EELSModelError.crossSectionFailed(shell.description)
                }
                row.append(xs)
            }
            sections.append(row)
        }
        if let ll = lowLoss {
            let llAxis = try EELSAxis(offset: ll.energyOffsetEV, scale: ll.energyScaleEV, size: ll.channels)
            guard abs(ll.energyScaleEV - axis.scale) <= 1e-9 * axis.scale else {
                throw EELSModelError.lowLossScaleMismatch(coreEV: axis.scale, lowEV: ll.energyScaleEV)
            }
            guard let j0 = llAxis.channel(ofEnergy: 0) else { throw EELSModelError.lowLossAxisHasNoZero }
            let g = ll.channels
            let offsetIndex = g - j0 - 1
            let size = n + g - 1
            // np.linspace(offset - offset_index * scale, offset + scale * (size - 1 - offset_index), size)
            let start = axis.offset - Double(offsetIndex) * axis.scale
            let stop = axis.offset + axis.scale * Double(size - 1 - offsetIndex)
            let step = size > 1 ? (stop - start) / Double(size - 1) : 0
            let convAxis = (0 ..< size).map { i in i == size - 1 && size > 1 ? stop : Double(i) * step + start }
            kernels = sections.map { row in
                var sum = [Double](repeating: 0, count: size)
                for xs in row { let f = xs.differential(convAxis); for i in 0 ..< size { sum[i] += f[i] } }
                return sum
            }
            direct = []
            lowLossChannels = g
            lowLossPixels = ll.pixelCount
            var reversed = [Double](repeating: 0, count: ll.counts.count)
            for p in 0 ..< ll.pixelCount { for j in 0 ..< g { reversed[p * g + j] = ll.counts[p * g + g - 1 - j] } }
            reversedLowLoss = reversed
        } else {
            direct = sections.map { row in
                var sum = [Double](repeating: 0, count: n)
                for xs in row { let f = xs.differential(localEnergies); for i in 0 ..< n { sum[i] += f[i] } }
                return sum.map { $0 * axis.scale }
            }
            kernels = []
            lowLossChannels = 0
            lowLossPixels = 0
            reversedLowLoss = []
        }
    }

    var convolved: Bool { !kernels.isEmpty }

    /// Group `g`'s column over `rows` for `pixel`: cross section x channel width, or `np.convolve(low loss, kernel, "valid")` x channel width.
    func column(group g: Int, pixel: Int, rows: Range<Int>) -> [Double] {
        if !convolved { return Array(direct[g][rows]) }
        var out = [Double](repeating: 0, count: rows.count)
        let n = lowLossChannels
        reversedLowLoss.withUnsafeBufferPointer { ll in
            kernels[g].withUnsafeBufferPointer { kernel in
                for (i, k) in rows.enumerated() {
                    var dot = 0.0
                    vDSP_dotprD(ll.baseAddress! + pixel * n, 1, kernel.baseAddress! + k, 1, &dot, vDSP_Length(n))
                    out[i] = dot * scale
                }
            }
        }
        return out
    }
}

public enum EELSModelFit {
    public static let methodName = "EELS edge model: power law + dft GOS edges, non-negative least squares with the exponent by Brent's method"

    // MARK: Public entry points

    /// The model fit (exSpy `create_model(...)` then `fit(kind="smart")`) of every pixel not masked out (`mask[p] == true` fits, false skips).
    ///
    /// With `edgeWindows` (one per fitted edge, i.e. per entry of the result's `edges`, in onset order; `options.startEnergyEV` and the
    /// pre-edge safe window are not used) the fit is a per-edge sequence instead of the one joint model: each edge's background is a power law
    /// fitted (non-negative least squares, exponent by Brent) on its own background window(s), extrapolated under its signal window, and the
    /// edge's intensity is the cross-section column fitted on the background-subtracted signal window. Signal windows that share energies are
    /// refused. This is the field's per-edge convention (GMS, eels.info), not exSpy's; `validation: "none"`. The same call is the per-pixel
    /// map: every pixel gets every edge's intensity and its own r (`EELSModelResult.exponent(pixel:edge:)`). Without `edgeWindows` nothing changes.
    ///
    /// The edges are fitted in onset order and each is stripped before the next: once edge i has its background (on its window) and its amplitude
    /// (on its signal window), amplitude x cross section, on every channel to the end of the range (the cross section's own tail beyond the signal
    /// window), is subtracted from a working copy of the spectrum, and edge i+1's power law and amplitude are fitted on that copy. Without it the
    /// next edge's background window lies in the earlier edge's tail, the fresh power law there is too steep and runs above the data under the
    /// next edge, and its non-negative amplitude clamps to 0 (N K behind C K on real files). The reported intensities are the amplitudes.
    public static func fit(
        coreLoss: CoreLossSpectrumImage, edges: [CoreLossEdge], microscope: EELSMicroscope, lowLoss: LowLossSpectrumImage? = nil,
        mask: PixelMask? = nil, options: EELSModelOptions = .init(), edgeWindows: [EdgeWindows]? = nil,
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> EELSModelResult {
        if let edgeWindows {
            return try fitWindowed(coreLoss: coreLoss, edges: edges, microscope: microscope, lowLoss: lowLoss, mask: mask, options: options,
                                   windows: edgeWindows, cancelled: cancelled, progress: progress)
        }
        let setup = try prepare(coreLoss: coreLoss, edges: edges, options: options, mask: mask, lowLoss: lowLoss)
        let basis = try EELSEdgeBasis(axis: setup.axis, groups: setup.groups.map(\.shells), microscope: microscope, lowLoss: lowLoss)
        let np = coreLoss.pixelCount, n = coreLoss.channels, m = setup.groups.count
        let rows = setup.start ..< (n - 1)                               // the last stage of smart_fit: [start, axis end), the end channel excluded
        let slots = EELSSlots<PixelFit?>(count: np, initial: nil)
        let logE = rows.map { log(basis.energies[$0]) }
        try coreLoss.counts.withUnsafeBufferPointer { counts in
            nonisolated(unsafe) let input = counts
            try EELSParallel.forEachPixel(count: np, cancelled: cancelled, progress: progress) { p in
                if let mask, !mask[p] { slots.set(p, PixelFit(failure: .masked)); return }
                let y = Array(UnsafeBufferPointer(start: input.baseAddress! + p * n + rows.lowerBound, count: rows.count))
                var columns = [[Double]](repeating: [], count: m)
                for g in 0 ..< m { columns[g] = basis.column(group: g, pixel: p, rows: rows) }
                slots.set(p, solve(y: y, logE: logE, scale: basis.scale, edgeColumns: columns, range: options.exponentRange))
            }
        }
        var pixels: [[EdgeIntensityPixel]] = []
        var backgrounds: [PowerLawParameters?] = [], atBound: [Bool] = [], rss: [Double?] = []
        for p in 0 ..< np {
            let f = slots[p]!
            if let why = f.failure {
                pixels.append([EdgeIntensityPixel](repeating: EdgeIntensityPixel(intensity: nil, arealDensityPerNM2: nil, unavailable: why), count: m))
                backgrounds.append(nil); atBound.append(false); rss.append(nil)
                continue
            }
            pixels.append((0 ..< m).map { g in
                let v = f.intensities[g]
                return EdgeIntensityPixel(intensity: v, arealDensityPerNM2: basis.convolved ? v * 1e10 : nil, unavailable: nil)
            })
            backgrounds.append(PowerLawParameters(a: f.a, r: f.r)); atBound.append(f.atBound); rss.append(f.rss)
        }
        return EELSModelResult(
            nx: coreLoss.nx, ny: coreLoss.ny, edges: setup.groups.map(\.master), shells: setup.groups.map(\.shells), pixels: pixels,
            backgrounds: backgrounds, exponentAtBound: atBound, residualSumOfSquares: rss,
            windowEV: setup.axis.energy(ofChannel: rows.lowerBound) ... setup.axis.energy(ofChannel: rows.upperBound - 1),
            preEdgeWindowEV: setup.axis.energy(ofChannel: setup.start) ... setup.axis.energy(ofChannel: setup.preEdgeEnd - 1),
            convolved: basis.convolved, methodName: methodName, validation: "none", basis: basis)
    }

    /// exSpy `fit_background()`: the power law alone over the pre-edge window `[start, first edge - safe window)`. nil where the fit failed.
    public static func fitBackground(
        coreLoss: CoreLossSpectrumImage, edges: [CoreLossEdge], options: EELSModelOptions = .init(), mask: PixelMask? = nil,
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> [PowerLawParameters?] {
        let setup = try prepare(coreLoss: coreLoss, edges: edges, options: options, mask: mask, lowLoss: nil)
        let np = coreLoss.pixelCount, n = coreLoss.channels
        let rows = setup.start ..< setup.preEdgeEnd
        let logE = rows.map { log(setup.axis.energy(ofChannel: $0)) }
        let slots = EELSSlots<PowerLawParameters?>(count: np, initial: nil)
        try coreLoss.counts.withUnsafeBufferPointer { counts in
            nonisolated(unsafe) let input = counts
            try EELSParallel.forEachPixel(count: np, cancelled: cancelled, progress: progress) { p in
                if let mask, !mask[p] { return }
                let y = Array(UnsafeBufferPointer(start: input.baseAddress! + p * n + rows.lowerBound, count: rows.count))
                let f = solve(y: y, logE: logE, scale: setup.axis.scale, edgeColumns: [], range: options.exponentRange)
                if f.failure == nil { slots.set(p, PowerLawParameters(a: f.a, r: f.r)) }
            }
        }
        return slots.values
    }

    /// exSpy `two_area_background_estimation()`: A and r from the two-area method over `[start, first edge - safe window]`. nil where it cannot answer.
    public static func twoAreaBackground(
        coreLoss: CoreLossSpectrumImage, edges: [CoreLossEdge], options: EELSModelOptions = .init(), mask: PixelMask? = nil
    ) throws -> [PowerLawParameters?] {
        let setup = try prepare(coreLoss: coreLoss, edges: edges, options: options, mask: mask, lowLoss: nil)
        let e1 = setup.axis.energy(ofChannel: setup.start)
        let window = try PowerLawWindow(axis: setup.axis, from: e1, to: setup.firstOnset - options.preEdgeSafeWindowEV)
        let n = coreLoss.channels
        return coreLoss.counts.withUnsafeBufferPointer { counts in
            (0 ..< coreLoss.pixelCount).map { p -> PowerLawParameters? in
                if let mask, !mask[p] { return nil }
                switch PowerLawFit.estimate(UnsafeBufferPointer(start: counts.baseAddress! + p * n, count: n), window: window) {
                case .success(let f): return PowerLawParameters(a: f.a, r: f.r)
                case .failure: return nil
                }
            }
        }
    }

    // MARK: Per-edge windows

    private struct WindowedPixel: Sendable {
        var failure: EELSUnavailable?
        var backgrounds: [PowerLawParameters?] = []
        var intensities: [Double] = []
        var rss = 0.0
        var atBound = false
    }

    private static func fitWindowed(
        coreLoss: CoreLossSpectrumImage, edges: [CoreLossEdge], microscope: EELSMicroscope, lowLoss: LowLossSpectrumImage?, mask: PixelMask?,
        options: EELSModelOptions, windows: [EdgeWindows], cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?
    ) throws -> EELSModelResult {
        // the same checks and the same twin grouping as `prepare`, without the one-range window
        guard !edges.isEmpty else { throw EELSModelError.noEdgeInRange(fromEV: coreLoss.energyOffsetEV, toEV: coreLoss.energyOffsetEV) }
        guard options.exponentRange.lowerBound.isFinite, options.exponentRange.upperBound.isFinite,
              options.exponentRange.lowerBound < options.exponentRange.upperBound else { throw EELSModelError.invalidExponentRange }
        if let mask, mask.count != coreLoss.pixelCount { throw EELSModelError.maskShapeMismatch(expected: coreLoss.pixelCount, got: mask.count) }
        if let ll = lowLoss, ll.pixelCount != coreLoss.pixelCount { throw EELSModelError.lowLossShapeMismatch(expected: coreLoss.pixelCount, got: ll.pixelCount) }
        let axis = try EELSAxis(offset: coreLoss.energyOffsetEV, scale: coreLoss.energyScaleEV, size: coreLoss.channels)
        var seen = Set<String>()
        var byKey: [String: [CoreLossEdge]] = [:]
        for e in edges {
            guard CoreLossEdge.bundled.contains(e) else { throw EELSModelError.edgeNotBundled(e.description) }
            guard seen.insert(e.element + " " + e.subshell).inserted else { throw EELSModelError.duplicateEdge(e.description) }
            byKey[e.element + " " + e.family, default: []].append(e)
        }
        var groups = byKey.values.map { shells -> Group in
            let sorted = shells.sorted { $0.subshell < $1.subshell }
            return Group(master: sorted.last!, shells: sorted)
        }
        groups.sort { ($0.master.onsetEV, $0.master.element) < ($1.master.onsetEV, $1.master.element) }
        let m = groups.count
        guard windows.count == m else { throw EELSModelError.edgeWindowCountMismatch(expected: m, got: windows.count) }

        // the channels of every window, checked
        var bgRowsV = [[Range<Int>]](), sigRowsV = [Range<Int>]()
        for g in 0 ..< m {
            let name = groups[g].master.element + " " + groups[g].master.family
            let w = windows[g]
            func check(_ r: ClosedRange<Double>, _ what: String, minChannels: Int) throws -> Range<Int> {
                guard r.lowerBound.isFinite, r.upperBound.isFinite else { throw EELSModelError.edgeWindowInvalid(edge: name, why: "\(what) window is not finite") }
                guard r.lowerBound >= axis.lowValue - 1e-9, r.upperBound <= axis.highValue + 1e-9 else {
                    throw EELSModelError.edgeWindowInvalid(edge: name, why: "\(what) window \(r.lowerBound) to \(r.upperBound) eV is not inside the axis \(axis.lowValue) to \(axis.highValue) eV")
                }
                let rows = EdgeWindows.rows(r, offset: axis.offset, scale: axis.scale, size: axis.size)
                guard rows.count >= minChannels else { throw EELSModelError.edgeWindowInvalid(edge: name, why: "\(what) window holds \(rows.count) channels, needs \(minChannels)") }
                guard axis.energy(ofChannel: rows.lowerBound) > 0 else { throw EELSModelError.edgeWindowInvalid(edge: name, why: "\(what) window is not at positive energy") }
                return rows
            }
            var bg = [try check(w.backgroundEV, "background", minChannels: 2)]
            if let second = w.secondBackgroundEV { bg.append(try check(second, "second background", minChannels: 2)) }
            guard bg.reduce(0, { $0 + $1.count }) >= 4 else { throw EELSModelError.edgeWindowInvalid(edge: name, why: "background windows hold fewer than 4 channels") }
            bgRowsV.append(bg)
            sigRowsV.append(try check(w.signalEV, "signal", minChannels: 2))
        }
        let bgRows = bgRowsV, sigRows = sigRowsV
        for a in 0 ..< m { for b in (a + 1) ..< max(m, a + 1) where sigRows[a].overlaps(sigRows[b]) {
            let n = { (g: Int) in groups[g].master.element + " " + groups[g].master.family }
            throw EELSModelError.overlappingSignalWindows(n(a), n(b))
        } }

        let basis = try EELSEdgeBasis(axis: axis, groups: groups.map(\.shells), microscope: microscope, lowLoss: lowLoss)
        let np = coreLoss.pixelCount, n = coreLoss.channels
        let slots = EELSSlots<WindowedPixel?>(count: np, initial: nil)
        let bgLogE = bgRows.map { rs in rs.flatMap { r in r.map { log(basis.energies[$0]) } } }
        let range = options.exponentRange
        try coreLoss.counts.withUnsafeBufferPointer { counts in
            nonisolated(unsafe) let input = counts
            try EELSParallel.forEachPixel(count: np, cancelled: cancelled, progress: progress) { p in
                if let mask, !mask[p] { slots.set(p, WindowedPixel(failure: .masked)); return }
                let base = input.baseAddress! + p * n
                var out = WindowedPixel()
                var work = Array(UnsafeBufferPointer(start: base, count: n))          // the spectrum with the edges fitted so far stripped
                for g in 0 ..< m {
                    var yb = [Double]()
                    for r in bgRows[g] { yb += r.map { work[$0] } }
                    let f = solve(y: yb, logE: bgLogE[g], scale: basis.scale, edgeColumns: [], range: range)
                    if f.failure != nil { slots.set(p, WindowedPixel(failure: .fitFailed)); return }
                    out.backgrounds.append(PowerLawParameters(a: f.a, r: f.r)); out.atBound = out.atBound || f.atBound
                    let rows = sigRows[g]
                    let column = basis.column(group: g, pixel: p, rows: rows)
                    var cc = 0.0, cd = 0.0
                    var d = [Double](repeating: 0, count: rows.count)
                    for (i, k) in rows.enumerated() {
                        d[i] = work[k] - f.a * Libm.pow(basis.energies[k], -f.r) * basis.scale
                        cc += column[i] * column[i]; cd += column[i] * d[i]
                    }
                    guard cc > 0 else { slots.set(p, WindowedPixel(failure: .fitFailed)); return }   // the window lies below the edge's onset
                    let intensity = max(0, cd / cc)
                    out.intensities.append(intensity)
                    for i in 0 ..< rows.count { let e = d[i] - intensity * column[i]; out.rss += e * e }
                    if options.stripPrecedingEdges, g + 1 < m, intensity > 0 {        // strip this edge, tail included, before the next one is fitted
                        let full = basis.column(group: g, pixel: p, rows: 0 ..< n)
                        for k in 0 ..< n { work[k] -= intensity * full[k] }
                    }
                }
                slots.set(p, out)
            }
        }
        var pixels: [[EdgeIntensityPixel]] = [], backgrounds: [PowerLawParameters?] = [], perEdge: [[PowerLawParameters?]] = []
        var atBound: [Bool] = [], rss: [Double?] = []
        for p in 0 ..< np {
            let f = slots[p]!
            if let why = f.failure {
                pixels.append([EdgeIntensityPixel](repeating: EdgeIntensityPixel(intensity: nil, arealDensityPerNM2: nil, unavailable: why), count: m))
                backgrounds.append(nil); perEdge.append([PowerLawParameters?](repeating: nil, count: m)); atBound.append(false); rss.append(nil)
                continue
            }
            pixels.append((0 ..< m).map { g in
                EdgeIntensityPixel(intensity: f.intensities[g], arealDensityPerNM2: basis.convolved ? f.intensities[g] * 1e10 : nil, unavailable: nil)
            })
            backgrounds.append(f.backgrounds[0]); perEdge.append(f.backgrounds); atBound.append(f.atBound); rss.append(f.rss)
        }
        let lo = bgRows.flatMap { $0 }.map(\.lowerBound).min()!, hi = sigRows.map(\.upperBound).max()!
        var result = EELSModelResult(
            nx: coreLoss.nx, ny: coreLoss.ny, edges: groups.map(\.master), shells: groups.map(\.shells), pixels: pixels,
            backgrounds: backgrounds, exponentAtBound: atBound, residualSumOfSquares: rss,
            windowEV: axis.energy(ofChannel: lo) ... axis.energy(ofChannel: hi - 1),
            preEdgeWindowEV: axis.energy(ofChannel: bgRows[0][0].lowerBound) ... axis.energy(ofChannel: bgRows[0][0].upperBound - 1),
            convolved: basis.convolved, methodName: methodName + "; per-edge windows (sequence: power law on each background window, then the edge on its signal window" + (options.stripPrecedingEdges ? ", then the edge stripped from the spectrum)" : ")"),
            validation: "none", basis: basis)
        result.edgeWindows = windows
        result.fitRangeEV = sigRows.map { axis.energy(ofChannel: $0.lowerBound) ... axis.energy(ofChannel: $0.upperBound - 1) }
        result.edgeBackgrounds = perEdge
        result.strippedPrecedingEdges = options.stripPrecedingEdges
        result.signalRows = sigRows
        return result
    }

    // MARK: Setup

    struct Group { var master: CoreLossEdge; var shells: [CoreLossEdge] }

    struct Setup {
        let axis: EELSAxis
        let groups: [Group]
        let start: Int
        let preEdgeEnd: Int
        let firstOnset: Double
    }

    static func prepare(coreLoss: CoreLossSpectrumImage, edges: [CoreLossEdge], options: EELSModelOptions, mask: PixelMask?,
                        lowLoss: LowLossSpectrumImage?) throws -> Setup {
        guard !edges.isEmpty else { throw EELSModelError.noEdgeInRange(fromEV: coreLoss.energyOffsetEV, toEV: coreLoss.energyOffsetEV) }
        guard options.preEdgeSafeWindowEV.isFinite, options.preEdgeSafeWindowEV >= 0 else { throw EELSModelError.invalidExponentRange }
        guard options.exponentRange.lowerBound.isFinite, options.exponentRange.upperBound.isFinite,
              options.exponentRange.lowerBound < options.exponentRange.upperBound else { throw EELSModelError.invalidExponentRange }
        if let mask, mask.count != coreLoss.pixelCount { throw EELSModelError.maskShapeMismatch(expected: coreLoss.pixelCount, got: mask.count) }
        if let ll = lowLoss, ll.pixelCount != coreLoss.pixelCount {
            throw EELSModelError.lowLossShapeMismatch(expected: coreLoss.pixelCount, got: ll.pixelCount)
        }
        let axis = try EELSAxis(offset: coreLoss.energyOffsetEV, scale: coreLoss.energyScaleEV, size: coreLoss.channels)
        var seen = Set<String>()
        var byKey: [String: [CoreLossEdge]] = [:]
        for e in edges {
            guard CoreLossEdge.bundled.contains(e) else { throw EELSModelError.edgeNotBundled(e.description) }
            guard seen.insert(e.element + " " + e.subshell).inserted else { throw EELSModelError.duplicateEdge(e.description) }
            byKey[e.element + " " + e.family, default: []].append(e)
        }
        var groups = byKey.values.map { shells -> Group in
            let sorted = shells.sorted { $0.subshell < $1.subshell }
            return Group(master: sorted.last!, shells: sorted)
        }
        groups.sort { ($0.master.onsetEV, $0.master.element) < ($1.master.onsetEV, $1.master.element) }
        // start: exSpy's `_get_start_energy`: below the axis start (or nil) is the axis start.
        var start = 0
        if let s = options.startEnergyEV, s > axis.lowValue {
            guard s.isFinite, s <= axis.highValue else { throw EELSModelError.noEdgeInRange(fromEV: s, toEV: axis.highValue) }
            start = try axis.valueRangeToIndices(s, axis.highValue).first
        }
        let startEV = axis.energy(ofChannel: start)
        // every shell must have its onset inside the fit range (exSpy turns one below the first channel into background; refused here)
        let all = groups.flatMap(\.shells)
        for shell in all where !(shell.onsetEV > startEV && shell.onsetEV <= axis.highValue) {
            throw EELSModelError.noEdgeInRange(fromEV: startEV, toEV: axis.highValue)
        }
        let firstOnset = all.map(\.onsetEV).min()!
        let (i1, i2) = try axis.valueRangeToIndices(startEV, firstOnset - options.preEdgeSafeWindowEV)
        guard i2 - i1 >= 4 else { throw EELSModelError.preEdgeWindowTooNarrow(channels: i2 - i1) }
        guard axis.energy(ofChannel: i1) > 0 else { throw EELSEdgeError.backgroundWindowNotPositive(fromEV: axis.energy(ofChannel: i1)) }
        return Setup(axis: axis, groups: groups, start: i1, preEdgeEnd: i2, firstOnset: firstOnset)
    }

    // MARK: The per-pixel solve

    struct PixelFit: Sendable {
        var failure: EELSUnavailable?
        var a = 0.0, r = 0.0, rss = 0.0
        var intensities: [Double] = []
        var atBound = false
        init(failure: EELSUnavailable) { self.failure = failure }
        init(a: Double, r: Double, rss: Double, intensities: [Double], atBound: Bool) {
            failure = nil; self.a = a; self.r = r; self.rss = rss; self.intensities = intensities; self.atBound = atBound
        }
    }

    /// min over r in `range`, A >= 0 and intensities >= 0 of |y - A E^-r scale - sum I_g column_g|^2 (variable projection).
    static func solve(y: [Double], logE: [Double], scale: Double, edgeColumns: [[Double]], range: ClosedRange<Double>) -> PixelFit {
        let w = y.count, m = edgeColumns.count
        var matrix = ColumnMatrix(rows: w, cols: m + 1)
        for g in 0 ..< m { for i in 0 ..< w { matrix.data[(g + 1) * w + i] = edgeColumns[g][i] } }
        var best: (rss: Double, coefficients: [Double], r: Double)?
        func profile(_ r: Double) -> Double {
            for i in 0 ..< w { matrix.data[i] = exp(-r * logE[i]) * scale }
            let solution = LeastSquaresFit.solve(nonNegative: matrix, y: y)
            guard solution.converged else { return .infinity }
            var sum = 0.0
            for i in 0 ..< w {
                var model = 0.0
                for j in 0 ... m { model += matrix.data[j * w + i] * solution.nonNegative[j] }
                let d = y[i] - model
                sum += d * d
            }
            guard sum.isFinite else { return .infinity }
            if best == nil || sum < best!.rss { best = (sum, solution.nonNegative, r) }
            return sum
        }
        // A coarse grid finds the basin; Brent's method then polishes the minimum inside the neighbouring grid points.
        let cells = 20
        let lo = range.lowerBound, hi = range.upperBound
        let step = (hi - lo) / Double(cells)
        var values = [Double](repeating: .infinity, count: cells + 1)
        for i in 0 ... cells { values[i] = profile(lo + step * Double(i)) }
        guard let gi = values.indices.min(by: { values[$0] < values[$1] }), values[gi].isFinite else { return PixelFit(failure: .fitFailed) }
        var a = lo + step * Double(max(gi - 1, 0)), c = lo + step * Double(min(gi + 1, cells))
        let r = lo + step * Double(gi)
        if c > a {
            // Brent (Numerical Recipes `brent`), golden-section with parabolic steps, on [a, c] starting from the grid minimum.
            let golden = 0.3819660112501051
            var x = r, w2 = r, v = r
            var fx = values[gi], fw = fx, fv = fx
            var d = 0.0, e = 0.0
            for _ in 0 ..< 100 {
                let xm = 0.5 * (a + c)
                let tol1 = 1e-10 * abs(x) + 1e-12, tol2 = 2 * tol1
                if abs(x - xm) <= tol2 - 0.5 * (c - a) { break }
                var useGolden = true
                if abs(e) > tol1 {
                    let r1 = (x - w2) * (fx - fv), q0 = (x - v) * (fx - fw)
                    var p = (x - v) * q0 - (x - w2) * r1
                    var q = 2 * (q0 - r1)
                    if q > 0 { p = -p }
                    q = abs(q)
                    let etemp = e
                    e = d
                    if !(abs(p) >= abs(0.5 * q * etemp) || p <= q * (a - x) || p >= q * (c - x)) {
                        d = p / q
                        let u = x + d
                        if u - a < tol2 || c - u < tol2 { d = xm >= x ? tol1 : -tol1 }
                        useGolden = false
                    }
                }
                if useGolden {
                    e = x >= xm ? a - x : c - x
                    d = golden * e
                }
                let u = abs(d) >= tol1 ? x + d : x + (d >= 0 ? tol1 : -tol1)
                let fu = profile(u)
                if fu <= fx {
                    if u >= x { a = x } else { c = x }
                    v = w2; fv = fw; w2 = x; fw = fx; x = u; fx = fu
                } else {
                    if u < x { a = u } else { c = u }
                    if fu <= fw || w2 == x { v = w2; fv = fw; w2 = u; fw = fu }
                    else if fu <= fv || v == x || v == w2 { v = u; fv = fu }
                }
            }
        }
        // the best evaluation seen is the answer (the grid or a Brent point, whichever fit better)
        guard let result = best else { return PixelFit(failure: .fitFailed) }
        let atBound = abs(result.r - lo) < 1e-6 * max(1, abs(lo)) + 1e-9 || abs(result.r - hi) < 1e-6 * max(1, abs(hi)) + 1e-9
        return PixelFit(a: result.coefficients[0], r: result.r, rss: result.rss, intensities: Array(result.coefficients.dropFirst()), atBound: atBound)
    }
}
