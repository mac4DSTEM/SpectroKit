//
//  KFactorImport.swift
//  Role: Cliff-Lorimer k-factor tables as text, as the instrument software exports them, into the kit's typed k-factor list
//        (`QuantificationMethod.TypedK`, the list `KFactorSource.typed` runs on and `PooledQuantification.kFactors` reports).
//
//  What it reads. One row per element and line: element, line, k, and optionally sigma. Separators: tab, semicolon or comma (the
//  first of these found in the text, in that order; with none, runs of whitespace). A decimal comma is accepted where the
//  separator is not a comma. A header row is optional (recognised when its k field is not a number); its column names (element,
//  line, k / k-factor / kfactor, sigma / error / uncertainty, with "%" or "rel" in a sigma name meaning relative sigma in percent)
//  decide the column order; without one the order is element, line, k, sigma. An element and its line may share one field
//  ("Fe K", "Fe-K", "Fe_Ka"). Lines are normalised to the kit's names: K, Ka, K-alpha, Kalpha, Ka1 and the Greek form are "Ka";
//  likewise "La" and "Ma"; "Kb" etc. are kept. Empty lines, lines starting with "#" or "//", and lines starting with "unit" or
//  "units" are ignored (they are comments or a units line).
//
//  What it refuses, by name and line: a row with too few fields, an element symbol the kit does not know, a k that is not a positive
//  finite number, a sigma that is not a finite number of zero or more, a line it cannot place, a repeated element and line.
//
//  Convention (eXSpy's, `quantification_cliff_lorimer`): C_A / C_B = (k_A / k_B) (I_A / I_B), only ratios of k enter. Values are
//  taken as given; a table that lists the inverse convention is the caller's to invert. No eXSpy table of k-factors exists (exSpy's
//  documentation gives the list `[1, 1.47, 1.72]` for `['Al_Ka', 'Cr_Ka', 'Ni_Ka']` as the example); the tests pin that the
//  parsed list drives the same composition as exSpy's own function (`tools/edx-0100/pins.py`).
//

import Foundation

/// One row of an imported table.
public nonisolated struct ImportedKFactor: Sendable, Equatable {
    public var element: String
    /// The kit's line name: "Ka", "La", "Ma", "Kb", ...
    public var line: String
    public var k: Double
    /// Absolute 1-sigma in the units of k, as the table gave it; nil if none.
    public var sigma: Double?
    /// The table line this row came from (1-based), for messages.
    public var sourceLine: Int

    public init(element: String, line: String, k: Double, sigma: Double? = nil, sourceLine: Int = 0) {
        self.element = element; self.line = line; self.k = k; self.sigma = sigma; self.sourceLine = sourceLine
    }
}

public nonisolated struct KFactorTable: Sendable, Equatable {
    public var rows: [ImportedKFactor]
    /// The header's column names as read, nil when the table had none.
    public var header: [String]?
    /// Lines that were ignored as comments or units, with their text (so a caller can show them).
    public var ignored: [String]

    public init(rows: [ImportedKFactor], header: [String]? = nil, ignored: [String] = []) {
        self.rows = rows; self.header = header; self.ignored = ignored
    }
}

public nonisolated enum KFactorImportError: Error, Equatable, LocalizedError {
    case noRows
    case tooFewFields(line: Int, text: String)
    case unknownElement(line: Int, symbol: String)
    case badK(line: Int, text: String)
    case badSigma(line: Int, text: String)
    case unknownLine(line: Int, text: String)
    case duplicate(element: String, line: String, sourceLine: Int)
    case missingColumn(String)
    case noEntry(element: String, line: String)
    case referenceNotInSet(String)

    public var errorDescription: String? {
        switch self {
        case .noRows: return "The k-factor table has no rows."
        case .tooFewFields(let n, let t): return "k-factor table line \(n): a row needs an element, a line and a k, but this has fewer fields: \"\(t)\"."
        case .unknownElement(let n, let s): return "k-factor table line \(n): \"\(s)\" is not an element symbol."
        case .badK(let n, let t): return "k-factor table line \(n): the k \"\(t)\" is not a positive number."
        case .badSigma(let n, let t): return "k-factor table line \(n): the sigma \"\(t)\" is not a number of zero or more."
        case .unknownLine(let n, let t): return "k-factor table line \(n): \"\(t)\" is not an X-ray line name (K, Ka, Kb, L, La, M, ...)."
        case .duplicate(let e, let l, let n): return "k-factor table line \(n): \(e) \(l) is listed twice."
        case .missingColumn(let c): return "The k-factor table's header has no \(c) column."
        case .noEntry(let e, let l): return "The k-factor table has no \(e) \(l) row."
        case .referenceNotInSet(let e): return "The reference element \(e) is not among the elements asked for."
        }
    }
}

public nonisolated enum KFactorImport {

    // MARK: Parse

    public static func parse(_ text: String) throws -> KFactorTable {
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Drop a byte-order mark.
        let lines = rawLines.enumerated().map { $0.offset == 0 ? $0.element.replacingOccurrences(of: "\u{FEFF}", with: "") : $0.element }
        let separator: Character? = lines.contains { $0.contains("\t") } ? "\t" : (lines.contains { $0.contains(";") } ? ";" : (lines.contains { $0.contains(",") } ? "," : nil))

        func fields(_ s: String) -> [String] {
            let parts: [Substring]
            if let sep = separator { parts = s.split(separator: sep, omittingEmptySubsequences: false) }
            else { parts = s.split(whereSeparator: { $0 == " " || $0 == "\t" }) }
            return parts.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func number(_ s: String) -> Double? {
            var t = s.trimmingCharacters(in: .whitespaces)
            if separator != "," { t = t.replacingOccurrences(of: ",", with: ".") }
            guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
            return v
        }

        var ignored: [String] = []
        var content: [(n: Int, text: String)] = []
        for (i, l) in lines.enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let low = t.lowercased()
            if t.hasPrefix("#") || t.hasPrefix("//") || low.hasPrefix("unit") { ignored.append(t); continue }
            content.append((i + 1, t))
        }

        var header: [String]? = nil
        var order = (element: 0, line: 1, k: 2, sigma: 3 as Int?)
        var sigmaIsPercent = false
        var combined = false   // element and line in one field
        var rows: [(n: Int, f: [String])] = []
        for (idx, c) in content.enumerated() {
            let f = fields(c.text)
            if idx == 0 {
                // A header: a first row with no number in it that names a column (element, symbol, line, family, sigma, factor, error).
                let words = ["element", "symbol", "line", "family", "sigma", "factor", "error", "uncertain"]
                if !f.contains(where: { number($0) != nil }), f.contains(where: { c in words.contains { c.lowercased().contains($0) } }) {
                    header = f
                    let names = f.map { $0.lowercased() }
                    func find(_ keys: [String]) -> Int? { names.firstIndex { n in keys.contains { n.contains($0) } } }
                    guard let e = find(["element", "elem", "symbol"]) else { throw KFactorImportError.missingColumn("element") }
                    guard let k = names.firstIndex(where: { $0.contains("k") && !$0.contains("sigma") && !$0.contains("error") && !$0.contains("line") && !$0.hasPrefix("elem") }) ?? find(["factor"]) else {
                        throw KFactorImportError.missingColumn("k")
                    }
                    let l = find(["line", "family", "shell", "series", "edge"])
                    let s = names.firstIndex { n in ["sigma", "error", "uncertain", "std", "\u{03C3}"].contains { n.contains($0) } }
                    if let l { order = (e, l, k, s) } else { order = (e, e, k, s); combined = true }
                    if let s, names[s].contains("%") || names[s].contains("rel") { sigmaIsPercent = true }
                    continue
                }
            }
            rows.append((c.n, f))
        }
        guard !rows.isEmpty else { throw KFactorImportError.noRows }
        // Without a header, an element field that carries its line ("Fe K") means the columns are element+line, k, sigma.
        if header == nil, let first = rows.first?.f.first, elementSplit(first).line != nil { order = (0, 0, 1, 2); combined = true }

        var out: [ImportedKFactor] = []
        for (n, f) in rows {
            let joined = f.joined(separator: " ")
            guard f.count > max(order.element, order.line, order.k) else { throw KFactorImportError.tooFewFields(line: n, text: joined) }
            var elementField = f[order.element]
            var lineField = f[order.line]
            if combined || elementSplit(elementField).line != nil {
                let (e, l) = elementSplit(elementField)
                guard let l else { throw KFactorImportError.tooFewFields(line: n, text: joined) }
                elementField = e; lineField = l
            }
            guard let symbol = normalisedSymbol(elementField) else { throw KFactorImportError.unknownElement(line: n, symbol: elementField) }
            guard let line = normalisedLine(lineField) else { throw KFactorImportError.unknownLine(line: n, text: lineField) }
            guard let k = number(f[order.k]), k > 0 else { throw KFactorImportError.badK(line: n, text: f[order.k]) }
            var sigma: Double? = nil
            if let si = order.sigma, si < f.count, !f[si].isEmpty {
                guard let s = number(f[si]), s >= 0 else { throw KFactorImportError.badSigma(line: n, text: f[si]) }
                sigma = sigmaIsPercent ? s / 100 * k : s
            }
            if out.contains(where: { $0.element == symbol && $0.line == line }) {
                throw KFactorImportError.duplicate(element: symbol, line: line, sourceLine: n)
            }
            out.append(ImportedKFactor(element: symbol, line: line, k: k, sigma: sigma, sourceLine: n))
        }
        return KFactorTable(rows: out, header: header, ignored: ignored)
    }

    private static func normalisedSymbol(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard (1...2).contains(t.count), t.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        let sym = t.prefix(1).uppercased() + t.dropFirst().lowercased()
        return QuantElementData.entry(sym) != nil ? sym : nil
    }

    /// "Fe K", "Fe-K", "Fe_Ka" -> ("Fe", "K"); a lone symbol -> (symbol, nil).
    private static func elementSplit(_ s: String) -> (element: String, line: String?) {
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).map(String.init)
        if parts.count >= 2 { return (parts[0], parts.dropFirst().joined()) }
        return (s, nil)
    }

    private static func normalisedLine(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespaces).lowercased()
        for w in [" series", "-series", "series", "-line", " line"] { t = t.replacingOccurrences(of: w, with: "") }
        t = t.replacingOccurrences(of: "\u{03B1}", with: "a").replacingOccurrences(of: "\u{03B2}", with: "b")
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "alpha", with: "a").replacingOccurrences(of: "beta", with: "b")
        guard let first = t.first, "klm".contains(first) else { return nil }
        let rest = String(t.dropFirst())
        let family = first.uppercased()
        switch rest {
        case "", "a", "a1": return family + "a"
        case "b", "b1": return family + "b"
        default:
            // Kb3, Lb1, Lg, Lg1, Ll, Ln, Mz ...: keep what the line table names (letter, then digits).
            guard rest.count <= 3, rest.first!.isLetter, rest.dropFirst().allSatisfy(\.isNumber) else { return nil }
            return family + rest
        }
    }

    // MARK: To the kit's typed list

    /// The typed k list for `elements`, in that order, taking each element's row for `line` (default "Ka"). With a `reference`, the
    /// factors are divided by the reference's so that it is 1 and carries sigma 0 (only ratios enter Cliff-Lorimer; the kit's
    /// convention for a set with a reference element). A sigma in the table becomes a relative sigma (sigma / k); a row without one
    /// takes the method's default (`relativeSigma` nil).
    public static func typedK(from table: KFactorTable, elements: [String], line: String = "Ka",
                              reference: String? = nil) throws -> [QuantificationMethod.TypedK] {
        if let r = reference, !elements.contains(r) { throw KFactorImportError.referenceNotInSet(r) }
        var picked: [ImportedKFactor] = []
        for e in elements {
            guard let row = table.rows.first(where: { $0.element == e && $0.line == line }) else {
                throw KFactorImportError.noEntry(element: e, line: line)
            }
            picked.append(row)
        }
        let scale = reference.flatMap { r in picked.first { $0.element == r }?.k } ?? 1
        return picked.map { row in
            let isRef = row.element == reference
            return QuantificationMethod.TypedK(element: row.element, k: row.k / scale,
                                               relativeSigma: isRef ? 0 : row.sigma.map { $0 / row.k })
        }
    }

    /// Sets `method` to the typed k from `table`: source, ISO date, reference, the factors for the method's elements that are
    /// switched on for quantification, each at `line`.
    public static func apply(_ table: KFactorTable, to method: inout QuantificationMethod, source: String, date: String,
                             line: String = "Ka", reference: String? = nil) throws {
        let quantified = method.elements.filter { $0.role == .quantify }.map(\.symbol)
        let typed = try typedK(from: table, elements: quantified, line: line, reference: reference)
        method.kFactorSource = .typed
        method.kSource = source
        method.kDate = date
        method.kReference = reference
        method.typedK = typed
    }

    /// The factors and relative sigmas as plain arrays in the order of `elements`, for
    /// `EDXQuantificationMethod.cliffLorimer(kFactors:thicknessNm:)` and `EDXQuantification.quantifyWithSigma`. A row without a sigma
    /// takes `defaultRelativeSigma` (the kit's 0.20), the reference 0.
    public static func cliffLorimerFactors(from table: KFactorTable, elements: [String], line: String = "Ka", reference: String? = nil,
                                           defaultRelativeSigma: Double = QuantificationMethod.defaultSigmaK) throws -> (k: [Double], relativeSigma: [Double]) {
        let typed = try typedK(from: table, elements: elements, line: line, reference: reference)
        return (typed.map(\.k), typed.map { $0.relativeSigma ?? defaultRelativeSigma })
    }
}
