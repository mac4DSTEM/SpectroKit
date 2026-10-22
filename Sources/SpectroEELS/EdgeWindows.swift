//
//  EdgeWindows.swift
//  Role: the per-edge background and signal windows of the EELS model fit, and the one-spectrum power-law preview for a live drag.
//        The convention is the field's (GMS "Background Subtraction" and "Elemental Quantification", eels.info: a power law fitted on a
//        window just below each edge, the signal integrated or fitted over a window above it); no Python counterpart for the windowing,
//        `validation: "none"`. The power law's estimate is HyperSpy's two-area method (`PowerLawBackground.swift`).
//

import Foundation
import SpectroCore

/// The windows one edge is fitted on: a power law on `backgroundEV` (and `secondBackgroundEV` when given, the two concatenated),
/// extrapolated under `signalEV`, where the edge's cross-section amplitude is fitted on the background-subtracted counts.
public struct EdgeWindows: Sendable, Equatable, Codable {
    public var backgroundEV: ClosedRange<Double>
    public var signalEV: ClosedRange<Double>
    public var secondBackgroundEV: ClosedRange<Double>?
    /// Which fallback rule set the background window ("background shares C K's window: edges 85 eV apart"); nil for the ordinary rule.
    public var note: String?

    public init(backgroundEV: ClosedRange<Double>, signalEV: ClosedRange<Double>, secondBackgroundEV: ClosedRange<Double>? = nil, note: String? = nil) {
        self.backgroundEV = backgroundEV; self.signalEV = signalEV; self.secondBackgroundEV = secondBackgroundEV; self.note = note
    }

    // The default rules (documented constants, eV unless a fraction).
    /// The background window ends this far below the onset.
    public static let backgroundGapEV = 5.0
    /// The background window is this fraction of the onset energy wide, clamped to `backgroundWidthLimitsEV`.
    public static let backgroundWidthFraction = 0.2
    public static let backgroundWidthLimitsEV: ClosedRange<Double> = 20 ... 100
    /// The background window stops this far above the preceding edge's signal end.
    public static let precedingEdgeGapEV = 5.0
    /// The signal window starts this far above the onset for an edge with a delayed maximum (L, M, N), at the onset for a K edge.
    public static let delayedSignalOffsetEV = 20.0
    /// The signal window is this fraction of the onset energy wide, clamped to `signalWidthLimitsEV`.
    public static let signalWidthFraction = 0.1
    public static let signalWidthLimitsEV: ClosedRange<Double> = 30 ... 150
    /// The signal window stops this far below the next edge's onset.
    public static let nextEdgeGapEV = 5.0

    /// The default windows of one edge. `family` is the shell letter ("K", "L", "M", ...: `CoreLossEdge.family`); `precedingSignalEndEV` is the
    /// signal end of the edge before this one, `nextOnsetEV` the onset of the one after. Both windows are clipped to the axis; a window the
    /// neighbours squeeze to nothing comes out empty and the fit refuses it by name.
    ///
    /// A preceding edge too close: when the preceding signal end leaves the background window narrower than `backgroundWidthLimitsEV.lowerBound`
    /// and `precedingOnsetEV` is given, the window is the stretch from the preceding onset to this onset minus the gap if that is wide enough
    /// (the fit strips the preceding edge from the spectrum first, so it is not under the window), else `precedingBackgroundEV` (the preceding
    /// edge's own window) is reused. `note` names the rule (with `precedingName`, e.g. "C K"); with neither fallback the window stays empty.
    public static func defaults(onsetEV: Double, family: String, precedingSignalEndEV: Double?, nextOnsetEV: Double?, axis: EnergyAxis,
                                precedingOnsetEV: Double? = nil, precedingBackgroundEV: ClosedRange<Double>? = nil, precedingName: String? = nil) -> EdgeWindows {
        let low = axis.offset, high = axis.offset + axis.scale * Double(axis.size - 1)
        func clip(_ lo: Double, _ hi: Double) -> ClosedRange<Double> {
            let l = min(max(lo, low), high), h = min(max(hi, low), high)
            return l ... max(l, h)
        }
        let bgWidth = min(max(backgroundWidthFraction * onsetEV, backgroundWidthLimitsEV.lowerBound), backgroundWidthLimitsEV.upperBound)
        let bgEnd = onsetEV - backgroundGapEV
        var bgStart = bgEnd - bgWidth
        if let p = precedingSignalEndEV { bgStart = max(bgStart, p + precedingEdgeGapEV) }
        var note: String? = nil
        var bgWindow = clip(bgStart, bgEnd)
        if precedingSignalEndEV != nil, bgWindow.upperBound - bgWindow.lowerBound < backgroundWidthLimitsEV.lowerBound - 1e-9 {
            let who = precedingName ?? "the preceding edge"
            if let po = precedingOnsetEV, bgEnd - po >= backgroundWidthLimitsEV.lowerBound {
                bgWindow = clip(po, bgEnd)
                note = "background between \(who)'s onset and this one: edges \(Int((onsetEV - po).rounded())) eV apart"
            } else if let pb = precedingBackgroundEV {
                bgWindow = clip(pb.lowerBound, pb.upperBound)
                note = "background shares \(who)'s window: edges \(precedingOnsetEV.map { String(Int((onsetEV - $0).rounded())) } ?? "close") eV apart"
            }
        }
        let sigStart = onsetEV + (family == "K" ? 0 : delayedSignalOffsetEV)
        let sigWidth = min(max(signalWidthFraction * onsetEV, signalWidthLimitsEV.lowerBound), signalWidthLimitsEV.upperBound)
        var sigEnd = sigStart + sigWidth
        if let n = nextOnsetEV { sigEnd = min(sigEnd, n - nextEdgeGapEV) }
        return EdgeWindows(backgroundEV: bgWindow, signalEV: clip(sigStart, sigEnd), note: note)
    }

    /// Channels `[first, last]` of `axis` with energy inside `window` (inclusive, 1e-9-channel tolerance); an empty range where none.
    package static func rows(_ window: ClosedRange<Double>, offset: Double, scale: Double, size: Int) -> Range<Int> {
        let first = max(0, Int(((window.lowerBound - offset) / scale - 1e-9).rounded(.up)))
        let last = min(size - 1, Int(((window.upperBound - offset) / scale + 1e-9).rounded(.down)))
        return last >= first ? first ..< (last + 1) : first ..< first
    }
}

public enum EELSBackground {
    case powerLaw

    /// The power law A E^-r of one spectrum by HyperSpy's two-area estimate over `window`, evaluated over `extrapolateTo` (clipped to the axis).
    /// `curve` is counts per channel (A E^-r times the channel width, 0 at E <= 0) on `channels`. Cheap enough for a live drag.
    /// `window` must lie inside the axis, hold at least 4 channels and sit at positive energy. `validation: "none"`.
    public static func preview(counts: [Double], axis: EnergyAxis, window: ClosedRange<Double>, extrapolateTo: ClosedRange<Double>) throws
        -> (parameters: (a: Double, r: Double), curve: [Double], channels: Range<Int>) {
        guard counts.count == axis.size else { throw EELSModelError.edgeWindowInvalid(edge: "preview", why: "counts have \(counts.count) channels, the axis \(axis.size)") }
        let eaxis = try EELSAxis(offset: axis.offset, scale: axis.scale, size: axis.size)
        let w = try PowerLawWindow(axis: eaxis, from: window.lowerBound, to: window.upperBound)
        let fit: PowerLawFit = try counts.withUnsafeBufferPointer { b in
            switch PowerLawFit.estimate(b, window: w) {
            case .success(let f): return f
            case .failure(let why): throw EELSModelError.backgroundNotEstimable("\(why)")
            }
        }
        let channels = EdgeWindows.rows(extrapolateTo, offset: axis.offset, scale: axis.scale, size: axis.size)
        guard !channels.isEmpty else { throw EELSModelError.backgroundWindowEmpty }
        let curve = channels.map { fit.counts(atEnergy: eaxis.energy(ofChannel: $0), scale: axis.scale) }
        return ((fit.a, fit.r), curve, channels)
    }
}
