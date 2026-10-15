# ``SpectroEELS``

EELS on top of SpectroCore: the thickness of a specimen from its low-loss spectrum (t/λ by the log-ratio method, and the
thickness in nanometres when a mean free path is given), and the areal density of an edge (the C, N and O K shells) by the
ratio method. A port of exSpy's EELS path; agreement with exSpy is not validation, so every value it reports is marked
unvalidated.

## Overview

The thickness map needs a low-loss spectrum image, a way to find the zero-loss intensity I₀, and optionally a mean free path.
The areal density needs a core-loss spectrum image and a low-loss intensity. ``EELSThickness`` and ``EELSEdgeQuantification``
are the two entry points; each returns a per-pixel result that says, for any pixel it cannot answer, why not.

Read <doc:Thickness-and-areal-density> for how the two fit together.

## Topics

### Guides

- <doc:Thickness-and-areal-density>

### Thickness from the low-loss spectrum

- ``EELSThickness``
- ``LowLossSpectrumImage``
- ``ThresholdRule``
- ``ThicknessMap``
- ``ThicknessPixel``
- ``ZeroLossSource``
- ``ThicknessUnavailable``
- ``SigmaUnavailable``
- ``EELSThicknessError``

### Mean free path

- ``InelasticMeanFreePath``
- ``MeanFreePathSource``

### Areal density of an edge

- ``EELSEdgeQuantification``
- ``CoreLossSpectrumImage``
- ``CoreLossEdge``
- ``EELSMicroscope``
- ``LowLossIntensity``
- ``ArealDensityMap``
- ``ArealDensityPixel``
- ``EdgeUnavailable``
- ``EELSEdgeError``
