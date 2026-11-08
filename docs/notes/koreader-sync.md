# KOReader sync: measured, not built

**Dropped from the first release (Adam, 2026-11-06).** It helps only people with a KOReader device and identical book files, a wrong place is the worst thing an e-reader can do, and real KOReader hadn't yet been tested against what Octavo would send (it has since: "On real KOReader", below). OPDS and Files books keep their place on the iPhone. No app code was written.

This note keeps what was measured, so nobody has to measure it again.

## After launch, if it comes back

One KOReader account in Settings (address, username, password), for OPDS and Files books. No per-server settings. BookOrbit keeps its own sync, and Kavita and Komga stay plain OPDS catalogs.

The steps are in `docs/notes/koreader-sync-plan.md`. The first, a test on real KOReader, passed on 2026-11-08 ("On real KOReader", below).

The account form would also fit Kavita's and Komga's built-in sync, since it's how KOReader itself connects to them. That's untested from Octavo, and Kavita's address carries a key.

## Which server does what

Signed in, against `dev/opds` and a local `koreader/kosync`. Calibre-Web and COPS have no endpoint: 404 on every path tried, and nothing in their source.

| | Kavita 0.9.1 | Komga 1.29.2 | Standalone `koreader/kosync` |
|---|---|---|---|
| Address | `/api/koreader/{apiKey}` | `/koreader` | `/` (plain on 17200, self-signed on 7200) |
| Sign-in | The key in the path; headers ignored | API key in `x-auth-user`; `x-auth-key` ignored; email gives 403. Needs role `KOREADER_SYNC` | `x-auth-user`, and `x-auth-key` = lowercase MD5 hex of the password. Registration is off unless `ENABLE_USER_REGISTRATION` is set |
| Unknown file | 400 "File was not found in book" | 404 "Book not found". Every book, if the library's `hashKoreader` is off (the default) | 200 `{}` |
| Never-read book | 200, percentage 0, `/body/DocFragment[1].0`, `timestamp` -62135596800 | 200, only `{timestamp (ISO string), status, error, message, path}` | 200 `{}` |
| What it keeps | `/body/DocFragment[n]/...elements.0`, no text offset. Percentage rebuilt as section number / section count | `/body/DocFragment[n].0`, the file section only. No `timestamp` on read | Everything, as sent. `timestamp` in seconds |
| Empty `progress` | 200, changes nothing | 400 | Stored |
| A CFI as `progress` | 200, moves the place to the book's start and leaves junk | 400 | Stored |
| No `device_id` | Accepted | 400 | Accepted |
| `Accept` header | Not needed | Not needed | Required (412) |

Ignore PUT response bodies; only status 200 counts. Their `timestamp` is an ISO string on Kavita, absent on Komga and a number on the standalone server.

`sync.koreader.rocks`, KOReader's default, timed out on `/healthcheck` from here.

## Matching a book

KOReader's default ("Binary") names a book by an MD5 over 1 KiB samples: at offset 0, then at 1024 × 4^i for i = 0 to 10, stopping at the first empty read. This matched Kavita's stored hash on all five sample books (Kavita stores it uppercase and accepts either case). An offset of 256 for the first sample doesn't match.

Komga, Kavita, Calibre-Web and COPS all download Alice with the hash of the file on disk. A copy that calibre converted or edited for the e-reader won't match, and nothing can tell you so. Sync needs the book's bytes, so a book that isn't downloaded has no place to fetch. Range requests would help on Calibre-Web and COPS (206); Komga ignores them.

## Why a percentage isn't enough

`CLAUDE.md` first planned percentage-only sync. It can't work:

- KOReader moves a reflowable book only by `progress`, as an xpointer. Its sync code has no percentage fallback.
- A bad place sends KOReader to page 1 (measured below).
- Kavita's percentage is up to 20 points from foliate's at a section start: Pride and Prejudice 19.9, Frankenstein 14.2, Sherlock 12.5, Alice 11.9, Moby-Dick 10.3.
- The largest file section in the sample books is 9–19% of the book, so a Komga place can land far behind. Moby-Dick has 13 sections, not one per chapter.

So Octavo would have to write and read `/body/DocFragment[n]/...` in `bridge.js`. Since DOM version 20240114, crengine makes a `DocFragment` for every spine item. BookOrbit's server converts between the two formats, so it's doable. Don't copy theirs or KOReader's (AGPL).

## On real KOReader (2026-11-08)

KOReader v2026.07.1's release build (`koreader-linux-arm64`), headless in a throwaway Linux container, on the five sample books at its emulator's 600 × 800 with default settings. `koreader-sync/tools/run.sh` re-runs all of it: `xpointer_check.py` builds places from each book's XHTML as a browser's XML parser sees it, and `places.lua` asks KOReader where they land (it calls KOReader's Lua API; nothing of KOReader is copied).

- **Its document hash is ours:** `util.partialMD5` gave `59feb863…` for Alice, as computed here and as Kavita stores it.
- **A bad place goes to page 1.** An empty string, a garbage string, a CFI, Kavita's junk (`/body/DocFragment[1]/body/epubcfi(...).0`) and a section past the end all land on page 1. So never send a place that might not resolve.
- **Octavo's places land on the same words** (30 per book, at word starts, spread over the book):

| | Alice | Frankenstein | Moby-Dick | Pride and Prejudice | Sherlock |
|---|---|---|---|---|---|
| Word level (`…/p[9]/text()[2].212`) | 30/30 | 30/30 | 30/30 | 29/30 | 30/30 |
| Paragraph level (`…/p[9].0`) | 30/30 | 30/30 | 30/30 | 30/30 | 30/30 |
| KOReader's own places, read in the DOM (every third page) | 53/55 | 129/130 | 366/376 | 229/230 | 226/230 |

  The one word-level miss is only a space where a chapter heading meets its text, not a different place. KOReader resolved all 300 places. The misses reading KOReader's places are the cover (an `svg`, which has no words to compare), whitespace inside `<pre>` (poems keep their spacing, and the rule below doesn't cover it), and three page tops in Sherlock where KOReader's offset lands on a different sentence of the same paragraph.
- **How crengine counts**, as measured:
  - **Elements:** the name, with `[n]` only where siblings share it: `div/p[9]`, not `div[1]/p[9]`. `[1]` is accepted too, and DOM version 20260812 (after this release) always writes it, so read both.
  - **Text nodes:** `text()`, with `[n]` when there's more than one. A blank text node counts only inside a paragraph's own text, after something in it, never between blocks. The line break before a drop cap (`<p>\n<span>W</span>hen…`, Sherlock Holmes) or leading italics (Moby-Dick) doesn't count (found 2026-11-08 through the bridge, below). A node of only no-break spaces does: it's text, not whitespace (measured on a test book, before a drop cap and between two inline elements).
  - **Offsets:** characters after collapsing whitespace. Each run of spaces, tabs and line breaks counts as one, at the start of the node too. A no-break space (U+00A0) is a character, not whitespace. Moby-Dick's XHTML has line breaks and indentation inside paragraphs, which is what showed this.
  - **No offset at all:** KOReader writes some element places without one (`…/div[6]/span`). Read an offset as optional.
  - **The browser's offsets** are UTF-16 code units, crengine's are characters. Convert where a book has characters outside the BMP.
- **KOReader's percentage is close to foliate's:** at the same words, a median gap of 0.2–0.9 points per book, 2.0 at the 90th percentile. It's farther only where pictures take whole pages: 16 points in Pride and Prejudice's illustrated front matter. Good enough for a place line, never for landing.

Not covered: Adam's modern EPUBs (calibre conversions, Kobo's `koboSpan`s, books from stores), a KOReader newer than v2026.07.1, other screen sizes and fonts, and KOReader's own sync menu (only the engine was driven).

### Octavo's bridge against it (2026-11-08)

`bridge.js` builds and reads these places (`xpointerOf`, `resolveXPointer`, `xpointerAt`; chunk 2 of the plan). `koreader-sync/tools/bridge-check.sh` opens each sample book in Octavo's reader on a simulator through the debug remote. KOReader then reads 30 places the bridge would send, and the bridge reads every third page of KOReader's own.

- **Octavo → KOReader:** 149/150 land on the words the bridge names, and none was refused. The one is a table whose cells KOReader joins with a space.
- **KOReader → Octavo:** 1,016/1,021 resolve to the same words (Alice 54/55, Frankenstein 129/130, Moby-Dick 375/376, Pride and Prejudice 229/230, Sherlock 229/230), after the drop-cap rule above (it was 1,012). The five left are each book's cover (`…/div/svg.0`), which resolves to the cover and only shows as a miss because a picture has no words to compare. The bridge also handles `<pre>`, which the Python model doesn't.
- **Where KOReader's DOM may differ** (a table, an SVG, MathML), Octavo sends the whole element. A table without `<tbody>` is one: the browser's XML parser adds none.

## What would go wrong as first designed

From an adversarial review of the design, against the code. `OpeningPosition.choose` trusts the server to be at least as new as the iPhone, which holds for BookOrbit and not here.

- **First sync after opting in:** a months-old server place opens and saves over a further-along local one. The first pull should only record what the server says.
- **Backward moves:** Octavo follows them silently. KOReader ignores them by default. A place behind yours shouldn't move you on open; the capsule can offer it.
- **Failed pull, then a page turn:** the push overwrites another device's place. Send nothing for a book until a pull has succeeded this session.
- **Servers that rewrite your place:** Kavita and Komga read back something else, so your own place looks like another device's. Read back after each push, and keep that.
- **"Synced just now" with nothing shared:** an empty pull counts as a sync (`BookPlaces.status`), and places from before opting in never go (`needsPush`).
- **KOReader's own settings:** auto sync is off by default, and forward moves prompt, so a device may do nothing until set up.
- **The account:** `KeychainSweep` deletes anything that isn't a saved server's, and unsent places aren't keyed by account. Both need the network-trust review.
- **Two copies now share one place,** against decision 36: the same file on two catalogs has one hash.
- **The capsule** names the book's server and falls back to the word "BookOrbit" (`ReaderView`), and prefers the server's percentage (`ReaderModel.checkServerPlace`).

The comments in `ReadingPosition.swift` and `ProgressSync.swift` still call kosync a percentage-only writer. Correct them with the feature.

## Sources

- [kosync-conformance](https://github.com/pid1/kosync-conformance): the protocol as observed, written up as a spec
- [koreader-sync-server](https://github.com/koreader/koreader-sync-server) (AGPL-3.0; image `koreader/kosync`)
- [Komga's KOReader guide](https://komga.org/docs/guides/koreader), [Kavita's KOReader guide](https://wiki.kavitareader.com/guides/3rdparty/koreader/)
- [Readest's sync docs](https://readest.com/docs/sync): how another app presents it
