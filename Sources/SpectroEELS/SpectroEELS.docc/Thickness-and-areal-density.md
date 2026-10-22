# Thickness and areal density

Measure t/λ from a low-loss spectrum image, then the areal density of an edge from a core-loss image and the low-loss intensity.

## Overview

Two measurements, two entry points. ``EELSThickness/logRatio(_:threshold:zeroLoss:meanFreePath:cancelled:progress:)`` gives t/λ
per pixel as ln(I_t / I₀). ``EELSEdgeQuantification/ratioMethod(coreLoss:edge:microscope:lowLoss:backgroundWindowEV:edgeOnsetEV:integrationWidthEV:coreLossToLowLossDose:cancelled:)``
gives the areal density n in atoms per nm². Both follow exSpy 7185a4d1, the pinned reference; both report `validation: "none"`.

## Thickness from the low-loss spectrum

A ``LowLossSpectrumImage`` holds counts per channel, with the zero-loss peak at 0 eV. Its counts are laid out `(y * nx + x) * channels + c`,
and channel `c` sits at `energyOffsetEV + energyScaleEV * c`.

```swift
import SpectroEELS

func thickness(of low: LowLossSpectrumImage) throws -> ThicknessMap {
    try EELSThickness.logRatio(low, threshold: .estimated(), meanFreePath: .given(100))   // nm; the caller's value
}
```

The threshold cuts I₀, the zero-loss sum, and it is the choice that matters most. ``ThresholdRule`` has three cases:

- ``ThresholdRule/estimated(window:start:windowLength:polynomialOrder:tolerance:)`` is exSpy's first inflexion of the Savitzky–Golay
  derivative. On noisy data it is not stable, because one noisy pixel can set the tolerance for every pixel; use a fixed value.
- ``ThresholdRule/fixed(_:)`` is one threshold in eV for every pixel. `.fixed(3)` is 3.0 eV.
- ``ThresholdRule/perPixel(_:)`` is one threshold per pixel, row-major; NaN marks a pixel with none.

Read a pixel with `map[x, y]`. A pixel the method cannot answer has `nil` values and a reason, not a throw:

```swift
func report(_ map: ThicknessMap, x: Int, y: Int) {
    let pixel = map[x, y]
    if let tOverLambda = pixel.tOverLambda {
        print("t/lambda = \(tOverLambda)")
    }
    if let thickness = pixel.thicknessNM {
        print("t = \(thickness) nm")    // only with a mean free path
    }
    if let why = pixel.unavailable {
        print("no t/lambda: \(why)")
    }
}
```

A mean free path comes from ``MeanFreePathSource``: ``MeanFreePathSource/given(_:)`` takes nanometres as given, and
``MeanFreePathSource/iakoubovskii(density:beamEnergyKeV:convergenceMrad:collectionMrad:)`` derives it from the density with the
angular correction. Without one, the map gives t/λ only. ``ThicknessMap/validation`` stays `"none"`.

## Areal density of an edge

The areal density of an edge needs three things: the core-loss spectrum image, the low-loss intensity that corrects for plural
scattering, and the microscope's parameters.

```swift
func arealDensity(core counts: [Double], nx: Int, ny: Int, channels: Int,
                  offsetEV: Double, scaleEV: Double, lowLoss: LowLossIntensity) throws -> ArealDensityMap {
    let core = try CoreLossSpectrumImage(nx: nx, ny: ny, channels: channels, counts: counts,
                                         energyOffsetEV: offsetEV, energyScaleEV: scaleEV)
    let microscope = EELSMicroscope(beamEnergyKeV: 200,        // the acquisition's values
                                    convergenceMrad: 0,
                                    collectionMrad: 10)
    return try EELSEdgeQuantification.ratioMethod(coreLoss: core, edge: .carbonK,
                                                  microscope: microscope, lowLoss: lowLoss)
}
```

The edge is one of ``CoreLossEdge/bundled``: 20 edges: K of C, N, O, Mg, Al, Si (``CoreLossEdge/carbonK``, ``CoreLossEdge/nitrogenK``, ``CoreLossEdge/oxygenK``, …) and the L edges of Mg, Al, Si, Fe and Cu.
Where I_low comes from is a ``LowLossIntensity``:

- ``LowLossIntensity/integratedToWidth(_:)`` integrates the low-loss counts to Δ eV past the zero loss (Egerton eq. 4.66, the
  plural-scattering correction). This is the default route. Its own bias is large at small Δ in thicker areas, so use a wide Δ
  where the data allow.
- ``LowLossIntensity/zeroLoss(_:)`` takes I₀ from a thickness map, for single scattering only.

The background is a power law fitted in ``EELSEdgeQuantification/defaultBackgroundWindow(onsetEV:)`` (E_k − 50 to E_k − 5 eV by
default); the edge is integrated over `integrationWidthEV` (50 eV by default). Each pixel gives an ``ArealDensityPixel`` in
row-major order:

```swift
func report(_ map: ArealDensityMap, x: Int, y: Int) {
    let pixel = map.pixels[y * map.nx + x]
    if let n = pixel.atomsPerNM2, let sigma = pixel.sigmaCounting {
        print("n = \(n) +- \(sigma) atoms/nm^2 (counting statistics only)")
    }
    if let why = pixel.unavailable {
        print("no areal density: \(why)")
    }
    if let caveat = map.caveat {
        print(caveat)    // N K and O K sit on a preceding edge's tail
    }
}
```

``ArealDensityPixel/sigmaCounting`` is counting statistics only. It leaves out the model, the cross section, the angle, the dose
ratio and the onset; where it is large against n the estimate is no longer near-Gaussian.

## Cancellation and errors

Both calls take a `cancelled` closure, which defaults to `SpectroCancellation.task`, and throw `SpectroCancelled` with nothing
kept. Inputs the method cannot start from throw ``EELSThicknessError`` or ``EELSEdgeError``; a pixel it cannot answer is a `nil`
with a reason.

## What is and is not validated

Both maps say `validation: "none"`. Agreement with exSpy is not validation, and recovery of a planted t/λ is not either. The
C, N and O K cross sections are the dft generalised oscillator strengths of Segger, Guzzinati and Kohl (table version 1.5.0), bundled as
resources of this module under CC-BY-4.0 (see the repository's NOTICE).
