# Formats spike (#4): MOBI, AZW3 and FB2 through foliate-js

Done 2026-11-01. Can v1 open MOBI, AZW3 and FB2 with the reader we have: upstream foliate-js `6b11e17` (patches 0001 and 0002) in a SwiftUI `WebView`, our `bridge.js`, and the `octavo://` CSP? Checked on simulator **Octavo Formats Duo** (`218FB9DD-3116-4E47-A2B9-232BE156FC3D`, iPhone Duo, iOS 27.1) and in macOS WebKit with the same bridge and foliate files. Raw results and every tool are in `formats-spike/` (`runs/script-tests.md` has every script-test summary).

## Verdict

| Format | Go? | One line |
|---|---|---|
| **AZW3** (KF8) | **Go** | Renders, pages, restores, holds its place across folds, syncs with BookOrbit 10/10. Book scripts are blocked, but only by the CSP: the bridge's script hook never fires for it. One rare restore miss (a page early) that a two-line bridge guard fixes. |
| **MOBI** (MOBI 6) | **Go** | Same results as AZW3. Older format: no CSS, a TOC scraped from the book's own contents page, images by record number. |
| **FB2** (and `.fbz`) | **Go, with three fixes in v1** | Renders, pages, restores, folds, syncs 10/10. Smallest script surface (foliate rebuilds FB2 from an allow-list, so no script element survives). Needs: covers (our CSP blocks foliate's cover read), percentages (skewed by images, a foliate bug), external links (silently dead). |

All three need the same v1 guard that no format has today: **refuse DRM-protected Kindle files before opening them** (foliate opens them as garbage without an error). Details in "What v1 needs".

Not covered: real devices, fixed-layout KF8 (comics/manga), right-to-left and vertical books, HUFF/CDIC-compressed MOBI, KF8 embedded fonts, KFX. See "Gaps".

## Samples

`Scripts/fetch-sample-books.sh` now fetches them into `SampleBooks/` (gitignored, never committed; treat as untrusted).

- **MOBI and AZW3: Project Gutenberg's own Kindle files** for the five spike books plus *Treasure Island* (120) and *The Time Machine* (35). Gutenberg's "Kindle" link (`<id>.kf8.images`) is a **KF8-only** file, saved as `.azw3`. Its "older Kindle" link (`<id>.kindle.images`) is a **MOBI 6-only** file, saved as `.mobi`. Both are made with calibre 9.5 (`formats-spike/tools/mobi-info.py` reads the headers). None is a joint MOBI 6 + KF8 file, so the script test also builds one.
- **FB2: converted from the Gutenberg EPUBs with calibre 9.7** (`ebook-convert`, run as a local tool only; calibre is GPL and nothing of it is in the repo). Gutenberg and Standard Ebooks don't publish FB2, and no FB2 source I found could be trusted the same way. Calibre's output is also what a calibre-based OPDS server serves when a user converts a book.
- **Script-test books**: `Scripts/make-script-test-books.py`, below.

| Book | MOBI 6 | KF8 (.azw3) | FB2 |
|---|---|---|---|
| Alice | 241 KB | 256 KB | 2.0 MB |
| Frankenstein | 520 KB | 548 KB | 1.6 MB |
| Moby-Dick | 1.1 MB | 1.2 MB | 5.3 MB |
| Sherlock Holmes | 529 KB | 546 KB | 1.9 MB |
| The Time Machine | 345 KB | 363 KB | 2.1 MB |
| Pride and Prejudice (illustrated) | 26 MB | 26 MB | 37 MB |
| Treasure Island (illustrated) | 49 MB | 50 MB | 69 MB |

FB2 is bigger because images are base64 inside the XML.

## Script blocking

### How each format reaches the page

All three end up as section documents in foliate's same-origin `blob:` iframes, which must allow scripts (WebKit bug 218086). The layers from `reader-spike.md` apply differently:

| Layer | EPUB | KF8 / AZW3 | MOBI 6 | FB2 |
|---|---|---|---|---|
| 1. CSP on every `octavo://` response, inherited by the blob iframes | yes | yes | yes | yes |
| 2. foliate's `load` hook refusing script items (`bridge.js`) | yes | **no**: `mobi.js` KF8 has a `transformTarget` but fires only `data`, never `load` | **no** hook at all | **no** hook, but not needed: see below |
| 3. Message relay accepts the main frame only | yes | yes | yes | yes |
| 4. External links cancelled and reported | yes | yes | yes | **no**: `fb2.js` has no `isExternal`, so a tap on an `http:` link becomes an internal `goTo` that silently fails |

- **KF8 and MOBI 6 keep scripts.** calibre's AZW3 writer keeps `<script>` elements (checked with the 1c scripted EPUB). Its MOBI 6 writer strips them, but a hand-made or other-tool MOBI can carry any HTML. `mobi.js` puts the book's HTML into the section document as is. A KF8 `kindle:embed:`/`kindle:flow:` reference becomes a `blob:` URL, so `<script src="kindle:embed:0001?mime=text/javascript">` loads the book's own record as a script. MOBI 6 does the same with `<script mediarecindex="00001">`.
- **FB2 is rebuilt from an allow-list** (`fb2.js` `FB2Converter`). Unknown elements, in any namespace, are dropped. The only attributes carried over are `id`, an image's `alt` and `title`, and table `colspan`, `rowspan`, `align` and `valign`, all set as values, never as markup. Two attacker-chosen values do get through as attributes: link `href` (`javascript:`, remote URLs) and image `src` (remote URLs).

### The test books

`Scripts/make-script-test-books.py` writes one book per format with the same 30 vectors. MOBI/KF8 are made by converting a placeholder EPUB with calibre (uncompressed), then swapping each placeholder for its payload **byte for byte**, so every offset and index in the file stays valid. The book's one image record is replaced with JavaScript for the resource-script vector.

- **Scripts (18):** inline `<script>` (two types), `img onerror`, `svg onload`, SVG `<script>`, SVG `<animate onbegin>`, `details ontoggle`, `onanimationstart`, `input autofocus onfocus`, `video <source onerror>`, `iframe srcdoc`, `iframe src=javascript:`, `iframe`/`object`/`embed` with `data:` documents, a `javascript:` link, a `javascript:` meta refresh, and a script loaded from the book's own resources (MOBI/KF8). The EPUB control has a manifest `.js` there instead, plus a `<head>` script.
- **Network without script (12):** remote `<img>`, stylesheet, `@import`, CSS background, `@font-face`, `<audio>`, video poster, SVG `<use>`, prefetch, `<base href>`, meta refresh to a remote URL, and an external link.
- **FB2 (27):** what FB2 can express: `<script>` at the root, in the body, in the annotation and in a notes body, in the FB2, XHTML or prefixed namespace; XHTML `img`/`iframe`; inline SVG; `javascript:` and remote link hrefs; attribute injection through `href`, `alt` and `id`; `on*` attributes on allowed elements; CDATA and comments holding markup; images from a remote URL, from `javascript:`/`data:text/html`, and from scripted SVG and HTML binaries; a remote cover; `<stylesheet>`/`xml-stylesheet` imports. Also a `.fbz` copy, and **`script-test-xxe.fb2`** with external entities (the beacon and `file:///etc/hosts`).

A script that runs marks its document (`data-ran-<vector>`), the top page (`top.__bookScriptRan`), posts to the app's `octavo` handler, and requests the beacon (`formats-spike/tools/beacon.py`, `http://localhost:8799`). Every beacon request is a failure.

### Results

**Positive control first.** Without a CSP, in macOS WebKit with the real `bridge.js` and foliate files (`tools/harness.py` + `tools/probe.swift`), the payloads are live:

| Book (no CSP) | Scripts that ran | Vectors that reached the beacon |
|---|---|---|
| script-test.azw3, .mobi, .joint.mobi | **16** each, the resource-script among them | **25** each |
| script-test.epub | **16** (the manifest `.js` was refused by the `load` hook, the `<head>` script ran) | **25** |
| script-test.fb2, .fbz | 0 | 2: the remote image, and the remote cover once `getCover()` is called |
| script-test-xxe.fb2 | 0 | the same 2; no entity fetched, both external entities expand to nothing |

Vectors that did nothing even without a CSP: the `javascript:` meta refresh (WebKit ignores it), both links (foliate cancels every link click; the bridge reports `externalLink`), prefetch and SVG `<use>`.

**Then with the app's CSP**:

| Where | Books | Payload elements in the rendered sections | Scripts that ran | Beacon requests |
|---|---|---|---|---|
| macOS WebKit, app policy (`harness.py csp`) | all 7 | all present (e.g. KF8: 4 `<script>`, 1 SVG script, 7 handlers, 3 iframes, 2 object/embed, `<base>`, 8 remote refs) | **0** | **0** |
| **The app on the simulator** (`tools/sim-scripts.py`, `octavo://` scheme, iOS 27.1 WebKit) | all 7 | identical counts | **0** | **0** |

- In the app, every link was clicked; MOBI, KF8 and EPUB logged `Ignored external link` for both the `javascript:` and the `http:` link. FB2 logged nothing (no `isExternal`, above).
- The simulator could reach the beacon (Mobile Safari's request arrived), so the zero is real.
- Screenshots: `formats-spike/screenshots/`.

**Conclusion:** for MOBI, KF8 and FB2 the CSP alone carries script blocking, and it holds against every vector here. FB2's converter is a strong second layer of its own; MOBI and KF8 have none.

### A second layer for every format (prototype, not shipped)

You asked for belts and suspenders. `formats-spike/tools/harden.js` is a prototype for `bridge.js` to apply between `view.open()` and the first page. It wraps each section's `load()` and, before foliate puts the document in an iframe:

1. **sanitizes** it: every `<script>` (HTML or SVG) gets an inert `type` and loses `src`; `on*` attributes and `javascript:`/`vbscript:` URLs are removed; iframes, objects and embeds lose what they would load; meta refresh and `<base href>` are disarmed. **It never adds, removes or moves a node in the body**, so CFIs can't change;
2. **adds a `Content-Security-Policy` `<meta>`** first in `<head>`: no scripts, no frames, no objects, nothing remote. Only `<head>` changes, and CFIs go through `<body>`.

Measured with the CSP **switched off**, so the prototype stands alone:

| Mode | Scripts that ran (EPUB, KF8, MOBI, joint, FB2) | Beacon |
|---|---|---|
| sanitize only | 0 | the 7 remote-load vectors (not its job) |
| meta CSP only | 0 | meta refresh to a remote URL only |
| both | 0 | **0**, except FB2's remote cover, which foliate's `getCover()` fetches from the reader page, where the app's CSP blocks it |
| both + the app's CSP | 0 | 0 |

**CFIs don't change.** `tools/cfi-walk.js` went to every section of 26 books (the 21 samples plus 5 EPUBs; every third section for *Treasure Island* FB2) and turned two pages, once with the app's CSP alone and once with the prototype added: **1043/1043 positions came back with the same CFI and the same first words** (`runs/harden-cfi-walk.txt`). The prototype handled every section it loaded.

**Recommendation:** add both parts to the bridge in v1 (the #5 session owns `bridge.js`; this spike didn't touch it). That gives every format a second, independent layer, and means a lost or weakened CSP no longer runs book scripts. It costs a parse and serialize per section on load (not measured on device). Keep the CSP as it is.

## Rendering and positions

Each of the 21 real samples (7 books × MOBI/KF8/FB2) went through `tools/sim-check.py` on the simulator, folded (from the second book on, in foliate's own single-column layout; see "Observed, not mine" under Gaps):

1. open;
2. three page turns, each must move;
3. 12%, 50% and 88% plus two page turns (the sync spike's positions), recording the point CFI the app saves;
4. from 88%, go back to the 50% and 12% CFIs: the same page must come back;
5. at 50%, kill the app and launch it: it must reopen on the same CFI and words.

Results (full table in `formats-spike/runs/sim-check.md`, raw in `runs/sim-check.jsonl`):

- **Paging: 21/21.** The P&P MOBI and FB2 rows first looked like failures. They are full-page illustrations with no text, and I checked that each page holds the image.
- **Go to CFI: 41/42 exact.** The miss is P&P KF8 at 12%. The app came back one page early, and that page *contains* the point (bridge `locate`: `contains: true`): the point's line is its last line. The page breaks had shifted by one line between recording and going back. Nothing in it is specific to KF8; it is the same straddle `sync-spike.md` describes.
- **Relaunch: 21/21** reopened on the same CFI and words, all restored from the CFI.
- **Point round trip in the harness** (`tools/point-roundtrip.js`, macOS WebKit, app CSP): for every section, turn three pages, note the page, leave, and come back by its point CFI. MOBI **99/99**, FB2 **82/82**, KF8 **132/133**, EPUB 64/67 (EPUB's misses are Frankenstein's text-free pages). On section-opening pages of P&P: KF8 76/76, MOBI 85/85, FB2 9/9 (`runs/point-roundtrip.jsonl`).
- **The KF8 miss is real and KF8-only.** P&P chapter LV ("A FEW days after this visit", illustrated initial): from that page's own point CFI, KF8 comes back **one page early**, by range CFI too, while EPUB, MOBI and FB2 of the same book come back exactly (`tools/restore-guard.js`). The page that comes back ends before the point, so it doesn't even contain it (unlike the simulator's 12% straddle above). **A two-line guard fixes it:** after going to a saved point, if the visible page ends before the point (`CFI.compare(CFI.collapse(page, true), point) < 0`), turn one page. With the guard, KF8 lands on the exact page. BookOrbit-style points (walk into the first text node) are no cure: at P&P's KF8 chapter openings they round-trip 74/76 against 76/76 for ours.
- **CFIs look like EPUB's**: `epubcfi(/6/N!/4/…)`, with N counted over foliate's sections. KF8 keeps the source EPUB's ids (`[pgepubid00004]`). MOBI 6 sections are cut at `<mbp:pagebreak>`, and `mobi.js` inserts `<a id="filepos…">` anchors, which can be a page's start point (`/6/24!/4/2[filepos0000114103]`). Both are deterministic, so the same file gives the same CFIs on every device.
- **Joint MOBI 6 + KF8 files** (what Amazon's tools make): foliate reads the KF8 part. Alice converted by calibre both ways gave 19/19 identical CFIs and first words for the joint `.mobi` and the KF8-only `.azw3` (harness, `cfi-walk.js`). CFIs belong to a file's bytes, though: the same book converted by another tool or version can differ, which is fine for sync because every device opens the server's copy.
- **KF8 parses every section as XHTML** in all samples (every section of the 7 KF8 books checked). `mobi.js` would switch the rest of the book to HTML parsing after the first section that isn't valid XHTML, which would make CFIs depend on the order sections were loaded. Not seen; noted as a risk below.
- Open time on the simulator, from the command to the first page: MOBI 1.6–2.0 s, KF8 4.3–6.8 s, FB2 2.5–3.6 s, including about 1 s of polling. Even the 69 MB *Treasure Island* FB2 opened in about 3 s. In macOS WebKit all of them open in under 1 s.

### Folds

`docs/notes/duo-spreads/tools/fold-run.py` (spike 2b's check) on Alice, Moby-Dick and P&P in all three formats: open at 50% plus two pages, folded, then the hinge goes open, close, half, close, open, half, open, close. Table: `runs/folds.md`, raw: `runs/folds.jsonl`.

| | MOBI | KF8 | FB2 |
|---|---|---|---|
| Folded back: the exact origin CFI | 9/9 | 9/9 | 9/9 |
| Open or half open: the spread contains the origin (foliate's CFI order) and its first 8 words | 15/15 | 15/15 | 15/15 |
| Spreads with text on the fold | 0 | 0 | 0 |

One page folded, two pages open and half open, as for EPUB. (The `origin` rows show `contains: false` for some books: `locate` compares an element-level point against the page's text-level start. They're exact CFI matches, which is the check that matters there.)

## BookOrbit

**BookOrbit's web reader opens all three.** It runs the same `mobi.js`/`fb2.js` (identical at `6b11e17`) and splits each book into the same sections (*The Time Machine*: MOBI 24, KF8 23, FB2 20 on both sides).

**Uploaded** to the local server (v3.6.0) as `octavo`, into a new library **Formats** (id 2, folder `/books/formats`), so the seeded Spike library and collection are untouched:

| File | BookOrbit book / file | Note |
|---|---|---|
| `the-time-machine.mobi` | book 6 / file 6 | stored as `The Time Machine (2004).mobi` |
| `the-time-machine.azw3` | book 6 / file 7 | grouped with the MOBI into one book |
| `the-time-machine.fb2` | book 7 / file 8 | a separate book (calibre's FB2 lost the date) |

The served files are byte-identical to the uploads (SHA-256).

**Round trip**, using the `sync-spike.md` method. BookOrbit's reader ran at 375×812 on its own cookie host (`formats4.localhost:3300`); the app ran on the simulator, opening the same bytes. Five positions per format and direction: 12%, 50%, 88% (+2 pages), and 30%/40%, 70% (+3 pages) for mid-chapter starts.

- **Web → app**: the web reader's CFI, confirmed as what the server stores, opened in the app with `goto`.
- **App → web**: the app's point CFI posted to `books/files/{id}/progress` exactly as `BookOrbitClient.saveProgress` sends it; then the web reader was reloaded.

| Format | Web → app | App → web |
|---|---|---|
| MOBI | 5/5 (one straddle) | 5/5 |
| KF8 | 5/5 | 5/5 |
| FB2 | 5/5 | 5/5 |

Rows: `runs/w2a-sources.tsv`, `runs/w2a.tsv`, `runs/a2w.tsv`. As with EPUB, the strings differ where a page starts at an element (the app pushes `/6/12!/4/10`; BookOrbit walks into the first text node), and both open the same page.

Two BookOrbit observations:

- **BookOrbit's web reader saves the start position on a book's first open.** For all three files, the first open (no stored progress yet) wrote a CFI at the cover page. Reopening with a stored position wrote nothing, as `sync-spike.md` saw for EPUB. So merely opening a new book on the web gives the server a CFI at the start, timestamped then. If the device holds an unpushed position from before that moment (read offline, say), the opening rule's "later timestamp wins" picks the server's start, and the app reopens at the cover. That applies to every format; worth a look when sync is built for v1.
- **FB2 percentages are off by the cover.** On *The Time Machine*, the first page shows **29%** in BookOrbit and in Octavo alike; on Alice, **31%**, so "go to 30%" shows the cover (foliate bug below). Both sides agree, so CFI sync is unaffected. But a percentage-only backend (kosync), or BookOrbit's list percentages, will disagree with other readers for illustrated FB2s.

## Metadata and covers

Through foliate (`collect.js` → `view.book.metadata`, `getCover()`), in the app's CSP:

| | MOBI 6 / KF8 | FB2 |
|---|---|---|
| Title, author | yes (EXTH) | yes |
| Shapes | `author`: array of strings; `language`: **array** (`["en"]`); `published`: ISO date | `author`: array of `{name, sortAs}`; `language`: string; `published`: empty from calibre's FB2 (the year is in `publish-info`, which foliate doesn't read) |
| Description | EXTH text, may contain HTML | **HTML** built from the annotation (scripts stripped, but `<a href="javascript:…">` kept) |
| TOC | MOBI 6: scraped from the book's contents page (Alice 16 items); KF8: NCX (16) | one entry per top-level section (Alice 15) |
| Cover | yes: same bytes as the EPUB's cover, **no MIME type** on the blob | **fails**: `fetch(data:…)` is blocked by our `connect-src`. Without a CSP the same call returns the JPEG |

## Foliate bugs found (not patched; patches described)

1. **`fb2.js` section sizes count image data**, so percentages jump over illustrated sections. It means to subtract each image's `src` length, but misses it twice:
   - the serialized section escapes every newline in the base64 as `&#10;` (4 extra bytes per line). calibre wraps base64 at 76 characters, so *The Time Machine*'s cover section comes to 87,425 of the book's 304,516 "bytes" (29%) for about 300 bytes of markup;
   - an image that is a direct child of `<body>` (common in FB2s from other tools) is never subtracted at all, because the subtraction only looks *inside* each top-level element. A synthetic book with a 400 KB cover there reads 77% on its first page; the same image inside a `<section>`, on one line, reads 0.2% (`tools/make-fb2-size-test.py` + `tools/section-sizes.js` in the harness).

   Patch: strip whitespace from `<binary>` text in `getImageSrc` (smaller data URLs too), and count the element itself in the subtraction, or measure text length instead. Changing sizes changes percentages, so BookOrbit's (unpatched) numbers would then differ from ours. Worth offering upstream.
2. **`fb2.js` has no `isExternal`.** External links aren't reported, so the bridge can't offer "open in Safari". Fix in the bridge instead of a patch: handle foliate's `link` event and treat any href with a URL scheme as external.
3. **`mobi.js` never checks the encryption field.** A DRM-marked MOBI (`tools/make-drm-sim.py`: Frankenstein with encryption type 2 and scrambled text) opens with no error: one section, the right title, no readable text. Fix natively before opening (below), not in foliate.
4. **`mobi.js` KF8 resources are typeless blobs.** `new Blob([data], { newType })` uses the wrong option name. JPEG, PNG and CSS still work (WebKit sniffs or doesn't care); SVG images weren't tested. A one-word upstream fix.

## What v1 needs

**#12 first run / supported formats:** accept `.mobi`, `.azw3`, `.azw`, `.fb2`, `.fbz`. `ReaderBook.supportedExtensions` already lists them. Recognize `.fb2.zip` too: today its extension is `zip`, so it's never listed. Save it as `.fbz`, or sniff.

**#10 downloads:**

- **DRM check before opening any Kindle file.** Bytes 60–67 of the file are `BOOKMOBI`; the big-endian 16-bit field at offset 12 of record 0 is the encryption type (0 = none). Show "This book is DRM-protected" instead of opening. ~20 lines of Swift; `formats-spike/tools/mobi-info.py` shows the layout.
- KFX, Topaz (`.azw1`, `.tpz`) and PalmDOC (`TEXtREAd`) don't open in foliate. Reject them with a clear message.
- Map OPDS types to extensions we list: any Kindle type (`application/x-mobipocket-ebook`, `application/x-mobi8-ebook`, `application/vnd.amazon.ebook`) → `.mobi` or `.azw3` (foliate tells MOBI 6 from KF8 by the file itself, so either works), `application/x-fictionbook+xml` → `.fb2`, `application/x-zip-compressed-fb2` → `.fbz`.

**#13 library / book detail:**

- Normalize foliate's metadata shapes (above), or read metadata natively.
- Covers: for FB2, either allow `data:` in `connect-src` (low risk: no network), or decode the `<binary>` natively. For MOBI/KF8, sniff the image type.
- **Render descriptions as plain text, never as HTML** (they carry book-controlled markup).

**Reader (`bridge.js`, #5's area; described, not changed here):**

1. Add the `harden.js` layer (sanitizer + section CSP).
2. Add the restore guard (`restore` and `goTo` in the bridge: if the page ends before the point, turn one page). It's format-independent and cheap.
3. Report FB2 external links (`link` event).
4. Fix the FB2 percentage, either with the upstream-able `fb2.js` patch or by deciding that percentages for FB2 are approximate.

**Change made in this spike:** `ReaderSchemeHandler` serves `.fbz` as `application/x-zip-compressed-fb2`, foliate's own FBZ type, so a zipped FB2 is recognized by type as well as by name. Book MIME types are now pinned in `ReaderSchemeHandlerTests`. 47/47 app tests pass.

## Gaps and risks

- **Not tested:** real devices; fixed-layout KF8 (comics, manga); RTL and vertical text; HUFF/CDIC compression (commercial MOBI); KF8 embedded fonts (obfuscated `FONT` records, which `mobi.js` decodes); SVG in KF8; memory with the 50–70 MB books on a device.
- **KF8 XHTML→HTML fallback** (above): it could make CFIs depend on load order. If a book triggers it, foliate parses later sections differently from what BookOrbit parsed. Not seen in 7 books.
- **MOBI 6 has no CSS.** foliate adds only a blockquote rule, so typography is the reader's defaults. Fine, but it looks plainer than the KF8 of the same book.
- **FB2 images inside paragraphs aren't centred** (calibre puts `<image>` in a `<p>`; foliate centres only top-level ones). Cosmetic. Parked, not a UI decision here.
- **Observed, not mine:** after a cold relaunch straight into the reader, the hinge and geometry were never reported (`posture: noHinge`, `geometry: null`, `cols auto`), until the next hinge move. 20 of the 21 `sim-check` books therefore ran with foliate's own single column instead of the closed-Duo layout. That doesn't affect the position checks; the fold runs set the hinge first. Passed to the #5/#6 sessions.

## Re-running

```bash
Scripts/fetch-sample-books.sh                         # samples (+ FB2 via calibre)
python3 -I Scripts/make-script-test-books.py          # script-test books
T=docs/notes/formats-spike/tools
$T/run-harness.sh /tmp/h && python3 -I $T/summarize.py /tmp/h        # macOS WebKit, no CSP vs app CSP
MODES="nocsp+sanitize nocsp+meta nocsp+sanitize+meta" $T/run-harness.sh /tmp/h2   # harden.js prototype
# Simulator (copy SampleBooks/*.* into the app's Documents first; see reader-spike.md)
SIM=<udid> python3 -I $T/sim-scripts.py /tmp/app script-test.epub script-test.azw3 script-test.mobi script-test.fb2
SIM=<udid> python3 -I $T/sim-check.py alice-in-wonderland.azw3 … > runs/sim-check.jsonl
SIM=<udid> python3 -I docs/notes/duo-spreads/tools/fold-run.py label book.azw3 --fraction 0.5 --next 2
SIM=<udid> python3 -I $T/w2a.py $T/../runs/w2a-sources.tsv the-time-machine
```

`tools/bo.sh` keeps its own BookOrbit token file (`$TMPDIR/octavo-formats-spike-bo-tokens.json`, outside the repo), so it never rotates another session's refresh token.
