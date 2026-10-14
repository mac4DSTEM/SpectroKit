# velox-metadata-parity

The six fields SpectroKit 0.2.0 added to `VeloxMetadata`, and each `VeloxDetectorInfo.exposureTimeSeconds`, read two
ways and compared bit for bit: by the library's public API (`VeloxEMDReader(path:).images()`), and by h5py plus the
pinned RosettaSciIO code, on RosettaSciIO 049e7d70's public Velox files. A reference for every number: the reader must
return what an independent reading of the same bytes returns, not merely something.

## What is compared with what

Per image entry (`Data/Image/<id>` with a rank-3 `Data` and a `Metadata`), column 0 of `Metadata` (the one the reader
and RosettaSciIO's `[:, 0]` read):

| field | reference (h5py, column 0) | compared |
|---|---|---|
| `nominalMagnification` | `Optics.NominalMagnification`, Python `float()` of the stored string or number; absent or unparseable: null | IEEE-754 bits |
| `stemMagnification` | `CustomProperties.StemMagnification.value`, the same; null too when `CustomProperties` or `StemMagnification` is not an object | bits |
| `cameraLengthMeters` | `Optics.CameraLength`, the same (metres as stored, no ×1e3) | bits |
| `operatingMode`, `projectorMode` | `Optics.OperatingMode`, `Optics.ProjectorMode`: the stored string; absent or not a string: null | string |
| `exposureTimeSeconds` | `ExposureTime` of the entry RosettaSciIO's own `_get_detector_metadata_dict(om, BinaryResult.Detector)` returns | bits |
| `detectors[i].exposureTimeSeconds` | every `Detector-<n>` entry's own `ExposureTime` | bits |
| `binaryResultDetector`, detector `name`, `type`, the set of indices | as stored | equal |

Also: a file without a Velox `Version` (the 13 Berkeley-EMD files) must be refused by the reader (`notVeloxFile`), and
the entry-id sets must be equal.

`_get_detector_metadata_dict` is not imported (`rsciio.emd._emd_velox` needs packaging, python-dateutil and pint, which
the reference venv does not have). `reference.py` asserts the sha256 of the pinned `_emd_velox.py`, cuts the function
out with `ast` and compiles it alone, so the code that runs is the pinned code (`_emd_velox.py:51-57`).

The Swift side (`swift/`) is a throwaway package that depends on SpectroKit by path and prints the fields as JSON. It
sees only public API: a field that is not `public` does not compile there.

## Doc-comment claims

`reference.py` also checks six claims that the doc comments of `VeloxEMDReader.swift` make about the public files and
the pinned source, and `compare.py` fails on any counterexample. In these claims a camera image is an entry whose
`BinaryResult.Detector` has `DetectorType` `ImagingDetector` (BM-Ceta); a STEM image is any other entry (24
`ScanningDetector`, 14 `AnalyticalDetector`); an EELS spectrometer entry is an entry whose `BinaryResult.Detector` is
the detector of the file's `Data/EelsSpectrumImage` datasets (Zebra, in the one public file that has them).

1. `Optics.NominalMagnification` is absent from every STEM image (all 38, every `Metadata` column; present on all 4
   camera images).
2. Per-detector `ExposureTime` is set only on `ImagingDetector` entries (924 `Detectors` entries over every column; 97
   carry one).
3. `Optics.OperatingMode` and `Optics.ProjectorMode` are `"1"` or `"2"` wherever present (192 values, every column).
4. `CustomProperties.StemMagnification` is not a STEM marker: the 4 camera images carry it (`"0"` on three, stored with
   `type` `bool`; `"115000"` on the fourth, `double`), the 3 EELS spectrometer entries and the 3 `EelsSpectrumImage`
   datasets carry none, and the other 35 entries all carry it.
5. In the pinned `_get_mapping`, `CustomProperties.StemMagnification.value` maps to `magnification` with `float` and
   `Optics.CameraLength` to `camera_length` with `float(x) * 1e3` (both in the function's own dict literal, nothing
   removes them), and no file under `rsciio/emd/` mentions `NominalMagnification`, `OperatingMode` or `ProjectorMode`.
6. Every `Detectors` section (every `Metadata` column of all 42 entries) stores its `Detector-<n>` keys in ascending
   index order, and no two entries of one section share a `DetectorName`. With both, the first entry as stored (what
   RosettaSciIO takes) and the first by index (what the reader takes) are one entry, so the exposure rule cannot part
   from RosettaSciIO's on a public file.

Planted and extra files are left out of the claims: they are built to break them.

## Pins

- RosettaSciIO 049e7d70 (`049e7d7070e84779b499adaf3295beee9facb004`), the checkout `References/rosettasciio` (or
  `$SPECTROKIT_REFERENCES/rosettasciio`): HEAD must equal the pin and the tree must be clean; the harness never writes
  there.
  - `rsciio/tests/registry.txt` sha256 `31417482938f80160be2c03525ba58dd810c7f16b1790f597470ece8dd0b1bcb`
  - `rsciio/emd/_emd_velox.py` sha256 `1a3e12f2d550c5378c5e3ee0e02c963f0ef547af9dd4bde9bd1c2ee2df56a8e3`
- Test data: the four zips (`fei_emd_files`, `velox_EELS_EDS`, `velox_emd_v11_elementSelection`, `velox_emd_version11`)
  and the 18 loose `.emd` files are each hashed against `registry.txt` (the registry names the zips, not their members).
  Each zip is unzipped into an empty directory under `.build/velox-metadata-parity/work/zips`, and every member is
  compared with the member of the verified archive. 31 files: 18 Velox (42 image entries, 440 detector records) and 13
  Berkeley-EMD files that both readers must refuse.
- h5py 3.16.0, numpy 2.5.4, Python 3.14 (`References/python-venv`, run as `python -I -B`).
- libhdf5 for the reader: `MAC4DSTEM_HDF5_PATH`, else `.build/hdf5` (filled by `tools/test.sh`), else Homebrew's.

## Run

    tools/velox-metadata-parity/run.sh               # lock check, unzip, reference, build the dump, compare
    tools/velox-metadata-parity/run.sh --table       # also print the per-entry table (always in .build/.../table.md)
    tools/velox-metadata-parity/run.sh --controls    # then the negative controls (11 mutants, about 5 minutes)
    tools/velox-metadata-parity/run.sh other.emd ... # more files, read both ways

`Tests/SpectroKitTests/Fixtures/velox-metadata-planted.emd` is added automatically when it exists. Pass: exit 0 and
`velox-metadata-parity: all passed — ...` (with `--controls`, also `negative controls: N of N caught`). A difference
prints one line `  FAIL  <file> | <entry id> | <field>: expected <x>, got <y>` and exits 1.

Everything is written under `.build/velox-metadata-parity/`: `work/reference.json` is the reference's output,
`work/swift.json` the reader's, `table.md` the per-entry table.

## The one documented deviation

RosettaSciIO takes the first `Detectors` entry in the order the JSON object was stored. Foundation's dictionaries have
no order, so the reader takes `Detector-<n>` in index order. The two agree whenever the keys are stored in index order
or no two entries share a name, which claim 6 shows for every public file. They part when an entry stores the keys out
of order and repeats a name: the planted fixture has one that does (`case-f`), on purpose. `compare.py` then prints
`  deviation  ...` with both values and does not fail, but only for a file labelled `planted/...`, only when the
entry's keys are out of index order, and only when the reader's value is the index-order one. Anywhere else, a public
file or an extra file given on the command line, the same difference is a FAIL (and a public file that stored its
keys out of order would also fail claim 6). The count appears in the pass line.

## Negative controls

`--controls` edits a copy of `VeloxEMDReader.swift` (never the package), rebuilds the dump against it and requires
`compare.py` to exit 1 with a FAIL line on the case named for the mutant; an edit that does not apply exactly once, or
does not compile, counts as not caught.

| mutant | caught on |
|---|---|
| `exposure-by-contains` (the energy axis's rule instead of equality) | planted fixture: an entry whose name contains `BinaryResult.Detector` precedes the equal one |
| `exposure-from-last-match` | planted fixture: two entries with the same name |
| `exposure-by-detector-index` (`BinaryResult.DetectorIndex`, as RosettaSciIO's frame-time path does) | `1854 Camera Ceta.emd` (index 0 is BF; the name matches Detector-8) |
| `camera-length-from-magnification` | `1532 Camera Ceta.emd` |
| `operating-mode-always-nil`, `modes-swapped` | `fei_emd_image.emd` |
| `detector-exposure-dropped` | `1854 Camera Ceta.emd`, `Detector-8` |
| `stem-from-nominal` (reads `Optics.NominalMagnification`) | `fei_emd_image.emd` (STEM: expected 40000, got null) |
| `stem-without-value-key` (`["Value"]`) | `fei_emd_image.emd` |
| `stem-zero-as-nil` (treats `"0"` as absent, a "STEM marker" filter) | `fei_example_complex_fft.emd` (camera image, `"0"`) |
| `nominal-from-stem` | `1854 Camera Ceta.emd` (8609.428 expected, 115000 got) |

The first two are caught only by the planted fixture; without it they count as not caught, and the run says why.

## What this cannot show

- **Agreement with RosettaSciIO and h5py is not truth.** Both read the same bytes and the same JSON. A wrong shared
  assumption (that column 0 is the frame to read, that `CameraLength` is metres) is invisible here. Nothing is called
  validated for passing.
- **The public files are few**: 18 Velox files, 42 image entries, 4 camera images, one file with EELS. A rule that no
  public file exercises is exercised only by the planted fixture (key order, JSON numbers, unparseable text, an empty
  detector name).
- **Codes are not decoded.** `OperatingMode` and `ProjectorMode` are compared as the strings stored (`"1"`, `"2"`); no
  published reader maps them, so the harness cannot say what they mean.
- **Only column 0 is compared** field by field. The other columns of `Metadata` are read for the claims only.
- **Python `float()` and Swift `Double(String)` are different parsers.** On the public files they agree on all 1763
  distinct strings stored in any `Metadata` column (a throwaway scan, not part of `run.sh`; no public file stores a JSON
  number there). `run.sh` itself compares the six fields on column 0. They differ on a throwaway file with odd values
  (not committed; run through this harness as an extra file): `" 5"` and `"1_0"` are 5.0 and 10.0 in Python and nil in
  Swift; `"0x10"` is nil in Python and 16.0 in Swift. `"nan"`, `"Infinity"` (any case, signed: both give a non-finite
  value, not nil), `"1.3e+006"`, a JSON number, a JSON `true` or `false` (1.0 / 0.0 in both: `float(True)` and
  `NSNumber`), and a `StemMagnification` that is not an object, has no `value`, or sits in a `CustomProperties` that
  is a string, agree.
- **An empty `BinaryResult.Detector`** gives null in the reference, by the reader's own rule (RosettaSciIO would look
  for an entry named `""`); no public file has one.
- The harness is not a test of the library: `swift test` is. It reads real files from outside the repository.
