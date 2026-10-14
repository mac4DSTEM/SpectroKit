//
//  Report.swift
//  Role: the check ledger of consumer-check: one printed line per check, a count of failures, no test framework (a
//        consumer package, not a test target). `finish()` is the process exit status.
//

import Foundation

struct Report {
    private(set) var passed = 0
    private(set) var failed = 0

    mutating func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if ok { passed += 1; print("PASS  \(name)") } else { failed += 1; print("FAIL  \(name)  [\(detail())]") }
    }
    mutating func equal<T: Equatable>(_ name: String, _ got: T, _ want: T) {
        check(name, got == want, "got \(got), want \(want)")
    }
    mutating func near(_ name: String, _ got: Double?, _ want: Double, _ tolerance: Double) {
        guard let got else { check(name, false, "got nil, want \(want)"); return }
        check(name, abs(got - want) <= tolerance, "got \(got), want \(want) +- \(tolerance)")
    }
    /// Runs `body`; a thrown error is one failed check, not a crash, so every later check still runs.
    mutating func section(_ name: String, _ body: (inout Report) throws -> Void) {
        var copy = self
        do { try body(&copy) } catch { copy.check("\(name): ran to the end", false, "threw \(error)") }
        self = copy
    }
    func finish() -> Int32 {
        print("consumer-check summary: \(passed + failed) checks, \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}

struct CheckError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// A JSON object read from a fixture's `.truth.json`.
func loadJSON(_ url: URL) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
        throw CheckError("\(url.lastPathComponent) is not a JSON object")
    }
    return object
}

extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) throws -> [String: Any] {
        guard let value = self[key] as? [String: Any] else { throw CheckError("truth has no object \(key)") }
        return value
    }
    func number(_ key: String) throws -> Double {
        guard let value = self[key] as? Double else { throw CheckError("truth has no number \(key)") }
        return value
    }
    func string(_ key: String) throws -> String {
        guard let value = self[key] as? String else { throw CheckError("truth has no string \(key)") }
        return value
    }
}
