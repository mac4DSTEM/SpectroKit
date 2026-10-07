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

/// A vertex in continuous pixel-grid coordinates: x in [0, nx], y in [0, ny], pixel (i, j) covering [i, i+1) x [j, j+1).
package nonisolated struct PixelPoint: Equatable, Sendable {
    package var x: Double, y: Double
    package init(x: Double, y: Double) { self.x = x; self.y = y }
}

package nonisolated enum SpectrumRegionShape: Equatable, Sendable {
    case rectangle(PixelRect)
    /// The ellipse inscribed in the rectangle: a pixel is in when its centre is.
    case ellipse(PixelRect)
    /// A closed polygon (the last vertex joins the first): a pixel is in when its centre is inside by the even-odd rule.
    /// Fewer than three vertices hold no pixel.
    case polygon([PixelPoint])

    /// The smallest pixel rectangle that holds the shape (the whole outline for a polygon).
    package var bounds: PixelRect {
        switch self {
        case .rectangle(let r), .ellipse(let r): return r
        case .polygon(let v):
            guard let first = v.first else { return PixelRect(x0: 0, y0: 0, x1: 0, y1: 0) }
            var lx = first.x, hx = first.x, ly = first.y, hy = first.y
            for p in v { lx = min(lx, p.x); hx = max(hx, p.x); ly = min(ly, p.y); hy = max(hy, p.y) }
            return PixelRect(x0: Int(lx.rounded(.down)), y0: Int(ly.rounded(.down)), x1: Int(hx.rounded(.up)), y1: Int(hy.rounded(.up)))
        }
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
        case .polygon(let v):
            guard v.count >= 3 else { return m }
            for y in ys {
                let py = Double(y) + 0.5
                // The crossings of the scanline with the edges, sorted: pixel centres between the 1st and 2nd, 3rd and 4th... are in.
                var xsCross: [Double] = []
                var j = v.count - 1
                for i in 0..<v.count {
                    let a = v[j], b = v[i]
                    if (a.y > py) != (b.y > py) { xsCross.append(a.x + (py - a.y) / (b.y - a.y) * (b.x - a.x)) }
                    j = i
                }
                xsCross.sort()
                var k = 0
                while k + 1 < xsCross.count {
                    for x in xs where Double(x) + 0.5 >= xsCross[k] && Double(x) + 0.5 < xsCross[k + 1] { m[y * nx + x] = true }
                    k += 2
                }
            }
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

    /// The family Velox quantifies an element with by default: K while the element's Kα is at most `veloxKFamilyLimitKeV`,
    /// otherwise L (M only when the table has no L alpha; the person may still pick M).
    ///
    /// DEVIATION from eXSpy (`_get_lines_from_elements`, `XRayLines.defaultLines`: "the first alpha line below the beam energy / 2"):
    /// at 200 kV on an 80 keV axis that picks Kα for Hf (55.8 keV) where Velox uses Lα. Velox's own table (the owner's
    /// SI 1339 file, 200 kV, `docs/archive/v5/velox-family-table-200kV-2026-10-07.json`) gives K for Z <= 44 (Ru Kα 19.28 keV)
    /// and L for Z >= 45 (Rh Kα 20.22 keV), never M; the 20 keV limit is the boundary that table shows, measured on 200 kV
    /// files only. It changes which line a map or marker uses by default, never the fit, which takes whole families.
    package static let veloxKFamilyLimitKeV = 20.0

    package static func defaultFamily(of symbol: String) -> XRayFamily {
        if let ka = XRayLines.line("\(symbol)_Ka"), ka.energy <= veloxKFamilyLimitKeV { return .K }
        if XRayLines.line("\(symbol)_La") != nil { return .L }
        if XRayLines.line("\(symbol)_Ma") != nil { return .M }
        return .K
    }

    /// Which line of `symbol` the windows use: with `family` nil the default family's alpha line (`defaultFamily`), otherwise
    /// that family's alpha line; either only when it lies inside the axis (and below the beam energy). When the default
    /// family's alpha does not (a 10 keV axis for Ru), eXSpy's pick (`defaultLines`) stands in, so an element that has a line
    /// on the axis keeps one.
    package static func lineID(of symbol: String, family: XRayFamily?, axis: EnergyAxis, beamEnergyKeV: Double?) -> String? {
        guard !XRayLines.notRealLines.contains(symbol) else { return nil }   // H and He "Ka" are ionisation energies (`XRayLines.notRealLines`)
        let id = "\(symbol)_\((family ?? defaultFamily(of: symbol)).rawValue)a"
        if let hit = XRayLines.linesInRange([id], axis: axis, beamEnergy: beamEnergyKeV).first { return hit }
        return family == nil ? XRayLines.defaultLines(elements: [symbol], axis: axis, beamEnergy: beamEnergyKeV).first : nil
    }

    /// One element of a map: its family (nil = the default) and the lines the person checked (empty = the family's alpha line).
    package struct Pick: Sendable {
        package var symbol: String
        package var family: XRayFamily?
        package var lines: [String]
        package init(symbol: String, family: XRayFamily? = nil, lines: [String] = []) {
            self.symbol = symbol; self.family = family; self.lines = lines
        }
    }

    /// The windows of every element in `elements` (symbol, family override), in that order. Windows are built
    /// together, as eXSpy does, so neighbouring lines merge their background windows; `conflicts` reports every other
    /// table line of the same elements that a background window then lies on (REPORT only, the counts are eXSpy's).
    package static func build(
        elements: [(symbol: String, family: XRayFamily?)], axis: EnergyAxis,
        resolutionMnKaEV: Double = defaultResolutionMnKaEV, beamEnergyKeV: Double?
    ) -> [LineWindow] {
        build(picks: elements.map { Pick(symbol: $0.symbol, family: $0.family) }, axis: axis,
              resolutionMnKaEV: resolutionMnKaEV, beamEnergyKeV: beamEnergyKeV)
    }

    /// As `build(elements:)`, with the lines the person checked: one window per checked line that lies on the axis, in energy
    /// order, after the element's neighbours (a line off the axis is dropped; none left is the element's "no usable line").
    /// An element with no checked line gets its family's alpha window. All windows are built together. Two checked lines of one
    /// element closer than a window (Al Kα 1.487 and Kβ 1.557 keV) would overlap; the later window's signal is clipped to start
    /// where the earlier one ends and its background scale shrinks with it (`clipOverlaps`), so a summed map counts every
    /// channel once — the sum of the clipped nets is the net over the union of the signal channels.
    package static func build(
        picks: [Pick], axis: EnergyAxis,
        resolutionMnKaEV: Double = defaultResolutionMnKaEV, beamEnergyKeV: Double?
    ) -> [LineWindow] {
        struct Entry { let symbol: String; let line: SpectralLine? }
        let entries: [Entry] = picks.flatMap { p -> [Entry] in
            var ids: [String] = []
            if p.lines.isEmpty {
                ids = lineID(of: p.symbol, family: p.family, axis: axis, beamEnergyKeV: beamEnergyKeV).map { [$0] } ?? []
            } else {
                let inRange = XRayLines.linesInRange(p.lines, axis: axis, beamEnergy: beamEnergyKeV)
                ids = inRange.sorted { (XRayLines.line($0)?.energy ?? 0, $0) < (XRayLines.line($1)?.energy ?? 0, $1) }
            }
            let lines = ids.compactMap { try? SpectralLine(id: $0, resolutionMnKaEV: resolutionMnKaEV) }
            return lines.isEmpty ? [Entry(symbol: p.symbol, line: nil)] : lines.map { Entry(symbol: p.symbol, line: $0) }
        }
        let lines = entries.compactMap(\.line)
        let integration = WindowIntensity.integrationWindows(lines: lines)
        let background = BackgroundWindows.estimate(lines: lines)
        let candidates = WindowIntensity.candidateLines(
            elements: picks.map(\.symbol).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }, resolutionMnKaEV: resolutionMnKaEV, axis: axis)
        let conflicts = WindowIntensity.conflicts(lines: lines, background: background, candidates: candidates)
        var out: [LineWindow] = []
        var next = 0
        for pick in entries {
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
        return clipOverlaps(out)
    }

    /// Where two windows of ONE element overlap in signal channels, the later (higher-energy) one starts where the earlier
    /// ends; its background scale is reduced by the kept fraction of its signal width (`scale = signalWidth / backgroundWidth`,
    /// `_eds.py:679`). Windows of different elements are left as eXSpy builds them. A window fully inside the earlier one keeps
    /// one channel (the net of an empty window would be the background alone).
    package static func clipOverlaps(_ windows: [LineWindow]) -> [LineWindow] {
        var out = windows
        var lastEnd: [String: Int] = [:]
        for i in out.indices.sorted(by: { (out[$0].energy, $0) < (out[$1].energy, $1) }) {
            guard let w = out[i].window else { continue }
            let element = out[i].element
            if let end = lastEnd[element], end > w.signal.lowerBound {
                let start = min(end, w.signal.upperBound - 1)
                let kept = Double(w.signal.upperBound - start) / Double(max(w.signal.count, 1))
                let bg = w.background.map { ResolvedWindow.Background(left: $0.left, right: $0.right, scale: $0.scale * kept) }
                out[i] = LineWindow(element: element, id: out[i].id, energy: out[i].energy, fwhm: out[i].fwhm,
                                    window: ResolvedWindow(signal: start..<w.signal.upperBound, background: bg),
                                    failure: out[i].failure, conflicts: out[i].conflicts)
            }
            lastEnd[element] = max(lastEnd[element] ?? 0, out[i].window?.signal.upperBound ?? 0)
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

    /// The integrated-intensity map of every window that has one (the room's "int" mode): the exact signal-window sum per
    /// pixel, no background taken off, so it is the net map plus the background term the net map subtracts.
    package static func integratedMaps(image: some SpectrumImage, windows: [LineWindow]) -> [[Double]?] {
        let sums = image.windowSums(windows.compactMap { $0.window?.signal })
        var next = 0
        return windows.map { lw in
            guard lw.window != nil else { return nil }
            defer { next += 1 }
            return sums[next].map { Double($0) }
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

    /// "Kα", "Lβ1": the line's name without its element, as the Lines menu lists it.
    package static func shortLabel(ofLineID id: String) -> String {
        let full = label(ofLineID: id)
        guard let space = full.firstIndex(of: " ") else { return full }
        return String(full[full.index(after: space)...])
    }

    /// One element's lines in a sentence: "Al Kα+Kβ" for two lines of one family, "Pt Lα+Mα" across families; the
    /// element named once. nil for no line.
    package static func summary(ofLineIDs ids: [String]) -> String? {
        guard let first = ids.first else { return nil }
        let rest = ids.dropFirst().map { shortLabel(ofLineID: $0) }
        return ([label(ofLineID: first)] + rest).joined(separator: "+")
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
