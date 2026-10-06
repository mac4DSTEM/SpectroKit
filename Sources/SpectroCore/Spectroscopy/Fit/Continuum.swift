//
//  Continuum.swift
//  Role: The default background of the spectrum fit: an empirical whole-spectrum continuum
//        with an absorption step at the Al K edge, fitted jointly with the lines (ADR 054
//        V5-Q2). It sits in the SAME linear design as the lines (free-sign coefficients), so
//        lines and continuum are fitted together and no separate background pass exists.
//
//  FUNCTIONAL FORM (goes to Fable's review):
//
//      B(E) = K(E) * P_s(E),     K(E) = (E0 - E) / E,
//      P_s(E) = sum_k c_{s,k} b_{k,n_s}(t),  t = (E - lo_s) / (hi_s - lo_s),  c_{s,k} >= 0,
//      b_{k,n}(t) = C(n,k) t^k (1 - t)^(n-k)  (the Bernstein basis),
//      the segments being cut at the absorption edges (default: the Al K edge, 1.5596 keV).
//
//  The Bernstein basis is non-negative, so with c >= 0 the continuum cannot go negative anywhere (the
//  fit is NNLS on lines and continuum together, and the Poisson fit needs mu >= 0). A plain
//  polynomial of the same order went negative in 10 channels at the empty high-energy end of the
//  Al-matrix test spectrum. The price: a polynomial with a negative Bernstein coefficient is not
//  reachable; a physical continuum is positive and smooth, and acceptance is F3/Q2.
//
//  K is Kramers' law for the thick-target bremsstrahlung intensity per unit energy,
//  I(E) ~ Z (E0 - E) / E (Kramers, Phil. Mag. 46 (1923) 836; Goldstein et al., Scanning Electron
//  Microscopy and X-ray Microanalysis, ch. on the continuum), E0 the beam energy. Everything
//  else that shapes the observed continuum is multiplicative and smooth between edges: the
//  detector's low-energy efficiency roll-off (window and dead layer), the specimen's own
//  absorption, and, at an absorption edge, a STEP: the mass absorption coefficient of Al rises
//  by roughly an order of magnitude across 1.5596 keV, so the transmitted continuum drops there. P_s absorbs
//  the smooth part and the independent polynomial on each side of the edge absorbs the step, so
//  the model has no nonlinear parameter: n_0 + 1 and n_1 + 1 coefficients, 10 + 6 = 16 by default, all
//  linear and non-negative.
//
//  The Al K edge energy 1.5596 keV is the standard tabulated value (X-ray Data Booklet, Table 1-1).
//  The Si K edge (1.839 keV, a detector dead-layer step) is NOT in the default: add it to `edges` to test it.
//
//  Orders (9, 5) are a design choice MEASURED ON A SYNTHETIC SPECTRUM, not a property of the method (threshold
//  rule): on an Al-matrix spectrum whose detector roll-off is (1 - exp(-(E/0.5 keV)^2.4)) (this lane's own
//  generator, a different functional form from the fit), orders (5, 4) left a systematic misfit of up to
//  10 sigma at 0.2-0.5 keV that leaked to ~2.5 sigma into 1.0-1.5 keV (F3 refuted: 2 of 30 seeds had all
//  |r| <= 3 in 1.1-1.9 keV, against 24 of 30 for the true model); (8, 5) gave 22, (9, 5) 25, (10, 5) 26.
//  The roll-off of the owner's Super-X is not known here: the continuum's acceptance is Q2 on his pooled
//  spectra, and the orders are exposed so that measurement can move them.
//

import Foundation

package nonisolated struct ContinuumForm: Sendable, Equatable {
    /// Equal when both are absent, or both carry the same source name AND the same values on a fixed energy grid (a typed
    /// parameter that sourceName does not spell out cannot hide).
    private static func sameEfficiency(_ x: (any DetectorEfficiency)?, _ y: (any DetectorEfficiency)?) -> Bool {
        switch (x, y) {
        case (nil, nil): return true
        case (let x?, let y?):
            return x.sourceName == y.sourceName && stride(from: 0.2, through: 20.0, by: 0.7).allSatisfy {
                x.efficiency(energyKeV: $0) == y.efficiency(energyKeV: $0)
            }
        default: return false
        }
    }

    package static func == (a: ContinuumForm, b: ContinuumForm) -> Bool {
        a.beamEnergy == b.beamEnergy && a.edges == b.edges && a.orders == b.orders && a.nonNegative == b.nonNegative
            && sameEfficiency(a.efficiency, b.efficiency)
    }

    /// Beam energy E0 in keV (the continuum ends there).
    package var beamEnergy: Double
    /// Absorption-edge energies (keV) where the polynomial may jump.
    package var edges: [Double]
    /// Polynomial order per segment; `edges.count + 1` entries.
    package var orders: [Int]
    /// Bernstein basis with non-negative coefficients (default). False: free-sign monomials in t.
    package var nonNegative: Bool
    /// Round 2: an optional detector efficiency epsilon(E) multiplying the whole form (B = K x epsilon x P_s), so the detector
    /// roll-off is modelled and P_s only carries what epsilon does not. nil: the round-1 form. The model is generic
    /// (`DetectorEfficiency`), not the owner's Super-X calibration.
    package var efficiency: (any DetectorEfficiency)?

    package static let alKEdge = 1.5596

    package init(beamEnergy: Double, edges: [Double] = [ContinuumForm.alKEdge], orders: [Int] = [9, 5],
                 nonNegative: Bool = true, efficiency: (any DetectorEfficiency)? = nil) {
        precondition(orders.count == edges.count + 1, "ContinuumForm needs one order per segment")
        precondition(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 }, "edges ascend")
        self.beamEnergy = beamEnergy; self.edges = edges; self.orders = orders; self.nonNegative = nonNegative
        self.efficiency = efficiency
    }

    package var coefficientCount: Int { orders.reduce(0) { $0 + $1 + 1 } }

    /// The basis columns over `energies` (ascending, the fitted channels). A coefficient with no
    /// support (an empty segment) is not produced. `names` label them for the result.
    package func columns(energies: [Double]) -> (values: [[Double]], names: [String]) {
        guard let lo = energies.first, let hi = energies.last, hi > lo else { return ([], []) }
        // Segment boundaries inside the fitted range.
        var bounds = [lo]
        var segmentIndex = [0]
        for (k, e) in edges.enumerated() where e > lo && e < hi { bounds.append(e); segmentIndex.append(k + 1) }
        bounds.append(hi)
        let eRef = 2.0
        let epsRef = efficiency?.efficiency(energyKeV: eRef) ?? 1
        let kRef = (beamEnergy - eRef) / eRef * (epsRef > 0 ? epsRef : 1)
        var values: [[Double]] = [], names: [String] = []
        for s in 0..<(bounds.count - 1) {
            let a = bounds[s], b = bounds[s + 1]
            let inSeg = energies.indices.filter { i in
                let e = energies[i]
                return e >= a && (s == bounds.count - 2 ? e <= b : e < b)
            }
            guard !inSeg.isEmpty else { continue }
            let order = min(orders[segmentIndex[s]], inSeg.count - 1)
            for k in 0...order {
                var col = [Double](repeating: 0, count: energies.count)
                for i in inSeg {
                    let e = energies[i]
                    let t = (e - a) / (b - a)
                    let basis = nonNegative
                        ? binomial(order, k) * pow(t, Double(k)) * pow(1 - t, Double(order - k))
                        : pow(t, Double(k))
                    let eps = efficiency?.efficiency(energyKeV: e) ?? 1
                    col[i] = ((beamEnergy - e) / e) * eps / kRef * basis
                }
                values.append(col)
                names.append("continuum s\(segmentIndex[s]) t^\(k)")
            }
        }
        return (values, names)
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        var r = 1.0
        for i in 0..<k { r = r * Double(n - i) / Double(i + 1) }
        return r
    }

    /// Named in every result's footer.
    package var label: String {
        let eps = efficiency.map { "\u{00D7}\u{03B5}(\($0.sourceName))" } ?? ""
        let ord = orders.map(String.init).joined(separator: ",")
        let split = edges.isEmpty ? "no edge split" : "split at " + edges.map { "\($0) keV" }.joined(separator: ", ")
        return "continuum: Kramers\(eps)\u{00D7}\(nonNegative ? "Bernstein" : "poly")(\(ord)), \(split); orders chosen on synthetic data"
    }

    /// Badge text the room shows beside any weak-line result (registered criterion 3: no form met |bias| <= 1 se at 0.3 %
    /// on both generators, so the bias is stated, never asserted away). Numbers: `testWeakLineRecoveryRegisteredSelection`,
    /// 30 seeds, Al K-alpha ~3e5 counts pooled, default form Kramers (9,5): the numbers below are that test's run.
    /// Wording after the tail experiment: supplying the true Al K-alpha tail as a reference shape on generator S takes the
    /// noise-free bias from about -300 to about +35 (Kramers-only), so on S the whole deficit is the tail; on generator A (no tail)
    /// an equal -300 is the continuum-line projection.
    package static let weakLineBiasNote =
        "a weak line next to Al K\u{03B1} reads low by \u{2248} 300 counts per pooled spectrum on synthetic data "
        + "(cause: the Al K\u{03B1} incomplete-charge tail, unmodelled until the owner's pure-Al reference spectrum is supplied); "
        + "unmeasured on real data. Weak-line bias measured on synthetic data: \u{0394} = \u{2212}295 \u{00B1} 31 counts at 900 planted Mg K\u{03B1} "
        + "(generator A, no tail: continuum\u{2013}line projection) and \u{2212}310 \u{00B1} 23 at 882 (generator S); "
        + "\u{2212}402 \u{00B1} 33 at 3000 (A) and \u{2212}310 \u{00B1} 23 at 2899 (S)"
}
