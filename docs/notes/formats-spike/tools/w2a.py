#!/usr/bin/env python3
"""Web → app position check on the simulator (formats spike).

    SIM=<udid> w2a.py runs/w2a-sources.tsv BOOK_BASENAME > runs/w2a.tsv

For each row of the sources file (positions read from BookOrbit's web reader
for the same file bytes, and confirmed as what the server stores): opens
BOOK_BASENAME.<format> in the app, goes to the web reader's CFI with the
`goto` command (what the app does with a pulled server position), and
checks that the page holds the web page's first 8 words. A straddle (the
words start on this page and run onto the next) counts as a hit, as in
sync-spike.md.

Also records extra app positions for app → web rows (APP_EXTRA=1): 30% and
70% plus three page turns, mid-chapter.
"""
import csv
import json
import os
import re
import subprocess
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import importlib.util
spec = importlib.util.spec_from_file_location('simcheck', os.path.join(TOOLS, 'sim-check.py'))
simcheck = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simcheck)


def norm(text):
    text = text.replace('’', "'").replace('‘', "'").replace('“', '"').replace('”', '"')
    return re.sub(r'\s+', ' ', text).strip()


def verdict(source_words, page_text):
    words, text = norm(source_words), norm(page_text)
    if words in text:
        return 'hit'
    # Straddle: the page ends with a prefix of the source words.
    parts = words.split(' ')
    for n in range(len(parts) - 1, 1, -1):
        if text.endswith(' '.join(parts[:n])):
            return f'hit (straddle {n}/{len(parts)})'
    return 'miss'


def open_book(name):
    simcheck.app('"cmd":"home"', wait=False)
    time.sleep(1)
    started = time.time()
    simcheck.app(f'"cmd":"openLocal","name":{json.dumps(name)}', wait=False)
    simcheck.wait_for_open(name, started)
    simcheck.settle()


def main():
    sources, base = sys.argv[1], sys.argv[2]
    rows = list(csv.DictReader(open(sources), delimiter='\t'))
    out = csv.writer(sys.stdout, delimiter='\t', lineterminator='\n')
    out.writerow(['format', 'position', 'webCFI', 'webFirstWords', 'appLandedCFI', 'appFraction', 'appFirstWords', 'verdict'])
    current = None
    for row in rows:
        book = f'{base}.{row["format"]}'
        if book != current:
            open_book(book)
            current = book
        simcheck.app(f'"cmd":"goto","cfi":{json.dumps(row["webCFI"])}')
        s = simcheck.settle()
        text = s.get('visibleText') or ''
        out.writerow([row['format'], row['position'], row['webCFI'], row['webFirstWords'],
                      s.get('cfi'), round(s.get('fraction') or 0, 5), simcheck.words(text),
                      verdict(row['webFirstWords'], text)])
        sys.stdout.flush()
    if os.environ.get('APP_EXTRA'):
        for fmt in ('mobi', 'azw3', 'fb2'):
            open_book(f'{base}.{fmt}')
            for fraction in (0.3, 0.7):
                simcheck.app(f'"cmd":"goto","fraction":{fraction}')
                for _ in range(3):
                    simcheck.app('"cmd":"next"', settle='1')
                s = simcheck.settle()
                print(json.dumps({'extra': fmt, 'position': f'{fraction}+3', 'cfi': s.get('cfi'),
                                  'fraction': s.get('fraction'), 'words': simcheck.words(s.get('visibleText'))}),
                      file=sys.stderr, flush=True)


if __name__ == '__main__':
    main()
