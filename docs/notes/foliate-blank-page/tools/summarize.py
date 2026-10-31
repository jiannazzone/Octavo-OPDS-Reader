"""Print a compact per-step summary of driver results.

Usage: python3 -I summarize.py LOGFILE [label-substring] [-v]
"""
import json
import sys

logfile = sys.argv[1]
needle = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != '-v' else ''
verbose = '-v' in sys.argv

with open(logfile) as f:
    rows = [json.loads(line) for line in f]

for d in rows:
    if needle not in d.get('label', '') or 'ver' not in d:
        continue
    ua = d.get('ua', '')
    print(f"== {d['label']}  ver={d['ver']} book={d['book']} {d['w']}x{d['h']} dpr={d.get('dpr')}")
    print(f"   ua: {ua}")
    if d.get('errors'):
        print('   ERRORS:', d['errors'][:3])
    print('   start:', d.get('start'))
    for s in d.get('steps_', []):
        st = s['settled']
        rel = [e for e in s['events'] if e['type'] == 'relocate']
        first = rel[0] if rel else {}
        flags = []
        if s['landedOnBody']:
            flags.append('BODY-FALLBACK')
        if s['jumped']:
            flags.append(f"JUMP {s['afterTurn']['page']}->{st['page']}")
        rnd = s.get('render')
        if rnd and rnd['pageBefore'] != rnd['pageAfter']:
            flags.append(f"RENDER-MOVED {rnd['pageBefore']}->{rnd['pageAfter']}")
        if rnd and rnd['cfiBefore'] != rnd['cfiAfter']:
            flags.append('RENDER-CFI-CHANGED')
        rs = s.get('resize')
        if rs and rs['pageBefore'] != rs['pageAfter']:
            flags.append(f"RESIZE-MOVED {rs['pageBefore']}->{rs['pageAfter']}")
        print(f"   step {s['i']}: idx {s['before']['index']} p{s['before']['page']} -> "
              f"idx {st['index']} p{st['page']}/{st['pages']}  turn-relocate="
              f"{first.get('reason')} frac={first.get('fraction')!s:.6} cfi={first.get('cfi')} {' '.join(flags)}")
        print(f"            settled cfi={st['cfi']}  text={st['range'] and st['range']['text'][:40]!r}")
        if verbose:
            for e in s['events']:
                print('              ', json.dumps({k: v for k, v in e.items() if k != 'range'}),
                      e.get('range', {}) and e['range'].get('start'))
            if rnd:
                for e in rnd['events']:
                    print('              render:', json.dumps({k: v for k, v in e.items() if k != 'range'}))
