# BookOrbit's foliate-js and the CFI risk

Research for spike task 1a, done 2026-10-31. Read for behavior only. No BookOrbit code is copied into this repo (it is AGPL-3.0 with additional terms; see CLAUDE.md "Licensing rules").

Sources read:

- `bookorbit/bookorbit` at `ba315c7` (2026-10-31; its foliate files are identical to release **v3.6.0**, which is what task 1b runs in Docker): `client/public/assets/foliate/*`, the reader composables under `client/src/features/reader/`, and `server/src/modules/reader/epub/`.
- `deranjer/bookorbit-android` at `18335ca` (2026-10-24): `app/src/main/assets/reader/`.
- Upstream `johnfactotum/foliate-js` history.

## TL;DR

- **Base commit:** BookOrbit's web reader is upstream foliate-js **`6b11e17`** (2025-11-29, "Properly handle empty fragments for MOBI (#107)"). It was vendored on 2025-12-25 and has never been rebased onto newer upstream commits. Its `epubcfi.js` is **identical** to upstream at that commit. **We pin the same commit.**
- **The CFI algorithm is identical.** Generating and resolving CFIs, section (spine) base CFIs and spine indexing all run upstream code unchanged.
- **The DOM is the same.** The server streams the original EPUB's zip entries byte for byte. BookOrbit's loader rewrites attribute values and CSS text, but it never adds, removes or reorders nodes.
- **The one real difference is the *shape* of the relocate CFI.** Since 2026-10-06, BookOrbit's web reader reports a **collapsed point CFI** at the start of the page. Stock foliate-js, and BookOrbit's own Android app, report a **range CFI** spanning the visible page. Both resolve to the same page, and the server parses both. But the strings are not equal. See "Risk 1". (Task 1b saw the same thing live: opening a book in the v3.6.0 web reader stores `epubcfi(/6/2!/4/2)`, a point.)
- **Overall risk: low for reflowable LTR books**, which is our main case and covers all five sample books. The risk is medium for vertical/RTL books and for fixed-layout books (see the table). Spike step 4 (task 2a) still has to confirm this against a live server.

## How the base commit was found

The first BookOrbit commit that adds foliate (`cb393644`, 2025-12-25, "feat(reader): add full ebook reader with foliate and annotations") was diffed against every upstream commit, ignoring whitespace. Against `6b11e17`, 12 of its 14 shared files are byte-identical, and only `epub.js` and `view.js` differ. The upstream commits `b0c02a5` and `fd20452` tie with it, because they only touch `package.json`/lockfile. `6b11e17` was upstream HEAD on the day BookOrbit vendored it.

BookOrbit's current HEAD has been reformatted with prettier (`semi: false`, `printWidth: 150`). So both sides were normalized with that config before diffing. HEAD is still closest to `6b11e17` (660 changed lines, all in `epub.js`, `view.js`, `paginator.js` and `fixed-layout.js`). It does not include any later upstream change. For example, the `nodeToParts` fix from `b74d50e` is absent from its `epubcfi.js`.

The Android client carries its own copy, derived from the web one. Its `epubcfi.js` is also identical to upstream `6b11e17`.

### Upstream changes after `6b11e17` (why not pin newer)

| Commit | File | CFI effect |
|---|---|---|
| `b74d50e` FILTER_SKIP wrappers keep offsets | `epubcfi.js` `nodeToParts` | Only when a `filter` is passed. `View.getCFI` passes none, so relocate and selection CFIs are unaffected. |
| `399248a` eslint | `epubcfi.js` | Whitespace only. |
| `a70ad3a`, `ab5abb9` | `epub.js` metadata | None. |
| `9a67679` | `mobi.js` anchors | MOBI only (MOBI has no real CFIs). |
| `6e13f24`, `78914ae`, `5ba02c7` | search draw options, external links, TTS | None. |

Moving to upstream HEAD (`78914ae`) would be CFI-neutral for EPUB. We stay on `6b11e17` anyway, so that 2a compares the exact same code and has one less variable. Revisit after the spike.

## What BookOrbit changed, file by file

### `epubcfi.js`: unchanged

### `view.js`

1. **Relocate CFI is collapsed to a point** (added in `e253f7ff`, 2026-10-06, "preserve exact positions when syncing with koreader"). Upstream computes `getCFI(index, range)` from the paginator's visible range. That gives a range CFI, `epubcfi(/6/N!/4/…,/…:a,/…:b)`. BookOrbit first reduces the range to a single point, then builds the CFI. It picks the point like this:
   - If the visible range starts inside a text node, it uses that text node and offset, which is the same point as upstream's range start.
   - Otherwise (the range starts at an element, which happens when the first visible node is a whole element such as an `<img>` or a fully visible block), it walks forward to the first non-blank text node that intersects the range and uses offset 0.
   - If neither applies, it falls back to the range end, and then to the range start.

   The result is a point CFI, `epubcfi(/6/N!/4/…/1:a)`.
2. `relocate` detail gains extra fields: `source` (section href), `koboLocationType`/`koboLocationValue` (the nearest `.koboSpan` id, which only exists in KEPUBs) and `contentSourceProgressPercent`. None of them affect the CFI.
3. `goTo` falls back to the next (then the previous) readable section when a section fails to load. This only matters for broken books.
4. Other changes: media-overlay highlight fixes, RTL detection also reads the renderer's `dir`, `makeStreamingBook` is exported, and FB2 is sniffed by content.

### `epub.js`

- **OPF namespace handling** (`childGetter`): BookOrbit matches by namespace only when `documentElement.namespaceURI` is the OPF namespace. Upstream uses `lookupNamespaceURI(null) === ns || lookupPrefix(ns)`. This only differs for a malformed OPF whose `<package>` lost its default `xmlns` but still binds the `opf:` prefix. On such a book, stock foliate sees no manifest or spine and **fails to open** it, while BookOrbit opens it. This is a failure, not drift.
- `Object.groupBy`/`Map.groupBy` are replaced by helpers, for older browsers. iOS 27 WebKit has both natively.
- **CSS**: there is a `css` transform hook, which BookOrbit uses for "scale publisher font sizes". `font-display: swap` is injected into `@font-face`. Optional direct URLs are used for images and fonts. All of these rewrite CSS text or attribute values. **No nodes are added.** The text inside a `<style>` element is replaced in place (one text node stays one text node), as upstream already does.
- Media-overlay race fixes. `loadDocument` throws on empty text instead of parsing nothing.
- `this.sections = this.resources.spine` is unchanged, and so are the spine order, `linear="no"` handling and section base CFIs.

### `paginator.js`

- **Page progression**: `getPageProgressionRtl(bookDir, contentRtl)` makes the book's `page-progression-direction` win over the content's own direction. Negative scroll is used only for RTL *horizontal* text, not vertical. For **horizontal LTR books this is identical to upstream**. For **vertical or RTL books** it changes which slice is "visible", so the range (and the CFI) that gets reported can differ from stock foliate's by a page.
- Section documents load through `iframe-loader.js` (below).
- `-webkit-`/`-epub-` `writing-mode`, `text-orientation` and `line-break` are unprefixed. This affects layout only.
- Touch paging is suppressed while text is selected. This is input handling only.

### `fixed-layout.js`

- `getContents()` returns `index` and `overlayer` for annotations, and a `create-overlayer` event is added. Position reporting is unchanged.

### New: `iframe-loader.js` (relevant to us)

The comment says "some embedded WebKit browsers leave blob frame navigations at about:blank". The workaround: if a section iframe's `blob:` navigation hasn't committed after 1 s, it fetches the blob, parses the XHTML, writes it into `srcdoc` with a `<base>`, and then **replaces the HTML-parsed `<body>` with the XHTML-parsed one**. That last step keeps the DOM tree (and therefore CFIs) equal to the XHTML parse. HTML parsing would insert nodes such as `<tbody>`, and serializing self-closing XHTML `<div/>` as HTML changes the tree.

**Lesson for Octavo:** the canonical DOM for CFIs is the **XML (XHTML) parse of the original file**. If WKWebView ever stalls on blob iframes for us, any workaround must keep that tree. Never fall back to HTML-parsing XHTML. (In task 1a, blob iframes loaded fine in `WebPage` under our custom scheme, for all five sample books. See `reader-spike.md`.)

### New: `streaming-loader.js`, plus the server

The web reader loads EPUBs entry by entry from `GET /api/v1/epub/{bookId}/file/{path}` instead of unzipping the whole file in the browser. Server side, `EpubService.streamFile` returns the **raw zip entry stream** of the original EPUB. The `Content-Type` comes from the OPF manifest. A server comment says "The web reader always renders the original EPUB: every stored CFI is epub-DOM". KEPUB conversion happens server-side for Kobo sync and is not served to the reader. So **the DOM BookOrbit renders is the same file we download** from `books/files/{fileId}/serve`.

### App-level code (Vue composables)

- `relocate` → `useReaderProgress` stores `detail.cfi` verbatim and posts `{ percentage, text: { cfi, page }, kobo…, koreader… }`. Percentage is `fraction * 100`.
- On open: `view.goTo(cfi)`, falling back to `goToFraction`. **Fixed-layout books restore by fraction, not CFI** (`isFixedLayoutBook` → `shouldRestoreByFraction`).
- Chapter `load` hooks only inject a media-overlay highlight `<style>` (only when the book has media overlays) and attach click handlers. Reader settings go through `renderer.setStyles`, which adds `<style>` elements to `<head>`. Upstream does the same, and `<head>` content doesn't shift `<body>` steps (`/4`).
- The server's position converter (`server/src/modules/position-converter/cfi.utils.ts`) re-implements foliate's CFI parsing for Kobo/KOReader conversion. Its `parseCfi` accepts both **point and range** CFIs.

## CFI risk assessment

| # | Risk | Affects | Likelihood | Impact | Mitigation |
|---|---|---|---|---|---|
| 1 | **Point vs range CFI.** Web reader posts point CFIs, stock foliate (and BookOrbit Android) range CFIs. | All books | Certain (the strings differ) | Low. Both resolve to the same page in both readers, and the server parses both. Breaks only exact-string comparisons such as "has the position changed" checks, dedup, or conflict detection. | 2a: compare by resolving (or by `epubcfi.compare` start points), never by string. **Decision for 2a/owner:** post as-is (like Android does), or collapse to a point before posting so web and iOS strings match. The collapse rule is described above, and we'd write our own implementation of it. |
| 2 | Layout differences: viewport, font, margins, column count, publisher-font scaling. A different word ends up at the top of a page. | All books | Certain | Low and symmetric. Each side lands on the page containing the other's CFI. "Same page" means "page containing that word", not an identical page break. | Accept. Judge 2a results by "contains the same text", not identical screenshots. |
| 3 | Page-progression change in BookOrbit's paginator: a different visible slice is reported. | Vertical (CJK) and RTL books | Medium for those books | Off by about one page | Test one vertical-rl book in 2a if available. If drift shows, port the *behavior* (book `page-progression-direction` wins; negative scroll only for horizontal RTL) in our own code. Don't patch foliate. |
| 4 | Fixed-layout (pre-paginated): BookOrbit restores by fraction, so its CFI there is not authoritative. | FXL EPUBs | Certain | Wrong page if we trust the CFI | For FXL, push/pull `fraction` (and `pageNumber`). Treat the CFI as advisory. |
| 5 | Malformed OPF (missing default xmlns): stock foliate can't open it, BookOrbit can. | Rare broken books | Low | Book fails to open (no silent drift) | Track it. If it shows up, add our own pre-parse fix in the bridge's loader, not in foliate. |
| 6 | Blob iframe stall in embedded WebKit. A workaround that HTML-parses XHTML would change the DOM tree. | Any book, if WKWebView stalls | Didn't happen in 1a | High if mishandled (`tbody`, self-closing `div`s) | If needed, keep the XHTML tree (see `iframe-loader` notes). |
| 7 | **Blank pages** (found in 1a): on an empty column, `getVisibleRange` falls back to `<body>`. The relocate CFI is the bare section body, and the next re-layout jumps to the section start. | Books with forced breaks and full-page images (P&P front matter) | Seen in 2 of 5 sample books | Position loss. Paging can loop. Shared by BookOrbit (same `getVisibleRange`). | See `reader-spike.md`. Owner decision: upstream patch vs. bridge CSS normalization. Don't sync bare-body CFIs. |
| 8 | Future upstream bumps (ours or BookOrbit's) diverge. | All | Low per bump | Varies | Pin. When either side bumps, diff `epubcfi.js`, `paginator.js#getVisibleRange` and `view.js#onRelocate`. Re-run the 2a round-trip table. |

**Bottom line:** BookOrbit's custom loader doesn't change how CFIs are computed or resolved, or which DOM they address. Stock foliate at `6b11e17` will read BookOrbit's positions correctly, and BookOrbit will read ours. The only systematic difference is point-vs-range shape (risk 1), which is cosmetic for navigation but matters for any string equality. The CLAUDE.md "known risk" about the custom document loader can be downgraded once 2a confirms this on a live server.

## Notes for task 2b (spreads)

The column count is decided by the paginator, not by us:

- `columns = min(--_max-column-count-spread, ceil(containerInlineSize / max-inline-size))`. Defaults: `max-inline-size` 720px, `max-column-count` 2, `gap` 7%, `margin` 48px.
- A container query switches `--_max-column-count-spread` to `--_max-column-count-portrait`, which is **hard-coded to 1 and not exposed as an attribute**, whenever the paginator's own box is portrait. The shadow root is closed, so it can't be overridden from outside.
- So in practice: **portrait box → always 1 column. Landscape box wider than `max-inline-size` → up to `max-column-count` (2).** To force 1 column on a wide box, set `max-column-count="1"`. Forcing 2 columns on a portrait box isn't possible without changing upstream code. 2b should check whether the unfolded Duo's reader box is landscape. If it isn't, options are to size the `foliate-view` box to landscape, or to lower `max-inline-size` (which only helps for landscape).
- The paginator re-renders on its own `ResizeObserver` and re-anchors to the Range at the start of the page (`#anchor`), so a fold/unfold should keep the position without help from us. Verify in 2b.
- Attributes on `foliate-paginator`: `flow` (`paginated`/`scrolled`), `gap`, `margin`, `max-inline-size`, `max-block-size`, `max-column-count`, `animated`.
