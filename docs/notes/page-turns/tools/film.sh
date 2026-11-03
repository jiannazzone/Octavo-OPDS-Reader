#!/bin/zsh
# film.sh <out.mov> <display> <command>...: records a display (LCD folded,
# LCD-1 unfolded) while sending remote commands (a bare number waits that
# many seconds), then writes <out>-sheet.png with the frames that change.
#   SIM=EB8983D2-... tools/film.sh /tmp/flip.mov LCD-1 '{"cmd":"turn","side":"right"}'
# Start simctl's recorder directly, as here: started from a backgrounded
# subshell it sometimes kept only the first two frames.
here=${0:A:h}; out=$1; display=$2; shift 2
xcrun simctl io ${SIM:?set SIM} recordVideo --display=$display --codec=h264 --force $out > $out.log 2>&1 &
pid=$!
for i in {1..50}; do grep -q "Recording started" $out.log && break; sleep 0.1; done
sleep 0.5
for c in "$@"; do if [[ $c == <->(.<->|) ]]; then sleep $c; else $here/remote.sh "$c" >/dev/null; fi; done
sleep 1.5; kill -INT $pid; wait $pid 2>/dev/null
frames=${out:r}-frames; rm -rf $frames; mkdir -p $frames
ffmpeg -loglevel error -i $out -vf "fps=30,scale=476:-1" $frames/%03d.png
python3 $here/sheet.py $frames ${out:r}-sheet.png
