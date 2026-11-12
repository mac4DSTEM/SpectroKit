//
//  EELSRegionSum.swift
//  Role: the summed spectrum of a region: the counts of every masked-in
//        pixel added channel by channel, as a one-pixel image on the same energy axis.
//

import Foundation
import SpectroCore

extension EELSSpectrumImage {
    /// The sum of the spectra of the pixels where `mask` is true (row-major, one entry per pixel), as a 1 x 1 image with the same axis.
    /// Counts are added pixel by pixel in row-major order. Throws `maskShapeMismatch` for a wrong length and `emptyMask` when no pixel is selected.
    public func sum(mask: PixelMask) throws -> Self {
        guard mask.count == pixelCount else { throw EELSModelError.maskShapeMismatch(expected: pixelCount, got: mask.count) }
        guard mask.contains(true) else { throw EELSModelError.emptyMask }
        var total = [Double](repeating: 0, count: channels)
        let n = channels
        // A row at a time (a float32 cube is never widened whole: SpectroKit#94); the same additions in the same order.
        let stored = storedCounts
        for p in 0 ..< pixelCount where mask[p] {
            stored.withRow(start: p * n, count: n) { row in
                for k in 0 ..< n { total[k] += row[k] }
            }
        }
        return try Self(nx: 1, ny: 1, channels: n, counts: total, energyOffsetEV: energyOffsetEV, energyScaleEV: energyScaleEV)
    }
}
