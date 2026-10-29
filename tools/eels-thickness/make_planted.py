#!/usr/bin/env python3
"""Planted EELS low-loss spectra with a known t/lambda: SpectroKit EELS slice 1, registration section 5.1.

NumPy only (no HyperSpy, no exSpy, no SciPy): this is the truth, independent of the reference the port is pinned to.

Writes, into the fixture directory (default Tests/SpectroEELSTests/Fixtures/, or --out DIR):

  planted-noiseless.f64 / .json   10 spectra as a 2 x 5 image (rows, cols, channels), float64 little-endian, C order
  planted-noisy.f64     / .json   the same, Poisson-noised with numpy.random.default_rng(20261014)
  planted-truth.json              tau per pixel and, per fixed threshold, the log-ratio the planted components imply
                                  and its bias against tau (the method's own bias), plus the sum-based value for the record

Run:  python3 tools/eels-thickness/make_planted.py [--out DIR]      (any Python with NumPy; the suite uses
      ../References/python/hyperspy/bin/python -I)

THE MODEL
---------
Energy axis: E_k = -10.0 + 0.05 * k, k = 0..3399 (-10 eV to 159.95 eV, 3400 channels). The channel of 0 eV is k = 200.
Counts are per channel (the axis is binned).

  Z[k]   zero-loss peak, a Gaussian exp(-E_k^2 / (2 * 0.25^2)) sampled on the grid, normalised to unit sum.
  S0[j]  single-scattering distribution as a LOSS-ORIGIN array: S0[j] is the Drude loss function at the loss
         j * 0.05 eV, E * G * Ep^2 / ((E^2 - Ep^2)^2 + (E * G)^2), Ep = 15.0 eV, G = 0.8 eV, for loss E > 0
         (j >= 1; S0[0] = 0 because E > 0 is strict), j = 0..3199 (the losses the axis can hold: 0.05 .. 159.95 eV;
         S0[j] = 0 for j >= 3200), normalised to unit sum. It is the same function of E as S on the channel grid
         (S at channel k is S0[k - 200]).

ALIGNMENT OF THE CONVOLUTIONS (so that the zero-loss peak at 0 eV stays at 0 eV and S^n lands at its losses)
  Z lives on the channel grid; S0 and its powers live on the loss grid (index j <-> loss j * 0.05 eV, index 0 <-> no
  loss). Then
        S0^(*0)[j] = delta[j]                                   (so term 0 is Z itself)
        S0^(*n)[j] = sum_i S0^(*(n-1))[i] * S0[j - i],   j < 3400
        term_n[m]  = sum_k Z[k] * S0^(*n)[m - k],               m = 0..3399
  The energy of term_n[m] is E_k + loss_j = (k - 200)*0.05 + j*0.05 = (m - 200)*0.05 = E_m. That is: a plain discrete
  convolution of a channel-grid array with a loss-origin array, first 3400 output entries, no shift. Entries beyond
  channel 3399 (energies >= 160 eV) are not on the axis and are lost; S0^(*n) is kept to j < 3400 because a loss
  j >= 3400 can never land on a channel m < 3400 (k >= 0). Z and S0 have unit sum, so term_n has unit mass in the
  full convolution and the mass lost beyond the axis is lost_n = 1 - sum(term_n[0..3399]) (conservation of mass).

THE SPECTRUM
  I[m] = N * sum_n w_n * term_n[m],  w_n = exp(-tau) * tau^n / n!   (Poisson plural scattering), N = 1e6,
  stored as  I = zl + inel  with  zl = N w_0 term_0  and  inel = sum_{n >= 1} N w_n term_n  (terms added in order n = 1, 2, ...).
  n runs while the term is not negligible: term n (n > 0) is NOT added if its summed intensity is below
  1e-14 of the running total of the terms already added (the first such n ends the sum; the terms fall monotonically
  past n = tau). The weight left out is recorded per tau (tail_weight_neglected).
  The convolutions are done by an explicit loop of numpy vector adds (no BLAS, no FFT), so they are byte-reproducible.

TAU (the planted t/lambda), as a 2 x 5 image in row-major order: [[0.05, 0.1, 0.2, 0.3, 0.5], [0.7, 1.0, 1.3, 1.6, 2.0]].

THE BIAS THE GENERATOR PREDICTS (the method's own, not a port's error)
  For a fixed threshold theta the log-ratio method sums the channels [0, ind) with ind = round((theta + 10) / 0.05)
  (the channel at theta itself is NOT included: the channels with E < theta; theta = 2.5, 4.5, 6.0 eV -> ind = 250, 290, 320)
  and divides the sum of ALL channels by it: value = ln(I_t / I_0). From the components:
        Z0         = N w_0                              the zero-loss intensity (all of Z is on the axis)
        zl_above   = N w_0 * sum(Z[ind:])               zero-loss intensity at or above theta (counted in neither I_0)
        inel_below = sum_{n>=1} N w_n sum(term_n[:ind]) inelastic intensity below theta (wrongly counted into I_0)
        lost       = sum_{n>=1} N w_n (1 - sum(term_n)) intensity scattered beyond the axis end (missing from I_t)
        I_0 = (Z0 - zl_above) + inel_below
        I_t = N * sum_{n <= n_max} w_n - lost
        value = ln(I_t / I_0),  bias = value - tau.
  The record also holds the noiseless SUM-BASED value (the same ln of np.sum over the stored spectrum) and the
  difference between the two; they agree to rounding (asserted < 1e-12; the sums are exact-rounded math.fsum for the
  components and numpy pairwise sums for the spectrum).
  The estimated threshold of the method is not known here (it is exSpy's rule on the data), so the truth file also holds,
  per pixel, the bias for EVERY channel of the method's default search range (biasByChannel: ind = 220..419, the
  channels [value2index(1.0 eV), value2index(11.0 eV)) of the default window), computed the same way from the
  components. A port that finds channel c for a pixel looks up biasByChannel[c - 220] and the planted-spectrum gate
  is as tight for the estimated threshold as for the fixed ones. (An addition to the registration's fixed thresholds,
  reported as such.)

Every float in the JSON is written with Python's repr (shortest string that round-trips): reading it back gives the
identical float64.
"""
import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np

# ---------------------------------------------------------------- the registered constants (section 5.1)
OFFSET = -10.0
SCALE = 0.05
SIZE = 3400
K_ZERO = 200                      # channel of 0 eV
SIGMA_ZLP = 0.25                  # eV
EP = 15.0                         # eV
GAMMA = 0.8                       # eV
TAUS = [0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0, 1.3, 1.6, 2.0]
ROWS, COLS = 2, 5
N_COUNTS = 1.0e6
SEED = 20261014
THRESHOLDS = [2.5, 4.5, 6.0]      # eV, the fixed thresholds
STOP_FRACTION = 1e-14
BIAS_FIRST, BIAS_COUNT = 220, 200   # biasByChannel: ind = 220..419 (the default threshold search range, 1 eV to 11 eV)
MICROSCOPE = {"beamEnergyKeV": 200.0, "convergenceAngleMrad": 10.0, "collectionAngleMrad": 20.0}

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "..", "Tests", "SpectroEELSTests", "Fixtures"))


# ---------------------------------------------------------------- JSON writer: repr floats, short numeric lists inline
def _scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "null"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if not math.isfinite(v):
            raise ValueError("non-finite float in JSON")
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    raise TypeError(type(v))


def _dump(v, ind, out):
    pad = "  " * ind
    if isinstance(v, dict):
        if not v:
            out.append("{}")
            return
        out.append("{\n")
        items = list(v.items())
        for i, (k, x) in enumerate(items):
            out.append(pad + "  " + json.dumps(k) + ": ")
            _dump(x, ind + 1, out)
            out.append(",\n" if i + 1 < len(items) else "\n")
        out.append(pad + "}")
    elif isinstance(v, (list, tuple)):
        if all(not isinstance(x, (dict, list, tuple)) for x in v):
            out.append("[" + ", ".join(_scalar(x) for x in v) + "]")
        else:
            out.append("[\n")
            for i, x in enumerate(v):
                out.append(pad + "  ")
                _dump(x, ind + 1, out)
                out.append(",\n" if i + 1 < len(v) else "\n")
            out.append(pad + "]")
    else:
        out.append(_scalar(v))


def write_json(path, obj):
    out = []
    _dump(obj, 0, out)
    data = ("".join(out) + "\n").encode("utf-8")
    with open(path, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest()


def write_raw(path, arr):
    data = np.ascontiguousarray(arr, dtype="<f8").tobytes()
    with open(path, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest(), len(data)


# ---------------------------------------------------------------- the model
def conv_head(a, b, n):
    """First n entries of the full discrete convolution of a and b: out[m] = sum_{i+j=m} a[i] * b[j].
    One numpy vector add per non-zero b[j], j ascending: deterministic, no BLAS, no FFT."""
    out = np.zeros(n)
    for j in np.flatnonzero(b):
        if j >= n:
            break
        out[j:] += b[j] * a[: n - j]
    return out


def build():
    k = np.arange(SIZE)
    E = OFFSET + SCALE * k
    assert E[K_ZERO] == 0.0
    # zero-loss peak on the channel grid, unit sum
    Z = np.exp(-0.5 * (E / SIGMA_ZLP) ** 2)
    Z = Z / Z.sum()
    # Drude single-scattering on the loss-origin grid j = 0..3199, unit sum
    jmax = SIZE - K_ZERO              # 3200 losses: j = 0..3199
    S0 = np.zeros(SIZE)
    Ej = E[K_ZERO:]                   # E[200 + j] = loss of j (0.0 at j = 0 ... 159.95)
    num = Ej * GAMMA * EP**2
    den = (Ej**2 - EP**2) ** 2 + (Ej * GAMMA) ** 2
    s = np.zeros(jmax)
    s[1:] = num[1:] / den[1:]         # E > 0 strictly: j = 0 stays 0
    S0[:jmax] = s / s.sum()
    return E, Z, S0


class Terms:
    """term_n[m] = sum_k Z[k] S0^(*n)[m-k], computed on demand and cached."""

    def __init__(self, Z, S0):
        self.Z, self.S0 = Z, S0
        self.sn = [np.zeros(SIZE)]    # S0^(*0) = delta
        self.sn[0][0] = 1.0
        self.terms = []
        self.mass = []

    def get(self, n):
        while len(self.terms) <= n:
            i = len(self.terms)
            if i >= len(self.sn):
                self.sn.append(conv_head(self.sn[i - 1], self.S0, SIZE))
            t = conv_head(self.sn[i], self.Z, SIZE)       # loop over Z's non-zeros, vector over S0^(*i)
            self.terms.append(t)
            self.mass.append(math.fsum(t))
        return self.terms[n], self.mass[n]


def poisson_w(tau, n):
    return math.exp(-tau) * tau**n / math.factorial(n)


def make_spectrum(tau, terms):
    """Returns (I, zl, inel, n_max, tail_weight_neglected, terms_used) for one tau."""
    zl = N_COUNTS * poisson_w(tau, 0) * terms.get(0)[0]
    inel = np.zeros(SIZE)
    running = math.fsum(zl)
    n = 1
    while True:
        t, m = terms.get(n)
        w = poisson_w(tau, n)
        tsum = N_COUNTS * w * m
        if tsum < STOP_FRACTION * running:
            break
        inel += (N_COUNTS * w) * t
        running += tsum
        n += 1
    n_max = n - 1
    tail = math.fsum(poisson_w(tau, i) for i in range(n_max + 1, n_max + 60))
    return zl + inel, zl, inel, n_max, tail


def component_row(tau, ind, n_max, terms, Z, z0, i_t, lost):
    """The log-ratio the planted components imply for I_0 = the sum of channels [0, ind)."""
    w0 = poisson_w(tau, 0)
    zl_above = N_COUNTS * w0 * math.fsum(Z[ind:])
    inel_below = math.fsum(
        N_COUNTS * poisson_w(tau, n) * math.fsum(terms.get(n)[0][:ind]) for n in range(1, n_max + 1)
    )
    i_0 = (z0 - zl_above) + inel_below
    value = math.log(i_t / i_0)
    return {
        "index": ind, "zeroLossIntensity": z0, "zeroLossAboveTheta": zl_above,
        "inelasticBelowTheta": inel_below, "lostBeyondAxis": lost, "i0": i_0, "it": i_t,
        "logRatio": value, "bias": value - tau,
    }


def components(tau, n_max, terms, Z):
    """Per fixed threshold, and per channel of the default search range: the log-ratio the planted components imply,
    from the components (math.fsum)."""
    w0 = poisson_w(tau, 0)
    z0 = N_COUNTS * w0                                    # zero-loss intensity
    lost = math.fsum(N_COUNTS * poisson_w(tau, n) * (1.0 - terms.get(n)[1]) for n in range(1, n_max + 1))
    n_planted = N_COUNTS * math.fsum(poisson_w(tau, n) for n in range(n_max + 1))
    i_t = n_planted - lost
    rows = []
    for theta in THRESHOLDS:
        x = (theta - OFFSET) / SCALE
        ind = int(round(x))
        assert abs(x - ind) < 1e-9
        rows.append({"theta": theta, **component_row(tau, ind, n_max, terms, Z, z0, i_t, lost)})
    by_channel = [component_row(tau, ind, n_max, terms, Z, z0, i_t, lost)["bias"]
                  for ind in range(BIAS_FIRST, BIAS_FIRST + BIAS_COUNT)]
    return rows, by_channel


def sum_based(image_row, tau):
    out = []
    it = float(np.sum(image_row))
    for theta in THRESHOLDS:
        ind = int(round((theta - OFFSET) / SCALE))
        i0 = float(np.sum(image_row[:ind]))
        v = math.log(it / i0)
        out.append({"theta": theta, "i0": i0, "it": it, "logRatio": v, "bias": v - tau})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=DEFAULT_OUT, help="fixture directory (default: Tests/SpectroEELSTests/Fixtures)")
    args = ap.parse_args()
    out = args.out
    os.makedirs(out, exist_ok=True)

    E, Z, S0 = build()
    terms = Terms(Z, S0)

    image = np.zeros((ROWS, COLS, SIZE))
    per_pixel = []
    worst = 0.0
    for p, tau in enumerate(TAUS):
        r, c = divmod(p, COLS)
        spec, zl, inel, n_max, tail = make_spectrum(tau, terms)
        image[r, c, :] = spec
        comp, by_channel = components(tau, n_max, terms, Z)
        sb = sum_based(spec, tau)
        for a, b in zip(comp, sb):
            d = abs(a["logRatio"] - b["logRatio"])
            worst = max(worst, d)
            assert d < 1e-12, (tau, a["theta"], d)
            b["differenceFromComponents"] = b["logRatio"] - a["logRatio"]
        per_pixel.append({
            "row": r, "col": c, "tau": tau, "nMax": n_max, "tailWeightNeglected": tail,
            "sumOfSpectrum": float(np.sum(spec)),
            "components": comp, "sumBased": sb,
            "biasByChannel": {"firstChannel": BIAS_FIRST, "bias": by_channel},
        })

    noisy = np.random.default_rng(SEED).poisson(image).astype(np.float64)

    np_ver = np.__version__
    axis = {"offset": OFFSET, "scale": SCALE, "size": SIZE, "units": "eV", "binned": True}
    layout = {"shape": [ROWS, COLS, SIZE], "dtype": "float64", "byteOrder": "little",
              "order": "C: rows, cols, channels (row-major; pixel index = row * 5 + col)"}
    microscope = {**MICROSCOPE, "note": "assigned for the absolute-thickness pins (registration section 4); "
                                       "not a property of the planted physics"}

    h_clean, n_clean = write_raw(os.path.join(out, "planted-noiseless.f64"), image)
    h_noisy, n_noisy = write_raw(os.path.join(out, "planted-noisy.f64"), noisy)

    common_prov = {
        "generator": "tools/eels-thickness/make_planted.py",
        "registration": "docs/eels-slice-1-registration.md section 5.1",
        "numpyVersion": np_ver,
        "licence": "SpectroKit's own (GPL-3.0-only); generated, no third-party data",
        "tauRowMajor": TAUS, "countsN": N_COUNTS,
        "model": "Poisson plural scattering of a Gaussian zero-loss peak (sigma 0.25 eV at 0 eV) and a Drude "
                 "single-scattering distribution (Ep 15.0 eV, Gamma 0.8 eV, unit sum); see the generator's docstring",
    }
    write_json(os.path.join(out, "planted-noiseless.json"), {
        "schema": "spectrokit.eels.raw-f64/1", "file": "planted-noiseless.f64", **layout,
        "energyAxis": axis, "microscope": microscope, "bytes": n_clean, "sha256": h_clean,
        "provenance": {**common_prov, "kind": "noiseless"},
    })
    write_json(os.path.join(out, "planted-noisy.json"), {
        "schema": "spectrokit.eels.raw-f64/1", "file": "planted-noisy.f64", **layout,
        "energyAxis": axis, "microscope": microscope, "bytes": n_noisy, "sha256": h_noisy,
        "provenance": {**common_prov, "kind": "poisson-noised copy of planted-noiseless.f64",
                       "noise": {"seed": SEED,
                                 "call": "numpy.random.default_rng(20261014).poisson(noiseless) once, on the "
                                         "(2, 5, 3400) float64 array in C order, result stored as float64",
                                 "noiselessSha256": h_clean}},
    })

    truth = {
        "schema": "spectrokit.eels.planted-truth/1",
        "generator": "tools/eels-thickness/make_planted.py",
        "numpyVersion": np_ver,
        "energyAxis": axis,
        "image": {"rows": ROWS, "cols": COLS, "order": "row-major", "tau": TAUS},
        "files": {"noiseless": {"file": "planted-noiseless.f64", "sha256": h_clean},
                  "noisy": {"file": "planted-noisy.f64", "sha256": h_noisy}},
        "thresholdRule": {
            "thresholdsEV": THRESHOLDS,
            "channelIndex": [int(round((t - OFFSET) / SCALE)) for t in THRESHOLDS],
            "i0": "sum of channels [0, index): the channels with E < theta; the channel at theta is excluded",
            "it": "sum of all 3400 channels",
            "value": "ln(it / i0); bias = value - tau",
            "biasByChannel": "per pixel: bias for I_0 = the sum of channels [0, firstChannel + i), i = 0..199 "
                             "(firstChannel 220 = value2index(1.0 eV)); for the estimated threshold, look up the channel found",
        },
        "model": {"sigmaZeroLossEV": SIGMA_ZLP, "plasmonEnergyEV": EP, "gammaEV": GAMMA,
                  "countsN": N_COUNTS, "stopFraction": STOP_FRACTION},
        "pixels": per_pixel,
        "worstComponentVsSumDifference": worst,
        "noise": {"seed": SEED, "realisationsForTheGate": "seeds 1..200, generated in the test, not stored"},
    }
    write_json(os.path.join(out, "planted-truth.json"), truth)

    print(f"worst |components - sum-based| = {worst:.3e}")
    for px in per_pixel:
        print(f"tau {px['tau']:<5} nMax {px['nMax']:>2}  " + "  ".join(
            f"bias@{c['theta']}={c['bias']:+.6f}" for c in px["components"]))


if __name__ == "__main__":
    sys.exit(main())
