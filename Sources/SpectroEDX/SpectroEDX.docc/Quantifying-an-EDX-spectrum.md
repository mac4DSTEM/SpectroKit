# Quantifying an EDX spectrum

Propose the elements a summed spectrum shows, fit them, and read net areas and composition with their sigmas.

## Overview

Quantification has four steps, each a public call: sum the spectrum (SpectroCore), propose the elements it shows, record the
choices in a ``QuantificationMethod``, and run the fit. The composition is reported with its sigma and its unvalidated status;
read the result's ``PooledQuantification/abundanceValidation`` before you call a number anything more.

## Propose the elements

``FitSettings/standard(elements:axis:resolutionMnKaEV:beamEnergy:efficiency:)`` gives the default fit: a continuum with the Al K
step from 0.2 keV to the end of the fitted range, escape peaks on, unweighted least squares. ``ElementProposer`` then tests the
line table's elements against the spectrum and returns a ``ProposalResult``.

```swift
import SpectroCore
import SpectroEDX

func proposeElements(counts: [UInt64], axis: EnergyAxis, beamEnergyKeV: Double) throws -> ProposalResult {
    let settings = FitSettings.standard(elements: [], axis: axis,
                                        resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV,
                                        beamEnergy: beamEnergyKeV)
    return try ElementProposer().propose(counts: counts.map { Double($0) }, axis: axis, settings: settings)
}
```

- ``ProposalResult/proposed`` lists the elements the proposer kept, each an ``ElementCandidate`` with its net counts and sigma.
- ``ProposalResult/refused`` and ``ProposalResult/notes`` say which elements were not tested and why, in plain words.
- The proposer throws ``ProposerError/cancelled`` when its task is cancelled. It keeps its own error rather than
  `SpectroCancelled`, and it returns nothing partial.

## Record the method

A ``QuantificationMethod`` holds every choice the number depends on: the estimator, the background, the k-factor source, the
absorption correction, the elements and their roles. Its defaults are the registered ones.

```swift
func method(for elements: [String], beamEnergyKeV: Double?) -> QuantificationMethod {
    var method = QuantificationMethod()
    method.elements = elements.map {
        QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false)
    }
    method.beamEnergyKeV = beamEnergyKeV   // only when the file does not state one
    return method
}
```

``QuantificationMethod/canonicalJSON`` and ``QuantificationMethod/hash`` identify the method, so a saved result can say what
produced it.

## Run the quantification

``PooledQuantifier/run(_:tables:cancelled:progress:)`` takes a ``PooledQuantificationInput`` and the bundled tables. The tables
are SpectroEDX's own resources; ``QuantificationTables/bundled(in:)`` returns `nil` when they are missing.

```swift
func quantify(_ image: LoadedSpectrumImage, counts: [UInt64], elements: [String],
              beamEnergyKeV: Double) throws -> PooledQuantification {
    let input = PooledQuantificationInput(
        counts: counts,
        axis: image.energyAxis,
        method: method(for: elements, beamEnergyKeV: beamEnergyKeV),
        metadata: image.metadata,
        regionName: "whole image",
        pixelCount: image.nx * image.ny)
    return try PooledQuantifier.run(input, tables: QuantificationTables.bundled())
}
```

A cancelled run throws `SpectroCancelled` with nothing returned. A run that cannot start (no beam energy in the file or typed,
no element switched on, an empty region) throws an error whose description gives the reason. An at% it cannot give, for example
with fewer than two quantified elements, does not throw: the reason is in ``PooledQuantification/abundanceRefusal`` and the net
areas are still there.

## Read the result

```swift
func report(_ result: PooledQuantification) {
    for row in result.rows {
        let at = row.atomicPercent.map { String(format: "%.2f", $0) } ?? "-"
        print("\(row.element)  net \(row.net) +- \(row.sigma)  at% \(at)  bound \(row.atBound)")
    }
    print(result.qualityText)                          // chi-squared or deviance, beside the at%
    print(result.footerLines.joined(separator: "\n"))  // one line per setting that shaped the number
}
```

- ``PooledQuantification/Row/net`` is the fitted area of the element's alpha line, in counts; `atBound` marks an upper limit.
- ``PooledQuantification/Row/atomicPercent`` and ``PooledQuantification/Row/atomicSigma`` are present only when at% was computed.
- ``PooledQuantification/absorption`` says whether the absorption correction applied or was refused, and why.

## What is and is not validated

``PooledQuantification/abundanceValidation`` is `"none"`. The k-factors (Bote-Salvat cross sections, Krause fluorescence yields,
the EPQ detector efficiency) are unvalidated too. Agreement with exSpy is not validation: a composition is called validated only
after it recovers a planted value and a sample of known composition.

The numbers follow exSpy 7185a4d1, the pinned reference. A departure from it is named in the source and in the result's footer.
