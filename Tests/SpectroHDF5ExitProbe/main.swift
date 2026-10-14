//
//  SpectroHDF5ExitProbe — main.swift
//  Role: The child process of `HDF5ExitBarrierTests` (SpectroKitTests). `exit()` runs the atexit handlers, which a
//        test cannot watch from inside its own process, so each scenario of the quit barrier
//        (`HDF5Serial.installExitBarrier`, macTEM ADR 021) runs here and the test reads what the process wrote and
//        how it ended.
//
//  Usage: SpectroHDF5ExitProbe <mode> [bound-seconds]
//    free           nobody holds the HDF5 lock; the main thread calls exit(0).
//    held-by-caller the main thread holds the lock (recursive) and calls exit(0): straight through.
//    held-briefly   a second thread holds the lock for ~0.4 s, writes "released", lets go; the main thread calls
//                   exit(0).
//    stuck          a second thread takes the lock and never lets go; the main thread calls exit(0).
//    print-bound    writes HDF5Serial.exitBarrierBound (the default, as setExitBarrierBound is not called) and
//                   exits 0.
//
//  Markers go through write(2) only: `_exit` (the barrier's way out) does not flush stdio, so a `print` would be lost
//  exactly when the test needs it. stdout: "calling-exit <ns>", "released", "teardown-ran". stderr: the barrier's
//  own line.
//
//  "calling-exit <ns>" carries the system-wide monotonic time (`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)`, the clock
//  the test reads too) taken just before `exit`. The test measures the barrier's wait from it, not from the moment
//  its own pipe handler happened to run: a late handler under CPU load would shorten the measured wait and fail the
//  lower bound.
//
//  "teardown-ran" stands in for HDF5's `H5_term_library`. HDF5 registers that handler inside the first `H5open`, and
//  the loaders install the barrier right after it, so atexit's last-in-first-out order runs the barrier first and
//  HDF5's teardown after it. Registered here BEFORE the barrier, the stand-in runs after it, and `_exit(70)` skips it.
//

import Foundation
import SpectroCore

/// One unbuffered write; nothing else is allowed to carry a marker.
func mark(_ fd: Int32, _ text: StaticString) {
    _ = write(fd, text.utf8Start, text.utf8CodeUnitCount)
}

/// Writes `text` to stdout with write(2), for the markers that are not literals.
func markDynamic(_ text: String) {
    let bytes = Array(text.utf8)
    _ = bytes.withUnsafeBufferPointer { write(STDOUT_FILENO, $0.baseAddress, $0.count) }
}

/// "calling-exit <ns>\n": the stamp is read first, so it is never later than the `exit` call that follows.
func markCallingExit() {
    let stamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    markDynamic("calling-exit \(stamp)\n")
}

func usage() -> Never {
    mark(STDERR_FILENO, "usage: SpectroHDF5ExitProbe free|held-by-caller|held-briefly|stuck|print-bound [seconds]\n")
    exit(64)
}

func run(mode: String, bound: Double?) -> Never {
    // Before the barrier, so it runs after it (last in, first out), as HDF5's teardown does.
    guard atexit({ mark(STDOUT_FILENO, "teardown-ran\n") }) == 0 else { exit(71) }
    if mode != "print-bound", let bound { HDF5Serial.setExitBarrierBound(bound) }
    HDF5Serial.installExitBarrier()

    switch mode {
    case "free":
        markCallingExit()
        exit(0)

    case "held-by-caller":
        HDF5Serial.acquire()
        markCallingExit()
        exit(0)

    case "held-briefly":
        let holding = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            HDF5Serial.acquire()
            holding.signal()
            usleep(400_000)
            mark(STDOUT_FILENO, "released\n")       // before release(): the barrier cannot pass until it is written
            HDF5Serial.release()
        }
        holding.wait()
        markCallingExit()
        exit(0)

    case "stuck":
        let holding = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            HDF5Serial.acquire()
            holding.signal()
            DispatchSemaphore(value: 0).wait()      // never signalled: a thread stuck in HDF5 holds the lock for good
        }
        holding.wait()
        markCallingExit()
        exit(0)

    case "print-bound":
        markDynamic("\(HDF5Serial.exitBarrierBound)\n")
        exit(0)

    default:
        usage()
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { usage() }
let boundSeconds: Double? = arguments.count >= 3 ? Double(arguments[2]) : nil
if arguments.count >= 3, boundSeconds == nil { usage() }
run(mode: arguments[1], bound: boundSeconds)
