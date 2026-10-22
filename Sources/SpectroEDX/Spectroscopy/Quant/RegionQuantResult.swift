//
//  RegionQuantResult.swift
//  Role: everything one report row needs about one region's quantification, as plain data: the region's name and pixel count, the
//        elements and their lines, the k-factors and where they came from, the net counts with sigma, wt% and at% with sigma, the
//        absorption note, the method hash, the unlisted-line check's outcome and the validation. Built from a finished
//        `PooledQuantification` by ONE function (`RegionQuantResult.make`), so a table row is printed without recomputing anything.
//        Codable and Sendable; nothing in it names an app.
//
//  The sigma on wt% and at% is the pooled quantification's own (counting sigma of the fitted areas through their covariance, the
//  k-factors' relative sigma, the typed thickness' sigma where the absorption correction is on), with the shares in `*SigmaText`.
//  `validation` is "none": every composition rests on a k (or zeta, cross section) that has not been checked against a standard.
//
//  The CSV writer follows `SpectroscopyExport`: RFC 4180 quoting, a period and six significant digits whatever the locale. One WIDE
//  row per region (`csvHeader(elements:)` and `csvRow(elements:)`, the elements fixed by the caller so regions line up) or one LONG
//  row per element (`csvLongHeader`, `csvLongRows`). `reportRow(elements:)` is the wide row as a string array for a table view.
//  An element with two fitted lines (two rows of one element) is ONE block of the wide row: `line` names them joined by "+", the net
//  counts, wt% and at% are their sums, and the sigmas and k are left empty (the lines' covariance is not in the result); the long
//  form has a row per line.
//

import Foundation

public nonisolated struct RegionQuantResult: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public var element: String
        /// The fitted group, for example "Al_Ka".
        public var line: String
        /// nil when the fit gave no finite value (a plain `JSONEncoder` refuses NaN).
        public var netCounts: Double?
        public var netSigma: Double?
        /// Held at 0 by the non-negativity bound: not detected, the sigma is an upper-limit scale.
        public var atBound: Bool
        public var isReference: Bool
        /// k relative to the reference element (computed or typed), its relative sigma; nil without a k source.
        public var k: Double?
        public var kRelativeSigma: Double?
        public var weightPercent: Double?
        public var weightSigma: Double?
        public var atomicPercent: Double?
        public var atomicSigma: Double?
        /// "counting 0.6 % + k 20 % + ... = 21 % -> +-1.1 at%".
        public var weightSigmaText: String
        public var atomicSigmaText: String
        /// net / net(reference), independent of k.
        public var kFreeRatio: Double?
        public var kFreeSigma: Double?
        /// Why the row has no number, or a caveat on it (line moved, bound, unsupported).
        public var flags: [String]
    }

    public var regionName: String
    /// Pixels pooled into the spectrum.
    public var pixelCount: Int
    /// The quantified elements, in row order.
    public var elements: [String]
    public var lines: [Line]
    /// "computed" or "typed"; nil when no at% was computed.
    public var kKind: String?
    public var kSource: String?
    public var kDate: String?
    public var kReference: String?
    /// "absorption correction: off", "absorption: <geometry, thickness>" or "absorption: not applied - <why>".
    public var absorptionNote: String
    /// SHA-256 of the method's canonical JSON, and its first eight characters.
    public var methodHash: String
    public var methodHashShort: String
    /// The unlisted-line check's summary, "check not finished" or "not run".
    public var unlistedLineCheck: String
    /// Names of the unlisted lines the check found (empty: none, or not run).
    public var unlistedElements: [String]
    /// The caveat on the at% rows, or nil.
    public var abundanceCaveat: String?
    /// Why no at% was computed, or nil.
    public var abundanceRefusal: String?
    public var estimator: String
    /// "chi2_r 1.04 (Pearson)" or "reduced deviance 1.02".
    public var fitQuality: String
    public var warnings: [String]
    /// The fit's own footer lines (estimator, background, escape and sum model, energy axis, range, sigma scope).
    public var footerLines: [String]
    public var validation: String

    // MARK: Build

    /// The one function. `regionName` and `pixelCount` are the ones the quantification was run on (`PooledQuantificationInput`).
    public static func make(from q: PooledQuantification, regionName: String, pixelCount: Int) -> RegionQuantResult {
        let k = q.kFactors
        var lines: [Line] = []
        for (i, r) in q.rows.enumerated() {
            var flags: [String] = []
            if let f = r.failure { flags.append(f) }
            if let n = r.lineNote, r.failure == nil { flags.append(n) }
            if r.atBound && r.failure == nil { flags.append("held at 0 by the non-negativity bound: not detected, sigma is an upper-limit scale") }
            if !r.supported && r.failure == nil { flags.append("not supported by the data") }
            let kf = k.flatMap { i < $0.count ? $0[i] : nil }
            lines.append(Line(element: r.element, line: r.groupID, netCounts: r.net.isFinite ? r.net : nil, netSigma: r.sigma.isFinite ? r.sigma : nil, atBound: r.atBound,
                              isReference: r.isReference, k: kf?.k, kRelativeSigma: kf?.relativeSigma,
                              weightPercent: r.weightPercent, weightSigma: r.weightSigma,
                              atomicPercent: r.atomicPercent, atomicSigma: r.atomicSigma,
                              weightSigmaText: r.weightTermsText, atomicSigmaText: r.atomicTermsText,
                              kFreeRatio: r.kFreeRatio, kFreeSigma: r.isReference ? nil : r.kFreeSigma, flags: flags))
        }
        let absorption: String
        switch q.absorption {
        case .off: absorption = "absorption correction: off"
        case .applied(let s): absorption = "absorption: " + s
        case .refused(let why): absorption = "absorption: not applied - " + why
        }
        let check: String = q.unlistedCheck?.summary ?? (q.unlistedCheckPending ? "check not finished" : "not run")
        return RegionQuantResult(
            regionName: regionName, pixelCount: pixelCount, elements: q.rows.map(\.element), lines: lines,
            kKind: q.kSet?.kind.rawValue, kSource: q.kFactorSourceDescription, kDate: q.kSet?.date, kReference: q.kSet?.reference,
            absorptionNote: absorption, methodHash: q.method.hash, methodHashShort: SpectroscopyExport.shortHash(q.method),
            unlistedLineCheck: check, unlistedElements: q.unlistedCheck?.names ?? [],
            abundanceCaveat: q.abundanceCaveat, abundanceRefusal: q.abundanceRefusal,
            estimator: q.fit.methodLabel, fitQuality: q.qualityText, warnings: q.warnings,
            footerLines: q.footerLines, validation: PooledQuantification.abundanceValidation)
    }

    // MARK: CSV

    private static let regionColumns = ["region", "pixels", "validation", "k_source", "absorption", "unlisted_line_check", "method_hash", "fit_quality"]
    private static let perElement = ["line", "net_counts", "sigma_net", "k", "wt_percent", "sigma_wt_percent", "at_percent", "sigma_at_percent"]

    /// Header of the wide row: the region columns, then eight per element in the order given.
    public static func csvHeader(elements: [String]) -> String {
        (regionColumns + elements.flatMap { e in perElement.map { "\(e)_\($0)" } }).map(SpectroscopyExport.field).joined(separator: ",")
    }

    /// The wide row as strings, in the order of `csvHeader(elements:)`; an element the region lacks gives empty fields.
    public func reportRow(elements: [String]) -> [String] {
        let num = SpectroscopyExport.num
        var out = [regionName, String(pixelCount), validation, kSource ?? "", absorptionNote, unlistedLineCheck, methodHash, fitQuality]
        for e in elements {
            let ls = lines.filter { $0.element == e }
            if ls.count == 1, let l = ls.first {
                out += [l.line, l.netCounts.map(num) ?? "", l.netSigma.map(num) ?? "", l.k.map(num) ?? "", l.weightPercent.map(num) ?? "",
                        l.weightSigma.map(num) ?? "", l.atomicPercent.map(num) ?? "", l.atomicSigma.map(num) ?? ""]
            } else if ls.count > 1 {
                func total(_ v: [Double?]) -> String { let f = v.compactMap { $0 }; return f.isEmpty ? "" : num(f.reduce(0, +)) }
                out += [ls.map(\.line).joined(separator: "+"), total(ls.map(\.netCounts)), "", "", total(ls.map(\.weightPercent)), "",
                        total(ls.map(\.atomicPercent)), ""]
            } else {
                out += [String](repeating: "", count: Self.perElement.count)
            }
        }
        return out
    }

    public func csvRow(elements: [String]) -> String { reportRow(elements: elements).map(SpectroscopyExport.field).joined(separator: ",") }

    /// Header of the long form: one row per element and region.
    public static let csvLongHeader = (regionColumns + ["element", "line", "net_counts", "sigma_net", "k", "sigma_k_rel", "wt_percent", "sigma_wt_percent",
                                                        "at_percent", "sigma_at_percent", "kfree_ratio", "sigma_kfree", "flags"]).joined(separator: ",")

    public var csvLongRows: [String] {
        let num = SpectroscopyExport.num
        let head: [String] = [regionName, String(pixelCount), validation, kSource ?? "", absorptionNote, unlistedLineCheck, methodHash, fitQuality]
        return lines.map { l in
            let net: [String] = [l.netCounts.map(num) ?? "", l.netSigma.map(num) ?? "", l.k.map(num) ?? "", l.kRelativeSigma.map(num) ?? ""]
            let wt: [String] = [l.weightPercent.map(num) ?? "", l.weightSigma.map(num) ?? ""]
            let at: [String] = [l.atomicPercent.map(num) ?? "", l.atomicSigma.map(num) ?? ""]
            let kfree: [String] = [l.kFreeRatio.map(num) ?? "", l.kFreeSigma.map(num) ?? "", l.flags.joined(separator: "; ")]
            let fields: [String] = head + [l.element, l.line] + net + wt + at + kfree
            return fields.map(SpectroscopyExport.field).joined(separator: ",")
        }
    }
}
