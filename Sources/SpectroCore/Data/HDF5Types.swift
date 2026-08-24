/// HDF5 C ABI scalar aliases shared by the dynamic reader and writer.
typealias hid_t = Int64
typealias herr_t = Int32
typealias hsize_t = UInt64

/// The session sidecar's identity, shared by the writer that stamps it and
/// the reader that recognises it. This file is the one `Core/Data` source
/// every standalone harness that compiles either side already includes, so
/// hosting the constants here costs no build-list edit anywhere — the
/// alternative (duplicated literals with "change one, change both" comments)
/// is exactly how a format constant drifts and recognition silently stops
/// firing. // v2 S4
// `nonisolated`: pure constants read from the reader actor and nonisolated
// writer statics; MainActor default isolation would wall them off (the S3
// rider's pattern for pure data types).
nonisolated enum SessionSidecarFormat {
    /// Root-group attribute stamped on every file the sidecar writer
    /// produces. Its *presence* is the identity marker; its value is the
    /// schema version.
    static let schemaAttribute = "mac4dstem_session_schema"
    /// The writer's root group name.
    static let rootGroupName = "braggvectors_root"
    /// A sidecar is named `<stem>.mac4dstem.h5` beside its source, where the
    /// stem is the source name with *any* extension stripped — the source is
    /// not necessarily an `.h5` file.
    static let nameSuffix = ".mac4dstem.h5"

    // MARK: - Schema versioning (v2 S5)

    /// The schema this build writes AND the newest it understands. History,
    /// so the numbers keep meaning: "5" was v1's format — and it stayed "5"
    /// across the 2026-08-18 load-specification addition, which is exactly
    /// the defect that made this constant necessary (a stamp that never moves
    /// identifies nothing). "6" is v2's: load specification honoured on
    /// restore, plus the replay record.
    static let currentSchema = 6

    /// Root attribute naming the OLDEST schema a reader may implement and
    /// still interpret this file **without misreading it** — not the newest
    /// feature present. Additive, safe-to-ignore content (the replay record)
    /// does not raise it; content that is dangerous to ignore (a reduced load
    /// specification: ignoring it restores scan-indexed results at wrong
    /// positions, the §5 evidence) does. Readers refuse, with both numbers
    /// named, when this exceeds `currentSchema` — never partially restore.
    /// The unfixable half, stated: v1.0.0 checks nothing, so this marker
    /// protects the NEXT format change, not the last one.
    static let minimumReaderAttribute = "mac4dstem_min_reader_schema"

    /// Root attribute carrying the serialized `SessionReplayRecord` (JSON).
    static let replayRecordAttribute = "mac4dstem_replay_record"
    // (The min-reader VALUE for a given specification is computed by
    //  `BraggVectorEMDWriter.minimumReaderSchema(for:)` — this file stays
    //  constants-only so harnesses can compile it without `LoadSpecification`.)
}
