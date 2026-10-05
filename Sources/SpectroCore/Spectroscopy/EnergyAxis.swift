//
//  EnergyAxis.swift
//  Role: A uniform spectral axis (offset, scale, units keV) and the channel <-> energy
//        rules of HyperSpy 2.4.0, which eXSpy's window sums stand on.
//
//  Ported from hyperspy/axes.py (UniformDataAxis.value2index, _get_array_slices) and
//  hyperspy/misc/_array_tools.py (round_half_towards_zero / round_half_away_from_zero),
//  hyperspy 2.4.0 as installed with eXSpy 7185a4d1. The rounding is NOT round-half-up
//  and NOT nearest-even: a value exactly between two channels goes to the LOWER
//  channel for a non-negative energy (validation.md §1a: an off-by-one source).
//

import Foundation

package nonisolated enum EnergyAxisError: Error, Equatable, Sendable {
    /// hyperspy's `ValueError("The value is out of the axis limits")`.
    case outsideAxis(value: Double)
    /// hyperspy's `IndexError` from `_get_array_slices` (a slice wholly beyond one end).
    case sliceBeyondAxis(start: Double, stop: Double)
    case notANumber
}

package nonisolated struct EnergyAxis: Equatable, Sendable {
    /// Energy of channel 0, keV.
    package let offset: Double
    /// Channel width, keV (> 0).
    package let scale: Double
    package let size: Int
    package var units: String { "keV" }

    package init(offset: Double, scale: Double, size: Int) {
        // DEVIATION: hyperspy also handles a negative scale (its rounding branch
        // swaps on the sign); EDS detectors never write one, so it is refused here.
        precondition(scale > 0 && size > 0, "EnergyAxis needs scale > 0 and size > 0")
        self.offset = offset; self.scale = scale; self.size = size
    }

    /// Energy of the last channel (hyperspy `high_value`, `axis.max()`).
    package var highValue: Double { offset + scale * Double(size - 1) }
    package var lowValue: Double { offset }

    /// Energy of channel `i`.
    package func energy(ofChannel i: Int) -> Double { offset + scale * Double(i) }

    /// hyperspy `value2index(value)` with the default `rounding=round`
    /// (axes.py:1283-1334 at 2.4.0). The index is first truncated at 1e-12
    /// channels so 0.5 +- 1e-13 is a tie, then a tie goes towards zero when the
    /// energy is >= 0 and away from zero when it is < 0 (scale > 0).
    package func index(of value: Double) throws -> Int {
        if value.isNaN { throw EnergyAxisError.notANumber }
        let multiplier = 1e12
        let index = 1 / multiplier * ((value - offset) / scale * multiplier).rounded(.towardZero)
        let rounded: Double
        if value >= 0 {
            // round_half_towards_zero
            rounded = index >= 0 ? (index - 0.5).rounded(.up) : (index + 0.5).rounded(.down)
        } else {
            // round_half_away_from_zero
            rounded = index >= 0 ? (index + 0.5).rounded(.down) : (index - 0.5).rounded(.up)
        }
        // `int(index)` on a double beyond Int would trap; such a value is outside any axis.
        guard rounded.magnitude < 9e15 else { throw EnergyAxisError.outsideAxis(value: value) }
        let i = Int(rounded)
        guard i >= 0, i < size else { throw EnergyAxisError.outsideAxis(value: value) }
        return i
    }

    /// The channel half-open range of `signal.isig[start:stop]` with float bounds
    /// (`_get_array_slices`, axes.py:401-471): a start below the axis clamps to
    /// channel 0, a stop above clamps to `size`; a start above or a stop below the
    /// axis throws (hyperspy `IndexError`). An empty or reversed pair gives an empty range.
    package func channelRange(from start: Double, to stop: Double) throws -> Range<Int> {
        var lo = 0, hi = size
        do { lo = try index(of: start) } catch EnergyAxisError.outsideAxis {
            if start > highValue { throw EnergyAxisError.sliceBeyondAxis(start: start, stop: stop) }
            lo = 0
        }
        do { hi = try index(of: stop) } catch EnergyAxisError.outsideAxis {
            if stop < lowValue { throw EnergyAxisError.sliceBeyondAxis(start: start, stop: stop) }
            hi = size
        }
        // Python slicing with lo > hi is empty.
        return lo <= hi ? lo..<hi : lo..<lo
    }

    /// `isig[value]` with a float: the single channel `index(of:)` (stop = start + 1).
    package func singleChannel(at value: Double) throws -> Range<Int> {
        let i = try index(of: value)
        return i..<(i + 1)
    }
}
