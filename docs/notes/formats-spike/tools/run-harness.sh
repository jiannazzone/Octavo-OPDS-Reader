#!/bin/zsh
# Formats spike: script-test books in macOS WebKit, without and with the app's CSP.
#   [MODES="nocsp csp"] run-harness.sh OUT_DIR [book ...]
# Books default to every SampleBooks/script-test*. MODES are harness.py modes,
# e.g. "nocsp+sanitize nocsp+meta" for the harden.js prototype.
# For each mode and book: a fresh beacon log, one probe run (collect.js, links
# clicked). Then summarize.py OUT_DIR prints the table.
set -e
TOOLS=${0:A:h}
REPO=${TOOLS:h:h:h:h}
OUT=${1:?out dir}; shift
mkdir -p $OUT
books=(${@:-${(f)"$(cd $REPO/SampleBooks && ls script-test*)"}})
[[ -x $OUT/probe ]] || swiftc -O -o $OUT/probe $TOOLS/probe.swift
port=8797
for mode in ${=MODES:-nocsp csp}; do
  python3 -I $TOOLS/harness.py $REPO $REPO/SampleBooks $port $mode > $OUT/harness-$mode.log 2>&1 &
  harness=$!
  sleep 1
  for book in $books; do
    rm -f $OUT/$mode-$book.beacon.jsonl
    python3 -I $TOOLS/beacon.py $OUT/$mode-$book.beacon.jsonl 8799 > /dev/null 2>&1 &
    beacon=$!
    sleep 0.5
    $OUT/probe http://localhost:$port $book $TOOLS/collect.js 3000 click > $OUT/$mode-$book.json 2> $OUT/$mode-$book.err || echo "$mode $book: probe failed"
    sleep 2
    kill $beacon
    touch $OUT/$mode-$book.beacon.jsonl
    echo "$mode $book: $(wc -l < $OUT/$mode-$book.beacon.jsonl | tr -d ' ') beacon hits"
  done
  kill $harness
  port=$((port - 1))  # a fresh origin, so nothing is cached between modes
done
