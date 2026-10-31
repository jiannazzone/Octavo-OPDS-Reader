#!/bin/zsh
# Run driver scenarios in parallel. Each line of stdin: ENGINE LABEL QUERY
# ENGINE is chrome or wk. Waits for all to finish.
SP=${0:A:h:h}
LOG=$SP/out/log.jsonl
while read -r engine label query; do
  [[ -z $engine || $engine == \#* ]] && continue
  if [[ $engine == wk ]]; then
    w=$(echo $query | sed -nE 's/.*&w=([0-9]+).*/\1/p'); h=$(echo $query | sed -nE 's/.*&h=([0-9]+).*/\1/p')
    $SP/tools/wkrun "http://127.0.0.1:8765/driver/driver.html?$query&label=$label" ${w:-390} ${h:-844} 400 &
  else
    python3 -I $SP/tools/run.py $engine $LOG $SP/profiles "$query&label=$label" 400 >/dev/null &
  fi
done
wait
