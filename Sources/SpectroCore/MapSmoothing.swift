//
//  MapSmoothing.swift
//  DSTEMCore
//
//  A count-conserving spatial filter for element maps (Velox 3.15 "pre-filter": Average or Gaussian, "counts are
//  redistributed and the total is conserved", UM pp. 64-68). Here it is display only: the controller applies it to the signed
//  net-count map before the display clamp, the raw map stays what the file gave, the export writes the raw map, and every
//  tile names the kernel. Nothing a quantification reads passes through it (ADR 054: at% on pooled spectra only).
//
//  Conservation: a normalised kernel conserves the total wherever its whole window is inside the map; at the border the
//  weights are renormalised over the in-bounds taps, so a flat map stays flat to the edge (no dark rim, the mean per pixel is
//  kept) — the total then moves only by what the border rows exchange with nothing, which a display never reads. A
//  zero-padded convolution would darken the rim; a reflected one would double the edge. Separable: one pass per axis.
//

import Foundation

/// A one-dimensional smoothing kernel for `MapSmoothing.apply(_:width:height:kernel:)`, applied along each axis in turn and
/// renormalised over the in-bounds taps at the border. The menu of `MapSmoothing` is five of these. The smoothed map is a plain
/// array with no notes: a caller that shows a map smoothed with a kernel of its own records the kernel beside the map.
public nonisolated enum SmoothingKernel: Sendable, Equatable, Codable {
    /// A box of `width` taps (odd, at least 1): 3 and 5 are the menu's.
    case box(width: Int)
    /// A Gaussian of standard deviation `sigma` pixels, cut at `truncation` standard deviations (taps out to `ceil(truncation * sigma)`
    /// pixels): the menu has sigma 1 and 2 with a truncation of 2, which holds 95 % of the weight.
    case gaussian(sigma: Double, truncation: Double = 2)

    /// The taps, centred, odd length. Empty when the kernel is not valid (see `isValid`).
    public var taps: [Double] {
        switch self {
        case .box(let width):
            return isValid ? [Double](repeating: 1, count: width) : []
        case .gaussian(let sigma, let truncation):
            guard isValid else { return [] }
            let r = Int((truncation * sigma).rounded(.up))   // ±2σ holds 95 % of the weight; the renormalisation keeps the sum exact
            return (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        }
    }

    /// A box needs an odd positive width; a Gaussian a positive finite sigma and a positive finite truncation.
    public var isValid: Bool {
        switch self {
        case .box(let width): return width >= 1 && width % 2 == 1
        case .gaussian(let sigma, let truncation): return sigma.isFinite && sigma > 0 && truncation.isFinite && truncation > 0
        }
    }
}

public nonisolated enum MapSmoothing: String, CaseIterable, Sendable, Codable {
    case none, box3, box5, gaussian1, gaussian2

    /// What a tile header and a file name say ("net · 3 × 3"); empty for none.
    public var label: String {
        switch self {
        case .none: ""
        case .box3: "3 \u{00D7} 3"
        case .box5: "5 \u{00D7} 5"
        case .gaussian1: "\u{03C3} 1 px"
        case .gaussian2: "\u{03C3} 2 px"
        }
    }

    /// A file-name-safe form ("3x3", "s1px"); empty for none.
    public var fileTag: String {
        switch self {
        case .none: ""
        case .box3: "3x3"
        case .box5: "5x5"
        case .gaussian1: "s1px"
        case .gaussian2: "s2px"
        }
    }

    /// The menu entry as a `SmoothingKernel`; nil for none.
    public var smoothingKernel: SmoothingKernel? {
        switch self {
        case .none: return nil
        case .box3: return .box(width: 3)
        case .box5: return .box(width: 5)
        case .gaussian1: return .gaussian(sigma: 1)
        case .gaussian2: return .gaussian(sigma: 2)
        }
    }

    /// The one-dimensional kernel, centred, odd length; `[1]` for none.
    package var kernel: [Double] { smoothingKernel?.taps ?? [1] }

    /// The map filtered with any valid kernel, row-major `width × height`; the input when the kernel is not valid or the shape does
    /// not match. `MapSmoothing.box3.apply(...)` is `apply(..., kernel: .box(width: 3))`.
    public static func apply(_ map: [Double], width: Int, height: Int, kernel: SmoothingKernel) -> [Double] {
        guard kernel.isValid, width > 0, height > 0, map.count == width * height else { return map }
        let k = kernel.taps
        let rows = pass(map, length: width, count: height, stride: 1, lineStride: width, kernel: k)
        return pass(rows, length: height, count: width, stride: width, lineStride: 1, kernel: k)
    }

    /// The filtered map, row-major `width × height`; the input when none, or when the shape does not match.
    public func apply(_ map: [Double], width: Int, height: Int) -> [Double] {
        guard self != .none, width > 0, height > 0, map.count == width * height else { return map }
        let k = kernel
        let rows = Self.pass(map, length: width, count: height, stride: 1, lineStride: width, kernel: k)
        return Self.pass(rows, length: height, count: width, stride: width, lineStride: 1, kernel: k)
    }

    /// One pass along lines of `length` samples (`stride` apart), `count` lines (`lineStride` apart): each output is the
    /// kernel-weighted mean of its in-bounds window.
    static func pass(_ v: [Double], length: Int, count: Int, stride: Int, lineStride: Int, kernel k: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: v.count)
        let r = k.count / 2
        for line in 0..<count {
            let base = line * lineStride
            for i in 0..<length {
                let lo = max(0, i - r), hi = min(length - 1, i + r)
                var w = 0.0, acc = 0.0
                for j in lo...hi { let kj = k[j - i + r]; w += kj; acc += v[base + j * stride] * kj }
                out[base + i * stride] = w > 0 ? acc / w : v[base + i * stride]
            }
        }
        return out
    }
}
