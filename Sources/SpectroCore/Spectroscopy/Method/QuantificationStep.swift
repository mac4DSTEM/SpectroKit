//
//  QuantificationStep.swift
//  Role: What the replay step "quantification" records (ADR 047 R1, ADR 054 item 8: the Quantify verb
//        writes one step): the method, the registration the pooling used, and which region was pooled.
//        Flat string-to-string parameters, the convention of every step (`SessionLineage.Node`).
//
//  The step is lineage-only (`SessionLineage.lineageOnlyKinds`): an older build's linear record never
//  carries it. Its input edges come from `SessionLineage.inputPolicy`: `phases` from the active phase
//  map and `objects` from the active precipitate objects, whichever exist. A rewind to the step puts
//  `QuantificationStep(parameters:)` back into the room (`SpectroscopySession.restoreQuantification`).
//
//  The hash is recorded beside the JSON so a reader can see two steps used the same method without
//  decoding either, and a restore refuses a step whose JSON no longer matches its hash.
//

import Foundation

package nonisolated struct QuantificationStep: Equatable, Sendable {
    package static let kind = "quantification"

    package var method: QuantificationMethod
    /// The registration the pooling went through; nil for a whole-map or spectrum-grid-drawn region.
    package var registration: RegistrationRecordM2?
    /// `wholeMap`, `drawn`, `phase`, `object` (as `PooledSpectrum.kind`) and the region's name.
    package var regionKind: String
    package var regionName: String

    package nonisolated init(method: QuantificationMethod, registration: RegistrationRecordM2? = nil,
                             regionKind: String = "wholeMap", regionName: String = "Whole map") {
        self.method = method
        self.registration = registration
        self.regionKind = regionKind
        self.regionName = regionName
    }

    /// The flat parameters of the step. Deterministic: the same step gives the same dictionary.
    package var parameters: [String: String] {
        var p: [String: String] = [
            "method": method.canonicalJSON,
            "method_hash": method.hash,
            "region_kind": regionKind,
            "region_name": regionName,
        ]
        if let registration {
            p["registration"] = registration.canonicalJSON
            p["registration_source"] = registration.source.rawValue
        }
        return p
    }

    /// Nil when the parameters are not a quantification step this build can read: no method, a method
    /// that does not decode, or JSON whose hash differs from the recorded one.
    package init?(parameters p: [String: String]) {
        guard let json = p["method"], let m = QuantificationMethod.decode(json),
              p["method_hash"].map({ $0 == m.hash }) ?? false else { return nil }
        var r: RegistrationRecordM2?
        if let rj = p["registration"] {
            guard let decoded = RegistrationRecordM2.decode(rj) else { return nil }
            r = decoded
        }
        self.init(method: m, registration: r, regionKind: p["region_kind"] ?? "wholeMap",
                  regionName: p["region_name"] ?? "Whole map")
    }
}
