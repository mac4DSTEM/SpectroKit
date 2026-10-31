//
//  Continuum.swift
//  Role: The default background of the spectrum fit: an empirical whole-spectrum continuum
//        with an absorption step at the Al K edge, fitted jointly with the lines.
//        It sits in the SAME linear design as the lines (free-sign coefficients), so
//        lines and continuum are fitted together and no separate background pass exists.
//
//  FUNCTIONAL FORM:
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
//  THE STEP SEEN THROUGH THE DETECTOR (opt-in `ContinuumEdgeStep.broadened`): a detector records the incoming spectrum
//  convolved with its resolution, so a measured edge is a Gaussian-blurred step (about 75 eV FWHM at 1.56 keV for 128 eV at
//  Mn K-alpha), never a jump between two channels. The broadened form weights segment s by
//      w_s(E) = Phi((E - a_s) / sigma(a_s)) - Phi((E - b_s) / sigma(b_s)),
//  Phi the standard normal CDF, sigma the line-width law's Gaussian sigma at the edge (`XRayLines.fwhm`, the line model's own
//  resolution), no factor at the fitted range's ends; each segment's polynomial continues past its edge at its end value
//  (t clamped to [0, 1]). The weights sum to 1 whenever every segment holds channels (a segment with none, two edges in one
//  channel gap, is skipped and its weight is lost) and are non-negative, so the continuum stays non-negative. This is the step
//  convolved with the detector Gaussian when the polynomials are flat across the edge's width. An edge outside the fitted range
//  is not modelled, including the blurred tail of a step just outside it.
//  Measured: on a pure Al wedge (Titan 200 kV, Super-X; Snelson, Collins, MacArthur, University of Leeds, doi 10.5518/1826,
//  CC BY 4.0) the sharp step made the model fall 351 counts more than the data between the channels at 1.559 and 1.564 keV,
//  left the data 1677 counts above the model in 1.53-1.65 keV and the model 39 % above the data in 1.65-2.2 keV; broadened:
//  42 counts, 907 counts and 19 %. `.sharp` (the default) is the earlier form, value for value: the kit's registered
//  synthetic generators plant an unbroadened step, so making `.broadened` the default re-measures those results first.
//
//  The Al K edge energy 1.5596 keV is the standard tabulated value (X-ray Data Booklet, Table 1-1).
//  The Si K edge (1.839 keV, a detector dead-layer step) is NOT in the default: add it to `edges` to test it.
//
//  Orders (9, 5) are a design choice MEASURED ON A SYNTHETIC SPECTRUM, not a property of the method (threshold
//  rule): on an Al-matrix spectrum whose detector roll-off is (1 - exp(-(E/0.5 keV)^2.4)) (this lane's own
//  generator, a different functional form from the fit), orders (5, 4) left a systematic misfit of up to
//  10 sigma at 0.2-0.5 keV that leaked to ~2.5 sigma into 1.0-1.5 keV (F3 refuted: 2 of 30 seeds had all
//  |r| <= 3 in 1.1-1.9 keV, against 24 of 30 for the true model); (8, 5) gave 22, (9, 5) 25, (10, 5) 26.
//  The roll-off of a given Super-X detector is not known here: the orders are exposed so that a measurement
//  on real pooled spectra can move them.
//

import Foundation

public nonisolated struct ContinuumForm: Sendable, Equatable {
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

    public static func == (a: ContinuumForm, b: ContinuumForm) -> Bool {
        a.beamEnergy == b.beamEnergy && a.edges == b.edges && a.orders == b.orders && a.nonNegative == b.nonNegative
            && sameEfficiency(a.efficiency, b.efficiency) && a.edgeStep == b.edgeStep
    }

    /// Beam energy E0 in keV (the continuum ends there).
    package var beamEnergy: Double
    /// Absorption-edge energies (keV) where the polynomial may jump.
    public var edges: [Double]
    /// Polynomial order per segment; `edges.count + 1` entries.
    package var orders: [Int]
    /// Bernstein basis with non-negative coefficients (default). False: free-sign monomials in t.
    package var nonNegative: Bool
    /// Round 2: an optional detector efficiency epsilon(E) multiplying the whole form (B = K x epsilon x P_s), so the detector
    /// roll-off is modelled and P_s only carries what epsilon does not. nil: the round-1 form. The model is generic
    /// (`DetectorEfficiency`), not a measured Super-X calibration.
    package var efficiency: (any DetectorEfficiency)?
    /// How the step at each edge is drawn: sharp at the edge channel (default) or broadened by the detector resolution.
    package var edgeStep: ContinuumEdgeStep

    package static let alKEdge = FitPolicy.alKEdgeKeV

    package init(beamEnergy: Double, edges: [Double] = [ContinuumForm.alKEdge], orders: [Int] = [9, 5],
                 nonNegative: Bool = true, efficiency: (any DetectorEfficiency)? = nil,
                 edgeStep: ContinuumEdgeStep = .sharp) {
        precondition(orders.count == edges.count + 1, "ContinuumForm needs one order per segment")
        precondition(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 }, "edges ascend")
        self.beamEnergy = beamEnergy; self.edges = edges; self.orders = orders; self.nonNegative = nonNegative
        self.efficiency = efficiency; self.edgeStep = edgeStep
    }

    package var coefficientCount: Int { orders.reduce(0) { $0 + $1 + 1 } }

    /// The basis columns over `energies` (ascending, the fitted channels). A coefficient with no
    /// support (an empty segment) is not produced. `names` label them for the result.
    /// `resolutionMnKaEV`: the detector resolution that broadens each edge step (the line model's). nil, or `edgeStep == .sharp`,
    /// or no edge inside the range: the sharp form, value for value the form before broadening existed.
    package func columns(energies: [Double], resolutionMnKaEV: Double? = nil) -> (values: [[Double]], names: [String]) {
        guard let lo = energies.first, let hi = energies.last, hi > lo else { return ([], []) }
        // Segment boundaries inside the fitted range.
        var bounds = [lo]
        var segmentIndex = [0]
        for (k, e) in edges.enumerated() where e > lo && e < hi { bounds.append(e); segmentIndex.append(k + 1) }
        bounds.append(hi)
        let eRef = 2.0
        let epsRef = efficiency?.efficiency(energyKeV: eRef) ?? 1
        let kRef = (beamEnergy - eRef) / eRef * (epsRef > 0 ? epsRef : 1)
        if edgeStep == .broadened, let r = resolutionMnKaEV, bounds.count > 2 {
            return broadenedColumns(energies: energies, bounds: bounds, segmentIndex: segmentIndex, resolutionMnKaEV: r, kRef: kRef)
        }
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

    /// The broadened form (header): B(E) = K(E) eps(E) sum_s w_s(E) P_s(clamp(t_s, 0, 1)) / kRef, w_s = Phi_a - Phi_b.
    private func broadenedColumns(energies: [Double], bounds: [Double], segmentIndex: [Int], resolutionMnKaEV r: Double,
                                  kRef: Double) -> (values: [[Double]], names: [String]) {
        let last = bounds.count - 2
        func sigma(_ e: Double) -> Double {
            // A width law with no real width at the edge (a resolution far below the line-width law's floor) falls back to the
            // Mn K-alpha width, as the proposer does.
            let fwhm = XRayLines.fwhm(resolutionMnKaEV: r, atEnergy: e) ?? r / 1000
            return max(fwhm, 1e-9) / (8 * log(2.0)).squareRoot()
        }
        func phi(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }
        var values: [[Double]] = [], names: [String] = []
        for s in 0...last {
            let a = bounds[s], b = bounds[s + 1]
            // The order follows the segment's own channels, as in the sharp form.
            let own = energies.filter { $0 >= a && (s == last ? $0 <= b : $0 < b) }.count
            guard own > 0 else { continue }
            let order = min(orders[segmentIndex[s]], own - 1)
            let sa = s > 0 ? sigma(a) : 0, sb = s < last ? sigma(b) : 0
            // Phi(lower edge) - Phi(upper edge): the weights telescope to 1 for any number of edges (a product would over-count
            // between two close edges); max(0, ...) guards the far tails where the lower edge's sigma is the smaller.
            let weight = energies.map { e -> Double in
                max(0, (s > 0 ? phi((e - a) / sa) : 1) - (s < last ? phi((e - b) / sb) : 0))
            }
            for k in 0...order {
                var col = [Double](repeating: 0, count: energies.count)
                for (i, e) in energies.enumerated() where weight[i] > 0 {
                    let t = min(max((e - a) / (b - a), 0), 1)
                    let basis = nonNegative
                        ? binomial(order, k) * pow(t, Double(k)) * pow(1 - t, Double(order - k))
                        : pow(t, Double(k))
                    let eps = efficiency?.efficiency(energyKeV: e) ?? 1
                    col[i] = ((beamEnergy - e) / e) * eps / kRef * basis * weight[i]
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
        let step = edgeStep == .broadened ? " (step broadened by the detector resolution)" : ""
        let split = edges.isEmpty ? "no edge split" : "split at " + edges.map { "\($0) keV" }.joined(separator: ", ") + step
        return "continuum: Kramers\(eps)\u{00D7}\(nonNegative ? "Bernstein" : "poly")(\(ord)), \(split); orders chosen on synthetic data"
    }

    /// Badge text the room shows beside any weak-line result (no form met |bias| <= 1 se at 0.3 %
    /// on both generators, so the bias is stated, never asserted away). Numbers: `testWeakLineRecoveryRegisteredSelection`,
    /// 30 seeds, Al K-alpha ~3e5 counts pooled, default form Kramers (9,5): the numbers below are that test's run.
    /// Wording after the tail experiment: supplying the true Al K-alpha tail as a reference shape on generator S takes the
    /// noise-free bias from about -300 to about +35 (Kramers-only), so on S the whole deficit is the tail; on generator A (no tail)
    /// an equal -300 is the continuum-line projection.
    public static let weakLineBiasNote =
        "a weak line next to Al K\u{03B1} reads low by \u{2248} 300 counts per pooled spectrum on synthetic data "
        + "(cause: the Al K\u{03B1} incomplete-charge tail, unmodelled until a tail is measured on an Al matrix, `TailEstimate`); "
        + "unmeasured on real data. Weak-line bias measured on synthetic data: \u{0394} = \u{2212}295 \u{00B1} 31 counts at 900 planted Mg K\u{03B1} "
        + "(generator A, no tail: continuum\u{2013}line projection) and \u{2212}297 \u{00B1} 23 at 882 (generator S); "
        + "\u{2212}402 \u{00B1} 33 at 3000 (A) and \u{2212}251 \u{00B1} 21 at 2899 (S)"
}

/// How the continuum's step at an absorption edge is drawn (`FitPolicy.continuumEdgeStep`).
public nonisolated enum ContinuumEdgeStep: String, Sendable, Codable, Equatable {
    /// Seen through the detector: each segment weighted by the detector's Gaussian step at its edges.
    case broadened
    /// A jump between the two channels either side of the edge (the default).
    case sharp
}
