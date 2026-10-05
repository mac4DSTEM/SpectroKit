//
//  EPQLineWeights.swift
//  Role: Relative emission weights of the K/L/M transitions from NIST EPQ
//        `LineWeights.csv` (public domain in the US; notice in EPQ LicenseFile.txt;
//        pinned by tools/lib/fetch-epq.sh).
//
//  Layout: a `//` header row of 77 transition names (K-L3, K-L2, K-M3, ...), then
//  one row per atomic number starting at Z = 0 (row index == Z), weights relative
//  to the strongest line of the shell (K-L3 = 1 for K). Row Z = 12 gives Mg:
//  K-L3 1, K-L2 0.507 (read 2026-10-05).
//

import Foundation

package nonisolated struct EPQLineWeights: Sendable {
    private let names: [String]
    private let rows: [[Double]]

    package init(csv: String) {
        var names: [String] = []
        var rows: [[Double]] = []
        for line in csv.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("//") {
                names = line.dropFirst(2).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if !line.isEmpty {
                rows.append(line.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) ?? 0 })
            }
        }
        self.names = names; self.rows = rows
    }

    package init(contentsOf url: URL) throws {
        self.init(csv: try String(contentsOf: url, encoding: .utf8))
    }

    /// Weight of one transition (e.g. "K-L3") for `element`, nil if unknown.
    package func weight(element: String, transition: String) -> Double? {
        guard let z = QuantElementData.entry(element)?.z, rows.indices.contains(z),
              let c = names.firstIndex(of: transition), rows[z].indices.contains(c) else { return nil }
        return rows[z][c]
    }

    /// Fraction of the whole shell's emission carried by `transitions`
    /// (sum over them / sum over every transition whose name starts with `shell`-).
    /// Ka of Al: (K-L3 + K-L2) / sum K-* = 1.505/1.5524.
    package func fraction(element: String, shell: String, transitions: [String]) -> Double? {
        guard let z = QuantElementData.entry(element)?.z, rows.indices.contains(z) else { return nil }
        var all = 0.0, part = 0.0
        for (i, n) in names.enumerated() where rows[z].indices.contains(i) && n.hasPrefix(shell + "-") {
            all += rows[z][i]
            if transitions.contains(n) { part += rows[z][i] }
        }
        return all > 0 ? part / all : nil
    }
}
