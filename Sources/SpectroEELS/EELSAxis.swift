//
//  EELSAxis.swift
//  Role: The channel <-> energy rules of HyperSpy 2.4.0 that exSpy's thickness code stands on, for an axis in eV:
//        `value2index`, `value_range_to_indices`, and the stop of `isig[:threshold]`.
//
//  `value2index` (the half-towards-zero rounding after a 1e-12-channel truncation) is NOT re-ported here: it is
//  SpectroCore's `EnergyAxis.index(of:)`, already pinned against HyperSpy for the EDX windows (`axes.py:1283-1349`).
//  EnergyAxis is written for keV (`units` says so) but its arithmetic is unit-free: offset and scale go in as eV here and
//  `units` is never read. `value_range_to_indices` and the fixed-threshold stop are not in EnergyAxis (it ports
//  `_get_array_slices` as `channelRange`, which has a start; the thickness code only ever slices `[:threshold]`), so they
//  are ported here, with the lines they come from.
//

import Foundation
import SpectroCore

package nonisolated struct EELSAxis: Sendable {
    package let offset: Double
    package let scale: Double
    package let size: Int
    package let rules: EnergyAxis

    package init(offset: Double, scale: Double, size: Int) throws {
        guard offset.isFinite, scale.isFinite, scale > 0, size > 0 else {
            throw EELSThicknessError.invalidEnergyAxis(offsetEV: offset, scaleEV: scale)
        }
        self.offset = offset; self.scale = scale; self.size = size
        self.rules = EnergyAxis(offset: offset, scale: scale, size: size)
    }

    /// HyperSpy `low_value` / `high_value` (`axes.py:504`: min and max of `offset + scale * arange(size)`).
    package var lowValue: Double { offset }
    package var highValue: Double { energy(ofChannel: size - 1) }

    /// `offset + scale * i`, the product rounded before the sum, as `update_axis` (`axes.py:1351-1352`) does with NumPy arrays.
    package func energy(ofChannel i: Int) -> Double {
        let step = scale * Double(i)
        return offset + step
    }

    /// `value2index(value)` with the default `rounding=round` (`axes.py:1283-1349`), nil where HyperSpy raises
    /// (`ValueError`: outside the axis, or NaN).
    package func channel(ofEnergy value: Double) -> Int? {
        try? rules.index(of: value)
    }

    /// `UniformDataAxis.value_range_to_indices(v1, v2)` (`axes.py:648-691`, increasing axis): `[i1, i2]` as HyperSpy
    /// returns them, to be used as the half-open crop `isig[i1:i2]` (exSpy `_eels.py:712-715`).
    /// `i1 = value2index(v1)` only if `low < v1 <= high`, else 0; `i2 = value2index(v2)` only if `high > v2 >= low`,
    /// else `size - 1`. `v1 > v2` raises (`axes.py:667-672`).
    package func valueRangeToIndices(_ v1: Double, _ v2: Double) throws -> (first: Int, last: Int) {
        guard v1.isFinite, v2.isFinite, !(v1 > v2) else {
            throw EELSThicknessError.invalidSearchWindow(startEV: v1, windowEV: v2 - v1)
        }
        var i1 = 0, i2 = size - 1
        if lowValue < v1 && v1 <= highValue, let i = channel(ofEnergy: v1) { i1 = i }
        if highValue > v2 && v2 >= lowValue, let i = channel(ofEnergy: v2) { i2 = i }
        return (i1, i2)
    }

    /// The end (exclusive) of `signal.isig[:threshold]` with a float threshold (exSpy `_eels.py:598`, HyperSpy
    /// `_get_array_slices`, `axes.py:401-471`, the stop at `:453-466`): `value2index(threshold)`; where that raises, a
    /// threshold below the axis is an `IndexError` (thrown here) and one above it slices to the end (`size`).
    /// The sum of channels `[0, stop)` is I_0; the channel nearest the threshold is not in it.
    package func zeroLossStop(forFixedThreshold threshold: Double) throws -> Int {
        guard !threshold.isNaN else { throw EELSThicknessError.invalidFixedThreshold(threshold) }
        if let i = channel(ofEnergy: threshold) { return i }
        if threshold < lowValue { throw EELSThicknessError.invalidFixedThreshold(threshold) }
        return size
    }
}
