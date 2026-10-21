//
//  FixtureDirs.swift
//  Role: Where each test target's `Fixtures/` directory lives, for the helpers in this support target and for the tests that
//        read a fixture directly. The fixtures stay beside the target that owns them (`exclude: ["Fixtures"]`); the support
//        target and the parity target reach them from here, so nothing is copied.
//

import Foundation

package enum FixtureDirs {
    /// `Tests/` of the package.
    package static let tests: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// `Tests/<target>/Fixtures`.
    package static func fixtures(of target: String) -> URL {
        tests.appendingPathComponent(target).appendingPathComponent("Fixtures")
    }
}
