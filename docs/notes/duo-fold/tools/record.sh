#!/bin/zsh
# SIM=<udid> record.sh <out.mov> <display> <move>: records one display while a hinge move runs.
# Only one recording per device at a time. iPhone Duo: LCD-1 is the inner display, LCD the outer.
# <move> is passed to hinge as words, e.g. "open" or "sweep 0 180 1".
S=${SIM:?}
xcrun simctl io $S recordVideo --codec=h264 --display=$2 --force $1 > $1.log 2>&1 &
p=$!
for i in {1..50}; do grep -q "Recording started" $1.log && break; sleep 0.2; done
sleep 1
hinge -d $S -t 0 ${=3} >/dev/null
sleep ${PER:-8}
kill -INT $p; wait $p
ls -la $1
