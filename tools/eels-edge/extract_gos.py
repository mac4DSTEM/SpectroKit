#!/usr/bin/env python3
"""Extract the dft GOS tables of C, N, O K1 from the GOSH file: SpectroKit EELS slice 2, registration section 3.3.

Run:  References/python/bin/python -I -B tools/eels-edge/extract_gos.py [--gosh FILE] [--exspy DIR] [--out DIR]

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
ap.add_argument("--task16", action="store_true", help="write the task-16 tables (K1 of Mg, Al, Si; L1 and L23 of Mg, Al, Si, Fe, Cu) in the per-TABLE schema instead of C, N, O K1")
ap.add_argument("--all", action="store_true", help="write every K, L and M edge exSpy builds with the dft GOS into one pack: dft-gos-tables.bin and dft-gos-index.json")
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


# Task 16 (docs/design/eels-task-16.md section 6.1): one file per element AND TABLE, dft-<El>-<table>.json, listing the edges that read it.
# L2 and L3 share the L23 table and differ only in their occupancy ratio (exSpy's `subshell_factor`: 0.333 and 0.667); Al has the single "L2,3"
# (factor 1.0). The onsets are exSpy's eels_binding_energies.json. Same float32-exact number writing and key sorting as the K1 files.
TASK16 = {
    "K1": {"Mg": ["K1"], "Al": ["K1"], "Si": ["K1"]},
    "L1": {el: ["L1"] for el in ("Mg", "Al", "Si", "Fe", "Cu")},
    "L23": {"Mg": ["L2", "L3"], "Al": ["L2,3"], "Si": ["L2", "L3"], "Fe": ["L2", "L3"], "Cu": ["L2", "L3"]},
}


def main_task16():
    assert md5_file(ARGS.gosh) == MD5, "the GOSH file is not the pinned one"
    with open(os.path.join(ARGS.exspy, "exspy", "material", "eels_binding_energies.json")) as f:
        be = json.load(f)
    os.makedirs(ARGS.out, exist_ok=True)
    with h5py.File(ARGS.gosh, "r") as h:
        assert h["/metadata/data_ref"].attrs["data_doi"] == DOI
        info = h["metadata/edges_info"]
        for table, elements in TASK16.items():
            for el, subshells in elements.items():
                g = h[f"/{el}/{table}"]
                data, q, fe = g["data"][:], g["q"][:], g["free_energies"][:]
                assert data.shape == (192, 97, 1) and q.shape == (192,) and fe.shape == (97,), (el, table, data.shape)
                gos = np.squeeze(data.T)
                assert gos.shape == (97, 192)
                edges = []
                for sub in subshells:
                    assert str(info[sub].attrs["table"]) == table, (sub, info[sub].attrs["table"])
                    key = "K" if sub == "K1" else sub
                    edges.append({"subshell": sub, "onsetEV": float(be["elements"][el][key]["onset_energy (eV)"]),
                                  "occupancyRatio": float(info[sub].attrs["occupancy_ratio"])})
                obj = {
                    "element": el, "table": table, "edges": edges,
                    "storedDtype": {"gos": str(data.dtype), "q": str(q.dtype), "freeEnergies": str(fe.dtype),
                                    "occupancyRatio": str(info[subshells[0]].attrs["occupancy_ratio"].dtype)},
                    "freeEnergies": [float(x) for x in fe], "q": [float(x) for x in q],
                    "gos": [[float(x) for x in row] for row in gos],
                    "source": {"file": "Segger_Guzzinati_Kohl_1.5.0.gosh", "md5": MD5, "doi": DOI,
                               "licence": "CC-BY-4.0", "attribution": ATTRIBUTION},
                }
                parts = []
                dump(obj, 0, parts)
                raw = ("".join(parts) + "\n").encode()
                p = os.path.join(ARGS.out, f"dft-{el}-{table}.json")
                with open(p, "wb") as f:
                    f.write(raw)
                print(f"{p}  {len(raw)} bytes  sha256 {hashlib.sha256(raw).hexdigest()}")


# Every edge exSpy builds with GOS="dft" (Paul, 2026-10-23: "we need to put everything in"): each K, L and M subshell of exspy/material/eels_binding_energies.json
# whose GOSH subshell (metadata/edges_info) names a table the file holds for the element: 383 edges from 231 tables (K 17, L 126, M 240 edges). One pack, not
# 231 JSON files (about 17 MB of float32 instead of about 100 MB of text): dft-gos-tables.bin holds, per table, free_energies (nE), q (nQ) and gos (nE x nQ,
# exSpy's np.squeeze(data.T) layout, row-major) as float32 little-endian, exactly the stored values; dft-gos-index.json lists each table's element, name, byte
# offset and sizes and the edges that read it (subshell as exSpy's binding-energy key, "K" written "K1"; onset; occupancy ratio), with the source and a sha256
# of the pack.
def main_all():
    assert md5_file(ARGS.gosh) == MD5, "the GOSH file is not the pinned one"
    with open(os.path.join(ARGS.exspy, "exspy", "material", "eels_binding_energies.json")) as f:
        be = json.load(f)["elements"]
    os.makedirs(ARGS.out, exist_ok=True)
    blob = bytearray()
    tables = {}
    with h5py.File(ARGS.gosh, "r") as h:
        assert h["/metadata/data_ref"].attrs["data_doi"] == DOI
        info = h["metadata/edges_info"]
        for el in sorted(be):
            for key in sorted(be[el]):
                sub = "K1" if key == "K" else key
                if sub[0] not in "KLM" or sub not in info:
                    continue
                table = str(info[sub].attrs["table"])
                if el not in h or table not in h[el]:
                    continue
                tk = (el, table)
                if tk not in tables:
                    g = h[f"/{el}/{table}"]
                    data, q, fe = g["data"][:], g["q"][:], g["free_energies"][:]
                    assert data.ndim == 3 and data.shape[2] == 1 and data.shape[0] == q.shape[0] and data.shape[1] == fe.shape[0], (el, table, data.shape)
                    gos = np.ascontiguousarray(data[:, :, 0].T).astype("<f4")    # = exSpy's np.squeeze(data.T) for (q, energy, 1)
                    assert gos.shape == (fe.shape[0], q.shape[0]), (el, table, gos.shape)
                    offset = len(blob)
                    blob += fe.astype("<f4").tobytes() + q.astype("<f4").tobytes() + gos.tobytes()
                    tables[tk] = {"element": el, "table": table, "offset": offset, "energies": int(fe.shape[0]), "q": int(q.shape[0]), "edges": []}
                tables[tk]["edges"].append({"subshell": sub, "onsetEV": float(be[el][key]["onset_energy (eV)"]),
                                            "occupancyRatio": float(info[sub].attrs["occupancy_ratio"])})
    raw = bytes(blob)
    index = {"tables": [tables[k] for k in sorted(tables)], "packSHA256": hashlib.sha256(raw).hexdigest(), "packBytes": len(raw),
             "source": {"file": "Segger_Guzzinati_Kohl_1.5.0.gosh", "md5": MD5, "doi": DOI, "licence": "CC-BY-4.0", "attribution": ATTRIBUTION,
                        "edgesFrom": "exspy/material/eels_binding_energies.json (exSpy 7185a4d1)"}}
    with open(os.path.join(ARGS.out, "dft-gos-tables.bin"), "wb") as f:
        f.write(raw)
    parts = []
    dump(index, 0, parts)
    text = ("".join(parts) + "\n").encode()
    with open(os.path.join(ARGS.out, "dft-gos-index.json"), "wb") as f:
        f.write(text)
    edges = sum(len(t["edges"]) for t in tables.values())
    print(f"{len(tables)} tables, {edges} edges, pack {len(raw)} bytes sha256 {index['packSHA256']}, index {len(text)} bytes")


def main():
    if ARGS.all:
        return main_all()
    if ARGS.task16:
        return main_task16()
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
