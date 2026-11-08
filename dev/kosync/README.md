# Local KOReader sync server (dev only)

A throwaway KOReader sync server for developing and testing Octavo's KOReader
sync (`docs/notes/koreader-sync.md`). It runs KOReader's published image,
`koreader/kosync` (AGPL-3.0); nothing of it is vendored here.

- **Image:** `koreader/kosync@sha256:bb3f1361…64e1`, its `latest` on
  2026-11-08 (built 2026-05-16). It has no other tag.
- **Address:** <http://localhost:3350> (plain), and <https://localhost:3351>
  with the image's self-signed certificate, for the "Trust this server" step.
  Both are bound to 127.0.0.1 (move them with `KOSYNC_PORT` and
  `KOSYNC_TLS_PORT`). The iOS Simulator reaches them at the same addresses.
- **Account:** `octavo` / `OctavoDev1`, created by `seed.sh`. Registration is
  on, so the tests can make others.
- **State:** `data/` (gitignored), Redis's files.

## Start

```bash
cd dev/kosync
docker compose up -d
./seed.sh
```

## Tests

```bash
cd Packages/OctavoKit
OCTAVO_KOSYNC_URL=http://localhost:3350 OCTAVO_KOSYNC_USER=octavo \
OCTAVO_KOSYNC_PASS=OctavoDev1 swift test --filter KOSyncLiveTests
```

They write places only for made-up documents, so they don't touch a real
book's place.

## What it does

Measured 2026-11-06: it keeps a place exactly as sent, answers `{}` for a
document it hasn't seen, sets `timestamp` itself in seconds, needs
`Accept: application/vnd.koreader.v1+json` (412 without), and checks
`x-auth-key` against the MD5 the account registered with. The full table is in
`docs/notes/koreader-sync.md`.

## Reset

```bash
cd dev/kosync
docker compose down
rm -rf data
docker compose up -d && ./seed.sh
```
