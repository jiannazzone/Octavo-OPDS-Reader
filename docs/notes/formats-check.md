# Formats check (step 15): MOBI, AZW3 and FB2 ship

Done 2026-11-02. v1 ships MOBI, AZW3 and FB2 only if they pass a check through foliate, the bridge and the script blocking (`docs/design/direction.md`, v1 scope). This note is that check, run against the reader as it is after steps 9–14, plus what the formats spike (`formats-spike.md`, #4) said v1 needs. Everything here ran on simulator **Octavo Formats Duo** (`3E2D3D8D-1A23-4EED-9C97-6C070A1E9268`, iPhone Duo, iOS 27.1), booted with `simctl` only, and was deleted afterwards. Nothing ran in macOS WebKit this time (the spike's `harness.py`/`probe.swift` open windows on the Mac).

## Verdict

| Format | Ships? | Script tests (shipping build) | Positions | Folds |
|---|---|---|---|---|
| **AZW3** (KF8) | **Yes** | 0 scripts, 0 network | Paging 4/4, go to CFI 7/8 (one straddle), relaunch 4/4 | 15/15 spreads hold the page, 0 text on the fold |
| **MOBI** (MOBI 6, joint MOBI 6 + KF8) | **Yes** | 0 scripts, 0 network | Go to CFI 8/8, relaunch 4/4; paging 4/4 (P&P's third turn is a picture) | 15/15 spreads hold the page, 0 text on the fold |
| **FB2** (and `.fbz`) | **Yes** | 0 scripts, 0 network | Go to CFI 8/8, relaunch 4/4; paging 4/4 (P&P's third turn is a picture) | 15/15 spreads hold the page, 0 text on the fold |

Every format now has two independent layers against book scripts, each measured alone in the app (below). DRM-protected and unreadable files are refused by their bytes before anything parses them.

## What was built

All of it was decided in the formats spike (Adam, 2026-11-01); the technical calls below are Claude's.

### 1. A second script-blocking layer in the bridge (`bridge.js`, `hardenBook`)

foliate hands each section to an iframe as a `blob:` URL. The bridge now wraps every section's `load()`, before the first one loads, and gives foliate a hardened copy instead:

- **Sanitize** (never adding, removing or moving a node under `<html>`, so CFIs can't change): every `<script>` (HTML or SVG) gets an inert type and loses its source; `on*` attributes and `javascript:`/`vbscript:` URLs go (in any attribute, control characters stripped first); `iframe`, `frame`, `object`, `embed`, `applet`, `portal`, `fencedframe` lose what they'd load; SVG animations can't target `href` or a handler; meta refresh and `<base href>` are disarmed; XSLT processing instructions go.
- **A section CSP**: a `<meta http-equiv="Content-Security-Policy">` first in `<head>`: `script-src 'none'`, no frames, objects or workers, `connect-src 'none'`, everything else `'self' blob: data:` only.
- A section that isn't well-formed XML is read as HTML, as foliate's own EPUB and KF8 loaders do, rather than passed on unsanitized (they already switch such sections before the bridge sees them, so this is a backstop).
- HTML sections' `<noscript>` elements are emptied: DOMParser reads their content with scripting off, the iframe with scripting on, so markup hidden in an attribute or comment there could come back as live elements (mutation XSS). With scripting on, `<noscript>` shows nothing, so no position can be inside one. Found in this step's own review.
- Each hardened copy shares foliate's `load`/`unload` life: made on load, revoked on unload, made again from foliate's new copy next time.

The reader's own CSP (every `octavo://` response) is unchanged and stays the first layer. EPUB's `load` hook, the main-frame-only message relay and the cancelled external links stay as they were (CLAUDE.md, "Book scripts never run").

### 2. The restore guard (`goToPoint`)

After going to a saved point (opening, `goTo` with a CFI), if the visible page ends before the point, turn one page. It fixes the spike's KF8 miss (P&P chapter LV came back one page early) and the straddle the sync spike described, for every format. Fixed-layout pages have no point to miss: their CFI names the section (`fixed-layout.md`).

### 3. FB2 external links

`fb2.js` has no `isExternal`, so foliate sent every FB2 link to `link`, and a web address became an internal jump to nowhere. The bridge now reports any `link` with a URL scheme (other than foliate's own `blob:`) as `externalLink`, like the other formats; the app ignores it as it does theirs.

### 4. Refusing files by their bytes (`OctavoKit/Formats/BookFileCheck.swift`)

`BookFileCheck.check(_ url: URL) throws -> BookFileFormat` reads only the file's first 4 KB, a Kindle file's record 0 and a ZIP's central directory (at most 8 MB), all bounds-checked:

| File | Answer |
|---|---|
| ZIP with `META-INF/container.xml` | `.epub`, unless it also has `META-INF/rights.xml` (Adobe ADEPT, B&N), `sinf.xml` (Apple FairPlay) or `license.lcpl` (Readium LCP): `drmProtected`. `encryption.xml` alone (font obfuscation) is fine |
| ZIP with an `.fb2` | `.fbz` |
| ZIP of pictures only | `.cbz` |
| PalmDB `BOOKMOBI` | `.azw3` (file version 8) or `.mobi`; encryption field ≠ 0: `drmProtected`; no MOBI header: `notABook` |
| `TEXtREAd` (PalmDOC), `TPZ` (Topaz), KFX (`CONT`, DRMION) | `unsupported("PalmDOC" / "Topaz" / "KFX")`, DRMION `drmProtected` |
| `%PDF-`, RAR (CBR), 7z (CB7) | `unsupported("PDF" / "CBR" / "CB7")` |
| XML whose root is `FictionBook` (any prefix, UTF-8 or UTF-16) | `.fb2` |
| Anything else | `notABook` |

The name never counts: a `.zip` that's an EPUB is an EPUB, an `.epub` that's text isn't.

### 5. Reading an imported file's details (`Octavo/Formats/BookInspector.swift`)

`BookInspector().inspect(_ file: URL) async throws(BookInspectionError) -> BookFileDetails` runs `BookFileCheck`, then asks foliate, through a new `octavo.inspect` in the bridge, in a `WebPage` of its own that's never shown: same scheme handler, same CSP, and `makeBook` only, so no section is ever laid out or rendered. A user script starts `inspect` as the page loads and the answer comes back on its own message handler (`octavoInspect`), so Swift never waits on a call into a page a book might keep busy; the page is freed once the answer is in or the timeout passes. One parser for every format, the one the reader uses, normalizing foliate's per-format shapes (formats spike, "Metadata and covers"): title, subtitle, authors, publisher, language, published (MOBI's times become days), description (plain text through `PlainText.fromHTML`, never rendered), and the cover's bytes.

- **FB2 covers in Swift** (`OctavoKit/Formats/FB2Cover.swift`): foliate makes the cover a `data:` URL and fetches it, which the reader's `connect-src` blocks, and the CSP stays (Adam, 2026-11-01). `FB2Cover` streams the XML with `XMLParser` (external entities off), keeps only the cover's base64, and stops at 16 MB. **`.fbz` has no cover in v1**: reading it would take a ZIP inflater of our own; rare enough to leave.
- **EPUB DRM beyond its own files**: an EPUB whose `encryption.xml` lists any algorithm but the two font obfuscations foliate undoes is refused as DRM-protected (Kobo's DRM leaves no file of its own for `BookFileCheck` to see).
- Errors: `drmProtected`, `unsupported(kind:)` (`nil` when it isn't a book at all), `damaged` (foliate couldn't read it, or it has no sections), `timedOut` (no answer in 30 s; an import reads it as damaged, `ci.md`).

### 6. DEBUG switches for the checks

`-readerWithoutCSP 1` serves the reader without its CSP (the book keeps its own), `-readerWithoutHarden 1` opens books without the bridge's layer. Both exist only in DEBUG builds, so each layer can be measured alone in the real app. `docs/notes/formats-spike/tools/app-walk.py` is new (cfi-walk.js through the debug remote); `sim-check.py` and `sim-scripts.py` know the reader's IDs since #17, and `sim-check.py` reopens the book after its relaunch (nothing reopens the last book at launch any more).

## Script blocking, measured in the app

`sim-scripts.py` on the seven script-test books (`Scripts/make-script-test-books.py`, the spike's 30 vectors per Kindle/EPUB book and 27 FB2 ones; every section visited, every link clicked), against `beacon.py` on `localhost:8799`. Raw: `formats-check/runs/scripts/` (`summary.txt` has everything).

| Mode | EPUB, KF8, MOBI 6, joint MOBI | FB2, FBZ, FB2 with external entities |
|---|---|---|
| **Neither layer** (positive control) | **12 scripts ran**, 15 script beacons, 24 vectors reached the network, in each | 0 scripts; 2 remote loads (the inline image and the cover) |
| Bridge layer alone (no reader CSP) | **0** scripts, **0** network | 0 scripts; 1 remote load: the cover, which foliate's `getCover()` fetches from the reader page itself |
| Reader CSP alone | **0**, **0** | **0**, **0** |
| **Both (shipping)** | **0**, **0** | **0**, **0** |

- The control proves the vectors are live in iOS 27.1 WebKit inside the app: inline and typed scripts, a script from the book's own resources (KF8/MOBI), handlers (`img onerror`, `svg onload`, `onanimationstart`, `details ontoggle`, `video source onerror`, SVG `animate onbegin`), SVG `<script>`, `iframe srcdoc` and `javascript:` frames, `data:` documents in `iframe`/`object`/`embed`.
- The FB2 cover in the bridge-alone row isn't a book document: it's foliate's reader-page code, covered by the reader CSP, and the app reads FB2 covers in Swift anyway.
- Screenshot of the vectors section, shipping build: `formats-check/shipping-script-test-azw3.jpg`.
- **Re-run after the independent review's fixes** (templates, links, the head check, `param`, the re-parse check), on `iPhone Duo` (8C35AF6E-5F3F-48D7-A283-AEE894511947) with the bridge layer alone (`-readerWithoutCSP 1`): all seven script-test books, **0 scripts**, and no beacon request but FB2's remote cover (as above). The new vectors (`formats-check/tools/`: `link-test.epub`, `template-test.epub`, run by `probe-modes.py`): with both layers off a declarative shadow root attached and its handler ran, and a click on an SVG link navigated the frame away; with the bridge layer alone, or both, neither. Positions with the layer off and on after these fixes (`app-walk.py`, the sample book, Moby-Dick, *The Time Machine* AZW3, Alice MOBI and FB2): **136/136 identical**.

**The bridge layer doesn't move positions.** `app-walk.py` went to every section of 11 books (Alice and Frankenstein in EPUB, MOBI, AZW3 and FB2; *The Time Machine* in MOBI, AZW3, FB2) and turned two pages, once with the layer off and once on: **269/269 positions came back with the same CFI and first words** (`runs/walk/compare.txt`). A rendered section carried the layer's CSP `<meta>` in the "on" run, so it really ran.

## Positions and folds

`sim-check.py` on 12 books (Alice, Moby-Dick, Pride and Prejudice, Treasure Island; MOBI, AZW3, FB2), folded, the shipping build: open, three page turns, 12/50/88% and two turns each, back to the 50% and 12% points from 88%, and a kill and relaunch at 50%. Table: `formats-check/runs/sim-check.md`; raw: `runs/sim-check.jsonl`.

- **Relaunch 12/12** reopened on the same CFI and words, from the CFI. **Go to CFI 23/24.**
- **The one miss is the spike's**: P&P KF8 at 12% came back a page early, on a page that holds the point as its last line (`locate`: contains). Going to the same point again from 60% landed exactly. It's the straddle `sync-spike.md` describes (page breaks a line apart between saving and going back), where the restore guard rightly doesn't turn: the page does contain the point.
- **Paging 12/12 that can page.** P&P's MOBI and FB2 rows say FAIL because their third turn lands on a full-page illustration with no text, as in the spike (the CFI moved; the check wants text). Alice's first pass failed paging because the CFI walk had left it on its last page; from a fresh position it passed (`runs/sim-check-first-pass.jsonl` keeps the first pass).
- Opening, command to first page: MOBI 2.3–4.1 s, KF8 4.7–5.7 s, FB2 2.4–2.9 s (about 1 s of it the tool's polling), as in the spike. The 50 and 69 MB *Treasure Island* files included.

**Folds** (`duo-spreads/tools/fold-run.py`, Alice, Moby-Dick and P&P in each format at 50% plus two pages, then open, half, open, half, open; raw: `runs/folds/`). Folding while reading closes the book by design (step 10), so the spike's "folded back" moves no longer apply; the reader's place on closing is what relaunch checks.

| | MOBI | KF8 | FB2 |
|---|---|---|---|
| Open or half open: the spread contains the origin and its first 8 words | 15/15 | 15/15 | 15/15 |
| Spreads with text on the fold | 0 | 0 | 0 |

Two pages in all 45 states (27 open, 18 half open, book mode); left pages end at 448.3–449.0 pt and right pages start at 503.1–503.8 pt, clear of the hinge at 455.5–495.5.

## Security review

Reviewed adversarially in this step (by Claude, against the code), then by an independent reviewer of commit 48ca1ab (read-only, 2026-11-02), plus the coordinator's review of the import path. Findings, all fixed unless marked:

| | Finding | Outcome |
|---|---|---|
| Medium | A section that isn't well-formed XML was passed to the iframe unsanitized (the spike's prototype did the same) | Read as HTML and hardened, as foliate's own loaders do |
| Low | HTML `<noscript>` round trip: what the sanitizer checks (scripting off) isn't what the iframe parses (scripting on) | `<noscript>` emptied in HTML sections; the section CSP held regardless |
| Low | EPUBs with encrypted content but no store file (Kobo) opened as scrambled text | Refused as DRM-protected by the inspector |
| Low (coordinator) | After the inspector's timeout, a pending call into the page kept it, and its web process, alive | The page answers by message, started by a user script; nothing waits on it, and it's freed at once (measured: gone 0 s after the drop) |
| Low (coordinator) | A description of 10⁵–10⁶ paragraphs is quadratic in `PlainText`, on the main actor, past the timeout | Cut to 20,000 characters first (`descriptionLimit`); the coordinator fixes `PlainText` itself |
| Low, open | A web process stuck in a script outlives its page: after the drop it kept 95–100% CPU for 45 s (until the test ended), and navigating the page away first or giving it its own data store didn't end it either (measured on the simulator, host `ps`). No public API kills it | No book is known to do this to foliate. Stays until the app quits |
| Low | `BookFileCheck` wasn't on the server-download path | Fixed by the coordinator: `BookOpener` checks a file as it lands, deletes a DRM-protected one, and the book's screen says "This file is DRM-protected and cannot be opened." with Download greyed out |
| Medium (automated review, after the commit) | A `<template>`'s content isn't reached by the sanitizer's walk, and in an HTML section the iframe's parser turns `<template shadowrootmode>` into a live shadow root (declarative shadow DOM) that DOMParser never made, so a handler inside arrived unchecked (the reader CSP still blocked it) | Fixed by the coordinator: every template's content is sanitized, recursively, and its `shadowroot*` attributes removed. Measured on the simulator with a test EPUB (an HTML section, `<template shadowrootmode="open"><img onerror>`): both layers off, the shadow root attached and the handler ran; the bridge layer alone, no shadow root, no handler, nothing ran. A literal `<parsererror>` element only re-reads the section as HTML, which is hardened too |
| Info | An XHTML section without `<head>` gets no section CSP (adding a head would move every CFI) | The sanitizer and the reader CSP still apply |
| Medium (independent review) | Links foliate doesn't intercept (it catches clicks on HTML `a[href]` only): an SVG `<a xlink:href>`, an image map's `<area href>`, MathML `href`, a form's `action`. Clicked, the frame navigates itself to a `data:` page, or (EPUB) to another section as foliate built it, never hardened (the reader CSP's `frame-src` still blocks a `data:` frame) | Fixed by the coordinator: the sanitizer drops those targets unless they're fragments (and every `formaction`), and a capture-phase click handler cancels clicks on such links; both are part of the `harden` layer. Measured on the simulator (`formats-check/tools/`, `link-test.epub`): both layers off, clicking the SVG link navigated the frame away; the bridge layer alone or both, every target gone and the frame stayed |
| Low (independent review) | The section CSP `<meta>` went into the first element named `head` anywhere (another namespace, the body), where WebKit ignores it and a CFI could move; markup before `<head>` loaded before it | Only a first-child XHTML `<head>` gets it; otherwise the section keeps the sanitizer and the reader CSP |
| Low (independent review) | `<object>` can take its URL from `<param value>` | `param` values are removed (`object-src 'none'` in both CSPs too) |
| Low (independent review) | The inspector's answer had no size cap before Swift parsed it on the main actor | Capped in the page: titles 1,000 characters, 50 authors of 500, description 100,000 before Swift cuts it to 20,000 |
| — (independent review, wider fix) | Any other serializer/parser disagreement | Each hardened section is written out, read back and checked again; anything live (a script without the blocked type, a handler, a `javascript:` URL, a shadow-root template) and the section is refused |
| Info (independent review) | The bridge's "main frame only" message check isn't independent of the CSP: a script already running in a same-origin book frame could call the parent's handlers | Not counted as a layer of its own; it matters only once a script runs |
| Info | The DEBUG switches (`-readerWithoutCSP`, `-readerWithoutHarden`) are compiled out of Release; the bridge's `harden: false` option exists in Release but only Swift passes `open`'s options | Kept |
| Info | The inspector page's only channel is `octavoInspect`: main frame, `octavo://app` only, JSON parsed with type checks; it has no `octavo` handler | Kept |
| Info | `FB2Cover`: external entities off, base64 capped at 16 MB; `BookFileCheck`: every read bounded, the central directory at 8 MB | Kept |
| Info | An attribute whose value starts with `javascript:` goes wherever it is, `id` included, which would break a CFI's id assertion for that element (the index still resolves) | Accepted |

## Left open

- `.fbz` covers (above). FB2 percentages stay approximate, and the same as BookOrbit's (Adam, 2026-11-01).
- CBZ: `BookFileCheck` and the inspector recognise it (foliate reads it), but v1 doesn't offer comics; whether an import accepts a `.cbz` is the import's call.
- A file that makes foliate spin forever (none seen) keeps a web process busy after the 30 s timeout gives up on it, until the app quits (Security review). Local files the user picked only.
- Upstream fixes from the spike (`fb2.js` sizes and `isExternal`, `mobi.js`'s Blob type) are still unsent, waiting for a separate vetting session and Adam's OK.

## Re-running

```bash
U=<udid of an iPhone Duo simulator, booted with simctl>
T=docs/notes/formats-spike/tools
# Copy SampleBooks/* into the app's Documents (Scripts/fetch-sample-books.sh, Scripts/make-script-test-books.py)
xcrun simctl launch $U com.ianazzone.ereader -readerWithoutCSP 1 -readerWithoutHarden 1   # or either, or neither
SIM=$U python3 -I $T/sim-scripts.py OUT script-test.epub script-test.azw3 script-test.mobi script-test.joint.mobi script-test.fb2 script-test.fbz script-test-xxe.fb2
python3 -I $T/summarize.py OUT
SIM=$U python3 -I $T/app-walk.py WALK noharden book…; SIM=$U python3 -I $T/app-walk.py WALK harden book…; python3 -I $T/compare-walk.py WALK noharden harden
SIM=$U python3 -I $T/sim-check.py book… > results.jsonl; python3 -I $T/sim-summary.py results.jsonl
SIM=$U python3 -I docs/notes/duo-spreads/tools/fold-run.py label book.azw3 --fraction 0.5 --next 2 --moves open,half,open,half,open
```
