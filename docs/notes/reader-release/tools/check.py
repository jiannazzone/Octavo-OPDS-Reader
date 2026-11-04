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
    print(f"{label:<36} {'same' if before == after else 'MOVED'}" + ("" if before == after else f"\n  before {before}\n  after  {after}"), flush=True)


def read_on(remote, fields):
    """A book open at a place in the middle of a chapter, already pushed."""
    remote.open_book(fields)
    remote.cmd({"cmd": "goto", "fraction": 0.37})
    time.sleep(2)
    remote.cmd({"cmd": "turn", "side": "left"})
    # Past the push's debounce.
    time.sleep(4)


def place_kept(check):
    """Closing leaves the saved place, and the server's, as they were."""
    remote = check.remote
    remote.angle(180)
    time.sleep(3)

    for label, close, wait in (
        ("back", {"cmd": "back"}, 0),
        ("layout under way", None, 0),
        ("fold", None, 3),
    ):
        read_on(remote, {"cmd": "openLocal", "name": "frankenstein.epub"})
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
        read_on(remote, {"cmd": "open", "fileID": BOOKORBIT_FILE})
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


def places_of(saved):
    return {name: place.get("position", {}).get("cfi") for name, place in saved.items()}


def watch_saved(remote, seconds, seen):
    """Adds each different set of saved places to `seen`, reading them every 0.2 s."""
    end = time.time() + seconds
    while time.time() < end:
        try:
            now = places_of(saved_places(remote))
        except (json.JSONDecodeError, FileNotFoundError):
            continue
        if now != seen[-1]:
            seen.append(now)
        time.sleep(0.2)


def left_the_app(check):
    """Leaving the app moves no place, whether or not the phone folds meanwhile (docs/notes/reader-background.md)."""
    remote = check.remote
    remote.cmd({"cmd": "signin"})
    for label, book, file_id in (
        ("local", {"cmd": "openLocal", "name": "frankenstein.epub"}, None),
        ("BookOrbit", {"cmd": "open", "fileID": BOOKORBIT_FILE}, BOOKORBIT_FILE),
    ):
        for fold_after in (None, 1, 5):
            remote.angle(180)
            time.sleep(3)
            read_on(remote, book)
            seen = [places_of(saved_places(remote))]
            server = json.loads(server_place(file_id))["cfi"] if file_id else None
            server_away = server
            subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.apple.Preferences"], capture_output=True)
            watch_saved(remote, 8 if fold_after is None else fold_after, seen)
            if file_id and fold_after is None:
                server_away = json.loads(server_place(file_id))["cfi"]
            if fold_after is not None:
                remote.angle(0)
                watch_saved(remote, 3, seen)
            subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.ianazzone.ereader"], capture_output=True)
            watch_saved(remote, 4, seen)
            moves = [[new for name, new in places.items() if seen[0].get(name) != new] for places in seen[1:]]
            fold = "no fold" if fold_after is None else f"fold after {fold_after} s"
            print(f"{label + ', ' + fold:<28} saved {'never changed' if not moves else f'CHANGED {len(moves)} times: {moves}'}; "
                  f"ended {'same' if seen[-1] == seen[0] else 'MOVED'}", flush=True)
            if file_id:
                end = json.loads(server_place(file_id))["cfi"]
                print(f"{'':<28} server {'same' if server == server_away == end else f'MOVED, away {server_away}, ended {end}'}", flush=True)
            # `home`, so the unfold that starts the next round opens nothing.
            remote.cmd({"cmd": "home"})
            time.sleep(1)


def changed_while_away(check):
    """A real change made while the app is away is laid out when it comes back."""
    remote = check.remote

    def report(label):
        state = remote.state()
        layout = state["layout"]
        before = state["relocations"]
        remote.cmd({"cmd": "turn", "side": "left"})
        time.sleep(2)
        turned = remote.state()["relocations"] > before
        print(f"{label:<28} columns {layout.get('columns')}, fold {layout.get('fold')}, page {state['geometry']['size']}, "
              f"insets {layout['leftInset']}/{layout['rightInset']}/{layout['topInset']}, {'turns' if turned else 'STOPPED'}", flush=True)

    def away_and_back(change):
        subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.apple.Preferences"], capture_output=True)
        time.sleep(3)
        change()
        time.sleep(3)
        subprocess.run(["xcrun", "simctl", "launch", check.udid, "com.ianazzone.ereader"], capture_output=True)
        time.sleep(4)

    hinge = os.environ.get("HINGE", "hinge")
    remote.angle(180)
    time.sleep(3)
    check.open("frankenstein.epub")
    report("unfolded, on screen")
    subprocess.run([hinge, "-d", check.udid, "orient", "landscape-left"], capture_output=True)
    time.sleep(4)
    report("rotated on screen")
    subprocess.run([hinge, "-d", check.udid, "orient", "portrait"], capture_output=True)
    time.sleep(4)
    away_and_back(lambda: subprocess.run([hinge, "-d", check.udid, "orient", "landscape-left"], capture_output=True))
    report("rotated while away")
    away_and_back(lambda: subprocess.run([hinge, "-d", check.udid, "orient", "portrait"], capture_output=True))
    report("rotated back while away")
    remote.cmd({"cmd": "home"})
    remote.angle(0)
    time.sleep(3)
    check.open("frankenstein.epub")
    report("folded, on screen")
    away_and_back(lambda: remote.angle(180))
    report("unfolded while away")
    remote.screenshot(os.path.join(os.environ.get("OCTAVO_SHOTS", "/tmp"), "unfolded-while-away.png"))
    remote.cmd({"cmd": "home"})
    remote.angle(180)
    time.sleep(3)
    check.open("frankenstein.epub")
    report("unfolded, on screen again")
    remote.cmd({"cmd": "home"})


SCENARIOS = {f.__name__: f for f in (plain, back, fixed, while_opening, while_turning, while_jumping, while_laying_out, folding, away, synced, place_kept, stays_open, left_the_app, changed_while_away)}

if __name__ == "__main__":
    check = Check(sys.argv[1])
    for name in sys.argv[2:]:
        check.remote.launch()
        print(f"== {name}; processes at launch: {len(content_processes(check.udid))}", flush=True)
        SCENARIOS[name](check)
