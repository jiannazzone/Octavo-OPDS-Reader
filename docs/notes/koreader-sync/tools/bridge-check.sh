#!/bin/bash
# The bridge itself against KOReader (docs/notes/koreader-sync.md): each
# sample book opened in Octavo's reader on a simulator, through the debug
# remote, then places the bridge writes read in KOReader and KOReader's own
# read by the bridge. Run run.sh first with the same work folder, for
# KOReader's own places.
#
# Usage: bridge-check.sh <simulator UDID> <SampleBooks dir> <work dir>
# A DEBUG build of Octavo must be installed and running on that simulator.
set -euo pipefail
sim=$1
books=$(cd "$2" && pwd)
work=$(mkdir -p "$3" && cd "$3" && pwd)
tools=$(cd "$(dirname "$0")" && pwd)
source "$tools/container.sh"
ensure_koreader "$books" "$work"
documents=$(xcrun simctl get_app_container "$sim" com.ianazzone.ereader data)/Documents
mkdir -p "$work/bridge" "$work/places"

# One remote command; waits for its ack.
remote() {
    local id=$(( $(date +%s) * 1000 + RANDOM % 1000 ))
    rm -f "$documents/spike-ack.json"
    python3 -I -c 'import json, sys; c = json.loads(sys.argv[2]); c["id"] = int(sys.argv[1]); print(json.dumps(c))' "$id" "$1" \
        > "$documents/spike-command.json.tmp"
    mv "$documents/spike-command.json.tmp" "$documents/spike-command.json"
    for _ in $(seq 600); do
        if grep -qs "$id" "$documents/spike-ack.json"; then return; fi
        sleep 0.2
    done
    echo "No answer from the app to $1" >&2
    exit 1
}

for epub in "$books"/*.epub; do
    b=$(basename "$epub" .epub)
    echo "=== $b"
    cp "$epub" "$documents/$b.epub"
    remote "{\"cmd\": \"openLocal\", \"name\": \"$b.epub\"}"
    sleep 6
    script=$(python3 -I - "$work/out/$b-ko.tsv" "$tools/bridge.js" <<'PY'
import json, sys
rows = [line.rstrip('\n').split('\t') for line in list(open(sys.argv[1], errors='replace'))[1:]]
print(f'const KO = {json.dumps([[r[2], r[3]] for r in rows])}\nconst SEED = 11\n' + open(sys.argv[2]).read())
PY
)
    rm -f "$documents/spike-js.json"
    remote "$(python3 -I -c 'import json, sys; print(json.dumps({"cmd": "js", "script": sys.stdin.read()}))' <<< "$script")"
    cp "$documents/spike-js.json" "$work/bridge/$b.json"
    python3 -I -c 'import json, sys
out = json.loads(json.load(open(sys.argv[1]))["result"])
with open(sys.argv[2], "w") as f:
    for p in out["places"]:
        if p["xpointer"]: f.write(p["id"] + "\t" + p["xpointer"] + "\n")' "$work/bridge/$b.json" "$work/places/$b-bridge.tsv"
    cp "$work/places/$b-bridge.tsv" "$work/places/$b.tsv"
    koreader_places "$b"
    python3 -I "$tools/xpointer_check.py" bridge "$work/bridge/$b.json" "$work/out/$b-landed.tsv"
    remote '{"cmd": "close"}'
done
