#!/bin/zsh
# shots.sh <simulator UDID> <output folder> [href]: Pride and Prejudice's "She is
# tolerable" (or href) in each posture, as PNGs. Headless: simctl and hinge only.
# Needs Octavo's DEBUG build running with the book in its Documents folder.
UDID=${1:?UDID}; OUT=${2:?folder}; HREF=${3:-OEBPS/909196632077550380_1342-h-0.htm.xhtml#img_images_i_044.jpg}
TOOLS=${0:A:h}
REMOTE=$TOOLS/../../page-turns/tools/remote.sh
mkdir -p $OUT
send() {
  local answer
  answer=$(SIM=$UDID $REMOTE "$1") || { print -u2 "no answer to $1"; exit 1 }
  [[ $answer == *'"ok":true'* ]] || { print -u2 "$1: $answer"; exit 1 }
}
# A move can take longer to confirm than hinge waits, and may still have worked,
# so this checks where the device ended up. Turns before folding into portrait
# and after unfolding out of it.
posture() { # angle orientation
  local now
  for i in {1..5}; do
    if [[ $2 == portrait ]]; then
      hinge -d $UDID -t 8 orient $2 >/dev/null 2>&1; hinge -d $UDID -t 8 $1 >/dev/null 2>&1
    else
      hinge -d $UDID -t 8 $1 >/dev/null 2>&1; hinge -d $UDID -t 8 orient $2 >/dev/null 2>&1
    fi
    sleep 3
    now=$(hinge -d $UDID --json posture)
    [[ $now == *"\"angle\": $1."* && $now == *"\"orientation\": \"$2\""* ]] && return
  done
  print -u2 "couldn't reach $1 $2: $now"
  exit 1
}
# Folding closes the reader, so the book opens folded and only unfolds.
send '{"cmd":"close"}'
posture 0 portrait
send '{"cmd":"openLocal","name":"pride-and-prejudice.epub"}'
sleep 6
go() { send "$(printf '{"cmd":"js","script":"await document.querySelector(\\"foliate-view\\").goTo(\\"%s\\"); return 1"}' $HREF)"; sleep 1 }
go; hinge -d $UDID screenshot $OUT/folded.png >/dev/null
posture 180 portrait; go; hinge -d $UDID screenshot $OUT/flat.png >/dev/null
posture 90 portrait; go; hinge -d $UDID screenshot $OUT/half.png >/dev/null
posture 180 landscape-left; go; hinge -d $UDID screenshot $OUT/sideways.png >/dev/null
posture 0 portrait
