#!/bin/zsh
# a2w.sh <fileID> <tag> <n next> | a2w.sh <fileID> <tag> goto <fraction> [n next]
# Moves the app, waits for the debounced push, prints the app's first words and the server row.
S=${0:A:h}; R=${RUNS:-${TMPDIR:-/tmp}/octavo-sync-runs}; mkdir -p $R; F=$1; TAG=$2; shift 2
if [[ $1 == goto ]]; then $S/app.sh "\"cmd\":\"goto\",\"fraction\":$2" >/dev/null; N=${3:-0}; else N=$1; fi
for i in $(seq 1 $N); do $S/app.sh '"cmd":"next"' >/dev/null; done
for i in {1..40}; do
  sleep 1
  st=$($S/app.sh state); cfi=$(echo $st | jq -r .cfi); srv=$($S/bo.sh progress $F)
  [[ $(echo $srv | jq -r .cfi) == $cfi ]] && break
done
echo $st > $R/$TAG.app.json
echo "app:    $(echo $st | jq -c '{cfi, rangeCFI, fraction, tocLabel, blankPage, syncStatus}')"
echo "server: $srv"
echo "first words: $(echo $st | jq -r .visibleText | cut -c1-120)"
