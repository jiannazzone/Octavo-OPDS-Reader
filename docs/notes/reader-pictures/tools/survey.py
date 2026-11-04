#!/usr/bin/env python3
"""Measures every picture of the sample books against its text column, in each
posture, on a Duo simulator with Octavo's DEBUG build running and the books in
its Documents folder. Headless: simctl and hinge only, no windows.

    survey.py <simulator UDID> <output.json> [book.epub ...]
"""
import json, os, random, subprocess, sys, time

udid, output, *books = sys.argv[1:]
books = books or ["pride-and-prejudice.epub", "alice-in-wonderland.epub", "frankenstein.epub",
                  "moby-dick.epub", "sherlock-holmes.epub"]
here = os.path.dirname(os.path.abspath(__file__))
probe = open(os.path.join(here, "picture-sizes.js")).read()
docs = os.path.join(subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", udid, "com.ianazzone.ereader", "data"], text=True).strip(), "Documents")

def hinge(*args):
    # A move can take longer to confirm than hinge waits, and then it may
    # have worked anyway: check the posture rather than the exit code.
    subprocess.run(["hinge", "-d", udid, "-t", "8", *args], capture_output=True)

def remote(command, timeout=120):
    command["id"] = random.randrange(1, 1 << 30)
    ack = os.path.join(docs, "spike-ack.json")
    if os.path.exists(ack): os.remove(ack)
    temporary = os.path.join(docs, "spike-command.json.tmp")
    with open(temporary, "w") as f: json.dump(command, f)
    os.rename(temporary, os.path.join(docs, "spike-command.json"))
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            answer = json.load(open(ack))
            if answer["id"] == command["id"]:
                if not answer["ok"]: raise RuntimeError(f"{command['cmd']}: {answer.get('message')}")
                return answer
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.1)
    raise TimeoutError(command["cmd"])

def js(script):
    remote({"cmd": "js", "script": script})
    result = json.load(open(os.path.join(docs, "spike-js.json")))
    if "error" in result: raise RuntimeError(result["error"])
    return result["result"]

def wait_for_book():
    for _ in range(120):
        ready = js("const v = document.querySelector('foliate-view'); return !!(v?.book && v.renderer?.getContents?.()?.length)") if reader_open() else False
        if ready: return
        time.sleep(0.5)
    raise TimeoutError("book didn't open")

def reader_open():
    try:
        remote({"cmd": "js", "script": "return 1"}, timeout=5)
        return True
    except RuntimeError:
        return False

def posture(name):
    angle, orientation = {"folded": (0, "portrait"), "flat": (180, "portrait"), "half": (90, "portrait"),
                          "sideways": (180, "landscape-left")}[name]
    for _ in range(5):
        if orientation == "portrait":
            hinge("orient", orientation); hinge(str(angle))
        else:
            hinge(str(angle)); hinge("orient", orientation)
        time.sleep(2.5)
        now = json.loads(subprocess.check_output(["hinge", "-d", udid, "--json", "posture"], text=True))
        if abs(now["angle"] - angle) < 1 and now["orientation"] == orientation: return
    raise RuntimeError(f"couldn't reach {name}: {now}")

results = {}
for book in books:
    # Folding closes the reader, so each book opens folded and only unfolds.
    remote({"cmd": "close"})
    posture("folded")
    remote({"cmd": "openLocal", "name": book})
    wait_for_book()
    results[book] = {}
    for name in ["folded", "flat", "half", "sideways"]:
        posture(name)
        sections = []
        index = 0
        while True:
            section = js(probe.replace("SECTION", str(index)))
            if section.get("done"): break
            sections.append(section)
            index += 1
        results[book][name] = sections
        pictures = [p for s in sections for p in s.get("pictures", [])]
        measured = [s for s in sections if "pictures" in s]
        widest = max(measured, key=lambda s: s["pages"])
        print(f"{book} {name}: column {widest['columnWidth']} × {widest['pageHeight']} "
              f"({widest['columns']} per spread), {sum(s['pages'] for s in measured)} pages, {len(pictures)} pictures, "
              f"{sum(p['over'] > 0.5 for p in pictures)} over the column, "
              f"{sum(p['wrapperOver'] > 0.5 for p in pictures)} in a box over it, "
              f"{sum(p['tall'] > 0.5 for p in pictures)} too tall, "
              f"{sum(p['split'] for p in pictures)} split across columns", flush=True)
    remote({"cmd": "close"})
    time.sleep(1)
    json.dump(results, open(output, "w"), indent=1)
posture("folded")
