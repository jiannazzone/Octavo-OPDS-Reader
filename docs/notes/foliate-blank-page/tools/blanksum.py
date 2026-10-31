"""Summarize mode=blank driver results. Usage: blanksum.py LOGFILE [label-substring]"""
import json
import sys

logfile = sys.argv[1]
needle = sys.argv[2] if len(sys.argv) > 2 else ''
TESTS = ['render', 'resize', 'bodyResize', 'restoreCFI', 'nextThenPrev', 'nextThenPrevThenRender']


def loc(h):
    text = (h.get('range') or {}).get('text', '')
    return f"s{h['index']} p{h['page']}/{h['pages']} {h['cfi']} {text[:28]!r}"


for line in open(logfile):
    d = json.loads(line)
    if needle not in d.get('label', '') or 'blank' not in d:
        continue
    b = d['blank']
    print(f"== {d['label']} ({d['book']} s{d['section']} p{b['page']}, {d['w']}x{d['h']})")
    if d.get('errors'):
        print('   ERRORS:', d['errors'][:3])
    first = b.get('render', {}).get('landed')
    if first:
        print(f"   landed:      {loc(first)}")
    for name in TESTS:
        t = b.get(name)
        if not t:
            continue
        ok = t['after']['page'] == t['landed']['page'] and t['after']['index'] == t['landed']['index']
        extra = ''
        if name == 'nextThenPrev':
            extra = f"  (next -> p{b['nextThenPrev_next']['page']})"
        print(f"   {name:24s} -> {loc(t['after'])} {'STAYED' if ok else 'MOVED'}{extra}")
