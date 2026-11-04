#!/usr/bin/env python3
"""Opens and closes books in the running app and counts what stays alive (docs/notes/reader-release.md).

    check.py <udid> <scenario>...    scenarios: see SCENARIOS

Copy the books into the app's Documents first (see the note). Each row is what's
alive `settled` seconds after the last close: of the readers opened since launch,
the models, web pages and web views, and this simulator's content processes.
"""
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../fixed-layout/tools"))
from remote import Remote  # noqa: E402

FLOWING = ["alice-in-wonderland.epub", "frankenstein.epub", "moby-dick.epub", "pride-and-prejudice.epub", "sherlock-holmes.epub"]
BOOKORBIT_FILE = int(os.environ.get("BOOKORBIT_FILE", "1"))


def content_processes(udid):
    """Pids of the content processes under this simulator's launchd_sim."""
    rows = subprocess.run(["ps", "-Ao", "pid=,ppid=,command="], capture_output=True, text=True).stdout.splitlines()
    rows = [re.match(r"\s*(\d+)\s+(\d+)\s+(.*)", row).groups() for row in rows]
    launchd = next(pid for pid, _, command in rows if "launchd_sim" in command and udid in command)
    return sorted(int(pid) for pid, ppid, command in rows if ppid == launchd and "WebKit.WebContent" in command)


class Check:
    def __init__(self, udid):
        self.udid = udid
        self.remote = Remote(udid)
        self.opened = 0

    def live(self):
        # The remote acks anything that comes back with a message as not ok.
        try:
            self.remote.cmd({"cmd": "liveReaders"})
        except RuntimeError as answer:
            return json.loads(str(answer).split(": ", 2)[2])

    def report(self, label, settled=(1, 5, 15)):
        """What's alive after each wait."""
        start = time.time()
        for wait in settled:
            time.sleep(max(0, start + wait - time.time()))
            live = self.live()
            processes = content_processes(self.udid)
            print(f"{label:<22} +{wait:>3}s  opened {live['opened']:>3}  models {live['models']:>3}  pages {live['pages']:>3}  "
                  f"webViews {live['webViews']:>3}  processes {len(processes):>3} (reader's {live['processes']})", flush=True)

    def open(self, name):
        self.remote.open_book({"cmd": "openLocal", "name": name})

    def close(self, how):
        self.remote.cmd({"cmd": how})


def plain(check):
    for name in FLOWING:
        check.open(name)
        check.close("close")
        check.report(f"close {name[:12]}", settled=(1,))
    check.report("after all")


def back(check):
    for name in FLOWING:
        check.open(name)
        check.close("back")
        check.report(f"back {name[:12]}", settled=(1,))
    check.report("after all")


def fixed(check):
    for _ in range(3):
        check.open("fixed.epub")
        check.close("back")
        check.report("back fixed", settled=(1,))
    check.report("after all")


def while_opening(check):
    """Closed while the book is still opening."""
    for delay in (0, 100, 300, 600, 1000, 1500, 2500):
        check.remote.cmd({"cmd": "openLocal", "name": "moby-dick.epub", "closeAfter": delay})
        check.report(f"opening +{delay} ms", settled=(1,))
    check.report("after all")


def while_turning(check):
    """Closed a moment after a page turn starts."""
    for delay in (0, 8, 16, 33, 50, 100, 200):
        check.open("frankenstein.epub")
        check.remote.cmd({"cmd": "turn", "side": "left", "closeAfter": delay})
        check.report(f"turning +{delay} ms", settled=(1,))
    check.report("after all")


def while_jumping(check):
    """Closed a moment after going somewhere new: `goTo` waits for frames, and a big section takes time to load."""
    for delay in (0, 16, 50, 100, 300, 600):
        check.open("moby-dick.epub")
        check.remote.cmd({"cmd": "goto", "fraction": 0.5, "closeAfter": delay})
        check.report(f"jumping +{delay} ms", settled=(1,))
    check.report("after all")


def while_laying_out(check):
    """Closed a moment after the layout changes, which re-renders the page and waits for frames."""
    for delay in (0, 16, 50, 100, 300, 600):
        check.open("frankenstein.epub")
        layout = check.remote.state()["layout"]
        layout["rightInset"] += 40
        check.remote.cmd({"cmd": "layout", "layout": layout, "closeAfter": delay})
        check.report(f"layout +{delay} ms", settled=(1,))
    check.report("after all")


def folding(check):
    """Folding while reading closes the book."""
    remote = check.remote
    remote.angle(180)
    time.sleep(3)
    for name in FLOWING[:3] + ["fixed.epub"]:
        check.open(name)
        remote.angle(0)
        check.report(f"fold {name[:12]}", settled=(3,))
        remote.angle(180)
        time.sleep(3)
    check.report("after all")


def away(check):
    """The app goes to the background with the book open, comes back, and it closes."""
    remote = check.remote
    check.open("frankenstein.epub")
    subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.apple.Preferences"], capture_output=True)
    time.sleep(8)
    subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.ianazzone.ereader"], capture_output=True)
    time.sleep(3)
    remote.cmd({"cmd": "back"})
    check.report("after all")


def synced(check):
    """A BookOrbit book: pulled, moved and pushed, with its cover's motion."""
    remote = check.remote
    remote.cmd({"cmd": "signin"})
    for _ in range(3):
        remote.cmd({"cmd": "detail", "fileID": BOOKORBIT_FILE})
        time.sleep(1)
        remote.open_book({"cmd": "open", "fileID": BOOKORBIT_FILE})
        time.sleep(2)
        remote.cmd({"cmd": "turn", "side": "left"})
        time.sleep(0.5)
        remote.cmd({"cmd": "back"})
        check.report("synced back", settled=(2,))
    check.report("after all")


def saved_places(remote):
    """What's saved for every book, as the store's files have it."""
    folder = os.path.join(os.path.dirname(remote.docs), "Library/Application Support/ReadingPositions")
    return {os.path.relpath(os.path.join(root, name), folder): json.load(open(os.path.join(root, name)))
            for root, _, names in os.walk(folder) for name in names}


def server_place(file_id):
    tool = os.path.join(os.path.dirname(__file__), "../../fixed-layout/tools/bo.sh")
    return subprocess.run(["zsh", tool, "progress", str(file_id)], capture_output=True, text=True).stdout.strip()


def compare(label, before, after):
    print(f"{label:<28} {'same' if before == after else 'MOVED'}" + ("" if before == after else f"\n  before {before}\n  after  {after}"), flush=True)


def place_kept(check):
    """Closing leaves the saved place, and the server's, as they were."""
    remote = check.remote
    remote.angle(180)
    time.sleep(3)

    def read_on(fields):
        remote.open_book(fields)
        remote.cmd({"cmd": "goto", "fraction": 0.37})
        time.sleep(2)
        remote.cmd({"cmd": "turn", "side": "left"})
        # Past the push's debounce.
        time.sleep(4)

    for label, close, wait in (
        ("back", {"cmd": "back"}, 0),
        ("layout under way", None, 0),
        ("fold", None, 3),
    ):
        read_on({"cmd": "openLocal", "name": "frankenstein.epub"})
        before = saved_places(remote)
        if close:
            remote.cmd(close)
        elif label == "fold":
            remote.angle(0)
        else:
            # The new layout is the reader's own and may move the place. What
            # counts is what the call under way does once it's closed.
            layout = remote.state()["layout"]
            layout["rightInset"] += 40
            remote.cmd({"cmd": "layout", "layout": layout, "closeAfter": 30})
            before = saved_places(remote)
        time.sleep(5)
        compare(f"saved, {label}", before, saved_places(remote))
        remote.angle(180)
        time.sleep(wait)

    remote.cmd({"cmd": "signin"})
    for label in ("back", "fold"):
        read_on({"cmd": "open", "fileID": BOOKORBIT_FILE})
        before = saved_places(remote), server_place(BOOKORBIT_FILE)
        print(f"  server has {before[1]}", flush=True)
        if label == "back":
            remote.cmd({"cmd": "back"})
        else:
            remote.angle(0)
        time.sleep(6)
        compare(f"saved and server, {label}", before, (saved_places(remote), server_place(BOOKORBIT_FILE)))
        remote.angle(180)
        time.sleep(3)
    # The unfold opened the book again, from its screen.
    remote.cmd({"cmd": "close"})
    check.report("after all", settled=(1,))


def stays_open(check):
    """Only a real close stops a reader: it still turns after everything else that happens to it."""
    remote = check.remote
    hinge = os.environ.get("HINGE", "hinge")

    def still_reads(label):
        time.sleep(3)
        before = remote.state()
        remote.cmd({"cmd": "turn", "side": "left"})
        time.sleep(2)
        after = remote.state()
        moved = before["cfi"] != after["cfi"] and after["relocations"] > before["relocations"]
        live = check.live()
        print(f"{label:<28} {'turns' if moved else 'STOPPED'}  models {live['models']} of {live['opened']}", flush=True)

    remote.angle(0)
    time.sleep(3)
    check.open("frankenstein.epub")
    still_reads("opened folded")
    remote.angle(180)
    still_reads("unfolded")
    remote.angle(90)
    still_reads("half open")
    remote.angle(180)
    still_reads("flat")
    for orientation in ("landscape-left", "portrait"):
        subprocess.run([hinge, "-d", check.udid, "orient", orientation], capture_output=True)
        still_reads(orientation)
    subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.apple.Preferences"], capture_output=True)
    time.sleep(8)
    subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.ianazzone.ereader"], capture_output=True)
    still_reads("back from the background")
    remote.cmd({"cmd": "back"})
    check.report("after all", settled=(1,))


SCENARIOS = {f.__name__: f for f in (plain, back, fixed, while_opening, while_turning, while_jumping, while_laying_out, folding, away, synced, place_kept, stays_open)}

if __name__ == "__main__":
    check = Check(sys.argv[1])
    for name in sys.argv[2:]:
        check.remote.launch()
        print(f"== {name}; processes at launch: {len(content_processes(check.udid))}", flush=True)
        SCENARIOS[name](check)
