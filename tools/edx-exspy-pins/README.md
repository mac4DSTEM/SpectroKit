# tools/edx-exspy-pins: exSpy's EDX answers for SpectroEDX

exSpy 7185a4d1 (the checkout `tools/reference/setup.sh` puts in `References/exspy-7185a4d1`, first on `PYTHONPATH`) and HyperSpy 2.4.0:

| script | writes `Tests/SpectroCoreTests/Fixtures/` | reproduces |
|---|---|---|
| `pins.py` | `eds-pins-exspy-7185a4d1.json`: example spectra, windows, intensities, FWHM, index vectors | byte for byte |
| `quant_pins.py` | `eds-quant-pins-exspy-7185a4d1.json`: `quantification` (Cliff-Lorimer, zeta, with and without absorption) | byte for byte |
| `fit_pins.py` | `eds-fit-exspy-7185a4d1.json`: `EDSModel` fits (FePt, closed loop) and SciPy NNLS references | 25 values differ in the last bit (3e-16 relative, BLAS order) |

Run as `PYTHONPATH=References/exspy-7185a4d1 References/python/bin/python -B tools/edx-exspy-pins/<script>.py <out.json>`.
