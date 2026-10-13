//
//  SpectrumImage.swift
//  Role: What the spectral maths needs from an EDX spectrum image, whatever holds it: a
//        raster of `ny x nx` pixels with `channels` counts each. Two implementations:
//        `DenseSpectrumImage` (a DM4 EDS SI, a small cube) and `SparseSpectrumImage`
//        (per-pixel CSR: row offsets, channel indices, counts), which is the shape of
//        the Velox event store.
//
//  Counts are integers and every sum here is an exact `UInt64` sum, so a window map
//  from the sparse store and from the same data densified is identical bit for bit
//  (pre-registration C2): the only floating-point step is the net-count formula in
//  `WindowIntensity`, which both paths share.
//
//  Joining Velox (lane A, `VeloxEventStore`, not in this tree): it already has
//  `geometry.ny/nx/channels`, `rowOffsets: [Int]`, `channelIndex: [UInt16]`,
//  `counts: [UInt32]`. Conform it with
//      extension VeloxEventStore: CSRSpectrumStore {
//          package var ny: Int { geometry.ny };  package var nx: Int { geometry.nx }
//          package var channels: Int { geometry.channels }
//      }
//  and build the image with `try SparseSpectrumImage(store)` (it validates the CSR contract). The arrays are shared
//  copy-on-write, nothing is copied.
//

import Foundation

/// Pixels to include in a sum: row-major `y * nx + x`, `true` = in. `nil` means every pixel.
package typealias PixelMask = [Bool]

package nonisolated protocol SpectrumImage: Sendable {
    var ny: Int { get }
    var nx: Int { get }
    var channels: Int { get }

    /// Summed spectrum over the masked pixels (`channels` entries, exact).
    /// A mask of the wrong length is a programming error.
    func sum(mask: PixelMask?) -> [UInt64]

    /// For every channel range, the per-pixel exact sum of counts inside it
    /// (outer index = range, inner = pixel, row-major). Ranges are half-open and may overlap.
    func windowSums(_ ranges: [Range<Int>]) -> [[UInt64]]

    /// The same sums, cancellable (ADR 064 amendment 2 §2): `cancelled` is asked once per block of pixels, never per value, and
    /// `SpectroCancelled` is thrown with nothing kept; `progress` is monotone in 0...1 and ends at 1. A conformer that does not
    /// implement it gets the default below (one check before the plain call). The default `cancelled` of the concrete types
    /// and of `ElementWindows` is `SpectroCancellation.task`; a protocol requirement cannot carry it, so a caller through
    /// `any SpectrumImage` passes it.
    func sum(mask: PixelMask?, cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?) throws -> [UInt64]
    func windowSums(_ ranges: [Range<Int>], cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?) throws -> [[UInt64]]
}

extension SpectrumImage {
    package nonisolated var pixelCount: Int { ny * nx }

    package func sum(mask: PixelMask?, cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?) throws -> [UInt64] {
        try SpectroCancellation.check(cancelled)
        let out = sum(mask: mask)
        progress?(1)
        return out
    }

    package func windowSums(_ ranges: [Range<Int>], cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?) throws -> [[UInt64]] {
        try SpectroCancellation.check(cancelled)
        let out = windowSums(ranges)
        progress?(1)
        return out
    }
}

/// Pixels between two cancellation checks of the spectrum-image loops (a block, never a value).
private nonisolated let spectrumBlockPixels = 4096

/// The shape of a per-pixel compressed-sparse-row spectrum store. `rowOffsets` has
/// `ny * nx + 1` entries into `channelIndex` / `counts`; channels inside a pixel ascend and
/// each appears once (Velox event store contract).
package nonisolated protocol CSRSpectrumStore: Sendable {
    var ny: Int { get }
    var nx: Int { get }
    var channels: Int { get }
    var rowOffsets: [Int] { get }
    var channelIndex: [UInt16] { get }
    var counts: [UInt32] { get }
}

// MARK: - Dense

/// `(ny, nx, channels)` row-major counts.
package nonisolated struct DenseSpectrumImage: SpectrumImage {
    package let ny: Int
    package let nx: Int
    package let channels: Int
    package let counts: [UInt32]

    package init(ny: Int, nx: Int, channels: Int, counts: [UInt32]) {
        precondition(counts.count == ny * nx * channels, "DenseSpectrumImage: counts must be ny*nx*channels")
        self.ny = ny; self.nx = nx; self.channels = channels; self.counts = counts
    }

    package func sum(mask: PixelMask?) -> [UInt64] {
        // The closure never answers true, so the throwing core cannot throw.
        try! sum(mask: mask, cancelled: { false }, progress: nil)
    }

    package func sum(mask: PixelMask?, cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                     progress: (@Sendable (Double) -> Void)? = nil) throws -> [UInt64] {
        precondition(mask == nil || mask!.count == ny * nx, "mask length must be ny*nx")
        var out = [UInt64](repeating: 0, count: channels)
        let n = ny * nx
        for start in stride(from: 0, to: n, by: spectrumBlockPixels) {
            try SpectroCancellation.check(cancelled)
            for p in start..<min(start + spectrumBlockPixels, n) where mask?[p] ?? true {
                let base = p * channels
                for c in 0..<channels { out[c] &+= UInt64(counts[base + c]) }
            }
            progress?(Double(min(start + spectrumBlockPixels, n)) / Double(n))
        }
        if n == 0 { progress?(1) }
        return out
    }

    package func windowSums(_ ranges: [Range<Int>]) -> [[UInt64]] {
        try! windowSums(ranges, cancelled: { false }, progress: nil)
    }

    package func windowSums(_ ranges: [Range<Int>], cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                            progress: (@Sendable (Double) -> Void)? = nil) throws -> [[UInt64]] {
        let n = ny * nx
        var out = [[UInt64]](repeating: [UInt64](repeating: 0, count: n), count: ranges.count)
        let total = Double(max(ranges.count * n, 1))
        for (r, range) in ranges.enumerated() {
            let lo = max(range.lowerBound, 0), hi = min(range.upperBound, channels)
            for start in stride(from: 0, to: n, by: spectrumBlockPixels) {
                try SpectroCancellation.check(cancelled)
                let end = min(start + spectrumBlockPixels, n)
                if lo < hi {
                    for p in start..<end {
                        var s: UInt64 = 0
                        let base = p * channels
                        for c in lo..<hi { s &+= UInt64(counts[base + c]) }
                        out[r][p] = s
                    }
                }
                progress?(Double(r * n + end) / total)
            }
        }
        if ranges.isEmpty || n == 0 { progress?(1) }
        return out
    }
}

// MARK: - Sparse

package nonisolated enum CSRSpectrumError: Error, Equatable, Sendable {
    case rowOffsetCount(expected: Int, got: Int)
    case arraysDisagree
    case offsetsDecrease(pixel: Int)
    case channelOutOfRange(pixel: Int, channel: Int)
    /// A duplicate channel inside a pixel is reported here too (not strictly ascending).
    case channelsNotAscending(pixel: Int, channel: Int)
}

/// Per-pixel CSR spectra; the cube is never densified.
package nonisolated struct SparseSpectrumImage: SpectrumImage {
    package let ny: Int
    package let nx: Int
    package let channels: Int
    package let rowOffsets: [Int]
    package let channelIndex: [UInt16]
    package let counts: [UInt32]

    /// Validates the CSR contract in one O(N) pass (a store may come from a file): offsets start at 0,
    /// never decrease and end at `counts.count`; every channel index is < `channels` and strictly
    /// ascends inside its pixel. Throws `CSRSpectrumError`.
    package init(ny: Int, nx: Int, channels: Int, rowOffsets: [Int], channelIndex: [UInt16], counts: [UInt32]) throws {
        guard rowOffsets.count == ny * nx + 1 else { throw CSRSpectrumError.rowOffsetCount(expected: ny * nx + 1, got: rowOffsets.count) }
        guard channelIndex.count == counts.count, rowOffsets.first == 0, rowOffsets.last == counts.count else {
            throw CSRSpectrumError.arraysDisagree
        }
        for p in 0..<(ny * nx) {
            let lo = rowOffsets[p], hi = rowOffsets[p + 1]
            guard lo <= hi, hi <= counts.count else { throw CSRSpectrumError.offsetsDecrease(pixel: p) }
            var previous = -1
            for k in lo..<hi {
                let c = Int(channelIndex[k])
                guard c < channels else { throw CSRSpectrumError.channelOutOfRange(pixel: p, channel: c) }
                guard c > previous else { throw CSRSpectrumError.channelsNotAscending(pixel: p, channel: c) }
                previous = c
            }
        }
        self.ny = ny; self.nx = nx; self.channels = channels
        self.rowOffsets = rowOffsets; self.channelIndex = channelIndex; self.counts = counts
    }

    package init(_ s: some CSRSpectrumStore) throws {
        try self.init(ny: s.ny, nx: s.nx, channels: s.channels,
                  rowOffsets: s.rowOffsets, channelIndex: s.channelIndex, counts: s.counts)
    }

    package func sum(mask: PixelMask?) -> [UInt64] {
        try! sum(mask: mask, cancelled: { false }, progress: nil)
    }

    package func sum(mask: PixelMask?, cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                     progress: (@Sendable (Double) -> Void)? = nil) throws -> [UInt64] {
        precondition(mask == nil || mask!.count == ny * nx, "mask length must be ny*nx")
        var out = [UInt64](repeating: 0, count: channels)
        let n = ny * nx
        for start in stride(from: 0, to: n, by: spectrumBlockPixels) {
            try SpectroCancellation.check(cancelled)
            for p in start..<min(start + spectrumBlockPixels, n) where mask?[p] ?? true {
                for k in rowOffsets[p]..<rowOffsets[p + 1] { out[Int(channelIndex[k])] &+= UInt64(counts[k]) }
            }
            progress?(Double(min(start + spectrumBlockPixels, n)) / Double(n))
        }
        if n == 0 { progress?(1) }
        return out
    }

    package func windowSums(_ ranges: [Range<Int>]) -> [[UInt64]] {
        try! windowSums(ranges, cancelled: { false }, progress: nil)
    }

    package func windowSums(_ ranges: [Range<Int>], cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                            progress: (@Sendable (Double) -> Void)? = nil) throws -> [[UInt64]] {
        let n = ny * nx
        var out = [[UInt64]](repeating: [UInt64](repeating: 0, count: n), count: ranges.count)
        // One pass over the events: each event is tested against every window.
        // Channels ascend inside a pixel, so a pixel's scan stops at the highest upper bound.
        let los = ranges.map { $0.lowerBound }, his = ranges.map { $0.upperBound }
        let maxHi = his.max() ?? 0
        for start in stride(from: 0, to: n, by: spectrumBlockPixels) {
            try SpectroCancellation.check(cancelled)
            for p in start..<min(start + spectrumBlockPixels, n) {
                for k in rowOffsets[p]..<rowOffsets[p + 1] {
                    let c = Int(channelIndex[k])
                    if c >= maxHi { break }
                    let v = UInt64(counts[k])
                    for r in 0..<ranges.count where c >= los[r] && c < his[r] { out[r][p] &+= v }
                }
            }
            progress?(Double(min(start + spectrumBlockPixels, n)) / Double(n))
        }
        if n == 0 { progress?(1) }
        return out
    }
}

/// A dense image from a sparse one; small cubes only (tests, parity).
extension SparseSpectrumImage {
    package func densified() -> DenseSpectrumImage {
        try! densified(cancelled: { false }, progress: nil)
    }

    package func densified(cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                           progress: (@Sendable (Double) -> Void)? = nil) throws -> DenseSpectrumImage {
        var out = [UInt32](repeating: 0, count: ny * nx * channels)
        let n = ny * nx
        for start in stride(from: 0, to: n, by: spectrumBlockPixels) {
            try SpectroCancellation.check(cancelled)
            for p in start..<min(start + spectrumBlockPixels, n) {
                for k in rowOffsets[p]..<rowOffsets[p + 1] { out[p * channels + Int(channelIndex[k])] = counts[k] }
            }
            progress?(Double(min(start + spectrumBlockPixels, n)) / Double(n))
        }
        if n == 0 { progress?(1) }
        return DenseSpectrumImage(ny: ny, nx: nx, channels: channels, counts: out)
    }
}
