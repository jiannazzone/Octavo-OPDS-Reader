# Reader spike (task 1a): notes

How the foliate-js reader is wired, how to get books onto the simulator, and what we learned. Written 2026-10-31. The BookOrbit and CFI research is in `bookorbit-foliate.md`.

## How it fits together

```
SpikeLibraryView ──▶ SpikeReaderView ──▶ ReaderModel (@Observable)     (spike screens; since #17: AppShell ──▶ ReaderView, docs/notes/reader-page.md)
 (Octavo/Spike/)       debug strip,        ├─ WebPage + ReaderWebView (SwiftUI WebView)
                       prev/next           ├─ ReaderSchemeHandler  octavo://app/…   (ReaderWeb/ + the book)
                                           ├─ "octavo" script message handler → ReaderMessage (JSON)
                                           └─ ReadingPositionStore  (one JSON file per book)
                                                    ▲
ReaderWeb/reader.html ─ bridge.js ─ foliate-js/view.js (pinned 6b11e17, unmodified)
```

- **One origin.** `octavo://app/reader.html`, `octavo://app/foliate-js/*.js` and `octavo://app/book/<file name>` are all served by `ReaderSchemeHandler`, so ES-module imports and the bridge's `fetch` of the book are same-origin. Web files come from the bundled `ReaderWeb/` folder (path-traversal checked). The book is streamed in 1 MB chunks. MIME types for web files are pinned; `.js` must be `text/javascript` or WebKit refuses to run the module.
- **JS → Swift:** `bridge.js` posts JSON strings `{type, …}`: `ready`, `opened`, `relocate {cfi, fraction, tocLabel, sectionIndex, sectionCount, location}`, `tap`, `externalLink`, `error`, `log`. `ReaderMessage` decodes them tolerantly. Unknown types and missing or `null` fields never throw.
- **Swift → JS:** `WebPage.callJavaScript("return await window.octavo.open(options)")`, plus `goTo(cfi)`, `goToFraction(f)`, `next()` and `prev()`.
- **Opening:** the bridge fetches the book, calls `view.open(File)`, then restores. It tries the CFI first, then the fraction, then the start of the book. Fixed-layout books try the fraction first, as BookOrbit does.
- **Persistence:** every `relocate` after `opened` is saved to `Library/Application Support/ReadingPositions/<book id>.json` with an atomic write. Relocates that arrive while the book is still being restored are ignored, so a half-finished open can't overwrite the saved position. Book ID for now is the file name.
- **Paging:** foliate's paginator handles swipes itself. The bridge adds tap zones (outer 30% of the width on each side means previous/next page; the middle posts `tap`). The debug screen also has Previous/Next toolbar buttons.
- **Relaunch:** the spike library remembers the open book (`@AppStorage("spike.lastOpenBook")`) and pushes it again on launch. That's how "kill and relaunch lands on the same page" is exercised.

## Security: book scripts are blocked

foliate-js renders each section in a same-origin `blob:` iframe that has to allow scripts (WebKit bug 218086), so a book's own JavaScript would otherwise run with full access to the reader page and the native bridge. foliate's README makes blocking scripts the host's job. A scripted test EPUB confirmed the hole in the first commit: both an inline `<script>` and a manifest `.js` file ran and posted to the `octavo` message handler. Four layers now block it, and the same test shows nothing running:

1. **CSP on every `octavo://` response** (`ReaderSchemeHandler.contentSecurityPolicy`): `script-src` lists only `bridge.js` and `foliate-js/` by path, so the same-origin book at `/book/` is never a script source. Network loads are allowed only from `'self'`, `blob:` and `data:`, and `frame-src` is `blob:` only. Every response also sends `X-Content-Type-Options: nosniff`, so a book crafted to double as JavaScript (a MOBI's free-text header makes that plausible) can't run. The book response itself gets `default-src 'none'; sandbox`. The blob iframes inherit it. Book images, styles and fonts still load because they are `blob:` URLs. Remote images in a book are blocked, which also stops tracking pixels.
2. **foliate's `load` transform hook** refuses script items (`detail.allow = false`).
3. **The message relay** drops anything that isn't from the main frame at `octavo://app`.
4. **External links** are cancelled in the bridge (foliate would otherwise `window.open` them) and reported to Swift as `externalLink`.

Keep the CSP if the bridge or scheme ever changes. A unit test checks that every response carries it.

## Getting books onto the simulator

Books are never committed (`SampleBooks/` is gitignored). The app lists whatever is in its own **Documents** folder:

```bash
Scripts/fetch-sample-books.sh            # or copy SampleBooks/ from the main checkout
# Build and install the app once so its data container exists, then:
D=$(xcrun simctl get_app_container 8C35AF6E-5F3F-48D7-A283-AEE894511947 com.ianazzone.ereader data)
mkdir -p "$D/Documents" && cp SampleBooks/*.epub "$D/Documents/"
```

Then tap **Reload** in the Spike Library, or relaunch. Reinstalling the app (Xcode, `simctl install`) keeps the data container, so the books and saved positions survive rebuilds. To reset a saved position, delete `"$D/Library/Application Support/ReadingPositions/<file>.json"`.

## Results on the iPhone Duo simulator (folded, outer display)

- **Pride and Prejudice (24 MB, illustrated):** opens, pages with tap, swipe and buttons. Kill (SIGKILL) and relaunch lands on the identical page with the identical CFI (`epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)`, fraction 0.01110).
- **Alice, Frankenstein, Moby-Dick, Sherlock Holmes:** all open and page with no script errors. Frankenstein also restored from its CFI after a relaunch.
- **Open time** (from reader page load to `opened`): about 4 s for P&P, about 1.3 s for the others. Most of it is in-browser unzip of the whole file through zip.js. BookOrbit avoids this with per-entry streaming from the server (see `bookorbit-foliate.md`). We could do the same through the scheme handler later if it matters on device.

## Surprises and lessons

1. **`WebView`/`WebPage`/`URLSchemeHandler` just worked.** ES modules, `fetch` and foliate's `blob:` section iframes all load under the custom scheme. The "blob frame stays at about:blank" stall that BookOrbit works around in embedded WebKit **did not happen** with any of the five books.
2. **Swift 6 default-MainActor target:** the scheme handler must be a `nonisolated struct` to satisfy `URLSchemeHandler.reply(for:)`. `AsyncThrowingStream<URLSchemeTaskResult, any Error>` works as its `TaskSequence`. `URLSchemeTaskResult` is non-frozen, so switches need `@unknown default`.
3. **iOS WebKit doesn't deliver `click` to a document-level listener** when the tapped element isn't itself clickable, which is most of a book. Tap zones use `pointerdown`/`pointerup` with a slop and time limit instead.
4. **foliate's `location.current` can be NaN** (JSON `null`) while a section is still being measured. The first decoder treated it as required and dropped every relocate. It's optional now, and a test covers it.
5. **Three or four `relocate` events per page turn.** One for the turn, then repeats with a refined fraction as section sizes settle. We write the position file each time. Debounce later.
6. **foliate drops page turns while one is in flight** (an internal lock, released about 100 ms after the scroll). Rapid taps get ignored rather than queued. A fast, long swipe can move two pages because of foliate's snap velocity.
7. **`os.Logger` debug lines only show in a live `log stream --level debug`.** `log show` doesn't keep them.

## Bug found: blank pages lose the reading position (upstream foliate behavior)

> **Fixed by foliate-js patch 0001 (spike 2b)**, vetted in `foliate-blank-page-upstream.md`, which also has draft upstream text. Corrections to what's below: P&P's blank column comes from WebKit making two breaks out of `page-break-after` followed by `page-break-before`, not from a margin overflow. The loop needs a re-layout after the page turn, which upstream doesn't do on its own. In the spike, the likely trigger was the debug strip changing height with the CFI's length.

**Symptom:** in Pride and Prejudice, paging forward from the dedication (about 1.35%) jumps back to the start of that section (about 0.19%). Paging forward again loops. In practice you can't page past the front matter of our main test book. `goTo(cfi)` and restoring still work.

**Cause:**

1. The book's CSS has `.blk { page-break-after: always; margin: 2em auto }`, followed by an `h2 { page-break-before: always }`. foliate rewrites `page-break-*` to `-webkit-column-break-*`. The full-page dedication image plus the `.blk` bottom margin overflow into an extra, **empty column**.
2. On an empty page, `paginator.js` `getVisibleRange()` finds no visible node and falls back to `doc.body` (`nodes[0] ?? doc.body`). The relocate CFI becomes the section body (`epubcfi(/6/4!/4)`), and the paginator's internal anchor becomes the body start.
3. The next `expand()` (a `ResizeObserver` on the body, image decode or fonts) re-scrolls to that anchor, which is the first page of the section.

Neither upstream (no paginator changes after `6b11e17`) nor BookOrbit (its `getVisibleRange` is unchanged) fixes this, so **BookOrbit's web reader most likely behaves the same way on this book.**

**Why the bridge can't fix it cleanly:** foliate's `goTo` and page turns are both ignored while its turn lock is held, and the jump fires about 70 ms after the blank page shows, before the lock releases. A bridge workaround would be a timing hack.

**Experiment (reverted, not committed):** a bridge-side CSS transform through foliate's public `transformTarget` hook that rewrote `-webkit-column-break-*: always` to `break-*: column`. It **fixed a different blank page**: the leading empty column at the start of a Frankenstein section, which comes from `page-break-before` on its first element. It did **not** fix P&P's, which is the overflowing margin.

**Options (owner decision, since foliate is vendored unmodified):**

- (a) A small upstream patch to `getVisibleRange`: when nothing is visible, fall back to the nearest node before or after the viewport instead of `<body>`. Offer it to foliate-js as a PR, and carry it as a documented local patch until it lands.
- (b) Keep foliate stock and add bridge-side CSS normalization (like the experiment) to cut down blank columns. This reduces the problem but doesn't remove it.
- (c) Both.

Whatever we pick, blank-page CFIs (the bare section body) should probably not be pushed to a sync backend. They're less precise than the previous page's CFI.

## Notes for later tasks

- **2a (CFI round trip):** relocate CFIs here are **range** CFIs (stock foliate). BookOrbit's web reader posts **point** CFIs. Compare positions by resolving them, not by string. See `bookorbit-foliate.md` risk 1. To test past P&P's front matter, use `window.octavo.goTo(cfi)`. Paging won't get you there (bug above).
- **2b (spreads):** column count is decided inside the paginator (`max-column-count`, and a portrait box is always 1 column). Details are in `bookorbit-foliate.md` "Notes for task 2b". The bridge sets only `flow="paginated"` and leaves the other attributes at foliate's defaults.
- **`ReadingPosition`:** no change needed. `cfi` + `fraction` covered everything here.
