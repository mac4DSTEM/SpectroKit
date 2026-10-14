#!/usr/bin/env python3
"""Extract the dft GOS tables of C, N, O K1 from the GOSH file: SpectroKit EELS slice 2, registration section 3.3.

Run:  References/exspy-venv/bin/python -I -B tools/eels-edge/extract_gos.py [--gosh FILE] [--exspy DIR] [--out DIR]

Reads  References/gos-dft-1.5.0.gosh (= exSpy's Segger_Guzzinati_Kohl_1.5.0.gosh, md5 7fee8891c147a4f769668403b54c529b,
       DOI 10.5281/zenodo.7645765, CC-BY-4.0; the md5 is CHECKED) and exSpy's exspy/material/eels_binding_energies.json.
Writes Sources/SpectroEELS/Resources/GOS/dft-{C,N,O}-K1.json, one object per edge, keys sorted, no NaN:

  element, subshell "K1", table (the `table` attribute of metadata/edges_info/K1), onsetEV (exSpy's K onset: 284, 401, 532),
  occupancyRatio, storedDtype {gos, q, freeEnergies, occupancyRatio}, freeEnergies [97], q [192],
  gos[iEnergy][iQ] (97 x 192), source {file, md5, doi, licence, attribution}.

THE ORIENTATION. The file stores /X/K1/data as (192, 97, 1) = (q, energy, 1). exSpy (gosh_gos.py read_gos_data) does
`gos = np.squeeze(gos.T)` = (97, 192) and uses `gos_array[ienergy, :]` (base_gos.py get_qaxis_and_gos); that is the layout
written here (gos[iEnergy][iQ]). exSpy's rel_energy_axis = free_energies - min(free_energies), energy_axis = rel + onset
(both float32 in exSpy; see README "Findings").

EXACTNESS. The file holds float32 arrays (gos, q, free_energies, occupancy_ratio). Every number is written as
repr(float(value)): the float32 widened to float64 (exact), so a float64 parser recovers precisely the stored value. The
output is byte-reproducible (sorted keys, fixed layout; sha256 of each file printed).
"""
import argparse
import hashlib
import json
import math
import os
import sys

import h5py
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--gosh", default=os.path.join(REPO, "References", "gos-dft-1.5.0.gosh"))
ap.add_argument("--exspy", default=os.path.join(REPO, "References", "exspy-7185a4d1"))
ap.add_argument("--out", default=os.path.join(REPO, "Sources", "SpectroEELS", "Resources", "GOS"))
ARGS = ap.parse_args()

MD5 = "7fee8891c147a4f769668403b54c529b"
DOI = "10.5281/zenodo.7645765"
ATTRIBUTION = ("Segger, Guzzinati and Kohl, GOSH 1.5.0 (A set of Generalised Oscillator Strengths for the simulation of "
               "EELS spectra), DOI 10.5281/zenodo.7645765, CC-BY-4.0")


def md5_file(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if not math.isfinite(v):
            raise ValueError("non-finite float")
        return repr(v)
    return json.dumps(v, ensure_ascii=False)


def dump(v, ind, out):
    pad = "  " * ind
    if isinstance(v, dict):
        out.append("{\n")
        items = sorted(v.items())
        for i, (k, x) in enumerate(items):
            out.append(pad + "  " + json.dumps(k) + ": ")
            dump(x, ind + 1, out)
            out.append(",\n" if i + 1 < len(items) else "\n")
        out.append(pad + "}")
    elif isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            out.append("[" + ", ".join(scalar(x) for x in v) + "]")
        else:
            out.append("[\n")
            for i, x in enumerate(v):
                out.append(pad + "  ")
                dump(x, ind + 1, out)
                out.append(",\n" if i + 1 < len(v) else "\n")
            out.append(pad + "]")
    else:
        out.append(scalar(v))


def main():
    assert md5_file(ARGS.gosh) == MD5, "the GOSH file is not the pinned one"
    with open(os.path.join(ARGS.exspy, "exspy", "material", "eels_binding_energies.json")) as f:
        be = json.load(f)
    os.makedirs(ARGS.out, exist_ok=True)
    with h5py.File(ARGS.gosh, "r") as h:
        conv = h["metadata/edges_info"]["K1"]
        table = conv.attrs["table"]
        occ = conv.attrs["occupancy_ratio"]
        assert h["/metadata/data_ref"].attrs["data_doi"] == DOI
        for el in ("C", "N", "O"):
            g = h[f"/{el}/{table}"]
            data, q, fe = g["data"][:], g["q"][:], g["free_energies"][:]
            assert data.shape == (192, 97, 1) and q.shape == (192,) and fe.shape == (97,), data.shape
            gos = np.squeeze(data.T)                      # exactly exSpy's
            assert gos.shape == (97, 192)
            onset = float(be["elements"][el]["K"]["onset_energy (eV)"])
            obj = {
                "element": el, "subshell": "K1", "table": str(table), "onsetEV": onset,
                "occupancyRatio": float(occ),
                "storedDtype": {"gos": str(data.dtype), "q": str(q.dtype), "freeEnergies": str(fe.dtype),
                                "occupancyRatio": str(occ.dtype)},
                "freeEnergies": [float(x) for x in fe], "q": [float(x) for x in q],
                "gos": [[float(x) for x in row] for row in gos],
                "source": {"file": "Segger_Guzzinati_Kohl_1.5.0.gosh", "md5": MD5, "doi": DOI,
                           "licence": "CC-BY-4.0", "attribution": ATTRIBUTION},
            }
            parts = []
            dump(obj, 0, parts)
            raw = ("".join(parts) + "\n").encode()
            p = os.path.join(ARGS.out, f"dft-{el}-K1.json")
            with open(p, "wb") as f:
                f.write(raw)
            print(f"{p}  {len(raw)} bytes  sha256 {hashlib.sha256(raw).hexdigest()}")


if __name__ == "__main__":
    sys.exit(main())
