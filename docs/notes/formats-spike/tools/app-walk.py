#!/usr/bin/env python3
"""cfi-walk.js in the real app on the simulator (formats check, step 15).

    SIM=<udid> [STEP=1 TURNS=2] app-walk.py OUT_DIR MODE BOOK...

MODE is `harden` (the app as it ships) or `noharden` (the bridge's second
layer off, `-readerWithoutHarden`, DEBUG builds only). For each book: opens
it through the debug remote (`openLocal`), runs cfi-walk.js in the reader
page, and writes OUT_DIR/<MODE>-<book>.json. compare-walk.py OUT_DIR then
compares the two modes: the second layer must not move a single position.

Headless: it only writes the debug remote's command file and reads its
answers; nothing opens on the Mac.
"""
import json
import os
import subprocess
import sys
import time

SIM = os.environ['SIM']
TOOLS = os.path.dirname(os.path.abspath(__file__))
BUNDLE = 'com.ianazzone.ereader'
out, mode, books = sys.argv[1], sys.argv[2], sys.argv[3:]
os.makedirs(out, exist_ok=True)
walk = open(os.path.join(TOOLS, 'cfi-walk.js')).read() \
    .replace('__STEP__', os.environ.get('STEP', '1')).replace('__TURNS__', os.environ.get('TURNS', '2'))


def documents():
    path = subprocess.run(['xcrun', 'simctl', 'get_app_container', SIM, BUNDLE, 'data'],
                          capture_output=True, text=True, check=True).stdout.strip()
    return os.path.join(path, 'Documents')


def command(cmd, timeout=900, **fields):
    docs = documents()
    ident = int(time.time() * 1000)
    ack = os.path.join(docs, 'spike-ack.json')
    if os.path.exists(ack):
        os.remove(ack)
    tmp = os.path.join(docs, 'spike-command.json.tmp')
    with open(tmp, 'w') as f:
        json.dump({'id': ident, 'cmd': cmd, **fields}, f)
    os.replace(tmp, os.path.join(docs, 'spike-command.json'))
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data = json.load(open(ack))
            if data.get('id') == ident:
                return data
        except (OSError, ValueError):
            pass
        time.sleep(0.3)
    return {'ok': False, 'message': 'timeout'}


def reader_id(book):
    import hashlib
    return 'book-' + hashlib.sha256(book.encode()).hexdigest()[:32]


def state():
    try:
        return json.load(open(os.path.join(documents(), 'spike-state.json')))
    except (OSError, ValueError):
        return {}


subprocess.run(['xcrun', 'simctl', 'terminate', SIM, BUNDLE], capture_output=True)
args = ['-readerWithoutHarden', '1'] if mode == 'noharden' else ['-readerWithoutHarden', '0']
subprocess.run(['xcrun', 'simctl', 'launch', SIM, BUNDLE, *args], capture_output=True)
time.sleep(8)
for book in books:
    command('home')
    time.sleep(1)
    command('openLocal', name=book)
    started = time.time()
    while time.time() - started < 120 and state().get('bookID') not in (book, reader_id(book)):
        time.sleep(0.5)
    time.sleep(3)
    result = command('js', script=walk)
    try:
        answer = json.load(open(os.path.join(documents(), 'spike-js.json')))
    except (OSError, ValueError) as e:
        answer = {'error': str(e)}
    # compare-walk.py reads `report`, as the harness wrote it.
    report = {'report': answer.get('result') or {}, 'error': answer.get('error'), 'ack': result}
    with open(os.path.join(out, f'{mode}-{book}.json'), 'w') as f:
        json.dump(report, f)
    positions = report['report'].get('positions') or []
    print(f'{mode} {book}: {len(positions)} positions, ack {result.get("ok")}', flush=True)
