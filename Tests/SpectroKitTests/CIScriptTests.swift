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

    @Test func testGapAuditMeasuresBitsAndDoesNotInventMissingOperands() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        // These are arithmetic/diagnostic controls, not scientific reference outputs.
        process.arguments = ["-I", "-B", "-c", """
        import json, runpy, sys
        audit = runpy.run_path(sys.argv[1])
        gap = audit['gap']
        assert gap(1.0, float.fromhex('0x1.0000000000001p0'))['ulps'] == 1
        assert gap(-1.0, float.fromhex('-0x1.0000000000001p0'))['ulps'] == 1
        assert gap(0.0, -0.0)['ulps'] == 0
        tiny = float.fromhex('0x0.0000000000001p-1022')
        assert gap(-tiny, tiny)['ulps'] == 2
        json.dumps(gap(float('inf'), float('nan')), allow_nan=False)
        assert gap(1.5, 1.0)['relative'] == 0.5
        rows = audit['analyze']('Test testDerivative() recorded an issue at Test.swift:1:1: Expectation failed: (x.bitPattern → 4607182418800017408) == (pin.bitPattern → 4607182418800017409)')
        assert len(rows) == 1 and rows[0]['ulps'] == 1
        rows = audit['analyze']('Test testDerivative() recorded an issue at Test.swift:1:1: mismatches == 0')
        assert len(rows) == 1 and rows[0]['measurement'].startswith('unavailable')
        assert 'ulps' not in rows[0]
        """, root.appendingPathComponent("tools/ci-parity/gaps.py").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
