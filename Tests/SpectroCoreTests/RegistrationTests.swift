import Foundation
import Testing
import SpectroCore

struct RegistrationTests {
    struct Pins: Decodable { let cases: [Case] }
    struct Report: Decodable {
        let pixels, partial, edge: Int
        let outsideFraction, footprintArea, retainedFraction, purity: Double
    }
    struct Region: Decodable {
        let pixelsIncluded, partialIncluded, edgeIncluded, touchedExcluded: Int
        let regionArea, retainedFraction, outsideFraction, footprintArea, purity: Double
    }
    struct Case: Decodable {
        let name: String
        let matrix: [Double]
        let sw, sh, w, h, classCount: Int
        let inputLabels, labels: [Int]
        let overlap: [[Double]]
        let inside, footprint, outside: [Double]
        let tied: [Bool]
        let counts: [UInt32]
        let pools: [[UInt64]]
        let reports: [Report]
        let regions: [Region]
    }
    // Absolute 2e-12 pixel-area bound for scalar clipping arithmetic across CPUs.
    // Integers, memberships and pooled counts must be exact.
    func close(_ a: [Double], _ b: [Double]) {
        #expect(a.count == b.count)
        for (x,y) in zip(a,b) { #expect(abs(x-y) <= 2e-12) }
    }

    @Test func numpyTranscriptionPins() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/registration-pins.json")
        let pins = try JSONDecoder().decode(Pins.self, from: Data(contentsOf: file))
        var gap = 0.0
        for c in pins.cases {
            let r = try GridRegistration(matrix: c.matrix, scanWidth: c.sw, scanHeight: c.sh,
                                         spectrumWidth: c.w, spectrumHeight: c.h)
            let t = try MaskTransport.transport(labels: c.inputLabels, classCount: c.classCount, registration: r)
            #expect(t.labels == c.labels, "\(c.name)")
            #expect(t.tiedPixels == c.tied)
            #expect(t.tiedExcluded == c.tied.filter { $0 }.count)
            close(t.insideGrid,c.inside); close(t.footprintArea,c.footprint); close(t.footprintOutside,c.outside)
            for i in 0..<c.classCount {
                close(t.overlap[i],c.overlap[i])
                for (x,y) in zip(t.overlap[i],c.overlap[i]) { gap = max(gap,abs(x-y)) }
                let (mask, report) = try MaskTransport.region(t, class: i)
                #expect(mask == c.overlap[i].map { $0 >= 0.5-1e-6 })
                let e = c.regions[i]
                #expect(report.pixelsIncluded == e.pixelsIncluded)
                #expect(report.partialIncluded == e.partialIncluded)
                #expect(report.edgeIncluded == e.edgeIncluded)
                #expect(report.touchedExcluded == e.touchedExcluded)
                close([report.regionArea,report.retainedFraction,report.outsideFraction,report.footprintArea,report.purity],
                      [e.regionArea,e.retainedFraction,e.outsideFraction,e.footprintArea,e.purity])
            }
            let image = DenseSpectrumImage(ny: c.h, nx: c.w, channels: 3, counts: c.counts)
            let pools = try PoolBuilder.pools(image: image, transported: t,
                                             names: (0..<c.classCount).map(String.init), kind: "phase", validation: "none")
            for i in 0..<c.classCount {
                let p = pools[i], expected = c.reports[i]
                #expect(p.counts == c.pools[i])
                #expect(p.pixelCount == expected.pixels)
                #expect(p.partialPixels == expected.partial)
                #expect(p.edgePixels == expected.edge)
                close([p.outsideFraction,p.footprintArea,p.retainedFraction,p.purity],
                      [expected.outsideFraction,expected.footprintArea,expected.retainedFraction,expected.purity])
                #expect(p.isUnvalidated)
                #expect(p.mask == c.labels.map { $0 == i })
            }
        }
        print("Registration: maximum overlap gap \(gap) pixel areas")
    }

    @Test func invalidInputsAreRefused() throws {
        #expect(throws: MaskTransportError.self) { try GridRegistration(matrix: [], scanWidth: 1, scanHeight: 1, spectrumWidth: 1, spectrumHeight: 1) }
        #expect(throws: MaskTransportError.self) { try GridRegistration(matrix: [1,0,0,0,0,0], scanWidth: 1, scanHeight: 1, spectrumWidth: 1, spectrumHeight: 1) }
        #expect(throws: MaskTransportError.self) { try GridRegistration(matrix: [1,0,0,0,1,0], scanWidth: Int.max, scanHeight: 2, spectrumWidth: 1, spectrumHeight: 1) }
        #expect(throws: MaskTransportError.self) { try GridRegistration(matrix: [1,0,.nan,0,1,0], scanWidth: 1, scanHeight: 1, spectrumWidth: 1, spectrumHeight: 1) }
        let r = try GridRegistration(matrix: [1,0,0,0,1,0], scanWidth: 1, scanHeight: 1, spectrumWidth: 1, spectrumHeight: 1)
        for labels in [[], [1], [-2]] {
            #expect(throws: MaskTransportError.self) { try MaskTransport.transport(labels: labels, classCount: 1, registration: r) }
        }
        let t = try MaskTransport.transport(mask: [true], registration: r)
        #expect(throws: MaskTransportError.self) { try MaskTransport.region(t, class: 3) }
        let image = DenseSpectrumImage(ny: 1, nx: 1, channels: 2, counts: [2,3])
        #expect(throws: MaskTransportError.self) { try PoolBuilder.pool(image: image, mask: [], name: "", kind: "drawn") }
        #expect(throws: MaskTransportError.self) { try PoolBuilder.pools(image: image, transported: t, names: [], kind: "phase", validation: nil) }
    }

    @Test func regionPoolingAndMaskBuilders() throws {
        let r = try GridRegistration(matrix: [1,0,0,0,1,0], scanWidth: 2, scanHeight: 2, spectrumWidth: 2, spectrumHeight: 2)
        let image = DenseSpectrumImage(ny: 2, nx: 2, channels: 2, counts: [1,2,3,4,5,6,7,8])
        let mask = MaskTransport.mask(rectangle: -1, 0, 0, 4, width: 2, height: 2)
        #expect(mask == [true,false,true,false])
        #expect(MaskTransport.mask(pixelIndices: [-1,0,2,8], width: 2, height: 2) == mask)
        let pool = try PoolBuilder.pool(image: image, scanMask: mask, registration: r, name: "left", kind: "drawn")
        #expect(pool.counts == [6,8])
        #expect(pool.totalCounts == 14)
        #expect(pool.purity == 1)
        #expect(pool.validation == nil)
        #expect(pool.pixelCount == 2)
    }
}
