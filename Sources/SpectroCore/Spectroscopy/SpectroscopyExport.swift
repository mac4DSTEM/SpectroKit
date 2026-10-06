//
//  SpectroscopyExport.swift
//  Role: What the Spectroscopy room's Export step writes, built from a finished `PooledQuantification` and nothing
//        else: the results table as CSV and the method as JSON (the method's own sorted-keys encoding plus its hash).
//        Pure text; the room's view only hands it to a save panel.
//
//  The CSV states what the numbers are in its own header, so a file read alone keeps its caveats: the at% columns carry
//  validation "none" (the cross-section source is unvalidated), a row's flags say a line was held at 0 or refused, and
//  the footer lines of the fit (estimator, continuum, beam and its source, axis, k, absorption) travel as `#` lines.
//  Numbers are written with a period and six significant digits whatever the locale.
//

import Foundation

package nonisolated enum SpectroscopyExport {
    package static let columns = ["element", "line", "net_counts", "sigma_net", "kfree_ratio", "sigma_kfree",
                                  "at_percent", "sigma_at_percent", "validation", "flags", "estimator"]

    /// The results table, one row per fitted element, with the fit's provenance as `#` header lines.
    package static func csv(_ q: PooledQuantification, regionName: String) -> String {
        var out: [String] = []
        out.append("# mac4DSTEM Spectroscopy quantification, region: \(regionName)")
        out.append("# validation: " + (q.hasAbundance
            ? "UNVALIDATED (at% rests on a computed or typed k with validation \"none\"; net counts and k-free ratios are fit areas)"
            : q.unlistedCheck?.withholds == true
                ? "net counts only; at% and k-free ratios withheld by the unlisted-line check"
                : q.unlistedCheckPending
                    ? "net counts only; at% and k-free ratios held until the unlisted-line check finishes"
                    : "net counts and k-free ratios only; no at% was computed"))
        // WP3b F1: the unlisted-line check travels with the numbers, finished or not.
        out.append("# unlisted-line check: " + (q.unlistedCheck?.summary
            ?? (q.unlistedCheckPending ? "check not finished when this was exported; at% omitted" : "not run")))
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
    package static func methodJSON(_ m: QuantificationMethod) -> String {
        "{\"method\":\(m.canonicalJSON),\"sha256\":\"\(m.hash)\"}\n"
    }

    /// The inspector's readouts of what the step will write: the elements of the table and the method's short hash.
    package static func elementsLine(_ q: PooledQuantification) -> String { q.rows.map(\.element).joined(separator: ", ") }
    package static func shortHash(_ m: QuantificationMethod) -> String { String(m.hash.prefix(8)) }

    /// The default file name: the spectrum image's stem, the region, what it is.
    package static func fileStem(imageName: String, regionName: String) -> String {
        let base = (imageName as NSString).deletingPathExtension
        let raw = "\(base) \(regionName)"
        let allowed = raw.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return String(allowed)
    }

    private static func num(_ v: Double) -> String { v.isFinite ? String(format: "%.6g", v) : "" }

    /// RFC 4180: a field with a comma, quote or line break is quoted, quotes doubled.
    private static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
