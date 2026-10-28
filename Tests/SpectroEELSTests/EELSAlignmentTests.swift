//
//  EELSAlignmentTests.swift
//  Role: Refusals and shapes for every error case, rules derived by
//        hand (linear shifts of a ramp are exact, the crop indices, the mask width, floor and ceil value2index), and the planted truth
//        (the planted zero-loss shifts are recovered). The pins against exSpy are SpectroKitParityTests/AlignPinsTests.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS
import SpectroCore

struct EELSAlignmentTests {

    private func ramp(pixels: Int = 2, channels: Int = 20, offset: Double = 0, scale: Double = 1) throws -> LowLossSpectrumImage {
        // value = 3 + 2 * channel + pixel: linear in the channel, so a linear shift is exact (also its linear extrapolation)
        var counts = [Double]()
        for p in 0..<pixels { for c in 0..<channels { counts.append(3 + 2 * Double(c) + Double(p)) } }
        return try LowLossSpectrumImage(nx: pixels, ny: 1, channels: channels, counts: counts, energyOffsetEV: offset, energyScaleEV: scale)
    }

    // MARK: shift

    /// Linear interpolation at `axis - shift` of a linear signal is the line itself: value(x - s) = 3 + 2 (c - s/scale), extrapolation included.
    @Test func testShiftOfARampIsExactAndLinearlyExtrapolated() throws {
        let image = try ramp(pixels: 1, channels: 20, offset: 10, scale: 0.5)
        let (out, kept) = try EELSAlignment.shift(image, byEV: [0.75], crop: false)
        #expect(kept == 0..<20)
        for c in 0..<20 { #expect(isEqual(out.counts[c], 3 + 2 * (Double(c) - 1.5), accuracy: 1e-12), "channel \(c)") }
    }

    /// A positive shift of 1.6 channels (0.8 eV at 0.5): ilow = ceil(offset + 0.8 -> channel 1.6) = 2; ihigh stays 20; a negative one cuts the top.
    @Test func testCropKeepsTheChannelsEveryShiftLeavesDefined() throws {
        let image = try ramp(pixels: 3, channels: 20, offset: 10, scale: 0.5)
        let up = try EELSAlignment.shift(image, byEV: [0, 0.8, 0.1], crop: true)
        #expect(up.keptChannels == 2..<20)
        #expect(up.image.channels == 18)
        #expect(isEqual(up.image.energyOffsetEV, 11.0, accuracy: 1e-12))
        let down = try EELSAlignment.shift(image, byEV: [0, -0.8, 0.1], crop: true)
        // high value 19.5, minus 0.8 -> 18.7: floor((18.7 - 10) / 0.5) = 17, ihigh = 18; the 0.1 eV positive shift gives ilow = ceil(0.2) = 1
        #expect(down.keptChannels == 1..<18)
        // zero and nil shifts leave a pixel alone
        let same = try EELSAlignment.shift(image, byEV: [nil, 0, nil], crop: true)
        #expect(same.image.counts == image.counts)
        #expect(same.keptChannels == 0..<20)
    }

    @Test func testShiftRefusals() throws {
        let image = try ramp()
        #expect(throws: EELSAlignmentError.shiftCountMismatch(expected: 2, got: 3)) { try EELSAlignment.shift(image, byEV: [0, 0, 0]) }
        #expect(throws: EELSAlignmentError.nonFiniteShift(pixel: 1)) { try EELSAlignment.shift(image, byEV: [0, .infinity]) }
        // a shift larger than the axis leaves nothing
        #expect(throws: EELSAlignmentError.emptyAfterCrop) { try EELSAlignment.shift(image, byEV: [30, 0], crop: true) }
    }

    // MARK: axis rounding

    @Test func testValue2IndexFloorAndCeilTruncateAtOneEMinusTwelveChannels() throws {
        let axis = try EELSAxis(offset: 5.0, scale: 0.5, size: 40)
        #expect(axis.channel(ofEnergy: 6.6, rounding: .up) == 4)        // 3.2 channels -> 4
        #expect(axis.channel(ofEnergy: 6.6, rounding: .down) == 3)
        #expect(axis.channel(ofEnergy: 6.5, rounding: .up) == 3)        // exactly 3 -> 3, not 4
        #expect(axis.channel(ofEnergy: 6.5 + 1e-13, rounding: .up) == 3, "below the 1e-12-channel truncation, a tie stays a tie")
        #expect(axis.channel(ofEnergy: 4.9, rounding: .up) == 0, "ceil(-0.2) is -0, which HyperSpy takes as channel 0")
        #expect(axis.channel(ofEnergy: 4.4, rounding: .up) == nil, "ceil(-1.2) is -1: below the axis HyperSpy raises")
        #expect(axis.channel(ofEnergy: 25.0, rounding: .down) == nil)
        #expect(axis.channel(ofEnergy: .nan, rounding: .up) == nil)
    }

    // MARK: centre and mask

    @Test func testCentreIsTheFirstMaximumAndMaskedPixelsAreNil() throws {
        // two equal maxima: the first wins (NumPy argmax); pixel 1 is masked
        let counts: [Double] = [1, 5, 5, 2,   9, 9, 9, 9,   0, 0, 7, 0]
        let image = try LowLossSpectrumImage(nx: 3, ny: 1, channels: 4, counts: counts, energyOffsetEV: -1, energyScaleEV: 0.5)
        let centres = try EELSAlignment.zeroLossPeakCentre(image, mask: [false, true, false])
        #expect(centres[0] == -0.5)
        #expect(centres[1] == nil)
        #expect(centres[2] == 0.0)
        #expect(throws: EELSAlignmentError.maskShapeMismatch(expected: 3, got: 2)) { try EELSAlignment.zeroLossPeakCentre(image, mask: [false, true]) }
    }

    @Test func testSignalRangeRestrictsTheSearch() throws {
        // a spike larger than the peak at -1.0 eV; searching (-0.5, 1.0) finds the real peak at 0.5
        let counts: [Double] = [50, 1, 1, 9, 2, 1]
        let image = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 6, counts: counts, energyOffsetEV: -1, energyScaleEV: 0.5)
        #expect(try EELSAlignment.zeroLossPeakCentre(image)[0] == -1.0)
        #expect(try EELSAlignment.zeroLossPeakCentre(image, signalRangeEV: -0.5...1.0)[0] == 0.5)
        #expect(throws: EELSAlignmentError.self) { try EELSAlignment.zeroLossPeakCentre(image, signalRangeEV: 9...10) }
    }

    /// width 2 around the mean centre: the channels with |e - mean| <= 1 are true, edges included; the signal mask is OR-ed.
    @Test func testZeroLossPeakMaskWidthAndSignalMask() throws {
        let counts: [Double] = [0, 0, 0, 9, 0, 0, 0, 0, 0, 0]        // centre at channel 3 -> 1.0 eV (offset -0.5, scale 0.5)
        let image = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 10, counts: counts, energyOffsetEV: -0.5, energyScaleEV: 0.5)
        let mask = try EELSAlignment.zeroLossPeakMask(image, widthEV: 2.0)
        #expect(mask == [false, true, true, true, true, true, false, false, false, false], "0 <= e <= 2 eV: channels at 0, 0.5, 1, 1.5 and 2.0")
        var signal = [Bool](repeating: false, count: 10); signal[9] = true
        #expect(try EELSAlignment.zeroLossPeakMask(image, widthEV: 2.0, signalMask: signal)[9])
        #expect(throws: EELSAlignmentError.maskShapeMismatch(expected: 10, got: 3)) { try EELSAlignment.zeroLossPeakMask(image, signalMask: [true, false, true]) }
    }

    // MARK: alignment

    @Test func testAlignmentRefusals() throws {
        let image = try Eels16.lowLoss()
        #expect(throws: EELSAlignmentError.maskShapeMismatch(expected: 12, got: 5)) { try EELSAlignment.alignZeroLossPeak(image, mask: [Bool](repeating: false, count: 5)) }
        let wrong = try CoreLossSpectrumImage(nx: 2, ny: 2, channels: 10, counts: [Double](repeating: 1, count: 40), energyOffsetEV: 100, energyScaleEV: 0.5)
        #expect(throws: EELSAlignmentError.alsoAlignShapeMismatch(index: 0)) { try EELSAlignment.alignZeroLossPeak(image, alsoAlign: [wrong]) }
        #expect(throws: EELSAlignmentError.self) { try EELSAlignment.alignZeroLossPeak(image, options: ZeroLossAlignmentOptions(interpolationPoints: -1)) }
        #expect(throws: EELSAlignmentError.signalRangeOutsideAxis(fromEV: 200, toEV: 210)) {
            try EELSAlignment.alignZeroLossPeak(image, options: ZeroLossAlignmentOptions(signalRangeEV: 200...210))
        }
    }

    @Test func testAnAllMaskedImageIsReturnedUnchanged() throws {
        let image = try Eels16.lowLoss()
        let result = try EELSAlignment.alignZeroLossPeak(image, mask: [Bool](repeating: true, count: 12))
        #expect(result.aligned.counts == image.counts)
        #expect(result.shiftEV.allSatisfy { $0 == nil })
        #expect(result.keptChannels == 0..<600)
    }

    /// PLANTED TRUTH (tools/eels-task16/pins.py: the ZLP of pixel p is planted at CENTRES[p], none on a channel): after alignment every pixel's
    /// zero-loss peak is at the same place within a tenth of a channel (subpixel: the cross-correlation refines to 1/6 channel), the total shift
    /// differences recover the planted centre differences within a quarter channel (0.025 eV: the correlation is quantised to 1/(points + 1) channel and linear upsampling biases a Gaussian's peak; the pins show the port reproduces exSpy's own shifts to 1e-9 eV, so this is exSpy's accuracy on this set; the coarse step alone is within half a channel, 0.05 eV), and with `calibrate` the common peak sits within a channel of 0 eV.
    @Test func testPlantedShiftsAreRecovered() throws {
        let image = try Eels16.lowLoss()
        let truth = Eels16.flat(Eels16.dict("zlp", "truth")["zlpCentreEV"])
        let result = try EELSAlignment.alignZeroLossPeak(image)
        let shifts = result.shiftEV.map { $0! }
        for p in 1..<12 {
            let planted = truth[0] - truth[p]
            #expect(abs((shifts[p] - shifts[0]) - planted) <= 0.025, "pixel \(p): shift difference \(shifts[p] - shifts[0]) vs planted \(planted), truth \(truth[p]) \(truth[0])")
        }
        // the coarse step puts every maximum on the same CHANNEL: the re-estimated centres of the aligned image are equal
        let centres = try EELSAlignment.zeroLossPeakCentre(result.aligned).compactMap { $0 }
        #expect(centres.max()! - centres.min()! <= 1e-9)
        #expect(abs(centres[0]) <= 0.1 + 1e-9, "calibrate: the common peak is within a channel of 0 eV")
        // the diagnostic: the initial centres are the channel nearest each planted centre
        for p in 0..<12 { #expect(abs(result.initialCentreEV[p]! - truth[p]) <= 0.05 + 1e-9) }
    }

    @Test func testMaskedPixelsAreNotShiftedAndReportNil() throws {
        let image = try Eels16.lowLoss()
        let result = try EELSAlignment.alignZeroLossPeak(image, mask: Eels16.alignMask)
        #expect(result.shiftEV[1] == nil && result.shiftEV[10] == nil)
        #expect(result.initialCentreEV[1] == nil)
        #expect(result.shiftEV[0] != nil)
    }

    /// The mean centre is NumPy's nanmean (pairwise sum, 8 accumulators from 8 elements): the coarse shift of each pixel is bit-for-bit
    /// `-z + mean` with that mean. (HyperSpy's shifts of pixels near the mean are tiny non-zero numbers for the same reason; a left-to-right sum
    /// gives another mean in the last bit, and a crop index that sits on an integer number of channels can then move by one.)
    @Test func testTheMeanCentreIsSummedLikeNumPy() throws {
        var counts = [Double]()
        let channelOfPeak = (0..<37).map { 8 + (($0 * 7) % 11) }                    // irregular centres, 37 pixels
        for c in channelOfPeak { counts += (0..<60).map { $0 == c ? 100 : 1 } }
        let image = try LowLossSpectrumImage(nx: 37, ny: 1, channels: 60, counts: counts, energyOffsetEV: -1.3, energyScaleEV: 0.07)
        let result = try EELSAlignment.alignZeroLossPeak(image, options: ZeroLossAlignmentOptions(calibrate: false, subpixel: false, crop: false))
        let z = try EELSAlignment.zeroLossPeakCentre(image).map { $0! }
        let mean = z.withUnsafeBufferPointer { NumpySum.pairwise($0.baseAddress!, count: $0.count) } / Double(z.count)
        for p in 0..<37 { #expect(result.shiftEV[p] == -z[p] + mean, "pixel \(p)") }
    }

    @Test func testInterpolationPointsAreBounded() throws {
        let image = try Eels16.lowLoss()
        #expect(throws: EELSAlignmentError.self) { try EELSAlignment.alignZeroLossPeak(image, options: ZeroLossAlignmentOptions(interpolationPoints: Int.max)) }
        #expect(throws: EELSAlignmentError.self) { try EELSAlignment.estimateShift(image, fromEV: -3, toEV: 3, interpolationPoints: 1001) }
    }

    @Test func testAlsoAlignedImagesReportTheirOwnKeptChannels() throws {
        let image = try Eels16.lowLoss()
        let core = try Eels16.coreLoss()
        let result = try EELSAlignment.alignZeroLossPeak(image, alsoAlign: [core])
        #expect(result.alsoKeptChannels.count == 1)
        #expect(result.alsoKeptChannels[0].count == result.alsoAligned[0].channels)
        #expect(result.keptChannels.count == result.aligned.channels)
    }
}
