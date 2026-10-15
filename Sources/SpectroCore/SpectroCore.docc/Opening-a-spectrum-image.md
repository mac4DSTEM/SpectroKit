# Opening a spectrum image

Turn a file into a spectrum image, read its energy axis, sum it over a region, and stop a long call cleanly.

## Overview

Opening takes two steps: ask what the file is, then open it as that kind. The first is cheap: for a DM4 it walks the file's
tags and seeks past every data blob, for an EMD it opens the HDF5 file once. The readers are FormatoKit's (`FormatoEMD` for
Velox, `FormatoDM` for GMS); a consumer imports SpectroCore and gets them through the package.

## Ask what the file is, then open it

``SpectrumImageOpener/kind(ofFileAt:)`` returns a ``SpectrumFileKind``: ``SpectrumFileKind/veloxSpectrumImage`` (an EMD with a
spectrum stream), ``SpectrumFileKind/gmsEDSOnly`` (a DM4 with an EDS image and no diffraction stack), or
``SpectrumFileKind/other``. Opening `.other` throws ``SpectrumImageOpenError/notASpectrumImage(_:)``.

```swift
import SpectroCore

func openSpectrumImage(at path: String) throws -> LoadedSpectrumImage {
    let kind = SpectrumImageOpener.kind(ofFileAt: path)
    guard kind != .other else { throw SpectrumImageOpenError.notASpectrumImage(path) }
    return try SpectrumImageOpener.open(path: path, kind: kind,
                                        progress: { fraction in print("open: \(fraction)") })  // monotone, ends at 1
}
```

## Read the image and its axis

A ``LoadedSpectrumImage`` holds the image (``SpectrumImage``), its ``SpectrumImageMetadata`` and its ``EnergyAxis``.

- `nx`, `ny` and `channels` give the shape. Pixel `(x, y)` is index `y * nx + x`.
- ``EnergyAxis/energy(ofChannel:)`` maps a channel to keV: `offset + scale * channel`.
- ``LoadedSpectrumImage/scanImage`` is the HAADF or best scan image on the spectrum grid, when the file has one.
- ``LoadedSpectrumImage/metadata`` carries the beam energy, detectors, tilts and scan pixel size the file stated.

## Sum over a region

``LoadedSpectrumImage/sum(mask:)`` returns the exact spectrum summed over the masked pixels, one `UInt64` per channel. A `nil`
``PixelMask`` sums every pixel. A mask holds one `Bool` per pixel (`true` = in the sum) and must have `nx * ny` entries; a
wrong length is a programming error.

```swift
func regionSpectrum(_ image: LoadedSpectrumImage, inside: PixelMask) -> [UInt64] {
    precondition(inside.count == image.nx * image.ny, "a mask has one entry per pixel")
    return image.sum(mask: inside)
}
```

## Cancel a long call

Long calls take a `cancelled` closure and an optional `progress` closure. The default `cancelled` is
``SpectroCancellation/task``, so a call inside a Swift task stops when that task is cancelled. The check runs at a step or block
boundary, never per value, and the call throws ``SpectroCancelled`` with nothing partial kept.

```swift
func openCancellable(_ path: String) async throws -> LoadedSpectrumImage? {
    let task = Task {
        try SpectrumImageOpener.open(path: path, kind: SpectrumImageOpener.kind(ofFileAt: path))
    }
    // Elsewhere, for example when the user closes the window: task.cancel()
    do {
        return try await task.value
    } catch is SpectroCancelled {
        return nil   // nothing was kept
    }
}
```

`SpectroCancelled` is FormatoKit's `FormatoCancelled` under a SpectroKit name, so a reader's cancellation is caught by the same
clause.

## Next

- SpectroEDX's guide, "Quantifying an EDX spectrum", takes the summed spectrum and its axis to the X-ray half.
- SpectroEELS's guide, "Thickness and areal density", takes EELS spectrum images.
