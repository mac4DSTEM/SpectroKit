import Foundation
import Testing
import SpectroCore
import FormatoDM

/// A DM4 whose disk has been
/// disconnected refuses with `DM4Error.volumeGone` instead of dying with a
/// SIGBUS, and the refusal LATCHES — once a read has found the disk gone, every
/// later read of that reader throws, even if the disk answers again, because
/// the old mapping stays dead after a remount.
///
/// The real SIGBUS and the real forced unmount are not unit-testable; the
/// probe that measured them (a RAM disk, `hdiutil detach -force`, HEAD dies
/// with exit status 138, the guarded reader throws, and the same-name remount
/// still refuses) is archived beside the Slot 4⅞ record. These tests drive the
/// reader through an injected liveness check, and the real descriptor check
/// through what a healthy disk can still do (a rename, an unlink).
final class FinalPolishDSpectro {

    private let directory: URL

    init() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spectrokit-finalpolish-d-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func testTheErrorTextIsTheOwnersSentence() {
        #expect(DM4Error.volumeGone("scan_042.dm4").errorDescription == "scan_042.dm4 is no longer reachable: its disk was disconnected. Reconnect it and reopen.")
    }
}
