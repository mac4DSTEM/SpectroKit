//
//  EELSParallel.swift
//  Role: the pixel loop of task 16 (design section 11): pixels are independent, so the loop runs in chunks on all cores, a wave at a time,
//        asking `cancelled` and reporting progress between waves. Each chunk writes its own slots; results are assembled in pixel order,
//        so an answer never depends on the schedule. CPU float64 only (no Metal: the work per pixel is smaller than a copy).
//

import Foundation
import SpectroCore

package nonisolated enum EELSParallel {
    /// Runs `body(p)` for every pixel `0..<count`, in chunks of `chunk` pixels, several chunks at a time. Throws `SpectroCancelled` between
    /// waves when `cancelled()` is true. `body` must write only the slot of its own pixel.
    package static func forEachPixel(
        count: Int, chunk: Int = 256,
        cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?,
        body: @Sendable (Int) -> Void
    ) throws {
        guard count > 0 else { progress?(1); return }
        let chunks = (count + chunk - 1) / chunk
        let wave = max(ProcessInfo.processInfo.activeProcessorCount, 1) * 2
        var next = 0
        while next < chunks {
            try SpectroCancellation.check(cancelled)
            progress?(Double(next * chunk) / Double(count))
            let end = min(next + wave, chunks)
            let first = next
            DispatchQueue.concurrentPerform(iterations: end - first) { i in
                let ci = first + i
                for p in (ci * chunk)..<min(count, (ci + 1) * chunk) { body(p) }
            }
            next = end
        }
        progress?(1)
    }
}

/// A buffer several chunks write to at disjoint indices (the pixel loop's output): raw storage, so no array uniqueness check races between
/// threads. Read `values` after the loop.
package final class EELSSlots<T: Sendable>: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<T>
    package let count: Int

    package init(count: Int, initial: T) {
        self.count = count
        storage = UnsafeMutablePointer<T>.allocate(capacity: max(count, 1))
        storage.initialize(repeating: initial, count: count)
    }

    deinit {
        storage.deinitialize(count: count)
        storage.deallocate()
    }

    /// Writes slot `i` (callers write only their own pixel's slots).
    package func set(_ i: Int, _ value: T) { storage[i] = value }
    package subscript(i: Int) -> T { storage[i] }
    package var values: [T] { Array(UnsafeBufferPointer(start: storage, count: count)) }
}
