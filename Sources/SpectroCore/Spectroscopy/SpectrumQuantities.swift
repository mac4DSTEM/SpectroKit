//
//  SpectrumQuantities.swift
//  Role: What the Spectroscopy room shows before any fit exists (v5.0 WP2 R2): drawn region masks, the line
//        windows of the elements the user set, window net counts with their counting sigma and the places where
//        a background window sits on another line. Counts only: no k-factors, no fit, no at% (WP3).
//
//  Net counts and sigma: with signal sum G and background sums (left + right) = B scaled by s (eXSpy's
//  `corr_factor`), net = G - s B and, for independent Poisson counts, sigma^2 = G + s^2 B. Without a background
//  window net = G and sigma^2 = G. The sums are the exact integer sums of `SpectrumImage`; only the final
//  formula is floating point, and it is `ResolvedWindow.net`, shared with the per-pixel maps.
//

import Foundation

// MARK: - Regions

/// A half-open pixel rectangle `[x0, x1) x [y0, y1)` on the spectrum image's own grid.
package nonisolated struct PixelRect: Equatable, Sendable {
    package var x0: Int, y0: Int, x1: Int, y1: Int
    package init(x0: Int, y0: Int, x1: Int, y1: Int) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }
    package var width: Int { max(x1 - x0, 0) }
    package var height: Int { max(y1 - y0, 0) }

    /// The rectangle spanned by two pixel corners (inclusive of both), clamped to the grid; nil when it holds no pixel.
    package static func spanning(_ a: (x: Int, y: Int), _ b: (x: Int, y: Int), nx: Int, ny: Int) -> PixelRect? {
        let r = PixelRect(x0: max(min(a.x, b.x), 0), y0: max(min(a.y, b.y), 0),
                          x1: min(max(a.x, b.x) + 1, nx), y1: min(max(a.y, b.y) + 1, ny))
        return r.width > 0 && r.height > 0 ? r : nil
    }
}

package nonisolated enum SpectrumRegionShape: Equatable, Sendable {
    case rectangle(PixelRect)
    /// The ellipse inscribed in the rectangle: a pixel is in when its centre is.
    case ellipse(PixelRect)

    package var bounds: PixelRect {
        switch self { case .rectangle(let r), .ellipse(let r): return r }
    }

    /// Row-major `y * nx + x`, true = in. Pixels outside the grid are ignored.
    package func mask(nx: Int, ny: Int) -> PixelMask {
        var m = PixelMask(repeating: false, count: nx * ny)
        let r = bounds
        // Clamped to the grid; a shape wholly off it (or empty) has an empty range, never a reversed one.
        let ys = max(r.y0, 0)..<max(min(r.y1, ny), max(r.y0, 0)), xs = max(r.x0, 0)..<max(min(r.x1, nx), max(r.x0, 0))
        switch self {
        case .rectangle:
            for y in ys { for x in xs { m[y * nx + x] = true } }
        case .ellipse:
            let cx = Double(r.x0 + r.x1) / 2, cy = Double(r.y0 + r.y1) / 2
            let ax = Double(r.width) / 2, ay = Double(r.height) / 2
            for y in ys { for x in xs {
                let dx = (Double(x) + 0.5 - cx) / ax, dy = (Double(y) + 0.5 - cy) / ay
                if dx * dx + dy * dy <= 1 { m[y * nx + x] = true }
            } }
        }
        return m
    }
}

// MARK: - Line windows

/// One line (or an element that has none) with its windows resolved on an axis.
package nonisolated struct LineWindow: Equatable, Sendable {
    package let element: String
    /// `Element_Line`, e.g. "Al_Ka"; the bare symbol when the element has no line on the axis.
    package let id: String
    package let energy: Double
    package let fwhm: Double
    package let window: ResolvedWindow?
    /// Why there is no window: no line on the axis, a window edge outside it, an empty background window.
    package let failure: String?
    package let conflicts: [WindowConflict]
}

/// The net counts of one line in one spectrum, with the sums they came from.
package nonisolated struct LineNetCount: Equatable, Sendable {
    package let id: String
    package let element: String
    package let net: Double
    package let sigma: Double
    package let signal: UInt64
    /// left + right background sums; nil when the line has no background window.
    package let background: UInt64?
    package let scale: Double?

    /// s·B >= G: the background windows hold at least as much as the signal window, so the net count is not a
    /// measurement of this line (the windows sit on neighbouring peaks, or the element is absent). Decided by the sums of
    /// THIS line's own windows, never by which other elements are selected.
    package var backgroundExceedsSignal: Bool {
        guard let b = background, let s = scale else { return false }
        return s * Double(b) >= Double(signal)
    }

    /// "not a measurement: the background windows (s·B = …) hold more than the signal window (G = …); they sit on neighbouring peaks"
    package var notAMeasurementText: String? {
        guard backgroundExceedsSignal, let b = background, let s = scale else { return nil }
        return "not a measurement: the background windows (s·B = \(Int((s * Double(b)).rounded()))) hold more than the signal window (G = \(signal)); they sit on neighbouring peaks"
    }
}

package nonisolated enum ElementWindows {
    /// Detector resolution at Mn Kα when the file does not state one (eV). The simulated dataset and a Super-X G1 sit
    /// near it; it sets the window widths through eXSpy's width law and nothing else.
    package static let defaultResolutionMnKaEV = 130.0

    /// Which line of `symbol` the windows use: with `family` nil eXSpy's default (`defaultLines`, one line below the
    /// beam energy / 2), otherwise that family's alpha line when it lies inside the axis.
    package static func lineID(of symbol: String, family: XRayFamily?, axis: EnergyAxis, beamEnergyKeV: Double?) -> String? {
        if let family {
            let id = "\(symbol)_\(family.rawValue)a"
            return XRayLines.linesInRange([id], axis: axis, beamEnergy: beamEnergyKeV).first
        }
        return XRayLines.defaultLines(elements: [symbol], axis: axis, beamEnergy: beamEnergyKeV).first
    }

    /// The windows of every element in `elements` (symbol, family override), in that order. Windows are built
    /// together, as eXSpy does, so neighbouring lines merge their background windows; `conflicts` reports every other
    /// table line of the same elements that a background window then lies on (REPORT only, the counts are eXSpy's).
    package static func build(
        elements: [(symbol: String, family: XRayFamily?)], axis: EnergyAxis,
        resolutionMnKaEV: Double = defaultResolutionMnKaEV, beamEnergyKeV: Double?
    ) -> [LineWindow] {
        struct Pick { let symbol: String; let line: SpectralLine? }
        let picks: [Pick] = elements.map { e in
            guard let id = lineID(of: e.symbol, family: e.family, axis: axis, beamEnergyKeV: beamEnergyKeV),
                  let line = try? SpectralLine(id: id, resolutionMnKaEV: resolutionMnKaEV) else { return Pick(symbol: e.symbol, line: nil) }
            return Pick(symbol: e.symbol, line: line)
        }
        let lines = picks.compactMap(\.line)
        let integration = WindowIntensity.integrationWindows(lines: lines)
        let background = BackgroundWindows.estimate(lines: lines)
        let candidates = WindowIntensity.candidateLines(
            elements: elements.map(\.symbol), resolutionMnKaEV: resolutionMnKaEV, axis: axis)
        let conflicts = WindowIntensity.conflicts(lines: lines, background: background, candidates: candidates)
        var out: [LineWindow] = []
        var next = 0
        for pick in picks {
            guard let line = pick.line else {
                out.append(LineWindow(element: pick.symbol, id: pick.symbol, energy: 0, fwhm: 0, window: nil,
                                      failure: "No usable X-ray line inside the energy axis", conflicts: []))
                continue
            }
            defer { next += 1 }
            do {
                let w = try WindowIntensity.resolve(integration: integration[next], background: background[next], axis: axis)
                out.append(LineWindow(element: pick.symbol, id: line.id, energy: line.energy, fwhm: line.fwhm, window: w,
                                      failure: nil, conflicts: conflicts[next]))
            } catch {
                out.append(LineWindow(element: pick.symbol, id: line.id, energy: line.energy, fwhm: line.fwhm, window: nil,
                                      failure: "A window of \(line.id) lies outside the energy axis", conflicts: conflicts[next]))
            }
        }
        return out
    }

    /// Net counts and sigma of every window in one spectrum; nil where the line has no window.
    package static func netCounts(spectrum: [UInt64], windows: [LineWindow]) -> [LineNetCount?] {
        func sum(_ r: Range<Int>) -> UInt64 {
            let lo = max(r.lowerBound, 0), hi = min(r.upperBound, spectrum.count)
            var s: UInt64 = 0
            if lo < hi { for c in lo..<hi { s &+= spectrum[c] } }
            return s
        }
        return windows.map { lw in
            guard let w = lw.window else { return nil }
            let g = sum(w.signal)
            guard let b = w.background else {
                return LineNetCount(id: lw.id, element: lw.element, net: w.net(g, 0, 0), sigma: Double(g).squareRoot(),
                                    signal: g, background: nil, scale: nil)
            }
            let l = sum(b.left), r = sum(b.right)
            let variance = Double(g) + b.scale * b.scale * Double(l &+ r)
            return LineNetCount(id: lw.id, element: lw.element, net: w.net(g, l, r), sigma: variance.squareRoot(),
                                signal: g, background: l &+ r, scale: b.scale)
        }
    }

    /// Net-count map of every window that has one (outer = window, `nil` where there is none).
    package static func maps(image: some SpectrumImage, windows: [LineWindow]) -> [[Double]?] {
        let resolved = windows.compactMap(\.window)
        let m = WindowIntensity.maps(image: image, windows: resolved)
        var next = 0
        return windows.map { lw in
            guard lw.window != nil else { return nil }
            defer { next += 1 }
            return m[next]
        }
    }

    /// "Al Kα", "Cu Lα", "Mg Kβ": the table's line name with Greek letters.
    package static func label(ofLineID id: String) -> String {
        let parts = id.split(separator: "_")
        guard parts.count == 2 else { return id }
        var name = String(parts[1])
        for (a, g) in [("a", "α"), ("b", "β"), ("g", "γ")] where name.count >= 2 && name.dropFirst().hasPrefix(a) {
            name = String(name.prefix(1)) + g + name.dropFirst(2)
            break
        }
        return "\(parts[0]) \(name)"
    }

    /// "background overlaps Si Kα": one line for the conflicts of one result, at most two named. Lines whose INTEGRATION
    /// window the background reaches come first (a peak in the background), then those it only touches on a flank (a tail):
    /// on the owner's file Mg's windows touch Cu Lα's flank and sit on Si Kα's peak, and the peak is the one to say.
    package static func conflictNote(_ conflicts: [WindowConflict]) -> String? {
        var names: [String] = []
        for c in conflicts.filter(\.reachesIntegrationWindow) + conflicts.filter { !$0.reachesIntegrationWindow } {
            let n = label(ofLineID: c.other)
            if !names.contains(n) { names.append(n) }
        }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(2).joined(separator: ", ")
        return "background overlaps \(shown)" + (names.count > 2 ? " +\(names.count - 2) more" : "")
    }
}
