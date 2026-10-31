#!/bin/zsh
# BookOrbit helper for the `octavo` user. Logs in once (rate limit: 5/min/IP,
# shared with 1c), then refreshes with the native refresh token.
# bo.sh progress <fileId> | bo.sh raw <path>
S=${0:A:h}; B=http://localhost:3300/api/v1; T=${TMPDIR:-/tmp}/octavo-bo-tokens.json
login() { curl -s -X POST $B/auth/login -H 'Content-Type: application/json' -d '{"username":"octavo","password":"OctavoDev1","clientKind":"native","deviceLabel":"2a host script"}' > $T; }
refresh() { local r=$(jq -r .refreshToken $T); curl -s -X POST $B/auth/refresh -H 'Content-Type: application/json' -d "{\"refreshToken\":\"$r\"}" > $T.new && jq -e .accessToken $T.new >/dev/null && mv $T.new $T || login; }
[[ -f $T ]] || login
get() { local code=$(curl -s -o $T.body -w '%{http_code}' -H "Authorization: Bearer $(jq -r .accessToken $T)" $B/$1); if [[ $code == 401 ]]; then refresh; curl -s -H "Authorization: Bearer $(jq -r .accessToken $T)" $B/$1; else cat $T.body; fi; }
case $1 in
  progress) get books/files/$2/progress | jq -c '{cfi, percentage, textUpdatedAt}';;
  raw) get $2;;
esac
