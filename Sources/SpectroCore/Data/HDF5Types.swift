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
}
