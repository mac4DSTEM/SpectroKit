//
//  main.swift
//  Role: touches every SpectroKit 0.2.0 symbol macTEM reads across the package boundary, from a package that depends
//        on SpectroKit by path (so `package` access does not apply), and checks each against a committed fixture.
//        Exits non-zero on any failed check. `tools/consumer-check/run.sh` builds it in Debug and runs it.
//
//  usage: consumer-check [<Tests directory>]
//         (default: the Tests directory of the repository above this file; the fixtures are read from its
//         SpectroCoreTests/Fixtures and SpectroKitTests/Fixtures)
//

import Foundation

let tests: URL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests")
let fixtures = tests.appendingPathComponent("SpectroCoreTests/Fixtures")
let plantedFixtures = tests.appendingPathComponent("SpectroKitTests/Fixtures")
let eelsFixtures = tests.appendingPathComponent("SpectroEELSTests/Fixtures")

var report = Report()
report.section("DM4 demo fixture") { try dm4DemoChecks(&$0, fixtures) }
report.section("DM4 errors") { try dm4ErrorChecks(&$0, fixtures) }
report.section("DM4 tag tree") { try tagTreeChecks(&$0, fixtures) }
report.section("Velox fields") { try veloxChecks(&$0, fixtures) }
report.section("Velox planted file") { try veloxPlantedChecks(&$0, plantedFixtures) }
report.section("DM4 EELS spectrum image") { try eelsReaderChecks(&$0, plantedFixtures) }
report.section("SpectroEELS thickness map") { try spectroEELSChecks(&$0, eelsFixtures) }
report.section("HDF5 barrier") { try barrierChecks(&$0) }
exit(report.finish())
