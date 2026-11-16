#!/usr/bin/env python3
"""Highlights with VoiceOver, checked headless (#125).

Drives the running DEBUG app through the debug remote (`ReaderRemote`) as
VoiceOver would: it reads each screen's elements as VoiceOver walks them
(`voiceOver`), double-taps elements by their label (`voiceOverActivate`),
runs actions from the Actions rotor (`voiceOverAction`) and turns pages
(`voiceOverScroll`). Nothing is spoken and no window opens. What it can't
show is how VoiceOver says it; that still needs a person on a device.

It makes its own highlight by selecting a range as a finger would
(`select`) and deletes it again at the end, so the book is left as it was.

Usage (the app built for DEBUG, installed on a booted simulator, signed in
to the local BookOrbit; docs/notes/highlights.md):

    docs/notes/highlights/tools/voiceover_check.py <udid> \
        [--file 4] [--cfi 'epubcfi(/6/4!/4/38/2,/1:0,/1:4)'] [--words This]

Exits 1 at the first step that fails, printing what VoiceOver could reach.
"""

import argparse
import json
import os
import subprocess
import sys
import time

BUNDLE = "com.ianazzone.ereader"


class Remote:
    def __init__(self, udid):
        self.udid = udid
        self.next_id = 1000
        self.docs = None

    def launch(self):
        subprocess.run(["xcrun", "simctl", "spawn", self.udid, "defaults", "write", "com.apple.Accessibility",
                        "ApplicationAccessibilityEnabled", "-bool", "true"], check=True)
        subprocess.run(["xcrun", "simctl", "terminate", self.udid, BUNDLE], capture_output=True)
        subprocess.run(["xcrun", "simctl", "launch", self.udid, BUNDLE], check=True, capture_output=True)
        container = subprocess.run(["xcrun", "simctl", "get_app_container", self.udid, BUNDLE, "data"],
                                   check=True, capture_output=True, text=True).stdout.strip()
        self.docs = os.path.join(container, "Documents")
        time.sleep(3)

    def send(self, cmd, **fields):
        self.next_id += 1
        command = {"id": self.next_id, "cmd": cmd, **fields}
        ack_path = os.path.join(self.docs, "spike-ack.json")
        if os.path.exists(ack_path):
            os.remove(ack_path)
        with open(os.path.join(self.docs, "spike-command.json"), "w") as f:
            json.dump(command, f)
        for _ in range(120):
            time.sleep(0.25)
            try:
                with open(ack_path) as f:
                    ack = json.load(f)
            except (OSError, ValueError):
                continue
            if ack.get("id") == self.next_id:
                return ack
        raise SystemExit(f"no answer to {cmd}")

    def walk(self):
        self.send("voiceOver")
        with open(os.path.join(self.docs, "voiceover.txt")) as f:
            return f.read()

    def state(self):
        return self.send("highlightState").get("message", "")


class Check:
    def __init__(self, remote):
        self.remote = remote
        self.step = 0

    def expect(self, ok, what):
        self.step += 1
        if ok:
            print(f"✓ {self.step}. {what}")
            return
        print(f"✘ {self.step}. {what}")
        print("  state:", self.remote.state())
        print("  VoiceOver can reach:")
        for line in self.remote.walk().splitlines():
            print("   ", line[:160])
        sys.exit(1)

    def ok(self, ack, what):
        self.expect(ack.get("ok"), f"{what}" + ("" if ack.get("ok") else f" ({ack.get('message')})"))


def labels(walk):
    """Each element's label, as the walk prints it ('label'  traits …)."""
    return [line.split("'")[1] for line in walk.splitlines() if line.startswith("'") and line.count("'") >= 2]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("udid")
    parser.add_argument("--file", type=int, default=4, help="a BookOrbit EPUB's file ID")
    parser.add_argument("--cfi", default="epubcfi(/6/4!/4/38/2,/1:0,/1:4)", help="a range on one page to highlight")
    parser.add_argument("--words", default="This", help="the range's first words")
    args = parser.parse_args()

    remote = Remote(args.udid)
    remote.launch()
    check = Check(remote)
    action = f"Highlight: “{args.words}"

    check.ok(remote.send("signin"), "signed in to BookOrbit")
    check.ok(remote.send("open", fileID=args.file), "opened the book")
    for _ in range(40):
        if remote.send("pageState").get("message", "").startswith("open"):
            break
        time.sleep(0.5)
    time.sleep(2)
    # A way back left by an earlier jump would bring the book back to it.
    if "Stay Here" in labels(remote.walk()):
        remote.send("voiceOverActivate", name="Stay Here")
    check.ok(remote.send("unhighlight", cfi=args.cfi), "cleared any highlight left on the range")
    check.ok(remote.send("goto", cfi=args.cfi), "went to the range")
    time.sleep(2.5)
    check.expect(args.words in remote.walk().split("# the page's words:")[0], "the page shows the range's words")
    check.expect(action not in remote.walk(), "no highlight there yet")

    # Made with a finger; then VoiceOver's part.
    check.ok(remote.send("select", cfi=args.cfi), "selected the range")
    time.sleep(1)
    check.ok(remote.send("highlight", name="#4ADE80"), "highlighted it green")
    time.sleep(2)
    check.ok(remote.send("voiceOverScroll", side="next"), "turned the page with three fingers")
    time.sleep(1.5)
    check.ok(remote.send("voiceOverScroll", side="previous"), "turned back")
    time.sleep(1.5)
    check.expect("bar none" in remote.state(), "the turn closed the bar")

    walk = remote.walk()
    check.expect(action in walk, f"the page offers “{action}…” in the Actions rotor")
    check.ok(remote.send("voiceOverAction", name=action), "ran the action")
    time.sleep(1.5)
    check.expect("tapped none" not in remote.state(), "its card opened")

    walk = remote.walk()
    found = labels(walk)
    for label in ["Share", "Copy", "Delete", "Close", "Yellow", "Green", "Add Note"]:
        check.expect(label in found, f"the card has “{label}”")
    check.expect("Green'  button,selected" in walk or "'Green'  selected" in walk or "Green'  selected" in walk,
                 "Green reads as selected")
    check.expect("PageView" not in walk, "the page behind the card is hidden from VoiceOver")

    check.ok(remote.send("voiceOverActivate", name="Add Note"), "double-tapped Add Note")
    time.sleep(1.5)
    found = labels(remote.walk())
    check.expect("Cancel" in found and "Done" in found, "the note's sheet has Cancel and Done")
    check.ok(remote.send("voiceOverActivate", name="Cancel"), "double-tapped Cancel")
    time.sleep(1.5)
    check.ok(remote.send("voiceOverActivate", name="Close"), "closed the card")
    time.sleep(1)
    check.expect("tapped none" in remote.state(), "the card closed")

    # The Highlights tab's row.
    check.ok(remote.send("voiceOverActivate", name="Show Controls"), "showed the controls")
    time.sleep(1)
    check.ok(remote.send("voiceOverActivate", name="Contents"), "opened Contents")
    time.sleep(1.5)
    check.ok(remote.send("voiceOverActivate", name="Highlights"), "chose the Highlights tab")
    time.sleep(1.5)
    walk = remote.walk()
    # A row reads as "Chapter · Page N, its words[, its note]".
    row = next((line for line in walk.splitlines() if f", {args.words}" in line and "actions [" in line), "")
    check.expect(all(name in row for name in ["Add Note", "Share", "Delete"]),
                 f"its row has Add Note, Share and Delete ({row[:120] or 'no row'})")
    check.ok(remote.send("voiceOverActivate", name="Close"), "closed the panel")
    time.sleep(1.5)

    # Deleted from its card, as VoiceOver would.
    check.ok(remote.send("voiceOverAction", name=action), "opened its card again")
    time.sleep(1.5)
    check.ok(remote.send("voiceOverActivate", name="Delete"), "double-tapped Delete")
    time.sleep(2)
    check.expect(action not in remote.walk(), "the highlight is gone from the page's actions")
    print("All passed.")


if __name__ == "__main__":
    main()
