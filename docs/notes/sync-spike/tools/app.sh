#!/bin/zsh
# Drive the spike app (DEBUG command file, see Octavo/Spike/SpikeRemote.swift).
#   app.sh '"cmd":"goto","fraction":0.5'  → waits for the ack and a fresh state, prints state
#   app.sh state                          → prints state
# NOWAIT=1 skips waiting for a fresh state (commands that don't move the reader).
SIM=32DEFF1F-1885-4884-8DAF-2FC92AE08FC2
D=$(xcrun simctl get_app_container $SIM com.ianazzone.ereader data)/Documents
if [[ "$1" != "state" ]]; then
  ID=$(( $(date +%s) * 1000 + RANDOM % 1000 ))
  before=$(jq -r .updatedAt "$D/spike-state.json" 2>/dev/null)
  rm -f "$D/spike-ack.json"
  echo "{\"id\": $ID, $1}" > "$D/spike-command.json.tmp" && mv "$D/spike-command.json.tmp" "$D/spike-command.json"
  for i in {1..300}; do
    if [[ -f "$D/spike-ack.json" ]] && grep -q "$ID" "$D/spike-ack.json"; then grep -q '"ok":true' "$D/spike-ack.json" || cat "$D/spike-ack.json"; break; fi
    sleep 0.2
  done
  if [[ -z "$NOWAIT" ]]; then
    for i in {1..120}; do
      sleep 0.5
      now=$(jq -r .updatedAt "$D/spike-state.json" 2>/dev/null)
      [[ "$now" != "$before" ]] && break
    done
    sleep ${SETTLE:-1.5}
  fi
fi
cat "$D/spike-state.json" 2>/dev/null
