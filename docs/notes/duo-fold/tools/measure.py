#!/usr/bin/env python3
"""Re-layouts per fold (#5). SIM=<udid> measure.py <label> <move>...

Moves: open, close, half, <degrees>, or sweep:<from>:<to>:<seconds>. For each
move: clears the page's counters (instrument.js, installed first with
`../../duo-spreads/tools/js.sh "$(cat instrument.js)"`), moves the hinge,
waits until the page has been quiet for QUIET ms, and prints one JSON line:
foliate renders, relocations (in foliate, and as many as reached Swift),
the page's events with timestamps, the app's hinge/geometry events
(spike-events.jsonl), the position, and the model's fold timings."""
import json, os, subprocess, sys, time
SIM = os.environ["SIM"]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../.."))
TOOLS = f"{REPO}/docs/notes/duo-spreads/tools"
HERE = os.path.dirname(os.path.abspath(__file__))
D = subprocess.run(["xcrun", "simctl", "get_app_container", SIM, "com.ianazzone.ereader", "data"], capture_output=True, text=True).stdout.strip() + "/Documents"
WAIT = float(os.environ.get("WAIT", "4"))

def js(path):
    out = subprocess.run([f"{TOOLS}/js.sh", open(path).read()], capture_output=True, text=True, env=dict(os.environ)).stdout
    try: return json.loads(out).get("result")
    except Exception: return out

def state():
    return json.load(open(f"{D}/spike-state.json"))

def hinge(move):
    if move.startswith("sweep:"):
        _, a, b, s = move.split(":")
        subprocess.run(["hinge", "-d", SIM, "-t", "0", "sweep", a, b, s], capture_output=True)
    else:
        subprocess.run(["hinge", "-d", SIM, "-t", "0", move], capture_output=True)

label = sys.argv[1]
for move in sys.argv[2:]:
    js(f"{HERE}/drain.js")
    rel0 = state().get("relocations")
    mark = sum(1 for _ in open(f"{D}/spike-events.jsonl")) if os.path.exists(f"{D}/spike-events.jsonl") else 0
    t0 = time.time()
    hinge(move)
    t1 = time.time()
    # Wait until the page has gone quiet for QUIET ms (or nothing happens for 15 s).
    deadline = time.time() + 30
    while time.time() < deadline:
        time.sleep(1)
        p = js(f"{HERE}/peek.js") or {}
        if p.get("n") and p["now"] - p["last"] > float(os.environ.get("QUIET", "2500")): break
        if not p.get("n") and time.time() - t1 > 15: break
    page = js(f"{HERE}/drain.js") or {}
    st = state()
    swift = [json.loads(l) for l in open(f"{D}/spike-events.jsonl").readlines()[mark:]]
    ev = page.get("events", [])
    kinds = {}
    for e in ev: kinds[e["type"]] = kinds.get(e["type"], 0) + 1
    print(json.dumps({"label": label, "move": move, "hingeSeconds": round(t1 - t0, 1), "renders": page.get("renders"), "counts": kinds,
                      "swiftRelocations": (st.get("relocations") or 0) - (rel0 or 0),
                      "posture": st.get("posture"), "cfi": st.get("cfi"), "lastFold": st.get("lastFold"), "layout": st.get("layout"),
                      "events": ev, "swift": [s for s in swift if s.get("event") != "appear"]}), flush=True)
