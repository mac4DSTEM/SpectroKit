//
//  SpectroscopyExport.swift
//  Role: What the Spectroscopy room's Export step writes, built from a finished `PooledQuantification` and nothing
//        else: the results table as CSV and the method as JSON (the method's own sorted-keys encoding plus its hash).
//        Pure text; the room's view only hands it to a save panel.
//
//  The CSV states what the numbers are in its own header, so a file read alone keeps its caveats: a `# method:` line names
//  the k table and its reference element behind the at% columns, a row's flags say a line was held at 0 or refused, and
//  the footer lines of the fit (estimator, continuum, beam and its source, axis, k, absorption) travel as `#` lines.
//  Numbers are written with a period and six significant digits whatever the locale.
//

import Foundation

public nonisolated enum SpectroscopyExport {
    package static let columns = ["element", "line", "net_counts", "sigma_net", "kfree_ratio", "sigma_kfree",
                                  "at_percent", "sigma_at_percent", "validation", "flags", "estimator"]

    /// The results table, one row per fitted element, with the fit's provenance as `#` header lines.
    /// The first `#` line names the producing application: `title` is that name, defaulting to the neutral "Spectroscopy quantification".
    public static func csv(_ q: PooledQuantification, regionName: String,
                            title: String = "Spectroscopy quantification") -> String {
        var out: [String] = []
        out.append("# \(title), region: \(regionName)")
        out.append("# method: " + (q.hasAbundance
            ? "at% from k " + (q.kFactorSourceDescription ?? q.method.kSource) + "; net counts and k-free ratios are fit areas"
            : "net counts and k-free ratios only; no at% was computed"))
        if let c = q.abundanceCaveat { out.append("# at% caveat: " + c) }
        // WP3b F1: the unlisted-line check travels with the numbers, finished or not.
        out.append("# unlisted-line check: " + (q.unlistedCheck?.summary
            ?? (q.unlistedCheckPending ? "check not finished when this was exported" : "not run")))
        out.append("# method hash (sha256 of the method JSON): \(q.method.hash)")
        for line in q.footerLines { out.append("# " + line.replacingOccurrences(of: "\n", with: " ")) }
        if let r = q.refinement {
            out.append(String(format: "# axis refinement residual (RSS): file %.0f, refined %.0f", r.rssFile, r.rssRefined))
        }
        out.append("# \(q.qualityLabel) \(num(q.quality))")
        for w in q.warnings { out.append("# warning: " + w.replacingOccurrences(of: "\n", with: " ")) }
        out.append(columns.joined(separator: ","))
        for r in q.rows {
            var flags: [String] = []
            if let f = r.failure { flags.append(f) }
            if let n = r.lineNote, r.failure == nil { flags.append(n) }
            if r.atBound && r.failure == nil { flags.append("held at 0 by the non-negativity bound: not detected, sigma is an upper-limit scale") }
            if !r.supported && r.failure == nil { flags.append("not supported by the data") }
            if r.isReference { flags.append("reference element") }
            let fields = [r.element, r.groupID, num(r.net), num(r.sigma),
                          r.kFreeRatio.map(num) ?? "", r.isReference ? "" : (r.kFreeSigma.map(num) ?? ""),
                          r.atomicPercent.map(num) ?? "", r.atomicSigma.map(num) ?? "",
                          r.atomicPercent == nil ? "" : PooledQuantification.abundanceValidation,
                          flags.joined(separator: "; "), q.fit.methodLabel]
            out.append(fields.map(field).joined(separator: ","))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// `{"method": <the method's canonical JSON, byte for byte>, "sha256": "<its hash>"}`: the hash is over exactly the
    /// bytes of the `method` value, so a reader can verify it without re-encoding.
    public static func methodJSON(_ m: QuantificationMethod) -> String {
        "{\"method\":\(m.canonicalJSON),\"sha256\":\"\(m.hash)\"}\n"
    }

    /// The method's short hash, as an inspector shows it.
    public static func shortHash(_ m: QuantificationMethod) -> String { String(m.hash.prefix(8)) }

    /// The default file name: the spectrum image's stem, the region, what it is.
    public static func fileStem(imageName: String, regionName: String) -> String {
        let base = (imageName as NSString).deletingPathExtension
        let raw = "\(base) \(regionName)"
        let allowed = raw.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return String(allowed)
    }

    package static func num(_ v: Double) -> String { v.isFinite ? String(format: "%.6g", v) : "" }

    /// RFC 4180: a field with a comma, quote or line break is quoted, quotes doubled.
    package static func field(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
