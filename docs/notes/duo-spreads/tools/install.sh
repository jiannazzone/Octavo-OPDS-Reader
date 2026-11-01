#!/bin/zsh
# Build the app and (re)install it on 'Octavo Sync Duo', folded, then launch it.
set -e
SIM=${SIM:-32DEFF1F-1885-4884-8DAF-2FC92AE08FC2}
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
DD=${DERIVED_DATA:-$ROOT/build/DerivedData}
xcodebuild build -project "$ROOT/Octavo.xcodeproj" -scheme Octavo -destination "id=$SIM" -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error|warning: ' || true
hinge -d $SIM close >/dev/null
xcrun simctl terminate $SIM com.ianazzone.ereader 2>/dev/null || true
xcrun simctl install $SIM "$DD/Build/Products/Debug-iphonesimulator/Octavo.app"
D=$(xcrun simctl get_app_container $SIM com.ianazzone.ereader data)/Documents
rm -f "$D/spike-events.jsonl" "$D/spike-state.json"
# -spike 1: open on the spike screens (SpikeRemote) instead of the app shell.
xcrun simctl launch $SIM com.ianazzone.ereader -spike 1 >/dev/null
sleep 3
