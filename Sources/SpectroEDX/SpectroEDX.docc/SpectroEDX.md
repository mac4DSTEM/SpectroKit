# ``SpectroEDX``

X-ray spectroscopy on top of SpectroCore: the line table, the continuum and EDS fit models, the element proposer that decides
which elements a spectrum shows, and the pooled quantification that turns net areas into composition. A Swift port of exSpy's
EDS path; agreement with exSpy is not validation, so every composition it reports is marked as unvalidated.

## Overview

A quantification starts from a summed spectrum and its `EnergyAxis` (SpectroCore). ``ElementProposer`` proposes the elements
the spectrum shows; ``PooledQuantifier`` fits them and returns net areas, their sigmas and, when a k-factor source exists, atomic
and weight percent. ``QuantificationMethod`` records every choice the number depends on, with a canonical JSON and a hash, so a
result can say what produced it.

Read <doc:Quantifying-an-EDX-spectrum> for the walk from a summed spectrum to a composition.

## Topics

### Guides

- <doc:Quantifying-an-EDX-spectrum>

### Quantifying a spectrum

- ``PooledQuantifier``
- ``PooledQuantificationInput``
- ``PooledQuantification``
- ``QuantificationMethod``
- ``QuantificationTables``
- ``QuantError``
- ``SpectroscopyExport``

### Proposing elements

- ``ElementProposer``
- ``ProposalResult``
- ``ElementCandidate``
- ``ProposalRules``
- ``RuledProposal``
- ``LineConflict``
- ``LineConflicts``
- ``ProposerError``

### Fitting the spectrum

- ``FitSettings``
- ``EDSFitResult``
- ``EDSFitError``
- ``EDSLineModel``
- ``FitLineGroup``
- ``FitBackground``
- ``ContinuumForm``
- ``AxisRefinementResult``
- ``DetectorEfficiency``

### Fit range and unlisted lines

- ``FitRangeChoice``
- ``FitRangeSensitivity``
- ``FitRangeSensitivityCheck``
- ``UnlistedLineChecker``
- ``UnlistedLineCheck``

### X-ray lines and windows

- ``XRayLines``
- ``XRayLine``
- ``XRayFamily``
- ``ElementWindows``
- ``LineWindow``
- ``LineNetCount``
- ``ResolvedWindow``
- ``WindowConflict``
- ``SpectralLineError``
- ``SpectrumRegionShape``
- ``PixelRect``
- ``PixelPoint``
