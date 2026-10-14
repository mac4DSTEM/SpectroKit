#!/usr/bin/env python3
"""R2 of docs/eels-real-data-check-registration.md, exSpy's side: exSpy 7185a4d1 (HyperSpy 2.4.0, axis binned) on one low-loss
spectrum image of the owner's DM4 file, read by the pinned RosettaSciIO 049e7d70, with the fixed thresholds 3.0 and 5.0 eV and
the estimated rule (exSpy's defaults). Writes <outdir>/<rule>.exspy.f64: per pixel, row-major (y, x), float64 little-endian,
4 values: I_0, I_t, t/lambda, the threshold's channel (HyperSpy's value2index; NaN where exSpy gives NaN), plus <outdir>/
exspy.json (the estimated rule's global tol, the energy axis as exSpy saw it). Scratch output, never committed.

    References/exspy-venv/bin/python -I -B tools/eels-real-data/r2_exspy.py <file.dm4> <index> <outdir> [--references DIR]
"""
import argparse
import contextlib
import importlib.util
import json
import logging
import os
import sys
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser()
ap.add_argument("file")
ap.add_argument("index", type=int, help="ONE-BASED ImageList index (SpectroKit's DM4ImageObject.index)")
ap.add_argument("outdir")
ap.add_argument("--references", default=str(ROOT / "References"))
a = ap.parse_args()

spec = importlib.util.spec_from_file_location("truth", ROOT / "tools" / "eels-reader" / "truth.py")
truth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(truth)
file_reader, DigitalMicrographReader, pinned = truth.load_rsciio(a.references)
sys.path.insert(0, str(Path(a.references) / "exspy-7185a4d1"))
logging.disable(logging.CRITICAL)
warnings.simplefilter("ignore")
import numpy as np  # noqa: E402
with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
    import exspy  # noqa: E402
    from exspy.signals import EELSSpectrum  # noqa: E402
assert Path(exspy.__file__).resolve().parent == (Path(a.references) / "exspy-7185a4d1" / "exspy").resolve()

with open(a.file, "rb") as f:
    dm = DigitalMicrographReader(f)
    dm.parse_file()
    thumbs = [t["ImageIndex"] for t in dm.tags_dict["Thumbnails"].values()] if "Thumbnails" in dm.tags_dict else []
    groups = [k for k in dm.tags_dict["ImageList"] if int(k.replace("TagGroup", "")) not in thumbs]
signals = file_reader(a.file)
sig = signals[groups.index(f"TagGroup{a.index - 1}")]
data = np.asarray(sig["data"])
assert data.ndim == 3 and sig["metadata"]["Signal"]["signal_type"] == "EELS"
ch, ny, nx = data.shape
yxc = np.ascontiguousarray(data.transpose(1, 2, 0)).astype(np.float32).astype(np.float64)
eax = [ax for ax in sig["axes"] if ax["index_in_array"] == 0][0]
axes = [dict(size=ny, navigate=True, name="y"), dict(size=nx, navigate=True, name="x"),
        dict(size=ch, offset=float(eax["offset"]), scale=float(eax["scale"]), units=eax["units"], name="Energy loss",
             navigate=False, is_binned=True)]
s = EELSSpectrum(yxc, axes=axes)
ax = s.axes_manager.signal_axes[0]
os.makedirs(a.outdir, exist_ok=True)
meta = {"energyOffsetEV": float(ax.offset), "energyScaleEV": float(ax.scale), "nx": nx, "ny": ny, "channels": ch}
it = np.asarray(s.integrate1D(-1).data, dtype=float)
for name, thr in (("fixed3", 3.0), ("fixed5", 5.0), ("estimated", None)):
    with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), contextlib.redirect_stderr(dn):
        if thr is None:
            th = s.estimate_elastic_scattering_threshold()
            the = np.asarray(th.data, dtype=float)
            meta["estimatedTolerance"] = None    # exSpy does not return tol; the port's is in its own json
            i0 = np.asarray(s.estimate_elastic_scattering_intensity(threshold=th).data, dtype=float)
            tl = np.asarray(s.estimate_thickness(threshold=th).data, dtype=float)
            chan = np.array([np.nan if not np.isfinite(v) else float(ax.value2index(v)) for v in the.ravel()]).reshape(the.shape)
        else:
            i0 = np.asarray(s.estimate_elastic_scattering_intensity(threshold=thr).data, dtype=float)
            tl = np.asarray(s.estimate_thickness(threshold=thr).data, dtype=float)
            chan = np.full(i0.shape, float(ax.value2index(thr)))
    out = np.stack([i0, it, tl, chan], axis=-1).astype("<f8")
    out.tofile(os.path.join(a.outdir, f"{name}.exspy.f64"))
Path(a.outdir, "exspy.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n")
print("done", meta)
