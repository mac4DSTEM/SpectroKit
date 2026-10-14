//
//  GOSTable.swift
//  Role: The generalised oscillator strength of one K shell, as exSpy 7185a4d1 reads it from the GOSH database
//        (`exspy/_misc/eels/gosh_gos.py`, `read_gos_data`; `base_gos.py`, `TabulatedGOS`), and the edges SpectroKit ships.
//        EELS slice 2, registration section 3.3.
//
//  The tables are the dft GOS of Segger, Guzzinati and Kohl (GOSH 1.5.0, DOI 10.5281/zenodo.7645765, CC-BY-4.0; md5 of the
//  file exSpy fetches 7fee8891c147a4f769668403b54c529b), the groups C/K1, N/K1 and O/K1, extracted by
//  tools/eels-edge/extract_gos.py into `Resources/GOS/dft-<element>-K1.json` with every stored float32 written so that it
//  reads back bit for bit. Never Gatan's Hartree-Slater tables. Attribution: NOTICE.
//
//  The arrays stay float32, as exSpy holds them: NumPy 2.5 keeps several of exSpy's intermediates in float32 (NEP 50: a
//  Python float beside a float32 scalar is cast to float32), and the port reproduces that (`EdgeCrossSection`).
//

import Foundation

/// A core-loss edge SpectroKit can quantify: an element's K shell with its onset energy and its tabulated GOS.
public nonisolated struct CoreLossEdge: Sendable, Equatable, CustomStringConvertible {
    /// Element symbol, e.g. "C".
    public let element: String
    /// GOSH subshell name ("K1").
    public let subshell: String
    /// The onset energy exSpy uses (`exspy/material/eels_binding_energies.json`), eV.
    public let onsetEV: Double

    /// Carbon K, onset 284 eV.
    public static let carbonK = CoreLossEdge(element: "C", subshell: "K1", onsetEV: 284.0)
    /// Nitrogen K, onset 401 eV.
    public static let nitrogenK = CoreLossEdge(element: "N", subshell: "K1", onsetEV: 401.0)
    /// Oxygen K, onset 532 eV.
    public static let oxygenK = CoreLossEdge(element: "O", subshell: "K1", onsetEV: 532.0)

    /// The edges whose GOS ships with SpectroKit.
    public static let bundled: [CoreLossEdge] = [.carbonK, .nitrogenK, .oxygenK]

    public var description: String { "\(element) K" }
}

/// One edge's GOS table as exSpy holds it after `read_gos_data`.
package nonisolated struct GOSTable: Sendable {
    package let edge: CoreLossEdge
    /// `occupancy_ratio` (exSpy's `subshell_factor`), float32 as stored.
    package let occupancyRatio: Float
    /// `free_energies - min(free_energies)` + onset, in float32 as exSpy computes it (`energy_axis`).
    package let energyAxis: [Float]
    /// The q axis, 1/m, float32.
    package let q: [Float]
    /// `gos[iEnergy][iQ]` (exSpy's `gos_array`, `np.squeeze(gos.T)`), float32.
    package let gos: [[Float]]

    package init(edge: CoreLossEdge, occupancyRatio: Float, freeEnergies: [Float], q: [Float], gos: [[Float]]) {
        self.edge = edge
        self.occupancyRatio = occupancyRatio
        let lowest = freeEnergies.min() ?? 0
        let onset = Float(edge.onsetEV)                    // a Python float beside a float32 array: cast to float32
        self.energyAxis = freeEnergies.map { ($0 - lowest) + onset }
        self.q = q
        self.gos = gos
    }

    private struct Stored: Decodable {
        let element: String
        let subshell: String
        let onsetEV: Double
        let occupancyRatio: Double
        let freeEnergies: [Double]
        let q: [Double]
        let gos: [[Double]]
    }

    /// The table shipped for `edge`, or nil when SpectroKit ships none for it.
    package static func bundled(_ edge: CoreLossEdge) -> GOSTable? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let t = cache[edge.element + "_" + edge.subshell] { return t }
        guard CoreLossEdge.bundled.contains(edge),
              let url = Bundle.module.url(forResource: "dft-\(edge.element)-\(edge.subshell)", withExtension: "json",
                                          subdirectory: "GOS"),
              let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Stored.self, from: data),
              s.element == edge.element, s.subshell == edge.subshell, s.onsetEV == edge.onsetEV,
              s.gos.count == s.freeEnergies.count, s.gos.allSatisfy({ $0.count == s.q.count }) else { return nil }
        let t = GOSTable(edge: edge, occupancyRatio: Float(s.occupancyRatio), freeEnergies: s.freeEnergies.map { Float($0) },
                         q: s.q.map { Float($0) }, gos: s.gos.map { $0.map { Float($0) } })
        cache[edge.element + "_" + edge.subshell] = t
        return t
    }

    nonisolated(unsafe) private static var cache: [String: GOSTable] = [:]
    private static let cacheLock = NSLock()
}
