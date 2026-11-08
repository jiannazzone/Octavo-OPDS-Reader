#!/bin/bash
# Reads or moves a book's place on the local KOReader sync server
# (dev/kosync), as another device would.
#
#   ko.sh get <book.epub>
#   ko.sh set <book.epub> <xpointer> <percentage 0...1> [device]
#
# The book is named by its file's document (KOReader's partial MD5), so use
# the same file the app holds. KOSYNC_URL moves the server.
set -euo pipefail
server=${KOSYNC_URL:-http://127.0.0.1:3350}
user=octavo
key=$(printf '%s' OctavoDev1 | { command -v md5 > /dev/null && md5 || md5sum | cut -d' ' -f1; })
document=$(python3 -I -c '
import hashlib, sys
md5 = hashlib.md5()
with open(sys.argv[1], "rb") as f:
    for offset in [0] + [1024 << (2 * i) for i in range(11)]:
        f.seek(offset)
        sample = f.read(1024)
        if not sample: break
        md5.update(sample)
print(md5.hexdigest())' "$2")
headers=(-H "Accept: application/vnd.koreader.v1+json" -H "x-auth-user: $user" -H "x-auth-key: $key")
case "$1" in
get)
    curl -s "${headers[@]}" "$server/syncs/progress/$document"; echo ;;
set)
    body=$(python3 -I -c 'import json, sys; print(json.dumps({"document": sys.argv[1], "progress": sys.argv[2], "percentage": float(sys.argv[3]), "device": sys.argv[4], "device_id": "ko-sh"}))' \
        "$document" "$3" "$4" "${5:-Kindle}")
    curl -s -X PUT "${headers[@]}" -H 'Content-Type: application/json' -d "$body" "$server/syncs/progress"; echo ;;
*)
    echo "ko.sh get|set <book.epub> …" >&2; exit 1 ;;
esac
