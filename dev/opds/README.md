# Local OPDS servers (dev only)

Four throwaway OPDS catalogs for developing and testing Octavo's OPDS source
(#8). Each runs its project's published Docker image; no code from them is
vendored here. Calibre-Web, COPS and Kavita are GPL-3.0 and Komga is MIT:
run their images, never copy their code into the repo (see `CLAUDE.md`).

| Server | Image (pinned) | Catalog | Sign-in |
|---|---|---|---|
| Calibre-Web 0.6.27 | `lscr.io/linuxserver/calibre-web:0.6.27-ls408` | <http://localhost:3310/opds> (OPDS 1.2) | HTTP Basic: `octavo` / `OctavoDev1` |
| COPS 4.6.1 | `lscr.io/linuxserver/cops:4.6.1-ls17` | <http://localhost:3320/feed> (OPDS 1.2) | none |
| Komga 1.29.2 | `gotson/komga:1.29.2` | <http://localhost:3330/opds/v1.2/catalog> (OPDS 1.2), <http://localhost:3330/opds/v2/catalog> (OPDS 2.0) | HTTP Basic with the email: `octavo@example.com` / `OctavoDev1`; OPDS 2 answers 401 with an Authentication Document |
| Kavita 0.9.1.4 | `jvmilazz0/kavita:0.9.1` | `http://localhost:3340/api/opds/{apiKey}` (OPDS 1.2) | the API key in the path; web login `octavo` / `OctavoDev1` |

- Every port is bound to 127.0.0.1 and can be moved with `CALIBRE_WEB_PORT`,
  `COPS_PORT`, `KOMGA_PORT`, `KAVITA_PORT` (pass the same to `seed.sh`). The
  iOS Simulator reaches them at the same addresses. The tags can be moved with
  `CALIBRE_WEB_TAG` and so on.
- All passwords are dev-only placeholders. Calibre-Web's password policy is
  left on; the seed sets the hash directly.
- State lives in `data/` (gitignored): each server's config, the calibre
  library and the Komga and Kavita book folders.

## Start and seed

```bash
Scripts/fetch-sample-books.sh   # once: EPUBs, Kindle files and FB2 → SampleBooks/
cd dev/opds
docker compose up -d
./seed.sh
```

`seed.sh` needs curl, jq and calibre (for `calibredb`; set `CALIBREDB` if it
isn't on the path). It is safe to run again. It:

- builds a calibre library in `data/calibre-library` that **Calibre-Web and
  COPS both serve** (COPS read-only): the five spike EPUBs, Alice and
  Frankenstein also as AZW3 and MOBI, Sherlock Holmes also as FB2, and The
  Time Machine as AZW3, MOBI and FB2 with no EPUB. calibre runs with a
  throwaway config, so your own calibre plugins don't touch the files.
- signs Calibre-Web's first-run admin in as the dev account and points it at
  the library (Calibre-Web has no setup API).
- claims Komga, registers Kavita's first user, and creates a **Spike**
  library on each over one folder per book (`data/komga-books`,
  `data/kavita-books`), which Komga and Kavita list as one series each.
- prints the four catalog addresses, Kavita's with its API key.

Kavita's API key changes with every fresh `data/`. The app's debug rows and
the live tests ask Kavita's REST login for it (`POST api/Account/login`
returns `apiKey`), the same key Kavita's settings page shows.

## What each one shows

Measured 2026-11-01, for the chip and Home rules (`OPDSCatalogHints`):

- **Calibre-Web:** 15 root entries with no `rel`; no `sort/new` link
  (Recently added is the `/opds/new` entry); search template in the root.
  Sends AZW3 and MOBI as the same `application/x-mobipocket-ebook` and plain
  FB2 as `application/fb2+zip`, so the link's title decides the format.
- **COPS:** 5 entries with `thr:count`, `sort/new` on Recent additions,
  OpenSearch description. Its OPDS 2 endpoint (`/opds`) answers 500 in this
  image.
- **Komga:** 9 entries (Keep Reading first); OpenSearch searches series.
  OPDS 2 root: Browse plus three groups.
- **Kavita:** 7 entries (On Deck first); Recently Added lists series, not
  books; titles carry a read-state glyph ("⭘ ") that Octavo strips.

## In the app

DEBUG builds: Settings → Debug server → "Connect local Calibre-Web" (and
COPS, Komga, Komga OPDS 2, Kavita), or launch with
`-connectOPDS calibreWeb|cops|komga|komga2|kavita`. Passwords stay in memory.

## Tests

```bash
cd Packages/OctavoKit
swift test                                            # stubbed tests; live tests skip
OCTAVO_OPDS_LIVE=1 swift test --filter OPDSLiveTests  # against these servers, seeded
```

The live tests read only: root chips, start chip and Home's list, a walk to
Alice, her cover and EPUB download, details, search, and the sign-in check
(with and without the account) on all five catalogs. `OCTAVO_OPDS_<NAME>_URL`
(`CALIBRE_WEB`, `COPS`, `KOMGA`, `KAVITA`) moves a server.

## Reset

```bash
cd dev/opds
docker compose down
rm -rf data
docker compose up -d && ./seed.sh
```
