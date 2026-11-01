#!/usr/bin/env python3
"""Markdown table from fold-run.py output (formats spike).

    python3 -I fold-summary.py runs/folds.jsonl

Per book: folds back to closed that returned the exact origin CFI; unfolds
and half-opens whose spread contains the origin (foliate's CFI order) and
its first 8 words; spreads with text on the fold; settle timeouts.
"""
import json
import sys
from collections import defaultdict

runs = defaultdict(list)
for line in open(sys.argv[1]):
    r = json.loads(line)
    runs[r['label']].append(r)

print('| Book | Folded back: exact CFI | Unfolded / half-open: contains origin + words | Text on the fold | Timeouts |')
print('|---|---|---|---|---|')
for label, steps in runs.items():
    moves = [s for s in steps if s['step'] != 'origin']
    closes = [s for s in moves if s['posture'] == 'closed']
    opens = [s for s in moves if s['posture'] in ('open', 'halfOpen')]
    exact = sum(1 for s in closes if s['exact'])
    held = sum(1 for s in opens if s['contains'] and s['words'])
    crossing = sum(1 for s in opens if s['crossing'])
    timeouts = sum(1 for s in steps if s['timedOut'])
    print(f'| {label} | {exact}/{len(closes)} | {held}/{len(opens)} | {crossing} | {timeouts} |')
