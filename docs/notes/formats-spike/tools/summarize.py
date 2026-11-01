#!/usr/bin/env python3
"""Summarizes script-test runs (formats spike).

    python3 -I summarize.py DIR

DIR holds `<mode>-<book>.json` (probe.swift or app.sh js output) and
`<mode>-<book>.beacon.jsonl` (beacon.py). For each run: which vectors' marks
were found (in section documents, nested frames, `top.__bookScriptRan`),
which vectors reached the beacon, and how many payload elements the rendered
sections contained.
"""
import glob
import json
import os
import sys
from urllib.parse import parse_qs, urlparse

d = sys.argv[1]


def vector(path):
    q = parse_qs(urlparse(path).query)
    if 'v' in q:
        return q['v'][0]
    parts = urlparse(path).path.split('/')
    return parts[2] if len(parts) > 2 and parts[1] == 'load' else path


for f in sorted(glob.glob(os.path.join(d, '*.json'))):
    run = os.path.basename(f)[:-5]
    data = json.load(open(f))
    data = data.get('result', data)  # app.sh js output wraps it
    report = data.get('report', data)
    if 'error' in data and not report.get('visits'):
        print(f'{run}: ERROR {data["error"]}')
        continue
    ran, present = set(report.get('topMarks') or []), {}
    for visit in report.get('visits', []):
        ran.update(visit.get('marks') or [])
        ran.update(visit.get('marksAfterClicks') or [])
        for n in visit.get('nested') or []:
            ran.update(n.get('marks') or [])
        for k, v in (visit.get('present') or {}).items():
            present[k] = present.get(k, 0) + (len(v) if isinstance(v, list) else v)
    beacon_file = os.path.join(d, run + '.beacon.jsonl')
    hits = [json.loads(line) for line in open(beacon_file)] if os.path.exists(beacon_file) else []
    reached = sorted({vector(h['path']) for h in hits})
    script_hits = sorted({vector(h['path']) for h in hits if h['path'].startswith(('/ran', '/ran-fetch'))})
    print(f'{run}: opened in {data.get("openSeconds", 0):.1f}s, {report.get("sections")} sections')
    print(f'  scripts ran ({len(ran)}): {", ".join(sorted(ran)) or "none"}')
    print(f'  beacon ({len(hits)} requests, {len(reached)} vectors): {", ".join(reached) or "none"}')
    if script_hits:
        print(f'  of which script beacons: {", ".join(script_hits)}')
    print(f'  payload elements present: {present}')
