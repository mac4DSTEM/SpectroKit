//
//  ReferenceShapes.swift
//  Role: The slot for components MEASURED once on a pure sample and tied to the fit (ADR 054
//        V5-Q7, corrected by flag 2). It ships EMPTY and every result says "reference shapes: none".
//
//  Two ties exist, because the physics differs:
//   * `.lineAmplitude`: the Al K-alpha incomplete-charge tail follows Al K-alpha, so its measured
//     fraction f of the parent's area is folded into the parent's design column (parent + f * tail):
//     no extra free parameter.
//   * `.countsAboveEdge`: the detector's Si internal-fluorescence peak is excited by photons ABOVE
//     the Si K edge (1.839 keV), not by Al K-alpha (1.487 keV, below the edge). Its area is the
//     measured fraction c times the integrated counts above the edge in the fitted spectrum, a
//     data-derived known term added to the model, not a free column.
//
//  A profile is the measured shape resampled onto THIS axis's channels (length = axis.size), summing
//  to 1 (unit area in counts). The caller builds it from the pure-sample spectrum.
//

import Foundation

package nonisolated struct ReferenceShape: Sendable, Equatable {
    package enum Tie: Sendable, Equatable {
        /// profile * fraction * (area of the line group `group`), group named by its main line, e.g. "Al_Ka".
        case lineAmplitude(group: String, fraction: Double)
        /// profile * fractionPerCount * (counts in the fitted range at or above `edge` keV).
        case countsAboveEdge(edge: Double, fractionPerCount: Double)
    }
    package var name: String
    package var profile: [Double]
    package var tie: Tie

    package init(name: String, profile: [Double], tie: Tie) {
        self.name = name; self.profile = profile; self.tie = tie
    }
}

package nonisolated struct ReferenceShapes: Sendable, Equatable {
    package var shapes: [ReferenceShape]
    package init(_ shapes: [ReferenceShape] = []) { self.shapes = shapes }
    package static let none = ReferenceShapes()

    /// The footer line of every result.
    package var label: String {
        shapes.isEmpty ? "reference shapes: none" : "reference shapes: " + shapes.map(\.name).joined(separator: ", ")
    }
}
