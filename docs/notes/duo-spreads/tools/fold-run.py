#!/usr/bin/env python3
"""Fold-continuity run on 'Octavo Sync Duo' (spike 2b).

    fold-run.py <label> <book file> (--fraction F | --cfi CFI) [--next N] [--moves open,close,...]

Opens a local book folded, goes to the position (then N pages forward),
records that page as the origin, and watches its start CFI. Then moves the
hinge; after each move, once the reader has settled, records the posture,
page size, column count, CFI, first words, whether the visible page contains
the origin, and where the text sits against the fold. One JSON line per
step goes to stdout.

Checks, per move:
- fold (back to closed): `exact` = the start CFI equals the origin's.
- unfold/half-open: `contains` = the visible page contains the origin's start
  (foliate's CFI ordering, via bridge.js `locate`), and `words` = the page's
  text contains the origin's first 8 words.
- open/half-open: `crossing` = text boxes touching the fold region (want 0).
"""
import argparse
import json
import os
import subprocess
import sys
import time

SIM = os.environ.get("SIM", "32DEFF1F-1885-4884-8DAF-2FC92AE08FC2")
TOOLS = os.path.dirname(os.path.abspath(__file__))
WIDTH = {"close": 466, "open": 951, "half": 951}
POSTURE = {"close": "closed", "open": "open", "half": "halfOpen"}


def app(command, settle="1.5", wait=True):
    env = dict(os.environ, SETTLE=settle)
    if not wait:
        env["NOWAIT"] = "1"
    out = subprocess.run([f"{TOOLS}/app.sh", command], capture_output=True, text=True, env=env)
    if out.stderr.strip():
        print(f"app.sh: {out.stderr.strip()}", file=sys.stderr)
    return json.loads(out.stdout) if out.stdout.strip() else {}


def state():
    return app("state")


def hinge(move):
    subprocess.run(["hinge", "-d", SIM, move], capture_output=True)


def words(text, n=8):
    return " ".join((text or "").split()[:n])


def settled(move, timeout=40):
    """The state once the page has the expected size and posture, and two
    reads 1.5 s apart agree."""
    last = None
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(1.5)
        s = state()
        report = s.get("layoutReport") or {}
        key = (report.get("innerWidth"), s.get("posture"), s.get("relocations"), s.get("cfi"), json.dumps(s.get("layout"), sort_keys=True))
        if report.get("innerWidth") == WIDTH[move] and s.get("posture") == POSTURE[move] and key == last:
            return s
        last = key
    return state() | {"timedOut": True}


def record(step, s, origin):
    report = s.get("layoutReport") or {}
    watched = s.get("watched") or {}
    text = " ".join((s.get("visibleText") or "").split())
    return {
        "step": step,
        "posture": s.get("posture"),
        "angle": s.get("hingeAngle"),
        "width": report.get("innerWidth"),
        "columns": report.get("columns"),
        "cfi": s.get("cfi"),
        "rangeCFI": s.get("rangeCFI"),
        "first": words(text),
        "exact": s.get("cfi") == origin["cfi"] if origin else None,
        "contains": watched.get("contains"),
        "words": origin["words"] in text if origin and origin["words"] else None,
        "fold": report.get("fold"),
        "leftPageRight": report.get("leftPageRight"),
        "rightPageLeft": report.get("rightPageLeft"),
        "crossing": report.get("crossing"),
        "relocations": s.get("relocations"),
        "timedOut": s.get("timedOut", False),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("label")
    parser.add_argument("book")
    parser.add_argument("--fraction", type=float)
    parser.add_argument("--cfi")
    parser.add_argument("--next", type=int, default=0)
    parser.add_argument("--moves", default="open,close,half,close,open,half,open,close")
    args = parser.parse_args()

    hinge("close")
    time.sleep(2)
    app('"cmd":"home"', wait=False)
    time.sleep(1)
    app(f'"cmd":"openLocal","name":{json.dumps(args.book)}', settle="3")
    target = f'"fraction":{args.fraction}' if args.fraction is not None else f'"cfi":{json.dumps(args.cfi)}'
    app(f'"cmd":"goto",{target}')
    for _ in range(args.next):
        app('"cmd":"next"', settle="1")
    s = settled("close")
    origin = {"cfi": s.get("cfi"), "words": words(s.get("visibleText"))}
    app(f'"cmd":"watch","cfi":{json.dumps(origin["cfi"])}', wait=False)
    print(json.dumps({"label": args.label, "book": args.book, **record("origin", settled("close"), origin)}), flush=True)

    for move in args.moves.split(","):
        hinge(move)
        print(json.dumps({"label": args.label, "book": args.book, **record(move, settled(move), origin)}), flush=True)


if __name__ == "__main__":
    main()
