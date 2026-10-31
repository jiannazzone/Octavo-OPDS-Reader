#!/usr/bin/env bash
# Seeds the local BookOrbit (docker-compose.yml) through its REST API:
# creates the dev admin, a "Spike" library, uploads SampleBooks/*.epub and
# puts them all in a "Spike" collection. Safe to run again.
#
# Needs curl and jq. Run Scripts/fetch-sample-books.sh first.
set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd ../.. && pwd)"

BASE="${OCTAVO_BOOKORBIT_URL:-http://localhost:3300}"
API="$BASE/api/v1"
USERNAME="${OCTAVO_BOOKORBIT_USER:-octavo}"
PASSWORD="${OCTAVO_BOOKORBIT_PASS:-OctavoDev1}"
SETUP_TOKEN="octavo-dev-setup-token" # matches docker-compose.yml
BOOKS_DIR="${SAMPLE_BOOKS_DIR:-$REPO_ROOT/SampleBooks}"

shopt -s nullglob
epubs=("$BOOKS_DIR"/*.epub)
if [ ${#epubs[@]} -eq 0 ]; then
  echo "No EPUBs in $BOOKS_DIR. Run Scripts/fetch-sample-books.sh first." >&2
  exit 1
fi

echo "Waiting for $BASE …"
for _ in $(seq 1 60); do
  curl -sf "$API/auth/setup-status" >/dev/null && break
  sleep 2
done
status=$(curl -sf "$API/auth/setup-status")

if [ "$(jq -r .needsSetup <<<"$status")" = "true" ]; then
  echo "Creating admin '$USERNAME'"
  curl -sf -X POST "$API/auth/setup" \
    -H 'content-type: application/json' -H "x-setup-token: $SETUP_TOKEN" \
    -d "$(jq -n --arg u "$USERNAME" --arg p "$PASSWORD" \
      '{username: $u, name: "Octavo Dev", email: "octavo@example.com", password: $p}')" >/dev/null
fi

token=$(curl -sf -X POST "$API/auth/login" -H 'content-type: application/json' \
  -d "$(jq -n --arg u "$USERNAME" --arg p "$PASSWORD" \
    '{username: $u, password: $p, clientKind: "native", deviceLabel: "seed.sh"}')" | jq -r .accessToken)
auth=(-H "authorization: Bearer $token")

# The library's folder must exist inside the container (data/books is mounted at /books).
mkdir -p data/books/spike
library_id=$(curl -sf "${auth[@]}" "$API/libraries" | jq -r 'map(select(.name == "Spike"))[0].id // empty')
if [ -z "$library_id" ]; then
  library_id=$(curl -sf -X POST "${auth[@]}" "$API/libraries" -H 'content-type: application/json' \
    -d '{"name": "Spike", "icon": "BookOpen", "folders": ["/books/spike"]}' | jq -r .id)
  echo "Created library Spike (id $library_id)"
fi

for epub in "${epubs[@]}"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${auth[@]}" "$API/libraries/$library_id/upload" \
    -F "file=@$epub;type=application/epub+zip")
  case "$code" in
    201) echo "Uploaded $(basename "$epub")" ;;
    409) echo "Already there: $(basename "$epub")" ;;
    *) echo "Upload of $(basename "$epub") failed: HTTP $code" >&2; exit 1 ;;
  esac
done

collection_id=$(curl -sf "${auth[@]}" "$API/collections" | jq -r 'map(select(.name == "Spike"))[0].id // empty')
if [ -z "$collection_id" ]; then
  collection_id=$(curl -sf -X POST "${auth[@]}" "$API/collections" -H 'content-type: application/json' \
    -d '{"name": "Spike", "icon": "Rocket"}' | jq -r .id)
  echo "Created collection Spike (id $collection_id)"
fi

book_ids=$(curl -sf -X POST "${auth[@]}" "$API/libraries/$library_id/books" -H 'content-type: application/json' \
  -d '{}' | jq -c '[.items[].id]')
curl -sf -X POST "${auth[@]}" "$API/collections/$collection_id/books" -H 'content-type: application/json' \
  -d "{\"bookIds\": $book_ids}" >/dev/null

echo
echo "Collection Spike (id $collection_id):"
curl -sf "${auth[@]}" "$API/collections/$collection_id/books" |
  jq -r '.items[] | "  book \(.id)  file \(.files[0].id)  \(.title)"'
echo
echo "Web UI: $BASE  (user $USERNAME / $PASSWORD)"
