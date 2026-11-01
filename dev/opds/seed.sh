#!/usr/bin/env bash
# Seeds the local OPDS servers (docker-compose.yml) with the public-domain
# sample books and the dev accounts in README.md. Safe to run again.
#
# - Builds a calibre library in data/calibre-library with calibre's calibredb
#   (run as a local tool only; calibre is GPL and nothing of it is in the repo).
#   Calibre-Web and COPS both serve it.
# - Copies the EPUBs into data/komga-books and data/kavita-books, one folder per
#   book, and creates a library over each through the servers' REST APIs.
#
# Needs curl, jq, docker and calibre. Run Scripts/fetch-sample-books.sh first.
set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd ../.. && pwd)"
BOOKS_DIR="${SAMPLE_BOOKS_DIR:-$REPO_ROOT/SampleBooks}"
CALIBREDB="${CALIBREDB:-$(command -v calibredb || echo /Applications/calibre.app/Contents/MacOS/calibredb)}"

CALIBRE_WEB="http://127.0.0.1:${CALIBRE_WEB_PORT:-3310}"
COPS="http://127.0.0.1:${COPS_PORT:-3320}"
KOMGA="http://127.0.0.1:${KOMGA_PORT:-3330}"
KAVITA="http://127.0.0.1:${KAVITA_PORT:-3340}"
USERNAME=octavo
EMAIL=octavo@example.com
PASSWORD=OctavoDev1

# file stem : title (Komga and Kavita name a series after its folder)
BOOKS="
alice-in-wonderland:Alice's Adventures in Wonderland
frankenstein:Frankenstein
moby-dick:Moby-Dick
pride-and-prejudice:Pride and Prejudice
sherlock-holmes:The Adventures of Sherlock Holmes
"

for stem in alice-in-wonderland frankenstein moby-dick pride-and-prejudice sherlock-holmes; do
  [ -s "$BOOKS_DIR/$stem.epub" ] || { echo "Missing $BOOKS_DIR/$stem.epub. Run Scripts/fetch-sample-books.sh first." >&2; exit 1; }
done
[ -x "$CALIBREDB" ] || { echo "calibre's calibredb not found (set CALIBREDB to its path)." >&2; exit 1; }

wait_for() { # url
  echo "Waiting for $1 …"
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "$1" && return
    sleep 2
  done
  echo "$1 didn't answer. Is 'docker compose up -d' running?" >&2
  exit 1
}

# --- calibre library (Calibre-Web, COPS) -----------------------------------

library=data/calibre-library
mkdir -p "$library"
if [ ! -s "$library/metadata.db" ]; then
  echo "Building the calibre library"
  # A throwaway calibre config, so the user's own calibre plugins don't run.
  export CALIBRE_CONFIG_DIRECTORY="$(mktemp -d)"
  db() { "$CALIBREDB" --library-path "$library" "$@" >/dev/null; }
  # ids 1–5, in this order
  for stem in alice-in-wonderland frankenstein moby-dick pride-and-prejudice sherlock-holmes; do
    db add "$BOOKS_DIR/$stem.epub"
  done
  # Several formats per book, to check which one Octavo picks: EPUB first.
  for fmt in azw3 mobi; do
    [ -s "$BOOKS_DIR/alice-in-wonderland.$fmt" ] && db add_format 1 "$BOOKS_DIR/alice-in-wonderland.$fmt"
    [ -s "$BOOKS_DIR/frankenstein.$fmt" ] && db add_format 2 "$BOOKS_DIR/frankenstein.$fmt"
  done
  [ -s "$BOOKS_DIR/sherlock-holmes.fb2" ] && db add_format 5 "$BOOKS_DIR/sherlock-holmes.fb2"
  # No EPUB at all: Kindle first, then FB2.
  if [ -s "$BOOKS_DIR/the-time-machine.azw3" ]; then
    db add "$BOOKS_DIR/the-time-machine.azw3" # id 6
    [ -s "$BOOKS_DIR/the-time-machine.mobi" ] && db add_format 6 "$BOOKS_DIR/the-time-machine.mobi"
    [ -s "$BOOKS_DIR/the-time-machine.fb2" ] && db add_format 6 "$BOOKS_DIR/the-time-machine.fb2"
  fi
  rm -rf "$CALIBRE_CONFIG_DIRECTORY"
  unset CALIBRE_CONFIG_DIRECTORY
fi

# --- Komga and Kavita folders ----------------------------------------------

while IFS=: read -r stem title; do
  [ -n "$stem" ] || continue
  for dir in data/komga-books data/kavita-books; do
    mkdir -p "$dir/$title"
    [ -e "$dir/$title/$stem.epub" ] || cp "$BOOKS_DIR/$stem.epub" "$dir/$title/$stem.epub"
  done
done <<<"$BOOKS"

# --- Calibre-Web ------------------------------------------------------------
# No setup API: the first run makes /config/app.db with admin/admin123. This
# renames that admin to the dev account, points it at the library and
# restarts. The password hash comes from Calibre-Web's own werkzeug.

wait_for "$CALIBRE_WEB/login"
docker compose exec -T calibre-web python3 - "$USERNAME" "$EMAIL" "$PASSWORD" <<'PY'
import sqlite3, sys
from werkzeug.security import generate_password_hash
name, email, password = sys.argv[1:]
c = sqlite3.connect('/config/app.db')
c.execute("update user set name=?, email=?, password=? where id=1", (name, email, generate_password_hash(password)))
c.execute("update settings set config_calibre_dir='/books'")
c.commit()
PY
docker compose restart calibre-web >/dev/null
wait_for "$CALIBRE_WEB/login"
[ "$(curl -s -o /dev/null -w '%{http_code}' -u "$USERNAME:$PASSWORD" "$CALIBRE_WEB/opds")" = 200 ] \
  && echo "Calibre-Web ready" || { echo "Calibre-Web's OPDS didn't accept the dev account" >&2; exit 1; }

# --- COPS -------------------------------------------------------------------

wait_for "$COPS/feed"
echo "COPS ready"

# --- Komga ------------------------------------------------------------------

wait_for "$KOMGA/api/v1/claim"
if [ "$(curl -s "$KOMGA/api/v1/claim" | jq -r .isClaimed)" != "true" ]; then
  echo "Creating Komga's admin $EMAIL"
  curl -sf -X POST "$KOMGA/api/v1/claim" -H "X-Komga-Email: $EMAIL" -H "X-Komga-Password: $PASSWORD" >/dev/null
fi
komga=(-u "$EMAIL:$PASSWORD")
if [ -z "$(curl -sf "${komga[@]}" "$KOMGA/api/v1/libraries" | jq -r 'map(select(.name == "Spike"))[0].id // empty')" ]; then
  echo "Creating Komga library Spike"
  curl -sf "${komga[@]}" -X POST "$KOMGA/api/v1/libraries" -H 'content-type: application/json' \
    -d '{"name": "Spike", "root": "/books"}' >/dev/null # scans on creation
fi
echo "Komga ready"

# --- Kavita -----------------------------------------------------------------

wait_for "$KAVITA/api/health"
login() {
  curl -sf -X POST "$KAVITA/api/Account/login" -H 'content-type: application/json' \
    -d "$(jq -n --arg u "$USERNAME" --arg p "$PASSWORD" '{username: $u, password: $p}')"
}
if ! session=$(login); then
  echo "Creating Kavita's admin $USERNAME"
  curl -sf -X POST "$KAVITA/api/Account/register" -H 'content-type: application/json' \
    -d "$(jq -n --arg u "$USERNAME" --arg e "$EMAIL" --arg p "$PASSWORD" '{username: $u, email: $e, password: $p}')" >/dev/null
  session=$(login)
fi
kavita=(-H "authorization: Bearer $(jq -r .token <<<"$session")")
library_id=$(curl -sf "${kavita[@]}" "$KAVITA/api/Library/libraries" | jq -r 'map(select(.name == "Spike"))[0].id // empty')
if [ -z "$library_id" ]; then
  echo "Creating Kavita library Spike"
  # type 2 = Book; fileGroupTypes 2 = EPUB, 3 = PDF; metadataProvider 2 = Kavita's own
  curl -sf "${kavita[@]}" -X POST "$KAVITA/api/Library/create" -H 'content-type: application/json' \
    -d '{"name": "Spike", "type": 2, "folders": ["/books"], "fileGroupTypes": [2, 3], "excludePatterns": [],
         "metadataProvider": 2, "folderWatching": false, "includeInDashboard": true, "includeInSearch": true,
         "manageCollections": true, "manageReadingLists": true, "allowScrobbling": false,
         "allowMetadataMatching": false, "enableMetadata": true}' >/dev/null
  library_id=$(curl -sf "${kavita[@]}" "$KAVITA/api/Library/libraries" | jq -r 'map(select(.name == "Spike"))[0].id')
fi
curl -sf "${kavita[@]}" -X POST "$KAVITA/api/Library/scan?libraryId=$library_id" >/dev/null
echo "Kavita ready"

cat <<EOF

OPDS catalogs:
  Calibre-Web  $CALIBRE_WEB/opds  ($USERNAME / $PASSWORD)
  COPS         $COPS/feed  (no sign-in)
  Komga        $KOMGA/opds/v1.2/catalog, OPDS 2 at /opds/v2/catalog  ($EMAIL / $PASSWORD)
  Kavita       $KAVITA/api/opds/$(jq -r .apiKey <<<"$session")  (the API key is the sign-in)
EOF
