"""Drives the reader on a simulator through the debug remote (docs/notes/fixed-layout.md).

Import it from a check, or run it: remote.py <udid> shown | cmd '{"cmd":"next"}' | angle 120
"""
import json
import os
import random
import shutil
import subprocess
import sys
import time

APP = "com.ianazzone.ereader"
HINGE = os.environ.get("HINGE", "hinge")

# What's on screen: the pages' titles, the frames' places, what the bridge says.
SHOWN = """
const v = document.querySelector('foliate-view')
const r = v.renderer
const frames = r.getContents()
    .map(c => ({ doc: c.doc, frame: c.doc.defaultView?.frameElement }))
    .filter(({ doc, frame }) => doc.title && frame && frame.parentElement.style.display !== 'none')
const rect = e => { const b = e.getBoundingClientRect(); return [b.left, b.top, b.right, b.bottom].map(x => Math.round(x * 10) / 10) }
return JSON.stringify({
    pages: frames.map(({ doc }) => doc.title),
    index: r.index,
    cfi: v.lastLocation?.cfi ?? null,
    fraction: v.lastLocation?.fraction ?? null,
    view: rect(v),
    frames: frames.map(({ frame }) => rect(frame)),
    ran: r.getContents().map(c => c.doc.documentElement?.getAttribute('data-ran')).filter(Boolean),
})
"""


class Remote:
    def __init__(self, udid):
        self.udid = udid

    @property
    def docs(self):
        out = subprocess.run(["xcrun", "simctl", "get_app_container", self.udid, APP, "data"], capture_output=True, text=True).stdout.strip()
        return os.path.join(out, "Documents")

    def launch(self, *args, wait=6):
        subprocess.run(["xcrun", "simctl", "terminate", self.udid, APP], capture_output=True)
        subprocess.run(["xcrun", "simctl", "launch", self.udid, APP, *args], capture_output=True, check=True)
        time.sleep(wait)

    def copy_book(self, path):
        shutil.copy(path, self.docs)

    def cmd(self, fields, timeout=60):
        """Sends a command and waits for its ack. Returns the ack's message (or None)."""
        id_ = int(time.time() * 1000) + random.randrange(1000)
        command = os.path.join(self.docs, "spike-command.json")
        ack = os.path.join(self.docs, "spike-ack.json")
        if os.path.exists(ack):
            os.remove(ack)
        with open(command + ".tmp", "w") as f:
            json.dump({"id": id_, **fields}, f)
        os.replace(command + ".tmp", command)
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                answer = json.load(open(ack))
                if answer["id"] == id_:
                    if not answer["ok"]:
                        raise RuntimeError(f"{fields}: {answer.get('message')}")
                    return answer.get("message")
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(0.2)
        raise TimeoutError(f"no ack for {fields}")

    def js(self, script, timeout=30):
        result = os.path.join(self.docs, "spike-js.json")
        if os.path.exists(result):
            os.remove(result)
        self.cmd({"cmd": "js", "script": script}, timeout=timeout)
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                data = json.load(open(result))
                if "error" in data:
                    raise RuntimeError(data["error"])
                return data.get("result")
            except (FileNotFoundError, json.JSONDecodeError):
                time.sleep(0.2)
        raise TimeoutError("no script result")

    def open_book(self, fields, timeout=60):
        """Opens a book and returns once the reader is open: it writes the state file then."""
        state = os.path.join(self.docs, "spike-state.json")
        if os.path.exists(state):
            os.remove(state)
        self.cmd(fields)
        deadline = time.time() + timeout
        while not os.path.exists(state):
            if time.time() > deadline:
                raise TimeoutError(f"{fields} didn't open")
            time.sleep(0.2)
        time.sleep(0.5)

    def shown(self):
        return json.loads(self.js(SHOWN))

    def state(self):
        return json.load(open(os.path.join(self.docs, "spike-state.json")))

    def angle(self, degrees):
        # The confirmation sometimes times out on a busy Mac; the angle is set again.
        for attempt in range(3):
            done = subprocess.run([HINGE, "-d", self.udid, str(degrees)], capture_output=True, text=True)
            if done.returncode == 0:
                return
            time.sleep(2)
        raise RuntimeError(f"hinge {degrees}: {done.stderr}")

    def screenshot(self, path):
        subprocess.run([HINGE, "-d", self.udid, "screenshot", path], check=True, capture_output=True)


if __name__ == "__main__":
    remote = Remote(sys.argv[1])
    if sys.argv[2] == "shown":
        print(json.dumps(remote.shown(), indent=1))
    elif sys.argv[2] == "cmd":
        print(remote.cmd(json.loads(sys.argv[3])))
    elif sys.argv[2] == "angle":
        remote.angle(sys.argv[3])
