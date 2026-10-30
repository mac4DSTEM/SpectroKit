//
//  SpectroCancellation.swift
//  The one cancellation contract of the long spectroscopy calls: a `cancelled` closure with the
//  default `SpectroCancellation.task`, an optional `progress` closure (fraction 0…1), and `SpectroCancelled` thrown when the
//  closure answers true — nothing partial is kept.
//
//  Since 0.4.0 the error is FormatoKit's (`FormatoCancelled`), which the readers moved there with: `SpectroCancelled` is a
//  typealias, so one error type crosses both kits and a consumer's `catch is SpectroCancelled` still catches a reader's
//  cancellation (FormatoKit docs/consumers-0.0.1.md, item 3). `SpectroCancellation` stays SpectroCore's own enum, forwarding to
//  `FormatoCancellation`, so `SpectroCancellation.task` needs no `import FormatoCore` where `MemberImportVisibility` is on.
//

import FormatoCore

/// Thrown by a long call whose `cancelled` closure returned true. Nothing it was building is returned or kept.
public typealias SpectroCancelled = FormatoCancelled

public nonisolated enum SpectroCancellation {
    /// The default `cancelled` closure: Swift task cancellation, so a caller inside a Task needs to pass nothing.
    public static let task: @Sendable () -> Bool = FormatoCancellation.task

    /// Throws `SpectroCancelled` when `cancelled()` is true. Call at block or step boundaries, never per value.
    package static func check(_ cancelled: @Sendable () -> Bool) throws {
        try FormatoCancellation.check(cancelled)
    }
}
