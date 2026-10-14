//
//  SavitzkyGolayBitParityTests.swift
//  Role: The Savitzky-Golay first derivative against SciPy 1.18.1's own output, BIT FOR BIT (bit patterns compared, no tolerance):
//        `savgol_coeffs`, `savgol_filter(mode="interp")` (interior and both edges) for every window in {5,7,9,11,13,21,31,49} x
//        polyorder in {1..4} x delta in {0.05, 0.25, 1.0}, on whole images (1-D, 2-D and 3-D arrays: HyperSpy filters the whole
//        data array at once, and the edge fits' bits depend on the number of spectra), and the three accumulation paths of
//        `convolve1d`. The fixture is tools/eels-thickness/make_sg_parity.py's output (6 images, committed); set
//        SG_PARITY_BIG_DIR to a directory written by `make_sg_parity.py DIR big` for the large evidence run (52 images,
//        up to 140000 spectra).
//

import Foundation
import XCTest
import SpectroEELS
import SpectroCore

final class SavitzkyGolayBitParityTests: XCTestCase {

    struct Meta: Decodable {
        struct Setting: Decodable { let wl: Int; let po: Int; let delta: Double; let outOffset: Int }
        struct Image: Decodable { let ny: Int; let nx: Int; let n: Int; let rank: Int; let offset: Int; let settings: [Setting] }
        struct Coefficients: Decodable { let wl: Int; let po: Int; let delta: Double; let offset: Int }
        struct Conv: Decodable { let label: String; let wl: Int; let image: Int; let pixel: Int; let weightsOffset: Int; let outOffset: Int }
        let images: [Image]; let coefficients: [Coefficients]; let convolutions: [Conv]
    }

    private func load(_ dir: URL) throws -> (Meta, [Double]) {
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: dir.appendingPathComponent("sg-parity.json")))
        let raw = try Data(contentsOf: dir.appendingPathComponent("sg-parity.f64"), options: .alwaysMapped)
        let values = raw.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
        return (meta, values)
    }

    private var fixtureDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private func dirs() -> [URL] {
        var d = [fixtureDir]
        if let big = ProcessInfo.processInfo.environment["SG_PARITY_BIG_DIR"] { d.append(URL(fileURLWithPath: big)) }
        return d
    }

    private func same(_ a: Double, _ b: Double) -> Bool { a.bitPattern == b.bitPattern }

    /// `savgol_coeffs` of every setting, and the whole derivative (interior + both edges) of every spectrum of every image at
    /// every setting of that image, the image filtered as ONE array (as HyperSpy does): 0 bit mismatches.
    func testCoefficientsAndDerivativeAreBitIdenticalToSciPy() throws {
        for dir in dirs() {
            let (meta, v) = try load(dir)
            var compared = 0, coeffMismatch = 0, derivMismatch = 0, runs = 0, pixels = 0
            for c in meta.coefficients {
                let ours = try SavitzkyGolay.coefficients(windowLength: c.wl, polynomialOrder: c.po, derivative: 1, delta: c.delta)
                for k in 0..<c.wl where !same(ours[k], v[c.offset + k]) { coeffMismatch += 1 }
            }
            for im in meta.images {
                let np = im.nx * im.ny
                for s in im.settings {
                    let sg = try SavitzkyGolayFirstDerivative(windowLength: s.wl, polynomialOrder: s.po, delta: s.delta)
                    let table: SavitzkyGolayEdgeTable = v.withUnsafeBufferPointer { vp in
                        try! sg.edgeTable(nx: im.nx, ny: im.ny) { p in UnsafeBufferPointer(rebasing: vp[(im.offset + p * im.n)..<(im.offset + (p + 1) * im.n)]) }
                    }
                    var out = [Double](repeating: .nan, count: im.n)
                    for p in 0..<np {
                        v.withUnsafeBufferPointer { vp in
                            let f = UnsafeBufferPointer(rebasing: vp[(im.offset + p * im.n)..<(im.offset + (p + 1) * im.n)])
                            out.withUnsafeMutableBufferPointer { o in sg.apply(f, into: o, pixel: p, table: table) }
                        }
                        for i in 0..<im.n { compared += 1; if !same(out[i], v[s.outOffset + p * im.n + i]) { derivMismatch += 1 } }
                    }
                    runs += 1; pixels += np
                }
            }
            print("EELS-REPORT sg bit parity [\(dir.lastPathComponent)]: \(meta.images.count) images, \(runs) image x setting runs, \(pixels) spectra, \(compared) derivative values, \(derivMismatch) mismatches; \(meta.coefficients.count) coefficient sets, \(coeffMismatch) mismatches")
            XCTAssertEqual(coeffMismatch, 0)
            XCTAssertEqual(derivMismatch, 0)
        }
    }

    /// `convolve1d`'s interior for hand-made weights on each of the three paths (including pairs within and beyond DBL_EPSILON).
    func testConvolutionPathsAreBitIdenticalToSciPy() throws {
        for dir in dirs() {
            let (meta, v) = try load(dir)
            var mismatches = 0, compared = 0
            var paths = Set<String>()
            for c in meta.convolutions {
                let w = Array(v[c.weightsOffset..<(c.weightsOffset + c.wl)])
                let im = meta.images[c.image]
                let x = Array(v[(im.offset + c.pixel * im.n)..<(im.offset + (c.pixel + 1) * im.n)])
                var out = [Double](repeating: .nan, count: im.n)
                x.withUnsafeBufferPointer { f in out.withUnsafeMutableBufferPointer { o in SavitzkyGolay.convolveInterior(f, coefficients: w, into: o) } }
                let h = c.wl / 2
                for i in h..<(im.n - h) {
                    compared += 1
                    if !same(out[i], v[c.outOffset + i]) { mismatches += 1; XCTFail("\(c.label) wl \(c.wl) pixel \(c.pixel) index \(i): \(out[i]) vs SciPy \(v[c.outOffset + i])") }
                }
                paths.insert("\(SavitzkyGolay.interiorPath(coefficients: w))")
            }
            print("EELS-REPORT convolve paths [\(dir.lastPathComponent)]: \(meta.convolutions.count) cases, \(compared) values, \(mismatches) mismatches, paths hit \(paths.sorted())")
            XCTAssertEqual(mismatches, 0)
            XCTAssertEqual(paths, ["general", "antisymmetric", "symmetric"])
        }
    }

    /// Which path SciPy's own coefficients take: the nearly-antisymmetric derivative filter is "general" only when its
    /// asymmetry exceeds DBL_EPSILON (window 5, order 3, delta 0.05: yes; window 21, order 3, delta 1: anti-symmetric).
    func testPathSelectionOnSciPyCoefficients() throws {
        let general = try SavitzkyGolay.coefficients(windowLength: 5, polynomialOrder: 3, derivative: 1, delta: 0.05)
        XCTAssertEqual(SavitzkyGolay.interiorPath(coefficients: general), .general)
        let anti = try SavitzkyGolay.coefficients(windowLength: 21, polynomialOrder: 3, derivative: 1, delta: 1.0)
        XCTAssertEqual(SavitzkyGolay.interiorPath(coefficients: anti), .antisymmetric)
    }
}
