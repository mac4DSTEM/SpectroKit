import Foundation
import Testing

struct CIScriptTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func run(_ shell: String, script: String, in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-e", "-c", script]
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func testCIGatePropagatesSwiftTestFailureThroughTee() throws {
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
        let gate = try #require(workflow.components(separatedBy: "- name: Gate (tools/test.sh, release)").dropFirst().first)
            .components(separatedBy: "- name:")[0]
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("tools"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try "#!/bin/sh\nexit 23\n".write(to: temp.appendingPathComponent("tools/test.sh"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.appendingPathComponent("tools/test.sh").path)
        // GitHub's implicit bash shell uses -e without pipefail. An explicit bash shell adds pipefail.
        let explicitBash = gate.contains("shell: bash")
        let command = try #require(gate.components(separatedBy: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("run: ") })
            .trimmingCharacters(in: .whitespaces).dropFirst("run: ".count)
        let script = (explicitBash ? "set -o pipefail\n" : "") + command
        #expect(try run("/bin/bash", script: script, in: temp) == 23)
    }

    @Test func testConsumerTargetInventorySurvivesAbsentBuildDirectories() throws {
        let source = try String(contentsOf: root.appendingPathComponent("tools/consumer-check/run.sh"), encoding: .utf8)
        let start = try #require(source.range(of: "built=$("))
        let end = try #require(source.range(of: "print \"consumer-check: targets built:", range: start.upperBound..<source.endIndex))
        let inventory = String(source[start.lowerBound..<end.lowerBound])
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        #expect(try run("/bin/zsh", script: "set -uo pipefail\n" + inventory, in: temp) == 0)
        // Also exercise one existing backend directory; missing SwiftPM directories must not discard its inventory.
        try FileManager.default.createDirectory(at: temp.appendingPathComponent(".build/out/Intermediates.noindex/A/B/SpectroCore.build"), withIntermediateDirectories: true)
        #expect(try run("/bin/zsh", script: "set -uo pipefail\n" + inventory + "[[ $built == *SpectroCore* ]]", in: temp) == 0)
    }
}
