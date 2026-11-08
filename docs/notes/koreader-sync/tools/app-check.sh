#!/bin/bash
# KOReader sync in the app (docs/notes/koreader-sync.md), end to end: a DEBUG
# build on a simulator, launched with `-connectKOSync 1` and driven through
# the debug remote, against dev/kosync. ko.sh plays the other device.
# Prints each step and saves a screenshot of each capsule.
#
# Usage: app-check.sh <simulator UDID> <Octavo.app> <alice-in-wonderland.epub> <out dir>
# Installs the app afresh, so nothing from an earlier run is left. The
# places used are Alice's (KOReader's own, from run.sh).
set -euo pipefail
sim=$1
app=$2
book=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
out=$(mkdir -p "$4" && cd "$4" && pwd)
tools=$(cd "$(dirname "$0")" && pwd)
name=$(basename "$book")
ahead='/body/DocFragment[12]/body/div/p[68]/text().1'
behind='/body/DocFragment[6]/body/div/p[9]/text()[2].212'

xcrun simctl uninstall "$sim" com.ianazzone.ereader 2> /dev/null || true
xcrun simctl install "$sim" "$app"
documents=$(xcrun simctl get_app_container "$sim" com.ianazzone.ereader data)/Documents
cp "$book" "$documents/$name"
"$tools/ko.sh" set "$book" "/body/DocFragment[1].0" 0 reset > /dev/null
xcrun simctl launch "$sim" com.ianazzone.ereader -connectKOSync 1 > /dev/null
sleep 4

# One remote command; prints the ack's message, if any.
remote() {
    local id=$(( $(date +%s) * 1000 + RANDOM % 1000 ))
    rm -f "$documents/spike-ack.json"
    python3 -I -c 'import json, sys; c = json.loads(sys.argv[2]); c["id"] = int(sys.argv[1]); print(json.dumps(c))' "$id" "$1" \
        > "$documents/spike-command.json.tmp"
    mv "$documents/spike-command.json.tmp" "$documents/spike-command.json"
    for _ in $(seq 300); do
        if grep -qs "$id" "$documents/spike-ack.json"; then
            python3 -I -c 'import json, sys; a = json.load(open(sys.argv[1])); print("   app:", a.get("message", "ok"))' "$documents/spike-ack.json"
            return
        fi
        sleep 0.2
    done
    echo "No answer from the app to $1" >&2
    exit 1
}
reader() { python3 -I -c 'import json, sys; s = json.load(open(sys.argv[1])); print("   reader: %.1f%%  %s" % ((s.get("fraction") or 0) * 100, s.get("syncStatus")))' "$documents/spike-state.json"; }
server() { echo "   server: $("$tools/ko.sh" get "$book" | python3 -I -c 'import json, sys; p = json.load(sys.stdin); print(p.get("device"), round(p.get("percentage", 0) * 100, 1), p.get("progress"))')"; }
# Both of the Duo's displays: the one in use shows the reader.
shot() {
    for display in 1 3; do xcrun simctl io "$sim" screenshot --display="$display" "$out/$1-display$display.png" > /dev/null 2>&1 || true; done
    echo "   screenshots: $out/$1-display*.png"
}

echo "1. Import and open the book, go to 50%: the place reaches the server"
remote "{\"cmd\": \"importLocal\", \"name\": \"$name\"}"; sleep 5
remote '{"cmd": "goto", "fraction": 0.5}'; sleep 5
reader; server

echo "2. Another device reads on to 74.5%; the app comes back: offered, not jumped to"
"$tools/ko.sh" set "$book" "$ahead" 0.745 Kindle > /dev/null
remote '{"cmd": "connectionReturned"}'; sleep 4
remote '{"cmd": "serverPlace"}'; reader; shot 1-offered-ahead

echo "3. Go: the reader goes there, and nothing is sent back"
remote '{"cmd": "serverPlace", "name": "go"}'; sleep 5
reader; server; shot 2-went

echo "4. Closed; another device goes back to 24.8%; reopened and back in the app: stays at your place, offered"
remote '{"cmd": "close"}'; sleep 2
"$tools/ko.sh" set "$book" "$behind" 0.248 Kindle > /dev/null
# Straight back into the reader, it reuses the pull from minutes ago, as
# unfolding on the book's screen does (whose own pull this skips); coming
# back to the app asks again.
remote "{\"cmd\": \"importLocal\", \"name\": \"$name\"}"; sleep 6
remote '{"cmd": "connectionReturned"}'; sleep 4
reader; remote '{"cmd": "serverPlace"}'; shot 3-offered-behind

echo "5. ✕: your place goes to the server"
remote '{"cmd": "serverPlace", "name": "stay"}'; sleep 5
server

echo "6. Offline, a page on: nothing goes; back online: it does"
remote '{"cmd": "offline", "on": true}'; remote '{"cmd": "next"}'; sleep 5
reader; server
remote '{"cmd": "offline", "on": false}'; remote '{"cmd": "connectionReturned"}'; sleep 5
reader; server
