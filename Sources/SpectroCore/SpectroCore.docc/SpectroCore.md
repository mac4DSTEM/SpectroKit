# ``SpectroCore``

The shared part of SpectroKit: the spectrum image and how a file becomes one, the energy axis, counting statistics and the
cancellation contract every long call follows. The X-ray and EELS modules build on it; it depends on neither. The file readers
are FormatoKit's (`FormatoDM` and `FormatoEMD`), so opening a Velox EMD or a GMS DM4 needs no setup beyond the package.

## Overview

A spectrum image is a raster of `ny` by `nx` pixels, each with `channels` counts. ``SpectrumImageOpener`` turns a file into a
``LoadedSpectrumImage``, which carries the image, its ``SpectrumImageMetadata``, its ``EnergyAxis`` and, when the file has one,
the scan image. Sums over pixels, with an optional ``PixelMask``, are exact integers.

Read <doc:Opening-a-spectrum-image> for the walk from a file to a spectrum.

## Topics

### Guides

- <doc:Opening-a-spectrum-image>

### Opening a file

- ``SpectrumImageOpener``
- ``SpectrumFileKind``
- ``SpectrumImageOpenError``

### The spectrum image

- ``SpectrumImage``
- ``SpectrumImageSource``
- ``LoadedSpectrumImage``
- ``DenseSpectrumImage``
- ``PixelMask``

### Metadata

- ``SpectrumImageMetadata``
- ``SpectrumDetectorSegment``
- ``SpectrumImageOrigin``
- ``BeamEnergy``
- ``BeamEnergySource``

### The energy axis

- ``EnergyAxis``
- ``EnergyAxisError``

### Statistics and maps

- ``Currie``
- ``MapSmoothing``

### Cancellation

- ``SpectroCancellation``
- ``SpectroCancelled``
