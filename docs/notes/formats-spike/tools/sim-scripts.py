#!/usr/bin/env python3
"""Script-test books in the real app on the simulator (formats spike).

    SIM=<udid> sim-scripts.py OUT_DIR BOOK...

For each book: starts beacon.py with a fresh log, opens the book through the
spike app's DEBUG command file, runs collect.js in the reader page with the
`js` command (every section visited, every link clicked), and writes
`app-<book>.json` and `app-<book>.beacon.jsonl` for summarize.py. Also saves a
screenshot of the vectors section. The app's own log (book scripts that
reached the message handler would show as "foliate error: BOOK SCRIPT RAN")
is best captured alongside with `log stream`.
"""
import json
import os
import subprocess
import sys
import time

SIM = os.environ['SIM']
TOOLS = os.path.dirname(os.path.abspath(__file__))
BUNDLE = 'com.ianazzone.ereader'
out, books = sys.argv[1], sys.argv[2:]
os.makedirs(out, exist_ok=True)


def documents():
    path = subprocess.run(['xcrun', 'simctl', 'get_app_container', SIM, BUNDLE, 'data'],
                          capture_output=True, text=True, check=True).stdout.strip()
    return os.path.join(path, 'Documents')


def command(cmd, timeout=240, **fields):
    """Writes a command, waits for its ack. Returns the ack."""
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


def state():
    try:
        return json.load(open(os.path.join(documents(), 'spike-state.json')))
    except (OSError, ValueError):
        return {}


collector = open(os.path.join(TOOLS, 'collect.js')).read() \
    .replace('__SECTIONS__', 'null').replace('__WAIT__', '3000').replace('__CLICK__', 'true')

for book in books:
    log = os.path.join(out, f'app-{book}.beacon.jsonl')
    if os.path.exists(log):
        os.remove(log)
    beacon = subprocess.Popen([sys.executable, '-I', os.path.join(TOOLS, 'beacon.py'), log, '8799'],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    command('home')
    time.sleep(1)
    started = time.time()
    command('openLocal', name=book)
    while time.time() - started < 120 and state().get('bookID') != book:
        time.sleep(0.5)
    time.sleep(3)
    opened = state()
    result = command('js', script=collector)
    time.sleep(2)
    beacon.terminate()
    open(log, 'a').close()
    try:
        report = json.load(open(os.path.join(documents(), 'spike-js.json')))
    except (OSError, ValueError) as e:
        report = {'error': str(e)}
    report['ack'] = result
    report['opened'] = {'title': opened.get('title'), 'restoredFrom': opened.get('restoredFrom')}
    with open(os.path.join(out, f'app-{book}.json'), 'w') as f:
        json.dump(report, f)
    # The vectors section, as a picture.
    command('goto', fraction=0.3)
    time.sleep(3)
    subprocess.run(['hinge', '-d', SIM, 'screenshot', os.path.join(out, f'app-{book}.png')], capture_output=True)
    print(f'{book}: ack {result.get("ok")} {result.get("message") or ""}', flush=True)
