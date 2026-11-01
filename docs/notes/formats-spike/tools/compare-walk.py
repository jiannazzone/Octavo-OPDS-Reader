#!/usr/bin/env python3
"""Compares cfi-walk.js runs of two harness modes (formats spike).

    python3 -I compare-walk.py DIR [MODE_A] [MODE_B]

Defaults: `csp` against `csp+sanitize+meta`. For each book run in both
modes: how many positions came back with the same CFI and the same first
words, and the first differences.
"""
import glob
import json
import os
import sys

d = sys.argv[1]
a_mode = sys.argv[2] if len(sys.argv) > 2 else 'csp'
b_mode = sys.argv[3] if len(sys.argv) > 3 else 'csp+sanitize+meta'
total = same = 0
for f in sorted(glob.glob(os.path.join(d, f'{a_mode}-*.json'))):
    book = os.path.basename(f)[len(a_mode) + 1:-5]
    g = os.path.join(d, f'{b_mode}-{book}.json')
    try:
        a = json.load(open(f))['report']['positions']
        b = json.load(open(g))['report']
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f'{book}: not comparable ({type(e).__name__})')
        continue
    bp = b['positions']
    pairs = list(zip(a, bp))
    ok = sum(1 for x, y in pairs if x['cfi'] == y['cfi'] and x['words'] == y['words'])
    diffs = [(x['section'], x['cfi'], y['cfi']) for x, y in pairs if x['cfi'] != y['cfi'] or x['words'] != y['words']]
    total += max(len(a), len(bp))
    same += ok
    print(f'{book}: {ok}/{max(len(a), len(bp))} identical (sections hardened: {b.get("harden")})'
          + (f'; first differences {diffs[:3]}' if diffs else ''))
print(f'total: {same}/{total} identical')
