//
//  MassAbsorption.swift
//  Role: Mass absorption coefficients mu/rho (cm^2/g) of pure elements from the
//        NIST FFAST table, log-log interpolated, and the weight-fraction mixture.
//
//  Data: NIST EPQ `FFastMAC.csv` (usnistgov/EPQ, public domain in the US, notice in
//  LicenseFile.txt), pinned by tools/lib/fetch-epq.sh. Layout: one column PAIR per
//  element (energy keV, mu/rho cm^2/g), pair index = Z-1, rows padded with empty
//  fields; each element's list ends in a (0, 0) sentinel. Measured 2026-10-05: for
//  all 90 elements the lists equal eXSpy `_misc/eds/ffast_mac.py` value for value
//  (max relative difference 0), so eXSpy's pins hold on this file.
//
//  Port of eXSpy material/_material.py `mass_absorption_coefficient` (lines 318-376)
//  and `_mass_absorption_mixture` (378-433), 7185a4d1.
//  DEVIATION: the trailing (0, 0) sentinel is stripped. eXSpy leaves it in the
//  searched array; an energy above the last real point then makes its index run past
//  the end (IndexError) or interpolate against the zero. Here an energy above the
//  last point, or below the first, is `outsideTable`, a refusal.
//

import Foundation

package nonisolated struct MassAbsorptionTable: Sendable {
    private struct Curve: Sendable {
        var energies: [Double]   // keV, ascending, duplicates allowed at edges
        var macs: [Double]       // cm^2/g
    }
    private let curves: [Int: Curve]   // by Z

    /// Parse the EPQ csv text. `stripSentinel: false` exists only so the test can
    /// show what the sentinel does; production code never passes it.
    package init(csv: String, stripSentinel: Bool = true) {
        var rows: [[Substring]] = []
        for line in csv.split(whereSeparator: \.isNewline) where !line.isEmpty {
            rows.append(line.split(separator: ",", omittingEmptySubsequences: false))
        }
        let width = rows.map(\.count).max() ?? 0
        var out: [Int: Curve] = [:]
        var z = 1
        while 2 * z <= width {
            var e: [Double] = [], m: [Double] = []
            for r in rows where r.count >= 2 * z {
                let a = r[2 * (z - 1)].trimmingCharacters(in: .whitespaces)
                let b = r[2 * (z - 1) + 1].trimmingCharacters(in: .whitespaces)
                guard !a.isEmpty, !b.isEmpty, let ev = Double(a), let mv = Double(b) else { continue }
                if stripSentinel && ev == 0 && mv == 0 { continue }
                e.append(ev); m.append(mv)
            }
            if !e.isEmpty { out[z] = Curve(energies: e, macs: m) }
            z += 1
        }
        curves = out
    }

    package init(contentsOf url: URL, stripSentinel: Bool = true) throws {
        self.init(csv: try String(contentsOf: url, encoding: .utf8), stripSentinel: stripSentinel)
    }

    /// The copy shipped in the app bundle (Resources/Spectroscopy/FFastMAC.csv).
    package static func bundled(in bundle: Bundle = .main) -> MassAbsorptionTable? {
        guard let url = bundle.url(forResource: "FFastMAC", withExtension: "csv", subdirectory: "Spectroscopy")
            ?? bundle.url(forResource: "FFastMAC", withExtension: "csv") else { return nil }
        return try? MassAbsorptionTable(contentsOf: url)
    }

    package func hasElement(_ symbol: String) -> Bool {
        QuantElementData.entry(symbol).map { curves[$0.z] != nil } ?? false
    }

    /// Lowest and highest tabulated energy (keV) of `element`, sentinel excluded.
    package func energyRange(element: String) -> ClosedRange<Double>? {
        guard let z = QuantElementData.entry(element)?.z, let c = curves[z],
              let lo = c.energies.first, let hi = c.energies.last, lo <= hi else { return nil }
        return lo...hi
    }

    /// mu/rho in cm^2/g of `element` at `energyKeV`.
    package func mac(element: String, energyKeV: Double) throws -> Double {
        guard let z = QuantElementData.entry(element)?.z else { throw QuantError.unknownElement(element) }
        guard let c = curves[z] else { throw QuantError.outsideTable(element, energyKeV: energyKeV) }
        // numpy.searchsorted(side="left"): first index with energies[i] >= E.
        var lo = 0, hi = c.energies.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if c.energies[mid] < energyKeV { lo = mid + 1 } else { hi = mid }
        }
        let i = lo
        if i == c.energies.count { throw QuantError.outsideTable(element, energyKeV: energyKeV) }
        if i == 0 {
            if c.energies[0] == energyKeV { return c.macs[0] }
            throw QuantError.outsideTable(element, energyKeV: energyKeV)
        }
        let e0 = c.energies[i - 1], e1 = c.energies[i]
        let m0 = c.macs[i - 1], m1 = c.macs[i]
        return exp(log(m0) + log(m1 / m0) * (log(energyKeV / e0) / log(e1 / e0)))
    }

    /// Weighted mean mu/rho of a mixture; `weights` in any consistent unit (wt% or
    /// fractions), one per element.
    package func mixture(elements: [String], weights: [Double], energyKeV: Double) throws -> Double {
        guard elements.count == weights.count else {
            throw QuantError.countMismatch("Elements and weights must have the same length.")
        }
        var sum = 0.0, wsum = 0.0
        for (el, w) in zip(elements, weights) {
            sum += w * (try mac(element: el, energyKeV: energyKeV))
            wsum += w
        }
        return sum / wsum
    }
}
