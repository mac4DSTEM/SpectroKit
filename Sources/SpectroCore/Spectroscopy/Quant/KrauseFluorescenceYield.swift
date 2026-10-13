//
//  KrauseFluorescenceYield.swift
//  Role: K-shell fluorescence yield omega_K from NIST EPQ `Krause1979.csv`.
//
//  Source: M. O. Krause, J. Phys. Chem. Ref. Data 8, 307 (1979), as quoted in
//  Markowicz (Handbook of X-ray Spectrometry) and shipped by EPQ (public domain).
//  Loader mapping (EPQ FluorescenceYield.java, KrauseFluorescenceYield.compute):
//  after the `//` comment lines, row index = Z - 1; column 0 = omega_K, 1-3 =
//  omega_L1, L2, L3, then Coster-Kronig f12, f13, f23 (read here: K only).
//  Z = 1...4 have empty rows: EPQ stores null there (a lookup would throw a
//  NullPointerException); we return nil.
//  DEVIATION: K shell only. L needs the subshell yields plus Coster-Kronig and is
//  not used by a computed k yet.
//

import Foundation

package nonisolated struct KrauseFluorescenceYield: FluorescenceYield {
    package let sourceName = "Krause 1979 (NIST EPQ Krause1979.csv)"
    private let omegaK: [Int: Double]
    /// Data rows read (physical lines after the `//` comments, like EPQ's `loadTable`:
    /// a blank line would still advance Z). The shipped file has 110.
    package let rowCount: Int

    package init(csv: String) {
        var out: [Int: Double] = [:]
        var z = 0
        var lines = csv.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }   // the final newline
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") { continue }
            z += 1
            let first = line.split(separator: ",", omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if let v = Double(first) { out[z] = v }
        }
        omegaK = out; rowCount = z
    }

    package init(contentsOf url: URL) throws { self.init(csv: try String(contentsOf: url, encoding: .utf8)) }

    package static func bundled(in bundle: Bundle = .main) -> KrauseFluorescenceYield? {
        guard let url = bundle.url(forResource: "Krause1979", withExtension: "csv", subdirectory: "Spectroscopy")
            ?? bundle.url(forResource: "Krause1979", withExtension: "csv") else { return nil }
        return try? KrauseFluorescenceYield(contentsOf: url)
    }

    package func omegaK(z: Int) -> Double? { omegaK[z] }

    package func omega(element: String, line: String) -> Double? {
        guard line.hasPrefix("K"), let z = QuantElementData.entry(element)?.z else { return nil }
        return omegaK[z]
    }
}
