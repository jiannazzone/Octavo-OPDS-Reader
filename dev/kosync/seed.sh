#!/usr/bin/env bash
# Registers the dev account (README.md) on the local KOReader sync server.
# Safe to run again. Needs curl and md5 (macOS) or md5sum.
set -euo pipefail

SERVER="http://127.0.0.1:${KOSYNC_PORT:-3350}"
USERNAME=octavo
PASSWORD=OctavoDev1
ACCEPT="Accept: application/vnd.koreader.v1+json"
KEY=$(printf '%s' "$PASSWORD" | { command -v md5 > /dev/null && md5 || md5sum | cut -d' ' -f1; })

for _ in $(seq 30); do
    curl -sf -H "$ACCEPT" "$SERVER/healthcheck" > /dev/null && break
    sleep 1
done

# 201 registers; 402 (code 2002) means it already is.
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$ACCEPT" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$KEY\"}" "$SERVER/users/create")
case "$status" in
    201) echo "Registered $USERNAME." ;;
    402) echo "$USERNAME was already registered." ;;
    *) echo "Registering failed: HTTP $status" >&2; exit 1 ;;
esac

status=$(curl -s -o /dev/null -w '%{http_code}' -H "$ACCEPT" -H "x-auth-user: $USERNAME" -H "x-auth-key: $KEY" "$SERVER/users/auth")
[ "$status" = 200 ] || { echo "Signing in failed: HTTP $status" >&2; exit 1; }
echo "KOReader sync server: $SERVER (https on port ${KOSYNC_TLS_PORT:-3351}), $USERNAME / $PASSWORD"
