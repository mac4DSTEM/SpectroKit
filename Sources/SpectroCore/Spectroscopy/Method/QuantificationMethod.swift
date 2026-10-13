//
//  QuantificationMethod.swift
//  Role: The quantification method as ONE value (v5.0 WP3 lane M, ADR 054 items 1-3, 6, 9 and the
//        addendum): estimator, background, element roles, where k comes from, the absorption
//        correction and the thickness. Nothing here computes a number; the fit (lane F), the k-factors
//        and absorption (lane K) and the statistics (lane T) read it.
//
//  Codable with sorted keys, so encoding a decoded method gives the same bytes (`canonicalJSON`), and
//  `hash` is the SHA-256 of those bytes: two methods are the same method exactly when their hashes
//  are equal. The replay step "quantification" (`QuantificationStep`) records the JSON and the hash.
//
//  The defaults are ADR 054's and are those `SpectroscopySession.method` always had: least squares,
//  unweighted; empirical continuum with the Al K-edge step; computed k; four-detector absorption on;
//  no thickness assumed.
//

import Foundation
import CryptoKit

public nonisolated struct QuantificationMethod: Codable, Equatable, Sendable {

    /// Bumped when a field's meaning changes; a decoder refuses a newer one (`decode`).
    package static let currentVersion = 1

    /// Item 1: least squares, unweighted, is the named default; Poisson maximum likelihood is Expert.
    public enum Estimator: String, CaseIterable, Codable, Sendable {
        case leastSquares
        case poissonMaximumLikelihood
    }

    /// Item 2: a fitted whole-spectrum empirical continuum with the Al K-edge step (Velox's
    /// "Empirical") by default; eXSpy's whole-range sixth-order polynomial is the parity path.
    public enum Background: String, CaseIterable, Codable, Sendable {
        case empiricalWithAlEdge
        case wholeRangePolynomial6
    }

    /// Item 3 and the addendum: k is computed (Bote-Salvat sigma, Krause omega_K, EPQ's SDD
    /// efficiency; unvalidated) or typed with its source. No zeta in the menu.
    public enum KFactorSource: String, CaseIterable, Codable, Sendable {
        case computed
        /// The name the room used before the addendum replaced Brown-Powell; same value as `computed`.
        package static var brownPowell: KFactorSource { .computed }
        case typed
    }

    /// Item 6: quantified, fitted only (its lines are modelled but it gets no at%), or off.
    public enum ElementRole: String, CaseIterable, Codable, Sendable {
        case quantify
        case fitOnly
        case off
    }

    public struct ElementState: Codable, Equatable, Identifiable, Sendable {
        /// The element symbol, e.g. "Mg".
        public var symbol: String
        public var role: ElementRole
        /// Picked by the user; the proposer never drops a manual pick (ADR 054).
        package var isManual: Bool

        public var id: String { symbol }

        public nonisolated init(symbol: String, role: ElementRole, isManual: Bool) {
            self.symbol = symbol
            self.role = role
            self.isManual = isManual
        }
    }

    /// A typed k with its own uncertainty, relative to the method's reference element.
    public struct TypedK: Codable, Equatable, Sendable {
        public var element: String
        public var k: Double
        /// Relative 1-sigma (0.20 = 20 %); nil takes `QuantificationMethod.sigmaK`.
        public var relativeSigma: Double?

        public nonisolated init(element: String, k: Double, relativeSigma: Double? = nil) {
            self.element = element
            self.k = k
            self.relativeSigma = relativeSigma
        }
    }

    /// Item 9: typed thickness ± sigma, nanometres.
    public struct Thickness: Codable, Equatable, Sendable {
        public var nanometres: Double
        public var sigmaNanometres: Double

        public nonisolated init(nanometres: Double, sigmaNanometres: Double) {
            self.nanometres = nanometres
            self.sigmaNanometres = sigmaNanometres
        }
    }

    package var version: Int = QuantificationMethod.currentVersion
    public var estimator: Estimator = .leastSquares
    public var background: Background = .empiricalWithAlEdge
    public var elements: [ElementState] = []
    public var kFactorSource: KFactorSource = .computed
    /// Where the k-factors came from, in words (a computed set's `sourceDescription`, a typed set's
    /// citation). Required non-empty for `.typed` (`isComplete`); for `.computed` it is filled when the
    /// quantification runs.
    public var kSource: String = ""
    /// ISO date the factors were typed or computed.
    public var kDate: String = ""
    /// The element whose k is fixed at 1 (Velox style); nil = no reference.
    public var kReference: String?
    /// Typed factors (empty for `.computed`).
    public var typedK: [TypedK] = []
    /// Default relative sigma_k per factor (Velox's rule, WP3 flag 5).
    public var sigmaK: Double = 0.20
    /// ADR 053 item 5: four-detector weighted transmission (solid-angle-weighted mean), badged; on by
    /// default, refused by the quantification (not here) when geometry or tilt is unknown.
    public var absorptionCorrection = true
    /// Unset until the user types one: no thickness is assumed.
    public var thickness: Thickness?
    /// v5.0 R3 (and WP3c for `fitToKeV`). The four fields below are Optional ON PURPOSE: a nil is omitted from the canonical JSON, so every
    /// method recorded before they existed keeps its bytes and its hash.
    /// Beam energy typed by the user, keV, for a file that does not state it (GMS EDS objects); nil takes the file's.
    public var beamEnergyKeV: Double?
    /// Expert: the order of the whole-range polynomial background (`.wholeRangePolynomial6`); nil is 6, eXSpy's.
    public var polynomialOrder: Int?
    /// Expert: keep the file's energy axis instead of refining offset, gain and width on the pooled spectrum (ADR 054
    /// item 4); nil is "refine".
    public var lockEnergyAxis: Bool?
    /// Expert (WP3c): the upper end of the fitted range, keV; nil is the default, min(axis end, beam energy, 20 keV)
    /// (`FitSettings.defaultFitTo`). A typed value past the axis end or the beam energy is clamped to them, and the footer says so.
    public var fitToKeV: Double?

    public nonisolated init() {}

    // MARK: - Byte-stable form

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    /// Sorted-key JSON. Encoding a decoded method returns the same string.
    public var canonicalJSON: String {
        // try! is safe: every field is a Codable string, number, bool or optional of them.
        String(decoding: try! Self.encoder().encode(self), as: UTF8.self)
    }

    /// SHA-256 of `canonicalJSON`, lowercase hex.
    public var hash: String {
        SHA256.hash(data: Data(canonicalJSON.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Nil for malformed JSON, a `version` below 1, or a `version` newer than this build knows (a method this build cannot
    /// read must not be read as a different one).
    public static func decode(_ json: String) -> QuantificationMethod? {
        guard let m = try? JSONDecoder().decode(QuantificationMethod.self, from: Data(json.utf8)),
              m.version >= 1, m.version <= currentVersion else { return nil }
        return m
    }

    // MARK: - Computed k

    /// The identity of the tables a computed k reads (NIST EPQ commit the Bote-Salvat transcription follows,
    /// Krause 1979, FFAST): a property of the build, not of the day. A computed choice records THIS as its
    /// `kDate`, so two identical choices hash identically wherever and whenever they were made.
    package static let computedKTableIdentity = "EPQ 249dd3f8 + Krause 1979 + FFAST"

    /// Selects the computed k with lane K's `sourceDescription` (`BrownPowellK.sourceDescription`) as its source.
    package mutating func useComputedK(sourceDescription: String) {
        kFactorSource = .computed
        kSource = sourceDescription
        kDate = Self.computedKTableIdentity
        typedK = []
        kReference = nil
    }

    // MARK: - What a run needs

    /// Whether the k choice is complete enough to run: a typed set needs a source, a date and a
    /// positive k for every element it quantifies; a computed set needs nothing typed.
    package var isComplete: Bool {
        guard kFactorSource == .typed else { return true }
        let quantified = elements.filter { $0.role == .quantify }.map(\.symbol)
        return !kSource.trimmingCharacters(in: .whitespaces).isEmpty && !kDate.isEmpty
            && !quantified.isEmpty
            && quantified.allSatisfy { s in typedK.contains { $0.element == s && $0.k > 0 && $0.k.isFinite } }
    }

    /// The typed factors as lane K's set, relative to `kReference`; nil for `.computed`, an
    /// incomplete set, or a non-positive value.
    package func typedKFactorSet() -> KFactorSet? {
        guard kFactorSource == .typed, isComplete, !typedK.isEmpty else { return nil }
        return KFactorSet(kind: .typed, elements: typedK.map(\.element), values: typedK.map(\.k),
                          source: kSource, date: kDate,
                          relativeSigma: typedK.map { $0.relativeSigma ?? ($0.element == kReference ? 0 : sigmaK) },
                          reference: kReference)
    }
}
