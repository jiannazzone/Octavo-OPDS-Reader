#!/usr/bin/env python3
"""Per-book reader checks on the simulator (formats spike).

    SIM=<udid> sim-check.py BOOK... > results.jsonl

Drives the spike app through its DEBUG command file (docs/notes/duo-spreads/
tools/app.sh, Octavo/Spike/SpikeRemote.swift), folded, one JSON line per book:

- open: seconds from the command to the first state, how it restored, title;
- paging: three page turns, each must move (new CFI, fraction not going back,
  text on the page);
- positions: go to 12%, 50% and 88% and turn two pages (as in sync-spike.md),
  recording the point CFI and the page's first 8 words;
- goto: from the 88% page, go back to the 50% CFI and then the 12% CFI; the
  page must show the same first words and report the same CFI;
- relaunch: at the 50% position, kill the app and launch it again; the spike
  library reopens the book, which must land on the same CFI and words.

Folds are checked separately with docs/notes/duo-spreads/tools/fold-run.py.
"""
import json
import os
import subprocess
import sys
import time

SIM = os.environ['SIM']
TOOLS = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(TOOLS, '../../duo-spreads/tools/app.sh')
BUNDLE = 'com.ianazzone.ereader'


def documents():
    out = subprocess.run(['xcrun', 'simctl', 'get_app_container', SIM, BUNDLE, 'data'],
                         capture_output=True, text=True, check=True)
    return os.path.join(out.stdout.strip(), 'Documents')


def app(command, settle='1.5', wait=True):
    env = dict(os.environ, SETTLE=settle)
    if not wait:
        env['NOWAIT'] = '1'
    out = subprocess.run([APP, command], capture_output=True, text=True, env=env)
    if out.stderr.strip():
        print(f'app.sh: {out.stderr.strip()}', file=sys.stderr)
    try:
        return json.loads(out.stdout) if out.stdout.strip() else {}
    except ValueError:
        return {}


def state():
    try:
        return json.load(open(os.path.join(documents(), 'spike-state.json')))
    except (OSError, ValueError):
        return {}


def words(text, n=8):
    return ' '.join((text or '').split()[:n])


def page(s):
    return {
        'cfi': s.get('cfi'),
        'fraction': s.get('fraction'),
        'words': words(s.get('visibleText')),
        'chars': len(s.get('visibleText') or ''),
        'blank': s.get('blankPage'),
        'toc': s.get('tocLabel'),
    }


def wait_for_open(book, since, timeout=180):
    """The first state for `book` written after `since` (epoch seconds)."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        s = state()
        updated = s.get('updatedAt')
        if s.get('bookID') == book and updated and time.mktime(time.strptime(updated, '%Y-%m-%dT%H:%M:%SZ')) - time.timezone >= since - 1:
            return s, time.time() - since
        time.sleep(0.25)
    return {}, None


def settle():
    """Two state reads 1.5 s apart that agree."""
    last = None
    for _ in range(20):
        time.sleep(1.5)
        s = state()
        key = (s.get('cfi'), s.get('relocations'))
        if key == last:
            return s
        last = key
    return state()


def check(book):
    result = {'book': book}
    app('"cmd":"home"', wait=False)
    time.sleep(1)
    started = time.time()
    app(f'"cmd":"openLocal","name":{json.dumps(book)}', wait=False)
    s, seconds = wait_for_open(book, started)
    if not s:
        return result | {'error': 'did not open'}
    s = settle()
    result['open'] = {'seconds': round(seconds, 1), 'restoredFrom': s.get('restoredFrom'),
                      'title': s.get('title'), **page(s)}

    turns = []
    for _ in range(3):
        app('"cmd":"next"', settle='1')
        turns.append(page(settle()))
    pages = [result['open']] + turns
    result['paging'] = {
        'pages': turns,
        'ok': all(b['cfi'] != a['cfi'] and (b['fraction'] or 0) >= (a['fraction'] or 0) and b['chars'] > 0
                  for a, b in zip(pages, pages[1:])),
    }

    positions = {}
    for fraction in (0.12, 0.5, 0.88):
        app(f'"cmd":"goto","fraction":{fraction}')
        for _ in range(2):
            app('"cmd":"next"', settle='1')
        positions[str(fraction)] = page(settle())
    result['positions'] = positions

    gotos = {}
    for key in ('0.5', '0.12'):
        target = positions[key]
        app(f'"cmd":"goto","cfi":{json.dumps(target["cfi"])}')
        landed = page(settle())
        gotos[key] = {'landed': landed, 'sameCFI': landed['cfi'] == target['cfi'],
                      'sameWords': landed['words'] == target['words']}
    result['goto'] = gotos

    target = positions['0.5']
    app(f'"cmd":"goto","cfi":{json.dumps(target["cfi"])}')
    before = page(settle())
    subprocess.run(['xcrun', 'simctl', 'terminate', SIM, BUNDLE], capture_output=True)
    time.sleep(1)
    started = time.time()
    subprocess.run(['xcrun', 'simctl', 'launch', SIM, BUNDLE], capture_output=True)
    s, seconds = wait_for_open(book, started)
    s = settle() if s else s
    after = page(s)
    result['relaunch'] = {'before': before, 'after': after, 'restoredFrom': s.get('restoredFrom'),
                          'seconds': seconds and round(seconds, 1),
                          'sameCFI': after['cfi'] == before['cfi'], 'sameWords': after['words'] == before['words']}
    return result


if __name__ == '__main__':
    for book in sys.argv[1:]:
        print(json.dumps(check(book)), flush=True)
