//
//  TagTreeChecks.swift
//  Role: `DM4Experiment.tagTree(data:)` (macTEM's metadata reader of a DM-saved TIFF, tag 65027), exercised as
//        `DM4TagTreeTests` does, against `dm-tag65027-saved-with-DM.truth.json` (ncempy's `fileDM.allTags` on the
//        same bytes).
//

import Foundation
import SpectroCore

func tagTreeChecks(_ r: inout Report, _ fixtures: URL) throws {
    let bare = try Data(contentsOf: fixtures.appendingPathComponent("dm-tag65027-saved-with-DM.dm4"))
    let truth = try loadJSON(fixtures.appendingPathComponent("dm-tag65027-saved-with-DM.truth.json"))
    guard let wantNumbers = truth["numbers"] as? [String: Double],
          let wantStrings = truth["strings"] as? [String: String] else {
        throw CheckError("truth has no numbers / strings maps")
    }

    r.equal("a bare tag stream lists no image objects", try DM4Experiment.list(data: bare).count, 0)
    let tree = try DM4Experiment.tagTree(data: bare)
    r.check("the truth holds more than 80 numbers", wantNumbers.count > 80)
    r.check("tagTree(data:).numbers equals ncempy's scalar numbers (\(wantNumbers.count) keys)",
            tree.numbers == wantNumbers)
    r.check("tagTree(data:).strings equals ncempy's strings (\(wantStrings.count) keys)", tree.strings == wantStrings)
    r.equal("tagTree: Microscope Info.Voltage (200 kV, hand-checked in DigitalMicrograph)",
            tree.numbers["Microscope Info.Voltage"], 200_000)
    r.equal("tagTree: Microscope Info.Indicated Magnification (51x)",
            tree.numbers["Microscope Info.Indicated Magnification"], 51)
    r.equal("tagTree: Microscope Info.Illumination Mode", tree.strings["Microscope Info.Illumination Mode"], "TEM")
    r.equal("tagTree: DataBar.Device Name", tree.strings["DataBar.Device Name"], "BM-UltraScan")

    // The last 8 bytes are the stream's trailer, which no walk reads; every cut before it loses a required byte. Sampled
    // as DM4TagTreeTests does: every 7th byte, and the last byte before the trailer.
    var threw = 0, cuts = 0
    for cut in stride(from: 0, to: bare.count - 8, by: 7) + [bare.count - 9] {
        cuts += 1
        do { _ = try DM4Experiment.tagTree(data: bare.prefix(cut)) } catch is DM4Error { threw += 1 } catch {}
    }
    r.equal("tagTree(data:) of the stream cut at every 7th byte before its trailer, and at the last one, throws a DM4Error (\(cuts) cuts)",
            threw, cuts)

    // A stream WITH an ImageList keeps the root prefix in its keys.
    let demo = try Data(contentsOf: fixtures.appendingPathComponent("demo-edx-tiny.dm4"))
    let objects = try DM4Experiment.list(data: demo)
    let demoTree = try DM4Experiment.tagTree(data: demo)
    guard let eds = objects.first(where: { $0.role == .eds }) else { throw CheckError("no EDS object") }
    let prefix = "ImageList.\(eds.index).ImageTags."
    r.equal("tagTree of a stream with an ImageList keeps the 'ImageList.N.' prefix",
            demoTree.strings[prefix + "Meta Data.Signal"], "X-ray")
    r.equal("tagTree numbers under the prefix equal the object's imageTagNumbers (EDS)",
            demoTree.numbers[prefix + "Microscope Info.Voltage"], eds.imageTagNumbers["Microscope Info.Voltage"])
}
