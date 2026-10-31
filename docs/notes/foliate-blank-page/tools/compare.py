"""Compare mode=dump results of two foliate-js versions page by page.

Usage: compare.py LOGFILE [base=main] [other=patched]
For each engine and book, pairs pages by (section, step). Reports pages whose
layout differs, CFIs that differ on pages where the base had visible content,
and what each version reported on blank pages (base fell back to <body>).
"""
import json
import sys
from collections import defaultdict

logfile = sys.argv[1]
base = sys.argv[2] if len(sys.argv) > 2 else 'main'
other = sys.argv[3] if len(sys.argv) > 3 else 'patched'

runs = {}
for line in open(logfile):
    d = json.loads(line)
    if 'dump' not in d:
        continue
    engine = d['label'].split('-')[0]
    runs[(engine, d['label'].split('-dump-')[1], d['ver'])] = d  # later runs win

total = defaultdict(int)
for (engine, book, ver), d in sorted(runs.items()):
    if ver != base or (engine, book, other) not in runs:
        continue
    a = {(p['s'], p['i']): p for p in d['dump']}
    b = {(p['s'], p['i']): p for p in runs[(engine, book, other)]['dump']}
    keys = sorted(set(a) | set(b))
    same = layout = differ = blank = missing = 0
    notes = []
    for k in keys:
        pa, pb = a.get(k), b.get(k)
        if not pa or not pb:
            missing += 1
            notes.append(f'      missing in {"base" if not pa else "other"}: s{k[0]} step {k[1]}')
            continue
        if (pa['page'], pa['pages']) != (pb['page'], pb['pages']):
            layout += 1
            notes.append(f'      layout differs s{k[0]} step {k[1]}: p{pa["page"]}/{pa["pages"]} vs p{pb["page"]}/{pb["pages"]}')
            continue
        if (pa.get('range') or {}).get('isBodyFallback'):
            blank += 1
            notes.append(f'      blank s{k[0]} p{pa["page"]}/{pa["pages"]}: {base} {pa["cfi"]} -> {other} {pb["cfi"]}')
            continue
        if pa['cfi'] == pb['cfi']:
            same += 1
        else:
            differ += 1
            notes.append(f'      CFI DIFFERS s{k[0]} p{pa["page"]}: {pa["cfi"]} vs {pb["cfi"]}')
    print(f'{engine:6s} {book:28s} pages={len(keys):4d} same-cfi={same:4d} '
          f'blank={blank:3d} cfi-differs={differ} layout-differs={layout} missing={missing}')
    for n in notes:
        print(n)
    for key, value in (('pages', len(keys)), ('same', same), ('blank', blank), ('differ', differ)):
        total[key] += value
print('TOTAL', dict(total))
