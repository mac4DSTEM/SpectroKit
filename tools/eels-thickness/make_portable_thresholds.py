#!/usr/bin/env python3
"""Pinned SciPy derivatives plus SpectroKit's documented numerical-tie policy.

Run from SpectroKit (never on CI), under a memory cap:
../References/python/hyperspy/bin/python -I -B tools/eels-thickness/make_portable_thresholds.py
Retains all raw exSpy/SciPy fixtures. This is a deliberate policy deviation, not
an assertion that raw exSpy chooses the same channels on different CPUs.
"""
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
import scipy
from scipy.signal import savgol_coeffs, savgol_filter
import hyperspy
from hyperspy.axes import UniformDataAxis

assert np.__version__ == '2.5.4', np.__version__
assert scipy.__version__ == '1.18.1', scipy.__version__
assert hyperspy.__version__ == '2.4.0', hyperspy.__version__
ROOT = Path(__file__).resolve().parents[2]
FIX = ROOT / 'Tests/SpectroEELSTests/Fixtures'


def finite(v):
    return float(v) if np.isfinite(v) else None


def oracle(name, route_index, data, axis, route, raw):
    ax = UniformDataAxis(offset=axis['offset'], scale=axis['scale'], size=axis['size'])
    start = route.get('start', 1.0)
    lo, hi = ax.value_range_to_indices(start, start + route.get('window', 10.0))
    cropped = data[:, lo:hi]
    wl, po = route.get('windowLength', 5), route.get('polynomialOrder', 3)
    coeff = savgol_coeffs(wl, po, deriv=1, delta=ax.scale)
    derivative = savgol_filter(cropped, wl, po, deriv=1, delta=ax.scale, axis=-1)
    minima = np.min(np.abs(derivative), axis=-1)
    tol = float(np.max(minima))
    # Sequential sums and separated multiplies match the specified policy.
    l1 = sum(abs(float(c)) for c in coeff)
    slack = [((64 * sys.float_info.epsilon) * max(abs(float(x)) for x in row)) * l1 for row in cropped]
    hits = [int(np.argmax(np.abs(row) <= tol + error)) for row, error in zip(derivative, slack)]
    channels = [lo + hit if hit else None for hit in hits]
    energy = [float(ax.axis[lo]) + ax.scale * hit if hit else None for hit in hits]
    it = data.sum(axis=-1)
    i0 = [finite(data[p, :channel].sum()) if channel is not None else None for p, channel in enumerate(channels)]
    with np.errstate(divide='ignore', invalid='ignore'):
        tl = [finite(np.log(it[p] / value)) if value is not None else None for p, value in enumerate(i0)]
    old = raw.get('thrEV', raw.get('thresholdEV'))
    changed = [p for p, (a, b) in enumerate(zip(energy, old)) if a != b]
    return dict(name=name, routeIndex=route_index, firstChannel=lo, channels=hi-lo, windowLength=wl,
                polynomialOrder=po, coefficientL1=l1, tol=tol, minAbsDerivative=minima.tolist(), slack=slack,
                inflexionIndex=hits, thresholdChannel=channels, thresholdEV=energy, i0=i0,
                it=it.tolist(), tOverLambda=tl, changedFromRawExSpy=changed,
                rawThresholdEV=old, selectedAbsDerivative=[float(abs(derivative[p, hit])) for p, hit in enumerate(hits)])


rows = []
inputs = {}
pins = json.loads((FIX / 'pins.json').read_text())
for case in pins['cases']:
    path = FIX / case['file']
    inputs[case['file']] = hashlib.sha256(path.read_bytes()).hexdigest()
    data = np.fromfile(path, dtype='<f8').reshape(-1, case['energyAxis']['size'])
    rows.append(oracle(case['name'], 0, data, case['energyAxis'], {}, case['estimated']))
for directory in sorted((FIX / 'refuter').iterdir()):
    spec = json.loads((directory / 'spec.json').read_text())
    path = directory / 'data.f64'
    inputs[str(path.relative_to(FIX))] = hashlib.sha256(path.read_bytes()).hexdigest()
    data = np.fromfile(path, dtype='<f8').reshape(-1, spec['size'])
    raw = json.loads((directory / 'exspy.json').read_text())
    for i, entry in enumerate(raw):
        route = entry['route']
        if route['kind'] == 'estimated' and route.get('windowLength', 5) != 0 and route.get('tolerance') is None:
            rows.append(oracle(spec['name'], i, data, spec, route, entry['exspy']))
result = dict(schema='spectrokit.eels.portable-thresholds/1',
              reference=dict(numpy=np.__version__, scipy=scipy.__version__, hyperspy=hyperspy.__version__, exspy='7185a4d1'),
              policy='auto SG only: first abs(d) <= max(pixel minima) + 64*eps*maxAbs(cropped row)*coefficientL1; index zero remains unavailable',
              inputsSHA256=inputs, routes=rows)
path = FIX / 'portable-thresholds.json'
path.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
print(f'{path}: {len(rows)} routes, {sum(len(r["inflexionIndex"]) for r in rows)} pixel answers; {sum(len(r["changedFromRawExSpy"]) for r in rows)} changed thresholds')
