#!/bin/zsh
# Run a function body in the reader page on 'Octavo Sync Duo' and print what it returns.
#   js.sh 'return window.octavo ? Object.keys(window.octavo) : null'
SIM=${SIM:-32DEFF1F-1885-4884-8DAF-2FC92AE08FC2}
D=$(xcrun simctl get_app_container $SIM com.ianazzone.ereader data)/Documents
rm -f "$D/spike-js.json"
NOWAIT=1 "$(dirname "$0")/app.sh" "\"cmd\":\"js\",\"script\":$(jq -Rs . <<<"$1")" >/dev/null
for i in {1..50}; do [[ -f "$D/spike-js.json" ]] && break; sleep 0.2; done
cat "$D/spike-js.json"
