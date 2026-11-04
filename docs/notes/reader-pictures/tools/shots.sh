#!/bin/zsh
# shots.sh <simulator UDID> <output folder> [href]: Pride and Prejudice's "She is
# tolerable" (or href) in each posture, as PNGs. Headless: simctl and hinge only.
# Needs Octavo's DEBUG build running with the book in its Documents folder.
UDID=${1:?UDID}; OUT=${2:?folder}; HREF=${3:-OEBPS/909196632077550380_1342-h-0.htm.xhtml#img_images_i_044.jpg}
TOOLS=${0:A:h}
REMOTE=$TOOLS/../../page-turns/tools/remote.sh
mkdir -p $OUT
send() { SIM=$UDID $REMOTE "$1" >/dev/null || exit 1 }
# Folding closes the reader, so the book opens folded and only unfolds.
send '{"cmd":"close"}'
hinge -d $UDID -t 8 orient portrait >/dev/null; hinge -d $UDID -t 8 close >/dev/null
sleep 3
send '{"cmd":"openLocal","name":"pride-and-prejudice.epub"}'
sleep 6
go() { send "$(printf '{"cmd":"js","script":"await document.querySelector(\\"foliate-view\\").goTo(\\"%s\\"); return 1"}' $HREF)"; sleep 1 }
go; hinge -d $UDID screenshot $OUT/folded.png >/dev/null
hinge -d $UDID -t 8 open >/dev/null; sleep 3; go; hinge -d $UDID screenshot $OUT/flat.png >/dev/null
hinge -d $UDID -t 8 half >/dev/null; sleep 3; go; hinge -d $UDID screenshot $OUT/half.png >/dev/null
hinge -d $UDID -t 8 open >/dev/null; hinge -d $UDID -t 8 orient landscape-left >/dev/null; sleep 3; go; hinge -d $UDID screenshot $OUT/sideways.png >/dev/null
hinge -d $UDID -t 8 orient portrait >/dev/null; hinge -d $UDID -t 8 close >/dev/null
