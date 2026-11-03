#!/usr/bin/env python3
"""probe-modes.py <udid> <app.sh> <tools dir> — for each launch mode (both
layers off, the bridge layer alone, both on) and test book (link-test.epub,
template-test.epub, copied into the app's Documents first), opens the book
with the debug remote and runs <book>-probe.js in the reader page; prints
each result. Make the books with make-link-test.py and make-template-test.py."""
import json, os, subprocess, sys, time
udid, app, tools = sys.argv[1:4]
docs = subprocess.run(["xcrun", "simctl", "get_app_container", udid, "com.ianazzone.ereader", "data"], capture_output=True, text=True).stdout.strip() + "/Documents"
result = os.path.join(docs, "spike-js.json")
env = dict(os.environ, SIM=udid)
def remote(cmd):
    subprocess.run(["zsh", app, cmd], capture_output=True, text=True, env=env)
for mode in (["-readerWithoutCSP", "1", "-readerWithoutHarden", "1"], ["-readerWithoutCSP", "1"], []):
    for book in ("link", "template"):
        subprocess.run(["xcrun", "simctl", "terminate", udid, "com.ianazzone.ereader"], capture_output=True)
        subprocess.run(["xcrun", "simctl", "launch", udid, "com.ianazzone.ereader", *mode], capture_output=True)
        time.sleep(7)
        remote(f'"cmd":"openLocal","name":"{book}-test.epub"')
        before = os.path.getmtime(result) if os.path.exists(result) else 0
        script = open(os.path.join(tools, f"{book}-probe.js")).read()
        remote(json.dumps({"cmd": "js", "script": script})[1:-1])
        for _ in range(30):
            if os.path.exists(result) and os.path.getmtime(result) > before: break
            time.sleep(1)
        data = json.load(open(result))
        print(f"== [{' '.join(mode) or 'both layers'}] {book}:", json.dumps(data.get("result", data))[:800])
