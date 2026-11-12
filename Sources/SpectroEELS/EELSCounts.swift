//
//  EELSCounts.swift
//  Role: the counts of an EELS spectrum image, held at the precision they were given. A float32 GMS or Velox cube stays
//        four bytes a count, as exSpy keeps the file's dtype (HyperSpy `Signal1D.data`), not eight: the 1.46 GB 145_STEM spectrum
//        image cost 2.9 GB as Doubles, and Align held three such cubes (macTEM#571, SpectroKit#94).
//
//  Every value read is a Double (a Float widens exactly), so a method that reads the counts gives the same numbers from a float32
//  cube as from its widened Doubles. What writes counts (Align's shift, in place) writes them back at the cube's own precision,
//  as NumPy writes into a float32 array.
//

import Accelerate
import Foundation

/// Row-major counts, `[(y * nx + x) * channels + c]`, as `[Float]` or `[Double]`.
public nonisolated struct EELSCounts: Sendable, Equatable, RandomAccessCollection {
    /// What one count is stored as.
    public enum Precision: Sendable, Equatable {
        case single, double

        /// Bytes per count: 4 or 8.
        public var bytes: Int { self == .single ? 4 : 8 }
    }

    private enum Storage: Sendable, Equatable {
        case single([Float])
        case double([Double])
    }

    private var storage: Storage

    public init(_ values: [Double]) { storage = .double(values) }
    public init(_ values: [Float]) { storage = .single(values) }

    public var precision: Precision {
        if case .single = storage { return .single }
        return .double
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int {
        switch storage {
        case .single(let a): a.count
        case .double(let a): a.count
        }
    }

    /// Count `i`, widened to Double.
    public subscript(i: Int) -> Double {
        switch storage {
        case .single(let a): Double(a[i])
        case .double(let a): a[i]
        }
    }

    /// Every count as a Double: the array itself when held as Doubles, else a widened full-size copy (for a one-off, never per pixel).
    public var doubles: [Double] {
        switch storage {
        case .single(let a): a.map { Double($0) }
        case .double(let a): a
        }
    }

    /// The counts as single precision, when that is how they are held.
    public var singles: [Float]? {
        if case .single(let a) = storage { return a }
        return nil
    }

    /// Calls `body` with every count as Doubles. Held as Floats, the counts are widened into a full-size buffer for the call: for a method
    /// that reads the whole cube at once; per-pixel work reads `withRow` instead.
    public func withDoubles<R>(_ body: (UnsafeBufferPointer<Double>) throws -> R) rethrows -> R {
        switch storage {
        case .double(let a): return try a.withUnsafeBufferPointer(body)
        case .single(let a): return try a.map { Double($0) }.withUnsafeBufferPointer(body)
        }
    }

    /// Calls `body` with the `count` counts from `start` as Doubles: the stored values themselves when held as Doubles, else widened into a
    /// buffer of that length (one pixel's spectrum, not the cube).
    public func withRow<R>(start: Int, count: Int, _ body: (UnsafeBufferPointer<Double>) throws -> R) rethrows -> R {
        precondition(start >= 0 && count >= 0 && start + count <= endIndex, "EELSCounts.withRow: \(start)..<\(start + count) of \(endIndex)")
        switch storage {
        case .double(let a):
            return try a.withUnsafeBufferPointer { try body(UnsafeBufferPointer(rebasing: $0[start ..< start + count])) }
        case .single(let a):
            var row = [Double](repeating: 0, count: count)
            a.withUnsafeBufferPointer { src in
                row.withUnsafeMutableBufferPointer { dst in
                    if count > 0 { vDSP_vspdp(src.baseAddress! + start, 1, dst.baseAddress!, 1, vDSP_Length(count)) }
                }
            }
            return try row.withUnsafeBufferPointer(body)
        }
    }

    /// Copies the `count` counts from `start` into `destination`, widened to Double (one pixel's spectrum into a caller's buffer).
    public func copy(start: Int, count: Int, into destination: UnsafeMutablePointer<Double>) {
        precondition(start >= 0 && count >= 0 && start + count <= endIndex, "EELSCounts.copy: \(start)..<\(start + count) of \(endIndex)")
        guard count > 0 else { return }
        switch storage {
        case .single(let a):
            a.withUnsafeBufferPointer { vDSP_vspdp($0.baseAddress! + start, 1, destination, 1, vDSP_Length(count)) }
        case .double(let a):
            a.withUnsafeBufferPointer { destination.update(from: $0.baseAddress! + start, count: count) }
        }
    }

    /// Whether every count is finite; the index of the first that is not, else nil.
    public func firstNonFinite() -> Int? {
        switch storage {
        case .single(let a): a.firstIndex(where: { !$0.isFinite })
        case .double(let a): a.firstIndex(where: { !$0.isFinite })
        }
    }

    // MARK: In place

    /// Mutable access to the stored values, without a copy when this value is the only holder of its array. Exactly one of the two buffers
    /// is non-nil: the Floats or the Doubles.
    package mutating func withUnsafeMutableStorage<R>(
        _ body: (UnsafeMutableBufferPointer<Float>?, UnsafeMutableBufferPointer<Double>?) throws -> R
    ) rethrows -> R {
        switch storage {
        case .single(var a):
            storage = .single([])          // let go of the second reference, so `a` is unique and is written in place
            defer { storage = .single(a) }
            return try a.withUnsafeMutableBufferPointer { try body($0, nil) }
        case .double(var a):
            storage = .double([])
            defer { storage = .double(a) }
            return try a.withUnsafeMutableBufferPointer { try body(nil, $0) }
        }
    }

    /// Keeps the first `count` values (the rest are dropped; the storage is not reallocated).
    package mutating func truncate(to count: Int) {
        switch storage {
        case .single(var a):
            storage = .single([])
            a.removeLast(a.count - count)
            storage = .single(a)
        case .double(var a):
            storage = .double([])
            a.removeLast(a.count - count)
            storage = .double(a)
        }
    }
}
