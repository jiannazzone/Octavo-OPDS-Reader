#!/bin/zsh
# The local BookOrbit's row for a file (docs/notes/fixed-layout.md).
# bo.sh progress <fileId>
# bo.sh set <fileId> <cfi> <percentage> [pageNumber]   (another reader moving the place)
# Logs in once (5 logins a minute per address), then refreshes.
B=http://localhost:3300/api/v1
T=${OCTAVO_BO_TOKENS:-${TMPDIR:-/tmp}/octavo-fxl-bo-tokens.json}
login() { curl -s -X POST $B/auth/login -H 'Content-Type: application/json' -d '{"username":"octavo","password":"OctavoDev1","clientKind":"native","deviceLabel":"fixed-layout check"}' > $T; }
refresh() { local r=$(jq -r .refreshToken $T); curl -s -X POST $B/auth/refresh -H 'Content-Type: application/json' -d "{\"refreshToken\":\"$r\"}" > $T.new && jq -e .accessToken $T.new >/dev/null && mv $T.new $T || login; }
[[ -f $T ]] && refresh || login
auth=(-H "Authorization: Bearer $(jq -r .accessToken $T)")
case $1 in
  progress) curl -s $auth $B/books/files/$2/progress | jq -c '{cfi, percentage, pageNumber, textUpdatedAt}';;
  set)
    body=$(jq -n --arg c "$3" --argjson p "$4" --argjson n "${5:-null}" 'if $n == null then {cfi: $c, percentage: $p} else {cfi: $c, percentage: $p, pageNumber: $n} end')
    curl -s -o /dev/null -w '%{http_code}\n' -X POST $auth -H 'Content-Type: application/json' -d "$body" $B/books/files/$2/progress;;
esac
