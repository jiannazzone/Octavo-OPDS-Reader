# Local BookOrbit (dev only)

A throwaway BookOrbit server for developing and testing Octavo's BookOrbit
integration. It runs BookOrbit's published Docker image; no BookOrbit code is
vendored here (BookOrbit is AGPL-3.0, see `CLAUDE.md`).

- **Version:** BookOrbit **v3.6.0** — image `ghcr.io/bookorbit/bookorbit:3.6.0`
  (index digest `sha256:bbb5da52e96dbbff1dd36f55454f9845e6cde264b4b3428a3ea783124a4ca62e`),
  upstream tag `v3.6.0` = commit `a96ff0c85a4c25e9126dfa4c71ea87537a3baf7a`.
  Override with `BOOKORBIT_TAG=…`.
- **URL:** <http://localhost:3300> (bound to 127.0.0.1; override with `BOOKORBIT_PORT`).
  The iOS Simulator reaches it at the same address.
- **Login:** `octavo` / `OctavoDev1`. Local test account only, created by `seed.sh`.
  All secrets in `docker-compose.yml` are dev-only placeholders.
- **State:** `data/` (gitignored): `data/postgres`, `data/app`, and `data/books`
  (mounted at `/books`; the library lives in `/books/spike`).

## Start

```bash
cd dev/bookorbit
docker compose up -d
```

First start takes ~20 s while BookOrbit migrates the database. Check with
`curl http://localhost:3300/api/v1/auth/setup-status`.

## Seed

```bash
Scripts/fetch-sample-books.sh   # once: five Gutenberg EPUBs → SampleBooks/
dev/bookorbit/seed.sh
```

Through the REST API it creates the admin user, a **Spike** library, uploads
`SampleBooks/*.epub` and adds them all to a **Spike** collection, then prints
the book and file ids. Safe to re-run. Set `SAMPLE_BOOKS_DIR` to seed from
elsewhere.

On a fresh server the ids are: 1 Alice, 2 Frankenstein, 3 Moby-Dick,
4 Pride and Prejudice, 5 Sherlock Holmes (book id = file id).

## BookOrbit's web reader

Sign in at <http://localhost:3300>, then open `http://localhost:3300/read/{bookId}/{fileId}?format=epub`,
e.g. <http://localhost:3300/read/4/4?format=epub>. Opening a book there saves
progress for that file, so close the tab before comparing positions.

## Reset

```bash
cd dev/bookorbit
docker compose down
rm -rf data
docker compose up -d && ./seed.sh
```

## API schema

`SWAGGER_ENABLED` is on, so <http://localhost:3300/api/docs> works. To snapshot it:

```bash
curl -s http://localhost:3300/api/docs-json -o dev/bookorbit/openapi.local.json
```

`*.local.*` is gitignored. Never commit it (it's BookOrbit material). In
v3.6.0's published image the document lists routes and parameters, but its
request and response schemas are empty, so real shapes come from live
responses.

## Tests

```bash
cd Packages/OctavoKit
swift test                                     # stubbed tests; live tests skip

OCTAVO_BOOKORBIT_URL=http://localhost:3300 \
OCTAVO_BOOKORBIT_USER=octavo \
OCTAVO_BOOKORBIT_PASS=OctavoDev1 \
swift test --filter BookOrbitLiveTests         # against this server, seeded
```

The live tests log in, list the Spike collection, download its first EPUB,
write a progress position to it and read it back (then restore the previous
position), refresh an expired access token, and check the refresh cookie.
BookOrbit allows **5 logins per minute** per IP and the live suite uses 3. If a
run fails with HTTP 429, wait a minute.

## Troubleshooting

- **`docker compose up` fails with `denied` pulling from ghcr.io** (seen on the
  owner's Mac: every ghcr.io pull was denied, even for public images, while
  anonymous registry API calls worked; Docker Desktop has a ghcr.io login
  stored that may be stale). Try `docker logout ghcr.io`, or sign in again with
  a token that has `read:packages`. Once the image is local, `up` doesn't pull.
- **Port 3300 in use:** `BOOKORBIT_PORT=3400 docker compose up -d`, and pass the
  same URL to `seed.sh` via `OCTAVO_BOOKORBIT_URL`.
