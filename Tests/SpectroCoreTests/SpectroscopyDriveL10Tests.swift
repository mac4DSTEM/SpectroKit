import XCTest
import DSTEMCore

/// Lane L10 (the owner's drive findings, build 2): Velox's own element selection, read from the file (`VeloxEMDReader.storedElementSelection`).
/// The files are 600 to 700 byte synthetic Velox EMDs (a Version dataset and one quantification-settings group of variable-length JSON
/// strings, the layout rsciio's `_parse_metadata_group` reads), written with h5py: `Operations/ImageQuantificationOperation` (version 9)
/// and `SharedProperties/EDSSpectrumQuantificationSettings` (version 11), each entry the JSON `{"elementSelection": [atomic numbers], ...}`.
/// The v9 file holds TWO entries, "a-first" = Mg Al Si and "b-second" = O, so taking the last or any other entry is caught.
final class SpectroscopyDriveL10Tests: XCTestCase {
    private static let v9Base64 = "7VlNT9tAEN11iGohtXJvKV+y3EsPIIW2B8oNQYBIiKQFoUoVUo2zaa3GNrLXKBLKFcGtP6FHfgZH/hXd8e66toUCbaW0iHlSMp6d2dlN/DxR3l5sb2w+nZ6ZJgDTJFPEIkXcKDTtsq/jn5Wlyp4re2nocZrFGmr8uapfzdv/0GpB9k0Fep3mlLQmQTxGbLfWumA/Kl/RkVwb5bwDFid+FJLOMYtdLq6SMj9XfnNdSupyLtW+ZDKltFRX25qIw/ULEQemW3lMMrcuLPiGIYdNVa9GNbWtyg7O/6v7sLfb2aDEyHc5rJc//w/lW43y82rXkMNlXt3eF6vf31190Z7Fvog8uuX3VQ1czoyf/xK4Zv56hrfWOzu00IZoIQ9w6pzIDuus2s47Z9F2+lEcuBzcAzaIhs4oy9NteZTPYwMWsJDvCetxWeDTyqEooAJJuyfe/b7PehAqRLpxJLo591kCgVPH5VHge7tpcMRiMbL8WqT6oTdIe6wdrqU86jL3Wxuq8Dhlo8NR1pclzsbuB0otvxGvtxPbmML3Z8hlBAKBQCAQCAQCgUBMDlWd9ZWyzUY5rx24X9j71M3+GHuZ0ppLrkXdoHnPde/SuYbz0qLOhbwE2MpeV/Sto6WEeVHY07671PfjhP+x/i/17lycJ1dPpM3Pu+6psz12TO4cxVLUeBjnKLqtXi2Mz9f8+zqHXPo3vLIfBK/+FiBJ6/MA0PDPCj5o6D8B"
    private static let v11Base64 = "7ZlBS+NAFMdnUotBkM3eqqsQwh48eGg96d7Edm1BtGsWERbBbDNq2CaRdCIF6V2/hUc/hke/lTvPmWkzQbaCsAp9P2hfZ97Lm6T955V5uW03vy8uLC8QwLbJHHFIkSeF65pj7T9Vlip7o+y9pefps6+m5j+r/OW4n4etFkQ/ldDr1OektQkyi7Rb212wx2q8puyjZcYdsWwQpQnxL4KMhd0svWQZj9iAlHRaf+W6lFTlMVSPpZIppUY+bSvCD5+XhB+U7ox9UrlVYWFsWXLaVvkqVEvbKZ3BzYf6Hfz9gyYl1vgsh1Xz+u/U2KmZ96tbQQ2bunq5Lpa/v2l10f2CdRF19ML/q5q4X/738V9Ba/bkHt7dOdijhTJEC3HAtXclK6z3zfUaDW/d9c7SLA44jI9YPx16I4jTZfl2fBzrs5gl3Be2x2WCX5vr7saGeAm7uXUicqmgQScU79FZxEIIK3gmFR0c117A0zjq7efxb5aJmYbI5kVJr5+HrJNs5zztsuBPB7LwLGejk1Hp+mufUEMIgiAIgiAIgiDI7FHus+o+ab1mxrWavn8pNvJZHv/Ig+e9ei+Abb3POI+S8wEx+wdrU9ad1ucarkqLfS7UJaD7z4+l/laeR2FRd+03riv73ePmPHmYN3X92j7brPP/nqM4rqkQzUd8jjLR1cUKagR5f6Bfr58HQA//Lw=="
    private static let emptyBase64 = "7ZnPSwJBFMdnVqVFiLabWcGydPDQQa/dIi2DSGtDggha3DEXdDf2Rwjh3f6Ljv4ZHf2vbMedWXcWSSEqwfc5+Hzz3sys7nef+Oa9Xj3fzhfziCLLKIsUlGTKUFXR5/EnZjGzI2bHEh/Hs1iBje+y9dN5d7e1Gs2epuD7lLORlRGwidRrp01q75lfYnYiiXkt4nqWYyO9a7jEbLrOC3F9i3gopdPyivtilIvmYO5HSsYYC+txmwnj9P1eGKdKV+JYpNxcaKkvSdGwzNbLYC5tJXUFo7W6D/p1o4qRFF/lICd+/g/mKwXxeVUzoGFRV4vrYvr7W1YX1X2oi6CjBb+vbGBc/H7+EdWaPH+GL84aVzhRhnAij/KmvUYVVjtRtUpFO1a1juP2DZ/6LdJzBtqQ5vGyXIznkR7pE9v3Ls3w1epYxAynPDwOU9VuB+4pAAAAAAAAAAAAAPw26T4r75OWC2JerarrL6Ttu0H/JjBmf+jbhm85tk5837KfPST2D0pL9l3W5xocRhb6XKBLCu8/T1L9rSCwzKTu6j/cN+p3x8159Lkl6nrVPtum83fnKIoqKoSzjucoc111D0AjwP9Dyxg/D6A9/C8="

    private func write(_ base64: String) throws -> VeloxEMDReader {
        let compressed = try XCTUnwrap(Data(base64Encoded: base64))
        let raw = try (compressed as NSData).decompressed(using: .zlib) as Data
        let path = NSTemporaryDirectory() + "velox-selection-\(UUID().uuidString).emd"
        try raw.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return VeloxEMDReader(path: path)
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    // MARK: The pure half

    /// Atomic numbers become symbols in the order stored, across the table (H, Fe, La, U, Lr).
    func testSelectionSymbolsFollowTheAtomicNumbers() {
        XCTAssertEqual(VeloxEMDReader.elementSelection(fromSettingsJSON: json(#"{"elementSelection": [12, 13, 14]}"#)), ["Mg", "Al", "Si"])
        XCTAssertEqual(VeloxEMDReader.elementSelection(fromSettingsJSON: json(#"{"elementSelection": [14, 1, 26, 57, 92, 103]}"#)),
                       ["Si", "H", "Fe", "La", "U", "Lr"], "the order of the file, not sorted")
    }

    /// No key, an empty list, a number outside 1...103 or a non-number: no selection (never a partial or wrong one).
    func testNoSelectionIsNil() {
        XCTAssertNil(VeloxEMDReader.elementSelection(fromSettingsJSON: json(#"{"elementsIdentified": []}"#)))
        XCTAssertNil(VeloxEMDReader.elementSelection(fromSettingsJSON: json(#"{"elementSelection": []}"#)))
        XCTAssertNil(VeloxEMDReader.elementSelection(fromSettingsJSON: json(#"{"elementSelection": [12, 104]}"#)))
        XCTAssertNil(VeloxEMDReader.elementSelection(fromSettingsJSON: json(#"{"elementSelection": [0]}"#)))
        XCTAssertNil(VeloxEMDReader.elementSelection(fromSettingsJSON: json(#"{"elementSelection": ["Mg"]}"#)))
        XCTAssertNil(VeloxEMDReader.elementSelection(fromSettingsJSON: json("not json")))
    }

    // MARK: From a file

    /// Version 9: `Operations/ImageQuantificationOperation`, the first entry by name.
    func testVersion9ReadsTheFirstOperationEntry() throws {
        XCTAssertEqual(try write(Self.v9Base64).storedElementSelection(), ["Mg", "Al", "Si"])
    }

    /// Version 11 moved it to `SharedProperties/EDSSpectrumQuantificationSettings`; Z >= 89 is carried as stored (Ac here).
    func testVersion11ReadsTheSharedPropertiesEntry() throws {
        XCTAssertEqual(try write(Self.v11Base64).storedElementSelection(), ["O", "Ti", "Ni", "Ac"])
    }

    /// A Velox file whose session selected nothing, and one with no settings group at all (the tiny spectrum-image fixture): nil.
    func testAFileWithoutASelectionReturnsNil() throws {
        XCTAssertNil(try write(Self.emptyBase64).storedElementSelection())
        let tiny = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/velox-tiny.emd").path
        XCTAssertNil(try VeloxEMDReader(path: tiny).storedElementSelection())
    }
}
