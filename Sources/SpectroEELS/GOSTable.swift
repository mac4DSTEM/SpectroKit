//
//  GOSTable.swift
//  Role: The generalised oscillator strength of one K shell, as exSpy 7185a4d1 reads it from the GOSH database
//        (`exspy/_misc/eels/gosh_gos.py`, `read_gos_data`; `base_gos.py`, `TabulatedGOS`), and the edges SpectroKit ships.
//
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

/// A core-loss edge SpectroKit can quantify: an element's subshell with its onset energy and its tabulated GOS.
public nonisolated struct CoreLossEdge: Sendable, Equatable, CustomStringConvertible {
    /// Element symbol, e.g. "C".
    public let element: String
    /// GOSH subshell name: "K1", "L1", "L2", "L3", or "L2,3" (Al: exSpy's binding-energy table names one combined edge).
    public let subshell: String
    /// The onset energy exSpy uses (`exspy/material/eels_binding_energies.json`), eV.
    public let onsetEV: Double

    public init(element: String, subshell: String, onsetEV: Double) {
        self.element = element; self.subshell = subshell; self.onsetEV = onsetEV
    }

    /// Carbon K, onset 284 eV.
    public static let carbonK = CoreLossEdge(element: "C", subshell: "K1", onsetEV: 284.0)
    /// Nitrogen K, onset 401 eV.
    public static let nitrogenK = CoreLossEdge(element: "N", subshell: "K1", onsetEV: 401.0)
    /// Oxygen K, onset 532 eV.
    public static let oxygenK = CoreLossEdge(element: "O", subshell: "K1", onsetEV: 532.0)
    /// Magnesium K, onset 1305 eV.
    public static let magnesiumK = CoreLossEdge(element: "Mg", subshell: "K1", onsetEV: 1305.0)
    /// Aluminium K, onset 1560 eV.
    public static let aluminiumK = CoreLossEdge(element: "Al", subshell: "K1", onsetEV: 1560.0)
    /// Silicon K, onset 1839 eV.
    public static let siliconK = CoreLossEdge(element: "Si", subshell: "K1", onsetEV: 1839.0)

    // The L edges. L2 and L3 of one element are twins in exSpy's model: one intensity, the L3 name the master
    // (`eelsmodel.py:283-327`); Al has the single combined "L2,3". Onsets from exSpy's eels_binding_energies.json.
    /// Magnesium L1, onset 89 eV.
    public static let magnesiumL1 = CoreLossEdge(element: "Mg", subshell: "L1", onsetEV: 89.0)
    /// Magnesium L2, onset 51 eV.
    public static let magnesiumL2 = CoreLossEdge(element: "Mg", subshell: "L2", onsetEV: 51.0)
    /// Magnesium L3, onset 51 eV.
    public static let magnesiumL3 = CoreLossEdge(element: "Mg", subshell: "L3", onsetEV: 51.0)
    /// Aluminium L1, onset 118 eV.
    public static let aluminiumL1 = CoreLossEdge(element: "Al", subshell: "L1", onsetEV: 118.0)
    /// Aluminium L2,3 (combined), onset 73 eV.
    public static let aluminiumL23 = CoreLossEdge(element: "Al", subshell: "L2,3", onsetEV: 73.0)
    /// Silicon L1, onset 149.7 eV.
    public static let siliconL1 = CoreLossEdge(element: "Si", subshell: "L1", onsetEV: 149.7)
    /// Silicon L2, onset 99.8 eV.
    public static let siliconL2 = CoreLossEdge(element: "Si", subshell: "L2", onsetEV: 99.8)
    /// Silicon L3, onset 99.2 eV.
    public static let siliconL3 = CoreLossEdge(element: "Si", subshell: "L3", onsetEV: 99.2)
    /// Iron L1, onset 846 eV.
    public static let ironL1 = CoreLossEdge(element: "Fe", subshell: "L1", onsetEV: 846.0)
    /// Iron L2, onset 721 eV.
    public static let ironL2 = CoreLossEdge(element: "Fe", subshell: "L2", onsetEV: 721.0)
    /// Iron L3, onset 708 eV.
    public static let ironL3 = CoreLossEdge(element: "Fe", subshell: "L3", onsetEV: 708.0)
    /// Copper L1, onset 1096 eV.
    public static let copperL1 = CoreLossEdge(element: "Cu", subshell: "L1", onsetEV: 1096.0)
    /// Copper L2, onset 951 eV.
    public static let copperL2 = CoreLossEdge(element: "Cu", subshell: "L2", onsetEV: 951.0)
    /// Copper L3, onset 931 eV.
    public static let copperL3 = CoreLossEdge(element: "Cu", subshell: "L3", onsetEV: 931.0)

    /// The edges whose GOS ships with SpectroKit: every K, L and M edge exSpy builds with the dft GOS (its eels_binding_energies.json against the GOSH file's
    /// tables): 383 edges of 95 elements, K 17, L 126, M 240 (`Resources/GOS/dft-gos-index.json`, tools/eels-edge/extract_gos.py --all). The 20 named edges
    /// above are among them, with the same onsets. Ordered by element symbol, then subshell.
    public static let bundled: [CoreLossEdge] = GOSPack.shared?.edges ?? [
        .carbonK, .nitrogenK, .oxygenK, .magnesiumK, .aluminiumK, .siliconK,
        .magnesiumL1, .magnesiumL2, .magnesiumL3, .aluminiumL1, .aluminiumL23, .siliconL1, .siliconL2, .siliconL3,
        .ironL1, .ironL2, .ironL3, .copperL1, .copperL2, .copperL3,
    ]

    /// The bundled edge of this element and GOSH subshell ("K1", "L3", "L2,3"), or nil.
    public static func bundled(_ element: String, _ subshell: String) -> CoreLossEdge? {
        bundled.first { $0.element == element && $0.subshell == subshell }
    }

    /// "K" or "L" (the shell the subshell belongs to).
    public var family: String { String(subshell.prefix(1)) }

    /// The GOSH table the subshell reads (the file's metadata/edges_info): K1, L1, M1 alone; L2, L3 and L2,3 share L23, M2, M3 and M2,3 share M23, M4, M5
    /// and M4,5 share M45, each with its own occupancy ratio.
    package var table: String {
        switch subshell {
        case "L2", "L3", "L2,3": "L23"
        case "M2", "M3", "M2,3": "M23"
        case "M4", "M5", "M4,5": "M45"
        default: subshell
        }
    }

    public var description: String { "\(element) \(subshell == "K1" ? "K" : subshell)" }
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

    /// The file of one edge as the first three slices wrote it: `dft-<El>-K1.json`, one edge per file (C, N, O).
    private struct Stored: Decodable {
        let element: String
        let subshell: String
        let onsetEV: Double
        let occupancyRatio: Double
        let freeEnergies: [Double]
        let q: [Double]
        let gos: [[Double]]
    }

    /// A per-TABLE file (task 16): `dft-<El>-<table>.json` with the edges that read it and their own onset and occupancy ratio.
    private struct StoredTable: Decodable {
        struct Edge: Decodable { let subshell: String; let onsetEV: Double; let occupancyRatio: Double }
        let element: String
        let table: String
        let edges: [Edge]
        let freeEnergies: [Double]
        let q: [Double]
        let gos: [[Double]]
    }

    /// The table shipped for `edge`, or nil when SpectroKit ships none for it.
    package static func bundled(_ edge: CoreLossEdge) -> GOSTable? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        let key = edge.element + "_" + edge.subshell
        if let t = cache[key] { return t }
        guard CoreLossEdge.bundled.contains(edge) else { return nil }
        func data(_ name: String) -> Data? {
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "GOS").flatMap { try? Data(contentsOf: $0) }
        }
        let made: GOSTable?
        if let d = data("dft-\(edge.element)-\(edge.subshell)"), let s = try? JSONDecoder().decode(Stored.self, from: d) {
            guard s.element == edge.element, s.subshell == edge.subshell, s.onsetEV == edge.onsetEV,
                  s.gos.count == s.freeEnergies.count, s.gos.allSatisfy({ $0.count == s.q.count }) else { return nil }
            made = GOSTable(edge: edge, occupancyRatio: Float(s.occupancyRatio), freeEnergies: s.freeEnergies.map { Float($0) },
                            q: s.q.map { Float($0) }, gos: s.gos.map { $0.map { Float($0) } })
        } else if let d = data("dft-\(edge.element)-\(edge.table)"), let s = try? JSONDecoder().decode(StoredTable.self, from: d),
                  s.element == edge.element, s.table == edge.table,
                  let e = s.edges.first(where: { $0.subshell == edge.subshell }), e.onsetEV == edge.onsetEV,
                  s.gos.count == s.freeEnergies.count, s.gos.allSatisfy({ $0.count == s.q.count }) {
            made = GOSTable(edge: edge, occupancyRatio: Float(e.occupancyRatio), freeEnergies: s.freeEnergies.map { Float($0) },
                            q: s.q.map { Float($0) }, gos: s.gos.map { $0.map { Float($0) } })
        } else {
            made = GOSPack.shared?.table(for: edge)
        }
        if let made { cache[key] = made }
        return made
    }

    nonisolated(unsafe) private static var cache: [String: GOSTable] = [:]
    private static let cacheLock = NSLock()
}

/// The pack of every K, L and M table (tools/eels-edge/extract_gos.py --all): `dft-gos-index.json` lists each table's element, name, byte offset and
/// sizes and the edges that read it; `dft-gos-tables.bin` holds per table free_energies, q and gos (energy-major) as float32 little-endian, the GOSH file's
/// stored values. Read once, mapped, never copied whole; a table is cut out when an edge first asks for it.
package nonisolated final class GOSPack: Sendable {
    struct Index: Decodable {
        struct Table: Decodable {
            struct Edge: Decodable { let subshell: String; let onsetEV: Double; let occupancyRatio: Double }
            let element: String
            let table: String
            let offset: Int
            let energies: Int
            let q: Int
            let edges: [Edge]
        }
        let tables: [Table]
        let packBytes: Int
    }

    let index: Index
    let data: Data
    package let edges: [CoreLossEdge]

    package static let shared: GOSPack? = {
        guard let i = Bundle.module.url(forResource: "dft-gos-index", withExtension: "json", subdirectory: "GOS"),
              let b = Bundle.module.url(forResource: "dft-gos-tables", withExtension: "bin", subdirectory: "GOS"),
              let indexData = try? Data(contentsOf: i), let index = try? JSONDecoder().decode(Index.self, from: indexData),
              let data = try? Data(contentsOf: b, options: .alwaysMapped), data.count == index.packBytes else { return nil }
        return GOSPack(index: index, data: data)
    }()

    init(index: Index, data: Data) {
        self.index = index
        self.data = data
        self.edges = index.tables.flatMap { t in t.edges.map { CoreLossEdge(element: t.element, subshell: $0.subshell, onsetEV: $0.onsetEV) } }
            .sorted { ($0.element, $0.subshell) < ($1.element, $1.subshell) }
    }

    /// The table `edge` reads, with its own onset and occupancy ratio; nil when the pack holds no such edge or the bytes do not fit the index.
    package func table(for edge: CoreLossEdge) -> GOSTable? {
        guard let t = index.tables.first(where: { $0.element == edge.element && $0.edges.contains { $0.subshell == edge.subshell } }),
              let e = t.edges.first(where: { $0.subshell == edge.subshell }), e.onsetEV == edge.onsetEV else { return nil }
        let count = t.energies + t.q + t.energies * t.q
        guard t.offset >= 0, t.offset + 4 * count <= data.count else { return nil }
        let floats: [Float] = data.withUnsafeBytes { raw in
            (0 ..< count).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: t.offset + 4 * $0, as: UInt32.self))) }
        }
        let fe = Array(floats[0 ..< t.energies]), q = Array(floats[t.energies ..< t.energies + t.q])
        let gos = (0 ..< t.energies).map { i in Array(floats[(t.energies + t.q + i * t.q) ..< (t.energies + t.q + (i + 1) * t.q)]) }
        return GOSTable(edge: edge, occupancyRatio: Float(e.occupancyRatio), freeEnergies: fe, q: q, gos: gos)
    }
}
