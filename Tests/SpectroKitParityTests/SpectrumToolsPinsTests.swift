//
//  SpectrumToolsPinsTests.swift
//  Role: 0.10.0 spectrum tools against their references (Tests/SpectroCoreTests/Fixtures/spectrum-tools-*-pins.json,
//        tools/spectrum-tools/pins.py): the line profile against scikit-image 0.26.0 `measure.profile_line` where the
//        geometries coincide (hard = order 0, bilinear = order 1) and against a NumPy transcription of the hard geometry
//        elsewhere; display smoothing against SciPy 1.18.1 and HyperSpy 2.4.0.
//

import Foundation
import Testing
import SpectroCore
import SpectroTestSupport

struct SpectrumToolsPinsTests {

    struct Cube: Decodable { let ny, nx, channels: Int; let counts: [UInt32] }
    struct Straight: Decodable { let src, dst: [Double]; let width: Int; let mean, sum: [[Double]]; let spacing: Double?; let steps: Int? }
    struct Numpy: Decodable {
        let path: [[Double]]; let width, spacing: Double; let arcLengths: [Double]; let counts: [Int]; let mean, sum: [[Double]]
    }
    struct LineProfilePins: Decodable { let cube: Cube; let hardVsSkimage, bilinearVsSkimage: [Straight]; let hardNumpy: [Numpy] }

    static func load<T: Decodable>(_ name: String, as: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: FixtureDirs.fixtures(of: "SpectroCoreTests").appendingPathComponent(name)))
    }

    static func image(_ c: Cube) -> DenseSpectrumImage { DenseSpectrumImage(ny: c.ny, nx: c.nx, channels: c.channels, counts: c.counts) }

    @Test func hardMembershipMatchesSkimageOrder0WhereTheGeometriesCoincide() throws {
        let pins: LineProfilePins = try Self.load("spectrum-tools-lineprofile-pins.json")
        let image = Self.image(pins.cube)
        var gap = 0.0
        for c in pins.hardVsSkimage {
            let path = [PixelPosition(row: c.src[0], column: c.src[1]), PixelPosition(row: c.dst[0], column: c.dst[1])]
            let mean = try SpectrumLineProfile.compute(image: image, path: path, width: Double(c.width))
            let sum = try SpectrumLineProfile.compute(image: image, path: path, width: Double(c.width), reduction: .sum)
            #expect(mean.stepCount == c.mean.count, "\(c.src) \(c.dst) w \(c.width)")
            for k in 0..<min(mean.stepCount, c.mean.count) {
                #expect(mean.pixelCounts[k] == c.width)
                for ch in 0..<pins.cube.channels {
                    gap = max(gap, abs(mean.spectra[k][ch] - c.mean[k][ch]), abs(sum.spectra[k][ch] - c.sum[k][ch]))
                }
            }
        }
        print("line profile hard vs skimage order 0: max gap \(gap)")
        #expect(gap <= 1e-12)
    }

    @Test func bilinearMatchesSkimageOrder1() throws {
        let pins: LineProfilePins = try Self.load("spectrum-tools-lineprofile-pins.json")
        let image = Self.image(pins.cube)
        var gap = 0.0
        for c in pins.bilinearVsSkimage {
            let path = [PixelPosition(row: c.src[0], column: c.src[1]), PixelPosition(row: c.dst[0], column: c.dst[1])]
            let mean = try SpectrumLineProfile.compute(image: image, path: path, width: Double(c.width), spacing: c.spacing!,
                                                       weighting: .bilinear)
            let sum = try SpectrumLineProfile.compute(image: image, path: path, width: Double(c.width), spacing: c.spacing!,
                                                      weighting: .bilinear, reduction: .sum)
            #expect(mean.stepCount == c.steps!)
            #expect(mean.weightSums.allSatisfy { $0 == Double(c.width) })
            for k in 0..<min(mean.stepCount, c.mean.count) {
                for ch in 0..<pins.cube.channels {
                    gap = max(gap, abs(mean.spectra[k][ch] - c.mean[k][ch]) / max(1, abs(c.mean[k][ch])),
                              abs(sum.spectra[k][ch] - c.sum[k][ch]) / max(1, abs(c.sum[k][ch])))
                }
            }
        }
        print("line profile bilinear vs skimage order 1: max relative gap \(gap)")
        #expect(gap <= 1e-12)
    }

    @Test func hardGeometryMatchesTheNumpyTranscription() throws {
        let pins: LineProfilePins = try Self.load("spectrum-tools-lineprofile-pins.json")
        let image = Self.image(pins.cube)
        var gap = 0.0
        for c in pins.hardNumpy {
            let path = c.path.map { PixelPosition(row: $0[0], column: $0[1]) }
            let mean = try SpectrumLineProfile.compute(image: image, path: path, width: c.width, spacing: c.spacing)
            let sum = try SpectrumLineProfile.compute(image: image, path: path, width: c.width, spacing: c.spacing, reduction: .sum)
            #expect(mean.pixelCounts == c.counts, "\(c.path)")
            #expect(mean.arcLengths.count == c.arcLengths.count)
            for k in 0..<mean.stepCount {
                for ch in 0..<pins.cube.channels {
                    gap = max(gap, abs(mean.spectra[k][ch] - c.mean[k][ch]), abs(sum.spectra[k][ch] - c.sum[k][ch]))
                }
            }
        }
        print("line profile hard vs NumPy transcription: max gap \(gap)")
        #expect(gap <= 1e-12)
    }
}
