//
//  LinearDesign.swift
//  Role: The fit's linear model on the fitted channels: `counts ~ D theta + offset`, with
//        non-negative columns (line areas, escape areas) and free-sign columns (background).
//        Least squares (NNLS) and the Poisson IRLS both run on this one design.
//

import Foundation

package nonisolated enum FitBackground: Sendable, Equatable {
    /// Default: the empirical continuum with the Al K step, fitted jointly with the lines.
    case continuum(ContinuumForm)
    /// Expert, eXSpy parity: a polynomial of `order` over the fitted range inside the model
    /// (`add_polynomial_background(order=6)`), basis monomials of the range-normalised energy.
    case polynomial(order: Int)
    case none
}

package nonisolated struct LinearDesign: Sendable {
    package enum Kind: Sendable, Equatable { case line(group: Int), escape(group: Int), background }

    package struct Column: Sendable {
        package var kind: Kind
        package var name: String
        package var values: [Double]
        /// Free sign (polynomial background) or a non-negative coefficient (line and escape areas, Bernstein continuum).
        package var signed: Bool = false
        /// False when the column has no support in the fitted range (a line far outside it); it is
        /// zeroed, never enters the fit and its area is reported 0.
        /// DEVIATION (eXSpy): hyperspy leaves an out-of-range line at its start value (it has no data to move it);
        /// here its column is zeroed and its area reported 0 and unsupported.
        package var supported: Bool
    }

    package let channels: Range<Int>
    package let energies: [Double]
    /// Line and escape columns (non-negative areas).
    package var areaColumns: [Column]
    /// Background columns: free sign for the polynomial, non-negative for the continuum.
    package var backgroundColumns: [Column]
    /// A known additive term (counts per channel), from `.countsAboveEdge` reference shapes.
    package var offset: [Double]
    package let groupIDs: [String]

    /// Columns with a non-negative coefficient: line and escape areas, then any non-negative background.
    package var nonNegative: ColumnMatrix {
        let cols = areaColumns.map(\.values) + backgroundColumns.filter { !$0.signed }.map(\.values)
        // No column at all (every line dropped, no background): an empty matrix with the right row count.
        return cols.isEmpty ? ColumnMatrix(rows: channels.count, cols: 0) : ColumnMatrix(columns: cols)
    }
    package var free: ColumnMatrix {
        let f = backgroundColumns.filter(\.signed)
        return f.isEmpty ? ColumnMatrix(rows: channels.count, cols: 0) : ColumnMatrix(columns: f.map(\.values))
    }
    /// Background coefficients in `backgroundColumns` order, from the solver's two coefficient vectors.
    package func backgroundCoefficients(nonNegative x: [Double], free b: [Double]) -> [Double] {
        var xi = areaColumns.count, bi = 0
        return backgroundColumns.map { c in
            if c.signed { defer { bi += 1 }; return b[bi] } else { defer { xi += 1 }; return x[xi] }
        }
    }
    /// Free parameters declared by the model, supported or not (hyperspy's degrees of freedom count
    /// every free parameter of the model, including a line outside the fitted range).
    package var parameterCount: Int { areaColumns.count + backgroundColumns.count }

    /// Builds the design over `channels` of `axis`.
    /// - counts: the data, needed only for `.countsAboveEdge` reference shapes.
    package static func build(
        model: EDSLineModel, axis: EnergyAxis, channels: Range<Int>, background: FitBackground,
        shapes: ReferenceShapes = .none, counts: [Double]? = nil
    ) -> LinearDesign {
        let energies = channels.map { axis.energy(ofChannel: $0) }
        let n = channels.count
        var area: [Column] = []

        func support(_ v: [Double]) -> Bool { (v.max() ?? 0) >= 1e-8 }

        for (g, group) in model.groups.enumerated() {
            var v = EDSLineModel.column(of: group.lines, energies: energies, scale: axis.scale)
            for s in shapes.shapes {
                if case .lineAmplitude(let target, let f) = s.tie, target == group.id {
                    precondition(s.profile.count == axis.size, "reference profile must have one value per channel")
                    for (k, c) in channels.enumerated() { v[k] += f * s.profile[c] }
                }
            }
            let ok = support(v)
            if !ok { v = [Double](repeating: 0, count: n) }
            area.append(Column(kind: .line(group: g), name: group.id, values: v, signed: false, supported: ok))
        }
        for (g, group) in model.groups.enumerated() where !group.escapes.isEmpty {
            var v = EDSLineModel.column(of: group.escapes, energies: energies, scale: axis.scale)
            let ok = support(v)
            if !ok { v = [Double](repeating: 0, count: n) }
            area.append(Column(kind: .escape(group: g), name: group.id + " escape", values: v, signed: false, supported: ok))
        }

        var bg: [Column] = []
        switch background {
        case .none: break
        case .polynomial(let order):
            let lo = energies.first ?? 0, hi = energies.last ?? 1
            let mid = (lo + hi) / 2, half = max((hi - lo) / 2, 1e-12)
            for k in 0...order {
                let v = energies.map { pow(($0 - mid) / half, Double(k)) * axis.scale }
                bg.append(Column(kind: .background, name: "polynomial \(k)", values: v, signed: true, supported: true))
            }
        case .continuum(let form):
            let (cols, names) = form.columns(energies: energies)
            for (v, nm) in zip(cols, names) {
                bg.append(Column(kind: .background, name: nm, values: v.map { $0 * axis.scale },
                                 signed: !form.nonNegative, supported: true))
            }
        }

        var offset = [Double](repeating: 0, count: n)
        for s in shapes.shapes {
            if case .countsAboveEdge(let edge, let f) = s.tie {
                precondition(s.profile.count == axis.size, "reference profile must have one value per channel")
                guard let counts else { preconditionFailure(".countsAboveEdge needs the data") }
                var above = 0.0
                for (k, c) in channels.enumerated() where energies[k] >= edge { above += counts[c] }
                for (k, c) in channels.enumerated() { offset[k] += f * above * s.profile[c] }
            }
        }
        return LinearDesign(channels: channels, energies: energies, areaColumns: area, backgroundColumns: bg,
                            offset: offset, groupIDs: model.groups.map(\.id))
    }
}

extension EnergyAxis {
    /// hyperspy `set_signal_range(x1, x2)` (`Model1D._set_signal_range_in_pixels`): the channels
    /// `value2index(x1) ... value2index(x2)` INCLUSIVE of the last. Either bound nil is the axis end.
    /// A bound outside the axis clamps to the end (hyperspy `value_range_to_indices`).
    package nonisolated func fitChannels(from x1: Double?, to x2: Double?) -> Range<Int> {
        let i1 = x1.map { v in (try? index(of: v)) ?? (v < lowValue ? 0 : size - 1) } ?? 0
        let i2 = x2.map { v in (try? index(of: v)) ?? (v < lowValue ? 0 : size - 1) } ?? (size - 1)
        return i1 <= i2 ? i1..<(i2 + 1) : i1..<i1
    }
}
