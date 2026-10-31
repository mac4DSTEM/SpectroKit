# Test fixtures

One row per committed fixture under `Tests/*/Fixtures/` (304 files): its size and what writes it. Written by
`tools/fixtures/inventory.py`; do not edit by hand. Generators run in the Python reference `tools/reference/setup.sh` builds
(`References/python`), from the repo root, as each script's header says.

Licence: every fixture is generated from this kit's code and its pinned Python reference and ships under the kit's
GPL-3.0-only licence, except the 7 rows marked *third party*: keep their licence line when the files move. No
fixture holds anyone's measured data; real datasets are read from `$MACEM_DATA` and never copied into the repo.

A moved fixture is its own commit with the reason and a CHANGELOG line.

| File | Size | Written by | Note |
|---|---|---|---|
| `SpectroCoreTests/Fixtures/demo-edx-tiny.dm4` | 122.8 KB | mac4DSTEM's tools/demo-edx/sim_edx.py --tiny --seed 42 (mac4DSTEM history before 7a0f727f) | frozen input: the generator needs mac4DSTEM's 4D reflection export, so it is not carried here |
| `SpectroCoreTests/Fixtures/demo-edx-tiny.truth.json` | 371.0 KB | mac4DSTEM's tools/demo-edx/sim_edx.py --tiny --seed 42 (mac4DSTEM history before 7a0f727f) | frozen input: the generator needs mac4DSTEM's 4D reflection export, so it is not carried here |
| `SpectroCoreTests/Fixtures/qshape3.mac4dstem.h5` | 10.8 KB | copied from mac4DSTEM's test fixtures at extraction (commit 5ba712a0) | any non-EDS HDF5 file serves: the test only checks the sniff calls it `.other` |
| `SpectroCoreTests/Fixtures/registration-pins.json` | 39.1 KB | `tools/registration/pins.py` |  |
| `SpectroCoreTests/Fixtures/spectro-golden/demo-edx-tiny-dm4.arrays.f64` | 42.8 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/demo-edx-tiny-dm4.arrays.json` | 3.5 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/demo-edx-tiny-dm4.txt` | 66.4 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/demo-spectrum-fixture.txt` | 95.3 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-proposer-sim.arrays.f64` | 95.4 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-proposer-sim.arrays.json` | 2.0 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-proposer-sim.txt` | 42.6 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-realistic-l-sim.arrays.f64` | 319.6 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-realistic-l-sim.arrays.json` | 7.7 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-realistic-l-sim.txt` | 153.7 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-unlisted-sim.arrays.f64` | 181.3 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-unlisted-sim.arrays.json` | 9.3 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-unlisted-sim.txt` | 189.0 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-weakline-sim.arrays.f64` | 321.7 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-weakline-sim.arrays.json` | 2.0 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/eds-weakline-sim.txt` | 30.8 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/velox-tiny.arrays.f64` | 0.0 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/velox-tiny.arrays.json` | 0.1 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectro-golden/velox-tiny.txt` | 15.8 KB | SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`) |  |
| `SpectroCoreTests/Fixtures/spectrum-tools-lineprofile-pins.json` | 83.3 KB | `tools/spectrum-tools/pins.py` |  |
| `SpectroCoreTests/Fixtures/spectrum-tools-smoothing-pins.json` | 379.1 KB | `tools/spectrum-tools/pins.py` |  |
| `SpectroCoreTests/Fixtures/velox-tiny.emd` | 43.6 KB | `tools/edx-planted/make_velox_tiny.py` |  |
| `SpectroEDXTests/Fixtures/eds-absorption-truth.json` | 76.8 KB | `tools/edx-sim/absorption_truth_sim.py` |  |
| `SpectroEDXTests/Fixtures/eds-fit-exspy-7185a4d1.json` | 155.5 KB | `tools/edx-exspy-pins/fit_pins.py` | rewrites it to the last bit (BLAS order) |
| `SpectroEDXTests/Fixtures/eds-pins-exspy-7185a4d1.json` | 70.7 KB | `tools/edx-exspy-pins/pins.py` |  |
| `SpectroEDXTests/Fixtures/eds-proposer-sim.json` | 100.3 KB | `tools/edx-sim/proposer_sim.py` |  |
| `SpectroEDXTests/Fixtures/eds-quant-pins-exspy-7185a4d1.json` | 30.6 KB | `tools/edx-exspy-pins/quant_pins.py` |  |
| `SpectroEDXTests/Fixtures/eds-realistic-l-sim.json` | 39.0 KB | `tools/edx-sim/realistic_l_sim.py` |  |
| `SpectroEDXTests/Fixtures/eds-unlisted-sim.json` | 31.0 KB | `tools/edx-sim/unlisted_sim.py` |  |
| `SpectroEDXTests/Fixtures/eds-weakline-sim.json` | 378.2 KB | `tools/edx-sim/weakline_sim.py` |  |
| `SpectroEDXTests/Fixtures/edx-0100-exspy.json` | 2.8 KB | `tools/edx-kfactor-import/pins.py` |  |
| `SpectroEDXTests/Fixtures/edx-axis-e2.f64` | 100.6 KB | `tools/edx-planted/pins.py` |  |
| `SpectroEDXTests/Fixtures/edx-calibration-counts.u32` | 294.9 KB | `tools/edx-planted/make_planted.py` |  |
| `SpectroEDXTests/Fixtures/edx-calibration.json` | 95.2 KB | `tools/edx-planted/make_planted.py` |  |
| `SpectroEDXTests/Fixtures/edx-pins-intensity.f64` | 210.2 KB | `tools/edx-planted/pins.py` |  |
| `SpectroEDXTests/Fixtures/edx-planted-means.f64` | 3.6 MB | `tools/edx-planted/make_planted.py` |  |
| `SpectroEDXTests/Fixtures/edx-planted-resid.i16` | 8.3 MB | `tools/edx-planted/make_planted.py` |  |
| `SpectroEDXTests/Fixtures/edx-planted-truth.json` | 149.4 KB | `tools/edx-planted/make_planted.py` |  |
| `SpectroEDXTests/Fixtures/edx-planted.json` | 217.7 KB | `tools/edx-planted/make_planted.py` |  |
| `SpectroEDXTests/Fixtures/edx-quant-maps-exspy.json` | 72.4 KB | `tools/edx-quant-maps/pins.py` |  |
| `SpectroEDXTests/Fixtures/pins.json` | 2.0 MB | `tools/edx-planted/pins.py` |  |
| `SpectroEDXTests/Fixtures/public/SI_empty selection.emd` | 2.0 MB | copied from References/rosettasciio (rsciio/tests/data/emd) | third party: RosettaSciIO public test data (GPL-3.0-or-later, commit 049e7d70), copied unchanged |
| `SpectroEDXTests/Fixtures/public/Test SI 16x16 215 kx.emd` | 2.0 MB | copied from References/rosettasciio (rsciio/tests/data/emd) | third party: RosettaSciIO public test data (GPL-3.0-or-later, commit 049e7d70), copied unchanged |
| `SpectroEDXTests/Fixtures/public/fei_emd_si.emd` | 955.3 KB | copied from References/rosettasciio (rsciio/tests/data/emd) | third party: RosettaSciIO public test data (GPL-3.0-or-later, commit 049e7d70), copied unchanged |
| `SpectroEDXTests/Fixtures/velox-stream-1stream-1frame.emd` | 49.6 KB | `tools/edx-planted/make_velox_streams.py` |  |
| `SpectroEDXTests/Fixtures/velox-stream-1stream-3frames.emd` | 206.7 KB | `tools/edx-planted/make_velox_streams.py` |  |
| `SpectroEDXTests/Fixtures/velox-stream-4streams-2frames.emd` | 105.6 KB | `tools/edx-planted/make_velox_streams.py` |  |
| `SpectroEDXTests/Fixtures/velox-stream-axis-decoy.emd` | 49.6 KB | `tools/edx-planted/make_velox_streams.py` |  |
| `SpectroEDXTests/Fixtures/velox-stream-axis-order.emd` | 49.6 KB | `tools/edx-planted/make_velox_streams.py` |  |
| `SpectroEDXTests/Fixtures/velox-stream-unterminated.emd` | 49.6 KB | `tools/edx-planted/make_velox_streams.py` |  |
| `SpectroEDXTests/Fixtures/velox-streams-truth.json` | 80.6 KB | `tools/edx-planted/make_velox_streams.py` |  |
| `SpectroEDXTests/Fixtures/xray-lines-exspy-7185a4d1.json` | 37.9 KB | `tools/edx-lines/pins.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ps03-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ps03-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ps07-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ps07-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ps13-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ps13-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ss-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-R-ss-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ps03-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ps03-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ps07-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ps07-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ps13-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ps13-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ss-noiseless.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-core-ss-noisy.f64` | 240.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ps03-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ps03-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ps07-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ps07-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ps13-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ps13-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ss-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-R-ss-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ps03-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ps03-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ps07-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ps07-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ps13-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ps13-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ss-noiseless.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-low-ss-noisy.f64` | 408.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-pins.json` | 19.4 MB | `tools/eels-edge/pins.py` |  |
| `SpectroEELSTests/Fixtures/edge-planted-R.json` | 5.1 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-planted-truth-R.json` | 316.3 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-planted-truth.json` | 316.2 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-planted.json` | 5.0 KB | `tools/eels-edge/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/edge-sigma-CK.f64` | 16.3 KB | `tools/eels-edge/pins.py --sigma-only` |  |
| `SpectroEELSTests/Fixtures/edge-sigma-CK.json` | 1.0 KB | `tools/eels-edge/pins.py --sigma-only` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Al-K1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Al-K1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Al-L1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Al-L1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Al-L23-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Al-L23-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Cu-L1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Cu-L1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Cu-L2-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Cu-L2-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Cu-L3-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Cu-L3-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Fe-L1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Fe-L1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Fe-L2-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Fe-L2-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Fe-L3-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Fe-L3-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-K1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-K1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-L1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-L1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-L2-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-L2-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-L3-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Mg-L3-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-K1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-K1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-L1-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-L1-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-L2-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-L2-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-L3-0.f64` | 6.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edge-Si-L3-1.f64` | 4.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-edges-pins.json` | 108.3 KB | `tools/eels-chain/edges.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fl-add-zlp-crop.f64` | 150.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fl-add-zlp.f64` | 153.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fl-crop.f64` | 150.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fl-default.f64` | 153.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fr-default.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fr-fixed-threshold-6.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fr-fwhm-1.5.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fr-no-extrap-cl.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fr-no-extrap-ll.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-fr-no-extrap.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-cno-core.f64` | 33.6 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-cno-curve.f64` | 33.6 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fecu-core.f64` | 67.2 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fecu-curve.f64` | 67.2 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fel-conv-core.f64` | 28.8 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fel-conv-curve.f64` | 28.8 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fel-conv-ll.f64` | 5.8 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fel-core.f64` | 28.8 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fel-curve.f64` | 28.8 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fel-exact-core.f64` | 28.8 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-fel-exact-curve.f64` | 28.8 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-model-pins.json` | 13.1 KB | `tools/eels-chain/model.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pins.json` | 90.3 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-binned-w20-e100-fixneg.f64` | 14.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-binned-w20-e100.f64` | 14.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-binned-w20-e1024.f64` | 58.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-binned-w50-e100.f64` | 14.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-binned-w20-e100-fixneg.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-binned-w20-e100.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-binned-w20-e1024.f64` | 49.2 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-binned-w50-e100.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-unbinned-w20-e100-fixneg.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-unbinned-w20-e100.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-unbinned-w20-e1024.f64` | 49.2 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-exact-unbinned-w50-e100.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-input-binned.f64` | 9.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-input-unbinned.f64` | 9.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-unbinned-w20-e100-fixneg.f64` | 14.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-unbinned-w20-e100.f64` | 14.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-unbinned-w20-e1024.f64` | 58.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-pl-unbinned-w50-e100.f64` | 14.4 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-plural-core.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-plural-edge.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-plural-ll.f64` | 153.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-plural-single-broadened.f64` | 153.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-plural-single.f64` | 153.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-plural-zlp.f64` | 153.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-taper-both.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-taper-channels25.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-taper-input.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-taper-left-ch40-off5.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-taper-left.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-taper-offset10.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-taper-right.f64` | 4.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-also-align-core.f64` | 28.0 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-also-align.f64` | 54.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-default.f64` | 54.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-interp-ip3.f64` | 54.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-mask.f64` | 54.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-no-calibrate.f64` | 54.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-no-crop-no-calibrate.f64` | 57.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-no-crop.f64` | 57.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-no-subpixel.f64` | 54.7 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-signal-range.f64` | 54.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-spike-no-range.f64` | 57.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-align-spike-range.f64` | 54.5 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-core.f64` | 28.8 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-ll-spike.f64` | 57.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-ll.f64` | 57.6 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-shift1d-crop.f64` | 1.1 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-shift1d-input.f64` | 1.3 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eels16-zlp-shift1d-nocrop.f64` | 1.3 KB | `tools/eels-chain/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-B-K1-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-B-K1-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ba-M4-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ba-M4-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ba-M5-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ba-M5-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ti-L1-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ti-L1-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ti-L2-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ti-L2-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ti-L3-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Ti-L3-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Zr-M2-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Zr-M2-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Zr-M3-0.f64` | 6.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edge-Zr-M3-1.f64` | 4.0 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsall-edges-pins.json` | 177.4 KB | `tools/eels-chain/edges.py --all` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-cno-core.f64` | 33.6 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-cno-full-given-curve.f64` | 33.6 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-cno-full-twoArea-curve.f64` | 33.6 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-cno-win-given-curve.f64` | 33.6 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-cno-win-twoArea-curve.f64` | 33.6 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fecu-core.f64` | 67.2 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fecu-full-given-curve.f64` | 67.2 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fecu-full-twoArea-curve.f64` | 67.2 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-conv-core.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-conv-full-given-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-conv-full-twoArea-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-conv-ll.f64` | 5.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-core.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-exact-core.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-exact-full-given-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-exact-full-twoArea-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-full-given-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-full-twoArea-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-win-given-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-mlls-fel-win-twoArea-curve.f64` | 28.8 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-pins.json` | 43.9 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-early-centre-psf.f64` | 1.9 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-early-centre-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-early-centre-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-flat-top-psf.f64` | 1.9 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-flat-top-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-flat-top-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-0-psf.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-0-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-0-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-15-noisy-psf.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-15-noisy-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-15-noisy-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-15-psf.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-15-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-pixel-15-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-15-noisy-psf.f64` | 1.9 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-15-noisy-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-15-noisy-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-15-psf.f64` | 1.9 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-15-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-15-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-40-noisy-psf.f64` | 1.9 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-40-noisy-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-40-noisy-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-5-psf.f64` | 1.9 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-5-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-shared-5-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-zeros-psf.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-zeros-result.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/eelsrm-rl-zeros-signal.f64` | 11.5 KB | `tools/eels-rl-mlls/pins.py` |  |
| `SpectroEELSTests/Fixtures/exspy-linescan-ll.f64` | 139.3 KB | `tools/eels-thickness/pins.py` | third party: exSpy test data (GPL-3.0-or-later), re-encoded as raw float64 |
| `SpectroEELSTests/Fixtures/exspy-linescan-ll.json` | 1.9 KB | `tools/eels-thickness/pins.py` | third party: exSpy test data (GPL-3.0-or-later), re-encoded as raw float64 |
| `SpectroEELSTests/Fixtures/exspy-linescan-zlp.f64` | 139.3 KB | `tools/eels-thickness/pins.py` | third party: exSpy test data (GPL-3.0-or-later), re-encoded as raw float64 |
| `SpectroEELSTests/Fixtures/exspy-linescan-zlp.json` | 1.9 KB | `tools/eels-thickness/pins.py` | third party: exSpy test data (GPL-3.0-or-later), re-encoded as raw float64 |
| `SpectroEELSTests/Fixtures/pins.json` | 95.2 KB | `tools/eels-thickness/pins.py` |  |
| `SpectroEELSTests/Fixtures/planted-noiseless.f64` | 272.0 KB | `tools/eels-thickness/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/planted-noiseless.json` | 1.3 KB | `tools/eels-thickness/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/planted-noisy.f64` | 272.0 KB | `tools/eels-thickness/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/planted-noisy.json` | 1.6 KB | `tools/eels-thickness/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/planted-truth.json` | 72.3 KB | `tools/eels-thickness/make_planted.py` |  |
| `SpectroEELSTests/Fixtures/portable-thresholds.json` | 42.3 KB | `tools/eels-thickness/make_portable_thresholds.py` |  |
| `SpectroEELSTests/Fixtures/refuter/B1_negative_counts/data.f64` | 108.0 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B1_negative_counts/exspy.json` | 1.4 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B1_negative_counts/spec.json` | 0.2 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B3_flat_and_ramp/data.f64` | 9.6 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B3_flat_and_ramp/exspy.json` | 0.5 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B3_flat_and_ramp/spec.json` | 0.2 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B5_ramps/data.f64` | 14.4 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B5_ramps/exspy.json` | 0.8 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/B5_ramps/spec.json` | 0.2 KB | `tools/eels-thickness/edge_cases.py` | seed 777001; three of its cases |
| `SpectroEELSTests/Fixtures/refuter/R22/data.f64` | 6.3 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R22/exspy.json` | 2.8 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R22/spec.json` | 0.3 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R26/data.f64` | 2.9 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R26/exspy.json` | 1.4 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R26/spec.json` | 0.3 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R52/data.f64` | 10.5 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R52/exspy.json` | 4.0 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R52/spec.json` | 0.3 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R58/data.f64` | 5.6 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R58/exspy.json` | 2.3 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/refuter/R58/spec.json` | 0.3 KB | `tools/eels-thickness/random_cases.py` | seed 424242; four of its 60 cases |
| `SpectroEELSTests/Fixtures/sg-parity.f64` | 1.8 MB | `tools/eels-thickness/make_sg_parity.py` |  |
| `SpectroEELSTests/Fixtures/sg-parity.json` | 59.0 KB | `tools/eels-thickness/make_sg_parity.py` |  |
