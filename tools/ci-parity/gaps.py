#!/usr/bin/env python3
"""Measure Double pairs actually printed in a Swift Testing GitHub Actions log.

Usage: gh run view RUN --job JOB --log -R mac4DSTEM/SpectroKit > .build/ci-main.log
       python3 -I -B tools/ci-parity/gaps.py .build/ci-main.log

No oracle is run and no reference fixture is rewritten. Missing operands are
reported as unavailable; mismatch counts are not enough to infer a numeric gap.
"""
import json
import math
import re
import struct
import sys


def double(bits):
    return struct.unpack('>d', struct.pack('>Q', int(bits)))[0]


def ordered(value):
    bits = struct.unpack('>Q', struct.pack('>d', value))[0]
    magnitude = bits & ((1 << 63) - 1)
    return (1 << 63) - magnitude if bits >> 63 else (1 << 63) + magnitude


def gap(actual, reference):
    if not (math.isfinite(actual) and math.isfinite(reference)):
        return {'actual': str(actual), 'reference': str(reference), 'ulps': None, 'relative': None}
    return {'actual': actual, 'reference': reference,
            'ulps': abs(ordered(actual) - ordered(reference)) if actual != reference else 0,
            'relative': abs(actual - reference) / abs(reference) if reference else None,
            'absolute': abs(actual - reference)}


def analyze(text):
    rows = []
    for line in text.splitlines():
        # Golden tests compare a Swift baseline, not a Python reference.
        m = re.search(r'↳ (.*?) moved at line (\d+): now .*? = ([0-9a-f]{16}) [^|]+\| baseline .*? = ([0-9a-f]{16})', line)
        if m:
            rows.append({'test': 'testOutputsAreByteIdenticalToTheBaseline', 'detail': m[1],
                         'referenceKind': 'Swift golden', **gap(double(int(m[3], 16)), double(int(m[4], 16)))})
        m = re.search(r'Test (\w+)\(\) recorded an issue at (\S+): (.*)', line)
        if not m:
            continue
        test, location, assertion = m.groups()
        pairs = []
        bits = re.search(r'bitPattern → (\d+)\).*?bitPattern → (\d+)\)', assertion)
        arrays = re.search(r'ours.map.*?→ \[([\d, ]+)\].*?pinned.map.*?→ \[([\d, ]+)\]', assertion)
        numbers = re.search(r'isEqual\(\(a0? → ([^ )]+)\), \(e0? → ([^ )]+)\)', assertion)
        if bits:
            pairs = [(double(bits[1]), double(bits[2]))]
        elif arrays:
            pairs = [(double(a), double(b)) for a, b in zip(arrays[1].split(', '), arrays[2].split(', '))]
        elif numbers:
            pairs = [(float(numbers[1]), float(numbers[2]))]
        else:
            numbers = re.search(r'px.thresholdEV → ([^ )]+)\) == \(e → ([^ )]+)\)', assertion)
            if numbers:
                pairs = [(float(numbers[1]), float(numbers[2]))]
        for index, (a, b) in enumerate(pairs):
            rows.append({'test': test, 'location': location, 'element': index, 'referenceKind': 'Python pin', **gap(a, b)})
        if not pairs and test != 'testOutputsAreByteIdenticalToTheBaseline':
            rows.append({'test': test, 'location': location, 'measurement': 'unavailable: operands not logged', 'assertion': assertion})
    return rows


if __name__ == '__main__':
    with open(sys.argv[1], encoding='utf-8') as stream:
        print(json.dumps(analyze(stream.read()), indent=2, allow_nan=False))
