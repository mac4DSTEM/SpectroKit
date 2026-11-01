# tools/edx-sim: synthetic EDX spectra from a physical forward model

`forward.py` (absorption through four detector segments, escape, sum and tail peaks, Si internal fluorescence, an optional
detector Si dead layer `dead_layer_um`, default 0 = none) over
`xray_model.py` (lines, continuum, detector efficiency) writes the expected, noise-free pooled spectra the EDX tests draw
Poisson counts from. NumPy only; the FFAST mass absorption table is SpectroEDX's own resource.

| script | writes `Tests/SpectroEDXTests/Fixtures/` |
|---|---|
| `proposer_sim.py` | `eds-proposer-sim.json` |
| `weakline_sim.py` | `eds-weakline-sim.json` |
| `absorption_truth_sim.py` | `eds-absorption-truth.json` |
| `dead_layer_sim.py` | `eds-dead-layer-truth.json` (the same pool through a detector Si dead layer of 0.3 µm) |
| `realistic_l_sim.py` (standard library only) | `eds-realistic-l-sim.json` |
| `unlisted_sim.py` (standard library only) | `eds-unlisted-sim.json` |

Run each as `EDX_SIM_KBETA=exspy References/python/bin/python -I -B tools/edx-sim/<script>.py <out.json>` (`tools/reference/setup.sh`
first) to reproduce the committed fixture; without `EDX_SIM_KBETA` the K-beta lines are planted at EPQ's weights (below).

K-beta lines: `xray_model.py` plants each K-beta at the weight of one table, chosen with the environment variable `EDX_SIM_KBETA`:
`epq` (the default, the physical NIST EPQ weights from SpectroEDX's `LineWeights.csv`: Kβ/Kα Al 0.0315, Mg 0.0174, Si 0.0571,
Cu 0.146) or `exspy` (eXSpy's `xray_lines.json`: Al 0.0132, Mg 0.01, Si 0.0278, Cu 0.132). The committed fixtures were generated
with eXSpy's table, the one the default fit ties (`FitPolicy.lineWeights`, default `.exspy`); with `EDX_SIM_KBETA=exspy` every
output above is byte-identical to its committed fixture (checked 2026-10-31 for the weak-line and absorption-truth pools;
2026-10-28 for all). A fixture planted at the EPQ weights is fitted with `FitPolicy(lineWeights: .epq)` to be self-consistent.
`realistic_l_sim.py` and `unlisted_sim.py` keep their own line lists. The demo pools (`demo_pools.py`) are planted by the demo
set's own generator at eXSpy's weights; `LineWeightTableTests` re-plants their K-beta at EPQ's in memory.
