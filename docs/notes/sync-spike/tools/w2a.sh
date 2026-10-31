#!/bin/zsh
# w2a.sh <fileID> <tag> <source first words...>: server check, reopen in app, verdict.
S=${0:A:h}; R=${RUNS:-${TMPDIR:-/tmp}/octavo-sync-runs}; mkdir -p $R; F=$1; TAG=$2; shift 2; SRC="$*"
echo "server: $($S/bo.sh progress $F)"
NOWAIT=1 $S/app.sh '"cmd":"close"' >/dev/null; sleep 1
NOWAIT=1 $S/app.sh "\"cmd\":\"open\",\"fileID\":$F" >/dev/null
# Wait for the new reader's state: it says "pulled" (an old reader's says "pushed").
for i in {1..120}; do sleep 1; $S/app.sh state > $R/$TAG.app.json; jq -e '.syncStatus | startswith("pulled")' $R/$TAG.app.json >/dev/null && break; done
sleep 2; $S/app.sh state > $R/$TAG.app.json
jq -c '{openedFrom, restoredFrom, cfi, fraction, tocLabel, syncStatus}' $R/$TAG.app.json
echo "$SRC" > $R/$TAG.src.txt; jq -r .visibleText $R/$TAG.app.json > $R/$TAG.tgt.txt
python3 -I $S/check.py $R/$TAG.src.txt $R/$TAG.tgt.txt
