//
//  HDF5ExitBarrierTests.swift
//  Role: Gate for the bounded quit barrier (SpectroKit 0.2.0; macTEM ADR 021). `exit()` runs the atexit handlers,
//        which a test cannot watch from inside its own process, so each scenario runs in `SpectroHDF5ExitProbe` (a
//        child process; Tests/SpectroHDF5ExitProbe/main.swift) and the test reads what it wrote and how it ended.
//
//  The probe registers a stand-in for HDF5's `H5_term_library` BEFORE it installs the barrier, as HDF5 registers its
//  own inside the first `H5open`, before the loaders install the barrier. atexit is last in, first out: the barrier
//  runs first, the stand-in ("teardown-ran") after it, and `_exit(70)` must skip it.
//
//  Every probe runs under a hard deadline: a barrier that waits for ever (the 0.1.0 shape) goes red with "did not exit
//  within N s" after the child is killed, and never hangs the suite.
//
//  The one timing assertion (a stuck holder is waited for the bound, not less) measures from the child's own clock,
//  not from when the test's pipe handler ran. The probe writes `calling-exit <ns>` (CLOCK_UPTIME_RAW, system-wide)
//  just before `exit`; the test reads the same clock in the termination handler. A handler that runs late can only
//  make the measured wait longer than the real one, so the lower bound cannot fail on scheduler latency; the upper
//  bound has 5 s of room for it. Checked: a `usleep(300_000)` at the top of the pipe handlers fails a measurement that
//  starts when the handler sees the marker (0.199 s < 0.45 s) and leaves this one green.
//
//  Mutations (each applied to HDF5Types.swift in a scratch clone, this suite run, the file restored; red tests named):
//    handler `lock.lock(); return` (0.1.0: unbounded)       -> stuck: "did not exit within 10.5 s", child killed
//    `_exit(70)` -> `return`                                -> stuck: status 0, teardown ran
//    `_exit(70)` -> `_exit(0)`                              -> stuck: status 0
//    `Date(timeIntervalSinceNow: exitBarrierBound)` -> `Date()`
//                                                           -> held-briefly: status 70, no "released";
//                                                              stuck: left after 0.0008 s, not 0.45 s or more
//    handler body just `return` (no barrier)                -> held-briefly: no "released", teardown first;
//                                                              stuck: status 0, left after 0.002 s
//    `installExitBarrier` registers nothing (`atexit` -> `true`)
//                                                           -> same two tests as the line above
//    wait of `exitBarrierBound + 8`                         -> stuck: 8.5 s, not under 5.5 s
//    `Atomic<Int>(10_000)` -> `Atomic<Int>(5_000)`          -> default bound: "5.0", not "10.0"
//    `if lock.lock(before:)` -> `if !lock.lock(before:)`    -> all five: free, held-by-caller, held-briefly and
//                                                              default bound exit with 70 and the barrier line;
//                                                              stuck leaves with status 0, teardown ran
//    `NSRecursiveLock()` -> `NSLock()`                      -> held-by-caller: status 70 after waiting the 2 s bound
//    `write(STDERR_FILENO` -> `write(STDOUT_FILENO`         -> stuck: stderr empty, the line in stdout
//    `setExitBarrierBound` stores `Int(seconds)`            -> held-briefly: status 70; stuck: left after 0.0007 s
//  The free-lock test is red only under the inverted condition; each of the other four under two or more of these.
//

import XCTest
import Foundation

final class HDF5ExitBarrierTests: XCTestCase {
    /// The one stderr line the barrier writes before `_exit(70)` (HDF5Types.swift, `exitBarrier()`), newline included.
    private static let barrierLine =
        "SpectroKit: HDF5Serial's quit barrier passed its bound with the HDF5 lock still held; "
        + "_exit(70) without HDF5's shutdown\n"
    private static let teardown = "teardown-ran\n"
    private static let calling = "calling-exit\n"

    // MARK: The child process

    /// What the pipes' handlers (their own threads) and the termination handler hand to the test thread.
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data(), err = Data()
        private var endedAt: UInt64?

        func appendStdout(_ data: Data) { lock.lock(); out.append(data); lock.unlock() }
        func appendStderr(_ data: Data) { lock.lock(); err.append(data); lock.unlock() }
        /// Read in the termination handler, which runs after the child is gone: never earlier than the child's end.
        func markEnded() { lock.lock(); endedAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW); lock.unlock() }
        func snapshot() -> (out: String, err: String, endedAt: UInt64?) {
            lock.lock(); defer { lock.unlock() }
            return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self), endedAt)
        }
    }

    private struct Outcome {
        var status: Int32
        var reason: Process.TerminationReason
        /// Exactly what the probe wrote to stdout, `calling-exit <ns>` stamp included.
        var stdout: String
        var stderr: String
        /// `stdout` with the stamp line reduced to `calling-exit`, so the markers compare as plain text.
        var markers: String
        /// The probe's clock (CLOCK_UPTIME_RAW, ns) just before it called `exit`; nil if the stamp is missing.
        var calledExitAt: UInt64?
        /// The same clock in the test, read after the child was gone.
        var endedAt: UInt64?
        var timedOut: Bool

        /// Seconds from the child's `exit` call to the test seeing the child gone: at least the barrier's real wait.
        var secondsInExit: Double? {
            guard let calledExitAt, let endedAt else { return nil }
            return Double(Int64(bitPattern: endedAt &- calledExitAt)) / 1e9
        }
    }

    /// Splits the `calling-exit <ns>` line off the probe's stdout: the markers as plain text, and the stamp.
    private static func splitStamp(_ stdout: String) -> (markers: String, calledExitAt: UInt64?) {
        var stamp: UInt64?
        let prefix = "calling-exit "
        let lines = stdout.components(separatedBy: "\n").map { line -> String in
            guard line.hasPrefix(prefix), let ns = UInt64(line.dropFirst(prefix.count)) else { return line }
            stamp = ns
            return "calling-exit"
        }
        return (lines.joined(separator: "\n"), stamp)
    }

    /// `swift test` puts the probe (an executable the test target depends on) next to the .xctest bundle.
    private func probeURL() throws -> URL {
        let url = Bundle(for: HDF5ExitBarrierTests.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("SpectroHDF5ExitProbe")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            let message = "SpectroHDF5ExitProbe is not next to the test bundle (looked at \(url.path)). "
                + "SpectroKitTests depends on that executable target (Package.swift): run through "
                + "tools/test.sh / `swift test`, which builds it."
            XCTFail(message)
            throw NSError(domain: "HDF5ExitBarrierTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return url
    }

    /// Runs the probe in `mode`, reading both pipes to EOF concurrently (no pipe-buffer deadlock). If the child is
    /// still there after `deadline` seconds it is terminated (then killed), the test fails with "did not exit
    /// within", and `timedOut` is set so the caller stops asserting on a half-run.
    private func runProbe(_ mode: String, bound: Double? = nil, deadline: TimeInterval) throws -> Outcome {
        let process = Process()
        process.executableURL = try probeURL()
        process.arguments = [mode] + (bound.map { [String($0)] } ?? [])
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let capture = Capture()
        let drained = DispatchGroup()
        for (pipe, isStdout) in [(stdout, true), (stderr, false)] {
            drained.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; drained.leave(); return }
                if isStdout { capture.appendStdout(data) } else { capture.appendStderr(data) }
            }
        }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in capture.markEnded(); exited.signal() }
        try process.run()

        var timedOut = false
        if exited.wait(timeout: .now() + deadline) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 5)
            }
            XCTFail("SpectroHDF5ExitProbe \(mode) did not exit within \(deadline) s (terminated by the test)")
        }
        if drained.wait(timeout: .now() + 5) == .timedOut {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            XCTFail("SpectroHDF5ExitProbe \(mode): its pipes did not reach EOF")
        }
        let seen = capture.snapshot()
        let (markers, calledExitAt) = Self.splitStamp(seen.out)
        return Outcome(
            status: process.terminationStatus, reason: process.terminationReason, stdout: seen.out, stderr: seen.err,
            markers: markers, calledExitAt: calledExitAt, endedAt: seen.endedAt, timedOut: timedOut)
    }

    /// Index of `needle` in `haystack`, as an offset, or nil.
    private func offset(of needle: String, in haystack: String) -> Int? {
        haystack.range(of: needle).map { haystack.distance(from: haystack.startIndex, to: $0.lowerBound) }
    }

    private func assertNoBarrierLine(
        _ outcome: Outcome, _ mode: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(
            outcome.stderr.contains("quit barrier"),
            "\(mode): the barrier fired when it should not have: \(outcome.stderr)", file: file, line: line)
        XCTAssertEqual(
            outcome.stderr, "", "\(mode): nothing is written to stderr on a clean exit", file: file, line: line)
    }

    // MARK: The five scenarios

    /// Nobody holds the lock: the barrier takes it at once, and `exit(0)` goes on to the handlers registered before it.
    func testExitWithTheLockFreeEndsCleanlyAndHDF5TeardownRuns() throws {
        let run = try runProbe("free", deadline: 20)
        guard !run.timedOut else { return }
        XCTAssertEqual(run.reason, .exit, "ended by exit(), not a signal")
        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.markers, Self.calling + Self.teardown, "the teardown handler ran after exit() was called")
        assertNoBarrierLine(run, "free")
    }

    /// The thread that calls `exit` already holds the lock: the lock is recursive, so the barrier goes straight
    /// through. The bound is 2 s here (the default 10 s would make a failure slow): a non-recursive lock waits it out
    /// and leaves with status 70.
    func testExitOnTheThreadThatHoldsTheLockGoesStraightThrough() throws {
        let run = try runProbe("held-by-caller", bound: 2, deadline: 20)
        guard !run.timedOut else { return }
        XCTAssertEqual(run.reason, .exit)
        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.markers, Self.calling + Self.teardown)
        assertNoBarrierLine(run, "held-by-caller")
    }

    /// Another thread is inside a locked operation (0.4 s) when `exit` is called: the barrier waits for it, and only
    /// then does the teardown run. This is what the barrier is for; "released" must come first in the child's stdout.
    func testExitWaitsForTheOperationInFlightBeforeTheTeardown() throws {
        let run = try runProbe("held-briefly", bound: 5, deadline: 20)
        guard !run.timedOut else { return }
        XCTAssertEqual(run.reason, .exit)
        XCTAssertEqual(run.status, 0, "the lock came back inside the bound: a normal exit, not _exit(70)")
        let released = offset(of: "released\n", in: run.markers)
        let teardown = offset(of: Self.teardown, in: run.markers)
        XCTAssertNotNil(released, "the holder finished and wrote \"released\": \(run.stdout.debugDescription)")
        XCTAssertNotNil(teardown, "the teardown ran: \(run.stdout.debugDescription)")
        if let released, let teardown {
            XCTAssertLessThan(
                released, teardown, "the barrier waited for the operation in flight: \(run.stdout.debugDescription)")
        }
        assertNoBarrierLine(run, "held-briefly")
    }

    /// A thread that never lets go: the barrier gives up at the bound, writes its one line and `_exit(70)`s, so the
    /// handlers registered before it (HDF5's shutdown) do not run. The wait is the bound, neither shorter nor
    /// open-ended.
    func testExitWithAStuckHolderLeavesAtTheBoundWithStatus70AndSkipsTheTeardown() throws {
        let bound = 0.5
        let run = try runProbe("stuck", bound: bound, deadline: bound + 10)
        guard !run.timedOut else { return }
        XCTAssertEqual(run.reason, .exit, "_exit(70) is an exit, not a signal")
        XCTAssertEqual(run.status, 70, "EX_SOFTWARE")
        XCTAssertEqual(run.stderr, Self.barrierLine, "exactly the barrier's one line")
        XCTAssertFalse(
            run.stdout.contains("teardown-ran"),
            "_exit skipped the handlers registered before the barrier (HDF5's shutdown): "
                + "\(run.stdout.debugDescription)")
        XCTAssertEqual(run.markers, Self.calling)
        guard let seconds = run.secondsInExit else {
            return XCTFail("the child's calling-exit stamp or its end was not seen: \(run.stdout.debugDescription)")
        }
        // 0.05 s: the barrier's Date is on the wall clock, the stamps are on the uptime clock.
        XCTAssertGreaterThanOrEqual(seconds, bound - 0.05, "the barrier waited the bound (\(bound) s) before giving up")
        XCTAssertLessThan(seconds, bound + 5, "and did not wait much longer than the bound")
    }

    /// Without `setExitBarrierBound` the bound a host gets is 10 s.
    func testTheDefaultBoundIsTenSeconds() throws {
        let run = try runProbe("print-bound", deadline: 20)
        guard !run.timedOut else { return }
        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.stdout, "10.0\n" + Self.teardown, "the bound, then the ordinary exit")
        assertNoBarrierLine(run, "print-bound")
    }
}
