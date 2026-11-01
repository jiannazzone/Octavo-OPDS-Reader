#!/bin/zsh
# BookOrbit helper for the `octavo` user (formats spike). Logs in once (login
# is limited to 5/min/IP and the server is shared), then refreshes with the
# rotating native refresh token, kept in its own file so no other session's
# tokens are rotated away.
#   bo.sh get <path>            GET /api/v1/<path>
#   bo.sh post <path> <json>    POST JSON
#   bo.sh upload <libraryId> <file> <mime>
#   bo.sh progress <fileId>     {cfi, percentage, textUpdatedAt}
B=${BOOKORBIT_URL:-http://localhost:3300}/api/v1
T=${BO_TOKENS:-${TMPDIR:-/tmp}/octavo-formats-spike-bo-tokens.json}
login() { curl -s -X POST $B/auth/login -H 'Content-Type: application/json' -d '{"username":"octavo","password":"OctavoDev1","clientKind":"native","deviceLabel":"formats spike host script"}' > $T; }
refresh() { local r=$(jq -r .refreshToken $T); curl -s -X POST $B/auth/refresh -H 'Content-Type: application/json' -d "{\"refreshToken\":\"$r\"}" > $T.new && jq -e .accessToken $T.new >/dev/null && mv $T.new $T || login; }
[[ -s $T ]] || login
call() { # curl args...
  local code=$(curl -s -o $T.body -w '%{http_code}' -H "Authorization: Bearer $(jq -r .accessToken $T)" "$@")
  if [[ $code == 401 ]]; then refresh; curl -s -H "Authorization: Bearer $(jq -r .accessToken $T)" "$@"; else cat $T.body; fi
}
case $1 in
  get) call $B/$2;;
  post) call -X POST $B/$2 -H 'Content-Type: application/json' -d "$3";;
  upload) call -w '\nHTTP %{http_code}\n' -X POST $B/libraries/$2/upload -F "file=@$3;type=$4";;
  progress) call $B/books/files/$2/progress | jq -c '{cfi, percentage, textUpdatedAt}';;
esac
