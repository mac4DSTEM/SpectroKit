//
//  LowLossSpectrumImage.swift
//  Role: The input of the thickness map: a low-loss EELS spectrum image, counts per pixel per channel on a uniform
//        energy axis in eV with the zero-loss peak at 0 eV.
//

import Foundation

/// A low-loss EELS spectrum image: `ny x nx` pixels of `channels` counts each on a uniform energy axis.
///
/// Layout: `counts[(y * nx + x) * channels + c]`, row-major in y, then x, then channel (the order of exSpy's
/// `(rows, cols, channels)` array). The energy of channel `c` is `energyOffsetEV + energyScaleEV * c`. The counts are the
/// detector's counts per channel (a BINNED axis in HyperSpy's sense: the sum over channels is the intensity). exSpy
/// integrates an unbinned axis with Simpson's rule instead; that path is not ported, so
/// counts must be per-channel sums, not densities.
///
/// The zero-loss peak must sit at 0 eV (the registration's assumption, exSpy `_eels.py:647-648`): nothing is aligned or
/// shifted here. Every count must be finite.
public nonisolated struct LowLossSpectrumImage: Sendable {
    public let nx: Int
    public let ny: Int
    public let channels: Int
    public let counts: [Double]
    /// Energy of channel 0, eV.
    public let energyOffsetEV: Double
    /// Channel width, eV (> 0).
    public let energyScaleEV: Double

    public init(nx: Int, ny: Int, channels: Int, counts: [Double], energyOffsetEV: Double, energyScaleEV: Double) throws {
        guard nx > 0, ny > 0, channels > 0, nx <= Int.max / ny, nx * ny <= Int.max / channels,
              counts.count == nx * ny * channels else {
            throw EELSThicknessError.invalidShape(nx: nx, ny: ny, channels: channels, counts: counts.count)
        }
        guard energyOffsetEV.isFinite, energyScaleEV.isFinite, energyScaleEV > 0 else {
            throw EELSThicknessError.invalidEnergyAxis(offsetEV: energyOffsetEV, scaleEV: energyScaleEV)
        }
        if let bad = counts.firstIndex(where: { !$0.isFinite }) {
            throw EELSThicknessError.nonFiniteCounts(pixel: bad / channels)
        }
        self.nx = nx; self.ny = ny; self.channels = channels; self.counts = counts
        self.energyOffsetEV = energyOffsetEV; self.energyScaleEV = energyScaleEV
    }

    /// The same from single-precision counts (widened exactly to Double).
    public init(nx: Int, ny: Int, channels: Int, counts: [Float], energyOffsetEV: Double, energyScaleEV: Double) throws {
        try self.init(nx: nx, ny: ny, channels: channels, counts: counts.map { Double($0) },
                      energyOffsetEV: energyOffsetEV, energyScaleEV: energyScaleEV)
    }

    public var pixelCount: Int { nx * ny }

    /// Energy of channel `c`, eV: `offset + scale * c` (HyperSpy `update_axis`, `axes.py:1351`).
    public func energy(ofChannel c: Int) -> Double {
        let step = energyScaleEV * Double(c)
        return energyOffsetEV + step
    }
}
