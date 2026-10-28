#!/usr/bin/env python3
"""Extract every K, L and M table exSpy builds its dft edges from into one pack: SpectroEELS's bundled GOS.

Run:  ../References/python/hyperspy/bin/python -I -B tools/eels-edge/extract_gos.py [--gosh FILE] [--exspy DIR] [--out DIR]

Reads  References/gos-dft-1.5.0.gosh (= exSpy's Segger_Guzzinati_Kohl_1.5.0.gosh, md5 7fee8891c147a4f769668403b54c529b,
       DOI 10.5281/zenodo.7645765, CC-BY-4.0; the md5 is CHECKED) and exSpy's exspy/material/eels_binding_energies.json.
Writes Sources/SpectroEELS/Resources/GOS/dft-gos-tables.bin and dft-gos-index.json (the layout is in the comment above main()).

THE ORIENTATION. The file stores /X/<table>/data as (q, energy, 1). exSpy (gosh_gos.py read_gos_data) does
`gos = np.squeeze(gos.T)` = (energy, q) and uses `gos_array[ienergy, :]` (base_gos.py get_qaxis_and_gos); that is the layout
written here. exSpy's rel_energy_axis = free_energies - min(free_energies), energy_axis = rel + onset (both float32 in exSpy;
see README "Findings").

EXACTNESS. The file holds float32 arrays (gos, q, free_energies, occupancy_ratio); the pack holds them as stored, and the index
writes every float as repr(float(value)). The output is byte-reproducible (sorted keys, fixed layout; the pack's sha256 is in the index).
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


# Every edge exSpy builds with GOS="dft": each K, L and M subshell of exspy/material/eels_binding_energies.json
# whose GOSH subshell (metadata/edges_info) names a table the file holds for the element: 383 edges from 231 tables (K 17, L 126, M 240 edges). One pack, not
# 231 JSON files (about 17 MB of float32 instead of about 100 MB of text): dft-gos-tables.bin holds, per table, free_energies (nE), q (nQ) and gos (nE x nQ,
# exSpy's np.squeeze(data.T) layout, row-major) as float32 little-endian, exactly the stored values; dft-gos-index.json lists each table's element, name, byte
# offset and sizes and the edges that read it (subshell as exSpy's binding-energy key, "K" written "K1"; onset; occupancy ratio), with the source and a sha256
# of the pack.
def main():
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


if __name__ == "__main__":
    sys.exit(main())
