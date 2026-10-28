// SpectroKit S1 test partition (ADR 064 section 3.3): the methods of SpectroscopyLaneUTests that move with the EDX core;
// the rest stay in SpectroscopyLaneUTests.swift. Helpers are duplicated, not shared, across the split.
import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// v5.0 lane U: the first drive's wiring, text and presentation findings (docs/archive/v5/room-drive-2026-10-06.md, 3-13).
/// Each test names the mutation that must turn it red.
/// The app labels a voltage supplied by the same run's 4D cube this way (Core/Data/GMSFourDRegistration.swift, which stays in
/// the app); the library sees only `.supplied(label:)`, so these moving tests name the value, not the app's constant.
private let suppliedCube = BeamEnergySource.supplied(label: "the 4D cube, same run")

@MainActor
struct SpectroscopyProvenanceExportTests {

    private typealias Q = SpectroscopyQuantifyTests

    // MARK: 3 - the beam energy and where it came from

    /// The EDS object's own voltage wins (volts -> kV); else the cube's, only when it is one run; else nothing.
    /// Mutation: `sameRun` ignored in `BeamEnergy.resolve` - red.
    @Test func testTheBeamEnergySourceIsTheObjectsThenTheSameRunCubes() {
        #expect(BeamEnergy.resolve(rawObjectVoltage: 200_000, suppliedKV: 300, suppliedAs: suppliedCube, sameRun: true)?.keV == 200)
        #expect(BeamEnergy.resolve(rawObjectVoltage: 200_000, suppliedKV: 300, suppliedAs: suppliedCube, sameRun: true)?.source == .file)
        #expect(BeamEnergy.resolve(rawObjectVoltage: nil, suppliedKV: 200, suppliedAs: suppliedCube, sameRun: true)?.source == suppliedCube)
        #expect(BeamEnergy.resolve(rawObjectVoltage: nil, suppliedKV: 200, suppliedAs: suppliedCube, sameRun: false) == nil, "another run's voltage is not this file's")
        #expect(BeamEnergy.resolve(rawObjectVoltage: 0, suppliedKV: nil, suppliedAs: suppliedCube, sameRun: true) == nil)
        #expect(BeamEnergy.resolve(rawObjectVoltage: 0, suppliedKV: 200, suppliedAs: suppliedCube, sameRun: true)?.source == suppliedCube, "a stored 0 is no voltage")
    }

    /// The provenance line names the value and its source; a typed value overrides and says so.
    /// Mutation: `typedKeV` ignored in `provenance` - red.
    @Test func testTheProvenanceNamesTheBeamAndItsSource() {
        var meta = SpectrumImageMetadata(fileName: "a.dm4", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: 1, energyOffsetEV: 0, energyDispersionEV: 10)
        #expect(BeamEnergy.provenance(typedKeV: nil, metadata: meta) == nil)
        meta.beamEnergyKeV = 200; meta.beamEnergySource = suppliedCube
        #expect(BeamEnergy.provenance(typedKeV: nil, metadata: meta) == "beam 200 kV \u{00B7} from the 4D cube, same run")
        meta.beamEnergySource = .file
        #expect(BeamEnergy.provenance(typedKeV: nil, metadata: meta) == "beam 200 kV \u{00B7} from the file")
        #expect(BeamEnergy.provenance(typedKeV: 120, metadata: meta) == "beam 120 kV \u{00B7} typed")
    }

    /// The fit's footer says where the beam came from; a typed value says "typed".
    /// Mutation: the provenance line not appended in `PooledQuantifier.run` - red.
    @Test func testTheFitFooterCarriesTheBeamProvenance() throws {
        var image = try Q.image()
        var meta = image.metadata
        meta.beamEnergyKeV = 200; meta.beamEnergySource = suppliedCube
        image = LoadedSpectrumImage(image: image.image, metadata: meta, energyAxis: image.energyAxis, scanImage: image.scanImage)
        var m = Q.method(); m.beamEnergyKeV = nil
        let r = try PooledQuantifier.run(Q.input(m, image: image), tables: Q.tables)
        #expect(r.footerLines.contains("beam 200 kV \u{00B7} from the 4D cube, same run"), "\(r.footerLines.joined(separator: "\n"))")
        let typed = try PooledQuantifier.run(Q.input(Q.method(), image: image), tables: Q.tables)
        #expect(typed.footerLines.contains("beam 200 kV \u{00B7} typed"))
    }

    // MARK: 5 - export

    /// The CSV: header lines (validation, method hash, provenance), the column row, one row per fitted element, at% empty
    /// without a k source, the reference's k-free sigma empty, the flags and the estimator on each row.
    /// Mutation: the `validation` header line removed from `SpectroscopyExport.csv` - red.
    @Test func testTheCSVCarriesTheTableTheValidationBadgeAndTheMethodHash() throws {
        let r = try PooledQuantifier.run(Q.input(Q.method(), image: try Q.image()), tables: Q.tables)
        let csv = SpectroscopyExport.csv(r, regionName: "Whole map")
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.contains { $0.hasPrefix("# validation: UNVALIDATED") })
        #expect(lines.contains("# method hash (sha256 of the method JSON): \(r.method.hash)"))
        #expect(lines.contains { $0.hasPrefix("# beam 200 kV") })
        let head = try #require(lines.firstIndex { !$0.hasPrefix("#") })
        #expect(lines[head] == SpectroscopyExport.columns.joined(separator: ","))
        let rows = lines[(head + 1)...].filter { !$0.isEmpty }
        #expect(rows.count == r.rows.count)
        let al = try #require(rows.first { $0.hasPrefix("Al,Al_Ka,") })
        let cells = al.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(cells[4] == "1"); #expect(cells[5] == "", "the reference carries no k-free sigma")
        #expect(cells[8] == "none"); #expect(cells[9].contains("reference element"))
        #expect(isEqual(Double(cells[2]) ?? 0, r.rows[0].net, accuracy: abs(r.rows[0].net) * 1e-5), "six significant digits")

        var m = Q.method(); m.kFactorSource = .typed          // no k: no at%
        let none = SpectroscopyExport.csv(try PooledQuantifier.run(Q.input(m, image: try Q.image()), tables: Q.tables), regionName: "Whole map")
        #expect(none.contains("# validation: net counts and k-free ratios only"))
        let row = try #require(none.split(separator: "\n").first { $0.hasPrefix("Al,Al_Ka,") }).split(separator: ",", omittingEmptySubsequences: false)
        #expect(row[6] == ""); #expect(row[7] == ""); #expect(row[8] == "")
    }

    /// The method JSON holds the method's own canonical bytes and the hash of exactly those bytes.
    /// Mutation: the hash taken of a re-encoding with spaces (not `canonicalJSON`) - red.
    @Test func testTheMethodJSONIsTheCanonicalEncodingAndItsHash() throws {
        let m = Q.method()
        let text = SpectroscopyExport.methodJSON(m)
        #expect(text.contains(m.canonicalJSON))
        let o = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((o["sha256"] as? String) == m.hash)
        #expect(QuantificationMethod.decode(m.canonicalJSON) == m)
        #expect(SpectroscopyExport.fileStem(imageName: "AlMgSi 4D.dm4", regionName: "Region 1") == "AlMgSi_4D_Region_1")
    }

    // MARK: 6 - the weak-line warning

    /// Shown only with Al K-alpha fitted at a non-zero area and a quantified Mg or Si K-alpha beside it.
    /// Mutation: the Al test dropped from `weakLineBiasApplies` - red.
    @Test func testTheWeakLineWarningNeedsAlAndAQuantifiedNeighbour() throws {
        let ids = ["Al_Ka", "Mg_Ka", "Si_Ka", "Cu_Ka"]
        #expect(PooledQuantifier.weakLineBiasApplies(groupIDs: ids, values: [10, 1, 1, 1], quantified: ["Mg"]))
        #expect(!PooledQuantifier.weakLineBiasApplies(groupIDs: ids, values: [0, 1, 1, 1], quantified: ["Mg"]), "Al at 0")
        #expect(!PooledQuantifier.weakLineBiasApplies(groupIDs: ["Mg_Ka", "Si_Ka"], values: [1, 1], quantified: ["Mg"]), "no Al in the fit")
        #expect(!PooledQuantifier.weakLineBiasApplies(groupIDs: ids, values: [10, 1, 1, 1], quantified: ["Al", "Cu"]), "no Mg or Si quantified")
        let image = try Q.image()
        let with = try PooledQuantifier.run(Q.input(Q.method(), image: image), tables: Q.tables)
        #expect(with.warnings.contains(ContinuumForm.weakLineBiasNote))
        let alCu = try PooledQuantifier.run(Q.input(Q.method(elements: [("Al", .quantify), ("Cu", .quantify)]), image: image), tables: Q.tables)
        #expect(!alCu.warnings.contains(ContinuumForm.weakLineBiasNote))
        let noAl = try PooledQuantifier.run(Q.input(Q.method(elements: [("Mg", .quantify), ("Si", .quantify)]), image: image), tables: Q.tables)
        #expect(!noAl.warnings.contains(ContinuumForm.weakLineBiasNote))
    }

    /// Mutation: the quote test back on Characters ("\r\n" is one Character equal to neither) - red.
    @Test func testACRLFInAFieldIsQuoted() throws {
        #expect(SpectroscopyExport.field("a\r\nb") == "\"a\r\nb\"")
        #expect(SpectroscopyExport.field("a\nb") == "\"a\nb\"" && SpectroscopyExport.field("a,b") == "\"a,b\"")
        #expect(SpectroscopyExport.field("a\"b") == "\"a\"\"b\"" && SpectroscopyExport.field("plain") == "plain")
    }
}
