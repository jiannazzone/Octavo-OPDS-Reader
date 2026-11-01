#!/usr/bin/env python3
"""Markdown table from sim-check.py output (formats spike).

    python3 -I sim-summary.py results.jsonl
"""
import json
import sys

print('| Book | Opens (s) | Paging | 12% / 50% / 88% point CFIs | Go to CFI | Relaunch |')
print('|---|---|---|---|---|---|')
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get('error'):
        print(f'| {r["book"]} | {r["error"]} | | | | |')
        continue
    pos = ' / '.join(f'`{p["cfi"].removeprefix("epubcfi(").removesuffix(")")}`' for p in r['positions'].values())
    goto = 'same CFI + words' if all(g['sameCFI'] and g['sameWords'] for g in r['goto'].values()) else \
        '; '.join(f'{k}: cfi {g["sameCFI"]}, words {g["sameWords"]}' for k, g in r['goto'].items())
    rel = r['relaunch']
    relaunch = f'same CFI + words ({rel["restoredFrom"]})' if rel['sameCFI'] and rel['sameWords'] else \
        f'cfi {rel["sameCFI"]}, words {rel["sameWords"]} ({rel["restoredFrom"]})'
    print(f'| {r["book"]} | {r["open"]["seconds"]} | {"ok" if r["paging"]["ok"] else "FAIL"} | {pos} | {goto} | {relaunch} |')
