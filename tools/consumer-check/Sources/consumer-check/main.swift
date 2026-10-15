//
//  main.swift
//  Role: touches the SpectroKit symbols a consumer reads across the package boundary (SpectroEELS in full; since 0.4.0 the
//        spectrum-image opening of SpectroCore, which reads through FormatoKit), from a package that depends on SpectroKit
//        by path (so `package` access does not apply), and checks each against a committed fixture or pin.
//        Exits non-zero on any failed check. `tools/consumer-check/run.sh` builds it in Debug and runs it.
//
//  usage: consumer-check [<Tests directory>]
//         (default: the Tests directory of the repository above this file; the fixtures are read from its
//         SpectroCoreTests/Fixtures and SpectroEELSTests/Fixtures)
//

import Foundation

let tests: URL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests")
let fixtures = tests.appendingPathComponent("SpectroCoreTests/Fixtures")
let eelsFixtures = tests.appendingPathComponent("SpectroEELSTests/Fixtures")

var report = Report()
report.section("SpectroCore through FormatoKit") { try spectroCoreOpeningChecks(&$0, fixtures) }
report.section("SpectroEELS thickness map") { try spectroEELSChecks(&$0, eelsFixtures) }
report.section("SpectroEELS areal density (slice 2)") { try edgeQuantificationChecks(&$0, eelsFixtures) }
report.section("SpectroEDX windows (WindowRules)") { windowRulesChecks(&$0) }
report.section("SpectroEDX quantification policy") { try quantificationPolicyChecks(&$0) }
exit(report.finish())
