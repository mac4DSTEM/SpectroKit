//
//  SpectroCancellation.swift
//  The one cancellation contract of the long spectroscopy calls (ADR 064, amendment (2) §2): a `cancelled` closure with the
//  default `SpectroCancellation.task`, an optional `progress` closure (fraction 0…1), and `SpectroCancelled` thrown when the
//  closure answers true — nothing partial is kept.
//

import Foundation

/// Thrown by a long call whose `cancelled` closure returned true. Nothing it was building is returned or kept.
public nonisolated struct SpectroCancelled: Error, Equatable {
    public init() {}
}

public nonisolated enum SpectroCancellation {
    /// The default `cancelled` closure: Swift task cancellation, so a caller inside a Task needs to pass nothing.
    public static let task: @Sendable () -> Bool = { Task.isCancelled }

    /// Throws `SpectroCancelled` when `cancelled()` is true. Call at block or step boundaries, never per value.
    package static func check(_ cancelled: @Sendable () -> Bool) throws {
        if cancelled() { throw SpectroCancelled() }
    }
}
