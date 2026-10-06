//
//  WindowIntensity.swift
//  Role: eXSpy's window-based line intensities: integration windows, the two background
//        windows with their overlap merge, and net counts per spectrum or per pixel.
//        Counts only, no k-factors, no fit.
//
//  Ported from eXSpy 7185a4d1 `exspy/signals/_eds.py`:
//    estimate_integration_windows  :744-785   (E +- windows_width * FWHM / 2, default 2.0)
//    estimate_background_windows   :787-838   (line_width [2, 2], windows_width 1; merge at :833-843)
//    get_lines_intensity           :541-715   (window sums :654-664, background :665-684)
//  on HyperSpy 2.4.0 slicing (`EnergyAxis`). The window sum is a plain sum of channel
//  counts: EDS axes are binned, `integrate1D` does not multiply by the channel width.
//

import Foundation

/// A line the windows are built around: its energy and the detector's line width there, keV.
package nonisolated struct SpectralLine: Equatable, Sendable {
    package let id: String
    package let energy: Double
    package let fwhm: Double

    package init(id: String, energy: Double, fwhm: Double) {
        self.id = id; self.energy = energy; self.fwhm = fwhm
    }

    /// `Element_Line` from the table with the width law at the detector's Mn Kα resolution (eV).
    /// Throws for a line the table lacks, or one whose width the law cannot give (eXSpy: ValueError).
    package init(id: String, resolutionMnKaEV: Double) throws {
        guard let l = XRayLines.line(id) else { throw SpectralLineError.unknownLine(id) }
        guard let f = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: l.energy) else {
            throw SpectralLineError.widthUndefined(id, resolutionMnKaEV: resolutionMnKaEV)
        }
        self.init(id: id, energy: l.energy, fwhm: f)
    }
}

package nonisolated enum SpectralLineError: Error, Equatable, Sendable {
    case unknownLine(String)
    /// Fiori-Newbury has no real width: 2.5 (E - E_MnKα) 1000 + res² < 0.
    case widthUndefined(String, resolutionMnKaEV: Double)
}

package nonisolated enum BackgroundWindows {
    /// `estimate_background_windows`: per line `[left start, left end, right start, right end]` (keV).
    /// Left = E - w0 F - W F ... E - w0 F; right = E + w1 F ... E + w1 F + W F, with
    /// `line_width = [w0, w1]`, `windows_width = W`, F the line's FWHM. Overlapping windows
    /// of different lines are then merged exactly as eXSpy does (see `merge`).
    package static func estimate(
        lines: [SpectralLine], lineWidth: [Double] = [2, 2], windowsWidth: Double = 1
    ) -> [[Double]] {
        var w: [[Double]] = lines.map { l in
            [l.energy - l.fwhm * lineWidth[0] - l.fwhm * windowsWidth,
             l.energy - l.fwhm * lineWidth[0],
             l.energy + l.fwhm * lineWidth[1],
             l.energy + l.fwhm * lineWidth[1] + l.fwhm * windowsWidth]
        }
        merge(&w)
        return w
    }

    /// eXSpy `_eds.py:833-843`: order the lines by their first value (`argsort(axis=0)[:, 0]`), and
    /// walking neighbours in that order, when the earlier line's right-window START exceeds the later
    /// line's left-window START, both lines get `[earlier left window, later right window]`.
    /// The walk is sequential, so a merged row feeds the next comparison (as in the original).
    /// DEVIATION: numpy's default argsort (quicksort) is not stable; equal first values are ordered
    /// here by line position. Equal left-window starts of two different lines cannot occur for
    /// distinct line energies and would only swap which of two identical rows is read first.
    package static func merge(_ w: inout [[Double]]) {
        guard w.count > 1 else { return }
        let order = w.indices.sorted { (w[$0][0], $0) < (w[$1][0], $1) }
        for i in 0..<(order.count - 1) {
            let ia = order[i], ib = order[i + 1]
            if w[ia][2] > w[ib][0] {
                let interval = [w[ia][0], w[ia][1], w[ib][2], w[ib][3]]
                w[ia] = interval
                w[ib] = interval
            }
        }
    }
}

/// One line's windows resolved to channels. Nothing here depends on how the counts are stored.
package nonisolated struct ResolvedWindow: Equatable, Sendable {
    package struct Background: Equatable, Sendable {
        package let left: Range<Int>
        package let right: Range<Int>
        /// `(i5 - i4) / ((i1 - i0) + (i3 - i2))` on the rounded indices (`_eds.py:679`).
        package let scale: Double
    }
    package let signal: Range<Int>
    package let background: Background?

    /// The channel ranges to sum, in the order `netCounts(fromSums:)` reads them: signal, then
    /// (left, right) when there is a background.
    package var ranges: [Range<Int>] {
        guard let b = background else { return [signal] }
        return [signal, b.left, b.right]
    }

    /// `img - (bck1 + bck2) * corr_factor` as eXSpy computes it: the integer sums are added first,
    /// converted to float, scaled, and subtracted from the float signal.
    package func netCounts(fromSums s: [UInt64]) -> Double {
        net(s[0], s.count > 2 ? s[1] : 0, s.count > 2 ? s[2] : 0)
    }

    /// The one formula, shared by the spectrum and the per-pixel paths.
    @inline(__always)
    package func net(_ signal: UInt64, _ left: UInt64, _ right: UInt64) -> Double {
        guard let b = background else { return Double(signal) }
        return Double(signal) - Double(left &+ right) * b.scale
    }
}

package nonisolated enum WindowIntensityError: Error, Equatable, Sendable {
    /// `(i1 - i0) + (i3 - i2) == 0`: Python's float division raises ZeroDivisionError here.
    case emptyBackgroundWindows
    case axis(EnergyAxisError)
}

package nonisolated enum WindowIntensity {
    /// `estimate_integration_windows`: `[E - W F / 2, E + W F / 2]` per line (keV).
    package static func integrationWindows(lines: [SpectralLine], windowsWidth: Double = 2.0) -> [[Double]] {
        lines.map { l in
            let det = windowsWidth * l.fwhm / 2.0
            return [l.energy - det, l.energy + det]
        }
    }

    /// Channels of one line's windows. Without a background the integration window is sliced
    /// (`isig[a:b]`, clamping at the axis ends). With one, eXSpy first converts all six edges
    /// with `value2index` (`_eds.py:668-669`), which raises for any edge outside the axis, so
    /// this throws too; a background window whose two rounded edges coincide is the single
    /// channel `isig[bw[0]]` (`:670-677`).
    package static func resolve(
        integration: [Double], background: [Double]?, axis: EnergyAxis
    ) throws -> ResolvedWindow {
        do {
            let signal = try axis.channelRange(from: integration[0], to: integration[1])
            guard let bw = background else { return ResolvedWindow(signal: signal, background: nil) }
            let i = try (bw + integration).map { try axis.index(of: $0) }
            let left = i[0] == i[1] ? try axis.singleChannel(at: bw[0]) : try axis.channelRange(from: bw[0], to: bw[1])
            let right = i[2] == i[3] ? try axis.singleChannel(at: bw[2]) : try axis.channelRange(from: bw[2], to: bw[3])
            let denominator = Double((i[1] - i[0]) + (i[3] - i[2]))
            guard denominator != 0 else { throw WindowIntensityError.emptyBackgroundWindows }
            return ResolvedWindow(signal: signal, background: .init(
                left: left, right: right, scale: Double(i[5] - i[4]) / denominator))
        } catch let e as EnergyAxisError {
            throw WindowIntensityError.axis(e)
        }
    }

    /// Net counts of every window in one spectrum.
    package static func netCounts(spectrum: [UInt64], windows: [ResolvedWindow]) -> [Double] {
        windows.map { w in
            w.netCounts(fromSums: w.ranges.map { r in
                let lo = max(r.lowerBound, 0), hi = min(r.upperBound, spectrum.count)
                var s: UInt64 = 0
                if lo < hi { for c in lo..<hi { s &+= spectrum[c] } }
                return s
            })
        }
    }

    /// Net-count map per window (outer = window, inner = pixel, row-major), any `SpectrumImage`.
    package static func maps(image: some SpectrumImage, windows: [ResolvedWindow]) -> [[Double]] {
        let sums = image.windowSums(windows.flatMap(\.ranges))
        let n = image.pixelCount
        var out: [[Double]] = []
        var next = 0
        for w in windows {
            var m = [Double](repeating: 0, count: n)
            if w.background == nil {
                let a = sums[next]
                for p in 0..<n { m[p] = w.net(a[p], 0, 0) }
                next += 1
            } else {
                let a = sums[next], l = sums[next + 1], r = sums[next + 2]
                for p in 0..<n { m[p] = w.net(a[p], l[p], r[p]) }
                next += 3
            }
            out.append(m)
        }
        return out
    }
}

// MARK: - Which other lines a background window sits on

/// One place where line `line`'s (merged) background window lies on another line.
package nonisolated struct WindowConflict: Equatable, Sendable {
    package enum Side: String, Sendable { case left, right }
    /// The line whose net counts the background correction biases.
    package let line: String
    package let side: Side
    /// The other line, its energy and its full interval `[E - h, E + h]`, `h = max(2 FWHM, half integration window)`.
    package let other: String
    package let otherEnergy: Double
    package let overlap: ClosedRange<Double>
    /// True when the overlap reaches the other line's integration window (E +- width FWHM / 2), not only its flank.
    package let reachesIntegrationWindow: Bool
}

nonisolated extension WindowIntensity {
    /// The candidates for `conflicts`: every table line of `elements` inside the axis, with weight >= `minWeight`.
    package static func candidateLines(
        elements: [String], resolutionMnKaEV: Double, axis: EnergyAxis, minWeight: Double = 0.01
    ) -> [SpectralLine] {
        elements.flatMap { XRayLines.lines(of: $0) }
            .filter { $0.weight >= minWeight && axis.lowValue < $0.energy && $0.energy < axis.highValue }
            .compactMap { try? SpectralLine(id: $0.id, resolutionMnKaEV: resolutionMnKaEV) }
    }

    /// For each of `lines`, where its `background` windows (the MERGED ones, as `BackgroundWindows.estimate`
    /// returns and `resolve` uses) intersect another line of `candidates`: the line's integration window or
    /// its flank to +-2 FWHM, sub-lines (Al Kβ 1.5596 keV) included. The line itself is skipped, and any
    /// candidate with the same id. Keyed by position in `lines`; ordered by overlap start.
    ///
    /// This only REPORTS: the counts are eXSpy's and unchanged. Why it exists: eXSpy's merge chains
    /// neighbouring lines, so Mg's right background window can end up on Si Kα's low flank, biasing
    /// Mg low when Si is strong (and Al/Si are corrected by windows straddling two peaks).
    package static func conflicts(
        lines: [SpectralLine], background: [[Double]], candidates: [SpectralLine], integrationWidth: Double = 2.0
    ) -> [[WindowConflict]] {
        lines.indices.map { i in
            var out: [WindowConflict] = []
            let bw = background[i]
            for (side, lo, hi) in [(WindowConflict.Side.left, bw[0], bw[1]), (.right, bw[2], bw[3])] {
                for c in candidates where c.id != lines[i].id {
                    let flank = max(2 * c.fwhm, integrationWidth * c.fwhm / 2)
                    let a = max(lo, c.energy - flank), b = min(hi, c.energy + flank)
                    guard a <= b else { continue }
                    let half = integrationWidth * c.fwhm / 2
                    out.append(WindowConflict(
                        line: lines[i].id, side: side, other: c.id, otherEnergy: c.energy, overlap: a...b,
                        reachesIntegrationWindow: max(lo, c.energy - half) <= min(hi, c.energy + half)))
                }
            }
            return out.sorted { ($0.overlap.lowerBound, $0.other) < ($1.overlap.lowerBound, $1.other) }
        }
    }
}
