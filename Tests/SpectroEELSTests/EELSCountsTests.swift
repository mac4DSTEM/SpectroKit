//
//  EELSCountsTests.swift
//  Role: the memory of an EELS cube (SpectroKit#94). A float32 cube is held at four bytes a count, as exSpy keeps the file's dtype; every
//        read widens exactly, so a method gives the same numbers from the Floats as from their Doubles; Align shifts and crops in place, so
//        it holds one cube, not three (the 1.46 GB 145_STEM spectrum image cost 2.9 GB open and 8.9 GB after Align in macEM, macTEM#571).
//
//  THE TRUTH: the eels16 set (the exSpy pins' input), rounded to Float, aligned once as Floats and once as the same values widened to Double.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS
import SpectroCore

struct EELSCountsTests {

    /// The eels16 low loss (and core loss) at single precision, built inline so no other array shares the counts' storage.
    private func singleLowLoss() throws -> LowLossSpectrumImage {
        let d = try Eels16.lowLoss()
        return try LowLossSpectrumImage(nx: d.nx, ny: d.ny, channels: d.channels, counts: d.counts.map { Float($0) },
                                        energyOffsetEV: d.energyOffsetEV, energyScaleEV: d.energyScaleEV)
    }

    private func singleCoreLoss() throws -> CoreLossSpectrumImage {
        let d = try Eels16.coreLoss()
        return try CoreLossSpectrumImage(nx: d.nx, ny: d.ny, channels: d.channels, counts: d.counts.map { Float($0) },
                                         energyOffsetEV: d.energyOffsetEV, energyScaleEV: d.energyScaleEV)
    }

    /// The same counts widened to Double: what the kit held before.
    private func widened(_ image: LowLossSpectrumImage) throws -> LowLossSpectrumImage {
        try LowLossSpectrumImage(nx: image.nx, ny: image.ny, channels: image.channels, counts: image.storedCounts.doubles,
                                 energyOffsetEV: image.energyOffsetEV, energyScaleEV: image.energyScaleEV)
    }

    private static func address(_ counts: EELSCounts) -> UInt? {
        counts.singles?.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    }

    /// Red before: the `[Float]` initialiser widened every count to Double (eight bytes a count).
    @Test func testAFloatCubeIsHeldAtFourBytesACount() throws {
        let single = try singleLowLoss()
        #expect(single.storedCounts.precision == .single)
        #expect(single.storedCounts.precision.bytes == 4)
        #expect(single.storedCounts.count == single.nx * single.ny * single.channels)
        let core = try singleCoreLoss()
        #expect(core.storedCounts.precision.bytes == 4)
        let double = try Eels16.lowLoss()
        #expect(double.storedCounts.precision == .double)
        #expect(double.storedCounts.precision.bytes == 8)
    }

    /// Every read is the Float widened exactly: element, row and whole.
    @Test func testReadsWidenExactly() throws {
        let single = try singleLowLoss()
        let floats = try #require(single.storedCounts.singles)
        #expect(single.counts == floats.map { Double($0) })
        for i in [0, 7, floats.count - 1] { #expect(single.storedCounts[i] == Double(floats[i])) }
        let n = single.channels
        let row = single.storedCounts.withRow(start: 3 * n, count: n) { Array($0) }
        #expect(row == floats[(3 * n) ..< (4 * n)].map { Double($0) })
        var copied = [Double](repeating: 0, count: n)
        copied.withUnsafeMutableBufferPointer { single.storedCounts.copy(start: 3 * n, count: n, into: $0.baseAddress!) }
        #expect(copied == row)
    }

    /// Read-only methods give the same numbers from the Floats as from the widened Doubles: the sum and the thickness map.
    @Test func testReadOnlyMethodsGiveTheSameNumbers() throws {
        let single = try singleLowLoss()
        let double = try widened(single)
        let mask = (0 ..< single.pixelCount).map { $0 % 3 != 1 }
        #expect(try single.sum(mask: mask).counts == double.sum(mask: mask).counts)
        let theta = single.energy(ofChannel: single.channels / 3)      // a threshold on the axis, whatever its offset
        let a = try EELSThickness.logRatio(single, threshold: .fixed(theta))
        let b = try EELSThickness.logRatio(double, threshold: .fixed(theta))
        #expect(a.pixels.map(\.tOverLambda) == b.pixels.map(\.tOverLambda))
        #expect(a.pixels.map(\.zlpCentreEV) == b.pixels.map(\.zlpCentreEV))
        // The estimated threshold (the default, run when the room opens) reads only its search window, a pixel at a time: the same thresholds.
        let c = try EELSThickness.logRatio(single)
        let d = try EELSThickness.logRatio(double)
        #expect(c.pixels.map(\.thresholdEV) == d.pixels.map(\.thresholdEV))
        #expect(c.pixels.map(\.tOverLambda) == d.pixels.map(\.tOverLambda))
        #expect(c.estimatedTolerance == d.estimatedTolerance)
    }

    /// Align of a float32 cube: the same shifts and crop as of its Doubles (the reads are exact) and the result stays four bytes a count. The
    /// counts are rounded to float32 after each pass, as NumPy writes into exSpy's float32 array: one pass (no subpixel) is the Double result
    /// rounded once, bit for bit; two passes are within one float32 ulp of it (the second pass interpolates the rounded first).
    @Test func testAligningFloatsGivesTheDoubleResultRoundedToFloat() throws {
        func compare(_ options: ZeroLossAlignmentOptions, exact: Bool) throws {
            let double = try widened(try singleLowLoss())
            let wide = try EELSAlignment.alignZeroLossPeak(double, alsoAlign: [try singleCoreLoss().widenedForTest()], options: options)
            let narrow = try EELSAlignment.alignZeroLossPeak(try singleLowLoss(), alsoAlign: [try singleCoreLoss()], options: options)
            #expect(narrow.shiftEV == wide.shiftEV)
            #expect(narrow.initialCentreEV == wide.initialCentreEV)
            #expect(narrow.keptChannels == wide.keptChannels)
            #expect(narrow.alsoKeptChannels == wide.alsoKeptChannels)
            #expect(narrow.aligned.energyOffsetEV == wide.aligned.energyOffsetEV)
            #expect(narrow.aligned.storedCounts.precision == .single)
            #expect(narrow.alsoAligned[0].storedCounts.precision == .single)
            let pairs = [(try #require(narrow.aligned.storedCounts.singles), wide.aligned.counts.map { Float($0) }),
                         (try #require(narrow.alsoAligned[0].storedCounts.singles), wide.alsoAligned[0].counts.map { Float($0) })]
            for (got, want) in pairs {
                #expect(got.count == want.count)
                if exact {
                    #expect(got == want)
                } else {
                    #expect(zip(got, want).allSatisfy { abs($0 - $1) <= $1.ulp })
                }
            }
        }
        try compare(ZeroLossAlignmentOptions(subpixel: false), exact: true)
        try compare(ZeroLossAlignmentOptions(), exact: false)
    }

    /// No second cube: the aligned counts are the input's own storage, shifted and cropped where they were, when the caller hands over its
    /// last copy. Red before: Align built a new array per pass (three cubes at the peak).
    @Test func testAlignWritesIntoTheCubeItWasGiven() throws {
        var image: LowLossSpectrumImage? = try singleLowLoss()
        let before = Self.address(image!.storedCounts)
        let given = image.take()!
        let result = try EELSAlignment.alignZeroLossPeak(consume given)
        #expect(before != nil)
        #expect(Self.address(result.aligned.storedCounts) == before, "the aligned counts live where the input's did")
        #expect(result.aligned.storedCounts.count == result.aligned.pixelCount * result.aligned.channels)
    }

    /// A caller that keeps its image keeps it unchanged (it pays for one copy, never sees its counts move).
    @Test func testACallerThatKeepsItsImageSeesItUnchanged() throws {
        let image = try singleLowLoss()
        let floats = image.storedCounts.singles
        _ = try EELSAlignment.alignZeroLossPeak(image)
        #expect(image.storedCounts.singles == floats)
    }
}

private extension CoreLossSpectrumImage {
    func widenedForTest() throws -> CoreLossSpectrumImage {
        try CoreLossSpectrumImage(nx: nx, ny: ny, channels: channels, counts: storedCounts.doubles,
                                  energyOffsetEV: energyOffsetEV, energyScaleEV: energyScaleEV)
    }
}
