#!/bin/zsh
# Cover-display handoff on 'Octavo Sync Duo' (spike 2b): folded on a book's
# detail screen, unfold, and check that the reader opens at the book's
# position with the app's state intact.
#   handoff.sh <label> '"name":"frankenstein.epub"'   local book
#   handoff.sh <label> '"fileID":2' signin            BookOrbit book (signs in first)
# Writes duo-spreads/screenshots/<label>-{folded,unfolded}.png and
# duo-spreads/events/<label>.jsonl (every probe event during the unfold),
# and prints the reader's state after the unfold.
SIM=${SIM:-32DEFF1F-1885-4884-8DAF-2FC92AE08FC2}
HERE=$(dirname "$0")
OUT=$HERE/..
D=$(xcrun simctl get_app_container $SIM com.ianazzone.ereader data)/Documents
label=$1; book=$2
mkdir -p $OUT/screenshots $OUT/events
hinge -d $SIM close >/dev/null; sleep 2
NOWAIT=1 $HERE/app.sh '"cmd":"home"' >/dev/null; sleep 1
if [[ "$3" == signin ]]; then NOWAIT=1 $HERE/app.sh '"cmd":"signin"' >/dev/null; sleep 2; fi
NOWAIT=1 $HERE/app.sh "\"cmd\":\"detail\",$book" >/dev/null; sleep 2
hinge -d $SIM screenshot $OUT/screenshots/$label-folded.png >/dev/null
rm -f $D/spike-state.json
mark=$(wc -l < $D/spike-events.jsonl)
hinge -d $SIM open >/dev/null
for i in {1..60}; do
  sleep 1
  [[ -f $D/spike-state.json ]] && jq -e '.posture == "open" and .restoredFrom != null' $D/spike-state.json >/dev/null 2>&1 && break
done
sleep 3
hinge -d $SIM screenshot $OUT/screenshots/$label-unfolded.png >/dev/null
tail -n +$((mark + 1)) $D/spike-events.jsonl > $OUT/events/$label.jsonl
jq -c '{bookID, posture, cfi, restoredFrom, openedFrom, syncStatus, t: .visibleText[0:60]}' $D/spike-state.json
