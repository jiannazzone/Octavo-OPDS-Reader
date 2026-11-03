#!/bin/zsh
# remote.sh '<json>': sends a ReaderRemote command to Octavo on a simulator
# and prints its ack. SIM is the simulator's UDID (or name).
#   SIM=EB8983D2-... tools/remote.sh '{"cmd":"turn","side":"right"}'
# Commands this note uses: openLocal, signin, detail, close, turn, swipe,
# turnState, pageTurn, coverMotion, turnProbe (Octavo/Debug/ReaderRemote.swift).
DOCS=$(xcrun simctl get_app_container ${SIM:?set SIM} com.ianazzone.ereader data)/Documents
ID=$RANDOM
JSON=$(printf "%s" "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); d['id']=$ID; print(json.dumps(d))")
rm -f $DOCS/spike-ack.json
printf "%s" "$JSON" > $DOCS/spike-command.json.tmp && mv $DOCS/spike-command.json.tmp $DOCS/spike-command.json
for i in {1..600}; do
  if [[ -f $DOCS/spike-ack.json ]] && grep -q "\"id\":$ID" $DOCS/spike-ack.json; then cat $DOCS/spike-ack.json; echo; exit 0; fi
  sleep 0.1
done
echo "no ack"; exit 1
