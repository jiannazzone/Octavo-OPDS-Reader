#!/bin/zsh
# Formats spike: cfi-walk.js over books in one harness mode, to compare CFIs
# with and without the harden.js prototype.
#   [STEP=1 TURNS=2] run-walk.sh MODE OUT_DIR PORT book...
# Writes OUT_DIR/<MODE>-<book>.json; compare-walk.py OUT_DIR compares modes.
set -e
TOOLS=${0:A:h}
REPO=${TOOLS:h:h:h:h}
mode=$1 out=$2 port=$3; shift 3
mkdir -p $out
[[ -x $out/probe ]] || swiftc -O -o $out/probe $TOOLS/probe.swift
python3 -I $TOOLS/harness.py $REPO $REPO/SampleBooks $port $mode > $out/harness-$mode.log 2>&1 &
harness=$!
sleep 1
for book in $@; do
  PROBE_STEP=${STEP:-1} PROBE_TURNS=${TURNS:-2} $out/probe http://localhost:$port $book $TOOLS/cfi-walk.js 0 > $out/$mode-$book.json 2>/dev/null || echo "$mode $book: probe failed"
done
kill $harness
