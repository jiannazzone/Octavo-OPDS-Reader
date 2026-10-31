# Spike 1c: Readium Swift Toolkit vs. foliate-js, position sync with BookOrbit

Task 1c of the first spike (see `docs/SPIKE.md`): can Readium, which stores positions as Locators, sync reading positions with BookOrbit's web reader, which stores foliate-js EPUB CFIs? This branch is an evaluation. It's merged only if Readium wins.

> **Outcome (2026-10-31):** the owner chose foliate-js with safeguards (see `CLAUDE.md`, Rendering). This note is kept on the main line for the record. The Readium code, plus the raw results table and run scripts (`docs/notes/readium-spike/`), live on the local branch `spike/readium-eval`, the escape hatch.

**Short answer:** yes. With a small CFI bridge built on upstream foliate-js `epubcfi.js`, positions moved between Readium and BookOrbit's web reader landed on the right page **30 out of 30 times** (15 each way), and the CFIs were character-exact both ways. The costs are elsewhere: a translation layer we own, a fold/unfold drift in Readium that we have to correct (fix tested), no MOBI/AZW3/FB2, and a few license and security items listed below.

## Setup

- **Readium Swift Toolkit 3.11.1** (2026-10-16, latest stable), pinned with `exactVersion` in `Octavo.xcodeproj`. Products used: `ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator`. No `ReadiumAdapterGCDWebServer`, no LCP.
- **No embedded HTTP server.** Since 3.8.0 the EPUB navigator serves books to its web views through a custom URL scheme handler (`readium://`), and the `httpServer:` initializer is deprecated and ignored.
- **BookOrbit v3.6.0** on `localhost:3300` (task 1b's Docker server). Own user `octavo-readium` (id 2, library access to "Spike", its own "Spike" collection, id 2), so progress writes don't collide with 2a's `octavo` user. The browser used the `http://127.0.0.1:3300` origin to keep its cookies separate from 2a's.
- **Simulator:** `Octavo Readium Duo` (3BDA3701-D63E-4D61-80C6-0DFA12D214BF), iPhone Duo device type, iOS 27.1, folded (outer display) unless noted. Reader area folded: 466×526 pt. Measurements used a **Release** build (Debug builds of Readium's dependencies are ~10× slower to open a book).
- **Web side:** built-in browser at the mobile preset (375×812).
- **App offline.** The app never talks to BookOrbit. Progress was posted and read from the Mac with curl as `octavo-readium`, so no ATS change was needed. The served EPUBs are byte-identical to `SampleBooks/` (checked by SHA-1), so the app reads local copies.

## What was built (`Octavo/Spike/Readium/`)

| File | Role |
|---|---|
| `epubcfi.js` | Upstream foliate-js `epubcfi.js` at `6b11e17`, unmodified (SHA-256 `0fdd0e1a…195662d`, same file 1a vendored and BookOrbit runs). |
| `ReadiumCFIScript.swift` | Wraps the ES module as a classic script at load time (drops `export`, publishes `window.OctavoCFI`) and appends our bridge. Injected into every chapter through `EPUBNavigatorDelegate.navigator(_:setupUserScripts:)`. |
| `readium-cfi-bridge.js` | Ours (MPL). In the chapter DOM: first-visible-character → CFI; CFI → DOM point → what Readium needs to go there; "is this CFI on screen?"; page text for the measurements. |
| `EPUBSpineCFI.swift` | Reads `container.xml` and the OPF; maps spine items ↔ base CFIs (`/6/N`) ↔ hrefs the same way foliate does. |
| `ReadiumSpikeReader.swift` | Opens the publication, hosts `EPUBNavigatorViewController`, runs both translations. |
| `ReadiumSpikeView.swift`, `ReadiumSpikeRun.swift` | Debug screens, and launch-argument-driven measured runs that write JSON reports. |

`ContentView` shows the spike screen (one line). Unit tests: `OctavoTests/ReadiumSpikeCFITests.swift`.

### Readium → CFI

On every location change, the bridge walks the chapter's text nodes, finds the first one with a box in the visible page (`[0, innerWidth)`), and bisects to the first visible character. `CFI.fromRange(point, filter)` turns that into the in-document part. Swift prefixes the spine step. The result is a point CFI at the page start, the shape BookOrbit's web reader stores.

Two details mattered:

- **Use the web view's own URL for the spine step**, not `navigator.currentLocation`: Readium's locator lags the web view by a few hundred ms after a jump, and the first version produced CFIs with the previous chapter's spine step.
- **Readium's DOM changes:** it injects `<link>`, `<meta>` and `<style>` into `<head>`, `dir`/`xml:lang`/`style` attributes on `<html>`/`<body>`, and at runtime appends `#readium-virtual-page` (filler column for odd two-column spreads) and `#r2-decoration-N` (highlight layers) to the end of `<body>`. CFIs into `<body>` don't depend on the first two. The bridge passes a filter that rejects the appended nodes to foliate's `fromRange`/`toRange`. Readium serves XHTML with the manifest's media type, so WebKit parses it as XML, like foliate does, and whitespace text nodes match.
- **Checked in two-column mode** (unfolded Duo, `twocol-*` reports): 30 consecutive spreads across chapter ends in Alice and Sherlock. `#readium-virtual-page` was in the DOM for all 15 Sherlock spreads. The CFI was the same with and without the filter on all 30, and BookOrbit's foliate resolved all 30 to the exact first character. Because Readium only appends at the end of `<body>`, the filter only matters for a point after the last real node, which a page start never is; it stays as a safeguard.

### CFI → Readium

1. Parse the spine step in Swift (by itemref index, like foliate's `resolveCFI`, which drops itemref id assertions), map it to the reading-order link, open or jump to that chapter.
2. In the chapter, `CFI.toRange(document, parts, filter)` → DOM point → move to the first non-whitespace character at or after it.
3. Navigate. Three methods were tried on every jump:

| Method | What Readium gets | Landed on the CFI's page |
|---|---|---|
| **Text quote** | `Locator.text` (`highlight` = 32 chars from the point, `before`/`after` = 48 chars of context) plus `locations.cssSelector` of the enclosing block. Readium anchors it with its Hypothesis-derived `TextQuoteAnchor` and snaps to the page. | **15/15** |
| Layout progression | `locations.progression` = x of the point's character in the live layout ÷ chapter scroll width | 15/15 |
| Text fraction | `locations.progression` = characters before the point ÷ characters in the chapter (no layout) | 11/15 |

**Use the text quote.** It's Readium's own API, it doesn't depend on the current layout, and the same Locator works for decorations (highlights). Layout progression is exact too but only if computed in the live layout immediately before the jump; it's the fallback when a quote can't be built (empty text, e.g. an image). Text fraction misses by a page about a quarter of the time. Readium's `go(to:)` uses the quote if `text.highlight` is set, else `fragments`, else `progression`; it ignores `cssSelector` without a quote. If the quote isn't found, `go(to:)` returns false and does **not** fall back, so the caller must.

Both directions are character-exact, not just page-exact:

- Web → Readium: for 15/15 stored web CFIs, the quote the bridge built starts with the web page's first visible words.
- Readium → web: for 15/15 Readium-made CFIs, BookOrbit's own foliate instance (`view.resolveCFI` + the section's document) resolves them to the exact character Readium showed first.
- For a chapter-start page (Sherlock VII), Readium's CFI and the web reader's are the identical string.

## Results

Method: like 2a's. **Readium → web:** Readium opened at a total progression (12 / 48 / 83 %) plus 2 page turns (P&P 4, to get off illustration pages), its CFI and percentage were POSTed to `books/files/{id}/progress`, and the web reader was reloaded. **Web → Readium:** in the web reader, `goToFraction` (20 / 55 / 88–90 %) plus two `next()` page turns, wait for its save, read the stored CFI back with GET, open it in the app. The probe is the source page's first 8 words; the target page "contains them" if the normalized text includes them (a straddle at the page end would count as a hit; none happened). Most positions are mid-chapter and mid-paragraph. Sherlock VII and P&P ch. XIII are chapter starts, and three more are within a few pages of one.

| Direction | hit | near | miss | failed |
|---|---|---|---|---|
| Readium → web | 15 | 0 | 0 | 0 |
| web → Readium | 15 | 0 | 0 | 0 |

| Book | Position | Direction | Source first visible words (~8) | Target page contains them? | Verdict | Notes |
|---|---|---|---|---|---|---|
| Alice | early (13%, ch. II, mid) | Readium→web | question is, Who in the world am I? | yes | hit | source `epubcfi(/6/8!/4/2[pgepubid00004]/20/1:407)`; web opened /18/1:509 p3/11 |
| Alice | middle (49%, ch. VII, page 2) | Readium→web | The table was a large one, but the | yes | hit | web page 1 of the chapter holds both; source `epubcfi(/6/18!/4/2[pgepubid00009]/6/1:0)`; web opened /2/3:0 p1/13 |
| Alice | late (83%, ch. XI, mid) | Readium→web | The King looked anxiously at the White Rabbit, | yes | hit | source `epubcfi(/6/26!/4/2[pgepubid00013]/136/1:0)`; web opened /116/1:0 p8/11 |
| Alice | early (21%, ch. III, mid) | web→Readium | oh, I wish you could see her after | yes | hit | method textQuote; source `epubcfi(/6/10!/4/2[pgepubid00005]/94/1:157)`; Readium page starts: your tongue, Ma!” said the young Crab, a |
| Alice | middle (57%, ch. VIII, mid-paragraph) | web→Readium | procession moved on, three of the soldiers remaining | yes | hit | method textQuote; source `epubcfi(/6/20!/4/2[pgepubid00010]/54/3:98)`; Readium page starts: the King, the Queen, the royal children, and |
| Alice | late (92%, Gutenberg licence section, mid) | web→Readium | the public domain in the United States. If | yes | hit | method textQuote; source `epubcfi(/6/30!/4/2[pg-footer]/22/1:227)`; Readium page starts: There are a lot of things you can |
| Frankenstein | early (12%, ch. 1, mid-paragraph) | Readium→web | them, but it would be unfair to her | yes | hit | source `epubcfi(/6/16!/4/2[pgepubid00007]/22/1:451)`; web opened /22/1:101 p7/9 |
| Frankenstein | middle (48%, ch. 12, mid-paragraph) | Readium→web | in the garden, but as there was little | yes | hit | source `epubcfi(/6/38!/4/2[pgepubid00018]/24/1:732)`; web opened /24/1:608 p6/11 |
| Frankenstein | late (83%, ch. 22, mid) | Readium→web | Preparations were made for the event, congratulatory visits | yes | hit | source `epubcfi(/6/58!/4/2[pgepubid00028]/66/1:0)`; web opened /64/1:207 p11/16 |
| Frankenstein | early (21%, ch. 4, mid-paragraph) | web→Readium | discovered more gradually, and the empires of Mexico | yes | hit | method textQuote; source `epubcfi(/6/22!/4/2[pgepubid00010]/26/1:933)`; Readium page starts: allowed any pursuit whatsoever to interfere with the |
| Frankenstein | middle (56%, ch. 15, mid-paragraph) | web→Readium | and where they ought to see a feeling | yes | hit | method textQuote; source `epubcfi(/6/44!/4/2[pgepubid00021]/54/1:253)`; Readium page starts: am full of fears, for if I fail |
| Frankenstein | late (89%, ch. 24, mid-paragraph) | web→Readium | mountain, and one, sinking under his fatigue, died, | yes | hit | method textQuote; source `epubcfi(/6/62!/4/2[pgepubid00030]/46/1:447)`; Readium page starts: grief from my eyes. Despair had indeed almost |
| Moby-Dick | early (12%, ch. 13, mid) | Readium→web | In vain the captain threatened to throw him | yes | hit | source `epubcfi(/6/6!/4/124/1:0)`; web opened /122/1:613 p32/97 |
| Moby-Dick | middle (48%, ch. 57-ish, mid-paragraph) | Readium→web | are pecking at the small crabs, shell-fish, and | yes | hit | source `epubcfi(/6/14!/4/14/1:443)`; web opened /12/1:1231 p4/96 |
| Moby-Dick | late (83%, ch. 110, mid-paragraph) | Readium→web | dark planks the coffin was recommended to be | yes | hit | source `epubcfi(/6/20!/4/428/1:354)`; web opened /426/1:322 p69/92 |
| Moby-Dick | early (20%, ch. 21-ish, mid) | web→Readium | “Face!” said I, “call that his face? very | yes | hit | method textQuote; source `epubcfi(/6/8!/4/76/1:0)`; Readium page starts: “Those sailors we saw, Queequeg, where can they |
| Moby-Dick | middle (55%, mid-paragraph, offset 1460) | web→Readium | are sometimes found, months afterwards, perpendicularly frozen into | yes | hit | method textQuote; source `epubcfi(/6/14!/4/412/1:1460)`; Readium page starts: themselves under the lee of an iceberg, as |
| Moby-Dick | late (88%, mid-paragraph, after inline element) | web→Readium | anchor here, though, so I can pass the | yes | hit | method textQuote; source `epubcfi(/6/22!/4/224/3:576)`; Readium page starts: fill pitchers at your coat collar. Don’t you |
| Pride and Prejudice | late (83%, ch. 47-ish, mid-paragraph) | Readium→web | weeks. Mrs. Bennet was quite in the fidgets. | yes | hit | source `epubcfi(/6/12!/4/676/1:353)`; web opened /674/1:0 p104/122 |
| Pride and Prejudice | early (12%, ch. 2-ish, mid-paragraph) | Readium→web | were all her own. Till the next morning, | yes | hit | source `epubcfi(/6/4!/4/504/1:110)`; web opened /502/1:0 p86/119 |
| Pride and Prejudice | middle (48%, ch. 33-ish, mid-paragraph) | Readium→web | course of their third encounter that he was | yes | hit | source `epubcfi(/6/10!/4/18/3:746)`; web opened /18/3:385 p6/124 |
| Pride and Prejudice | early (21%, ch. XIII start, illustrated drop cap) | web→Readium | CHAPTER XIII hope, my dear,” said Mr. Bennet | yes | hit | method textQuote; source `epubcfi(/6/6!/4/112[pgepubid00106]/9:0)`; Readium page starts: CHAPTER XIII hope, my dear,” said Mr. Bennet |
| Pride and Prejudice | middle (55%, ch. 35-ish, mid-chapter) | web→Readium | The compliment to herself and her sister was | yes | hit | method textQuote; source `epubcfi(/6/10!/4/204/1:0)`; Readium page starts: she could not help remembering what Charlotte’s opinion |
| Pride and Prejudice | late (88%, ch. 55-ish, mid-paragraph) | web→Readium | when Bingley was gone, Jane constantly sought the | yes | hit | method textQuote; source `epubcfi(/6/14!/4/108/1:359)`; Readium page starts: neighbour, who could not be enough detested, had |
| Sherlock Holmes | early (12%, Red-Headed League, mid) | Readium→web | “‘What would be the hours?’ I asked. “‘Ten | yes | hit | source `epubcfi(/6/8!/4/2[pgepubid00006]/144/1:0)`; web opened /128/1:99 p13/40 |
| Sherlock Holmes | middle (48%, start of story VII) | Readium→web | VII. THE ADVENTURE OF THE BLUE CARBUNCLE I | yes | hit | chapter start. Web reader reports the identical CFI string; source `epubcfi(/6/18!/4/2[pgepubid00011]/2/3:0)`; web opened /2/3:0 p1/35 |
| Sherlock Holmes | late (83%, Beryl Coronet, mid-paragraph) | Readium→web | the matter. The police have openly confessed that | yes | hit | source `epubcfi(/6/26!/4/2[pgepubid00015]/162/1:690)`; web opened /158/1:194 p16/41 |
| Sherlock Holmes | early (21%, A Case of Identity, mid) | web→Readium | “Thank you. You have made your statement very | yes | hit | method textQuote; source `epubcfi(/6/10!/4/2[pgepubid00007]/158/1:0)`; Readium page starts: “I fear not.” “Then what has happened to |
| Sherlock Holmes | middle (56%, Speckled Band, mid-word: web page starts inside a hyphenated word) | web→Readium | re were those of a woman of thirty, | yes | hit | method textQuote; source `epubcfi(/6/20!/4/2[pgepubid00012]/24/1:261)`; Readium page starts: I shall order you a cup of hot |
| Sherlock Holmes | late (89%, Copper Beeches, mid-paragraph) | web→Readium | and originality. As to my own little practice, | yes | hit | method textQuote; source `epubcfi(/6/28!/4/2[pgepubid00016]/20/1:359)`; Readium page starts: incident of the noble bachelor, were all matters |

The results table, `results.tsv`, the fold-cycle log, the test EPUB with scripts and the run scripts are in `docs/notes/readium-spike/` on branch `spike/readium-eval`. The per-run JSON reports and screenshots (about 15 MB) were not committed.

## Secondary observations

- **Two columns on the unfolded Duo:** yes, but not by default. Unfolded, the reader area is 951×517 pt (wider than tall; the inner display is 951×669 pt minus the navigation bar and debug strip). With `columnCount: .auto` Readium shows **one** centered column there (screenshot `fold-moby-open2.png`). With `columnCount: .two` it lays out a proper two-column spread (`duo-2col.png`), and the CFI bridge works unchanged across both columns. Why `auto` stays at one column here wasn't investigated (3.11.1's changelog mentions a fix for the Duo unfolded in landscape). The app should set the column count from the hinge state itself: one line.
- **Position across fold/unfold:** Readium alone doesn't keep it. It rebuilds its web views on every size change (a spinner for several seconds in the simulator) and restores from its own progression, which is approximate. Measured with 6 hinge moves per run (`fold-*` reports):
  - **One column both ways (Frankenstein):** every move kept the previous page's first words, but the page start crept backward each time (`/18/1:116` → `/14` → `/12` → `/12` → `/10` → `/8/1:0`); after 2 moves the original page was gone, after 6 it was ~4 folded pages back.
  - **Two-column spread unfolded (Moby-Dick):** in one run the first fold back jumped straight to the **chapter start**; in another it lost about a page per move and reached the chapter start after 5 moves.
  - **Fix, tested:** keep a sticky anchor (the CFI of the reader's own last navigation, which re-layouts don't move, like foliate's paginator anchor) and after each size change `go(to:)` it with the text quote once Readium has settled. Result: **12/12 moves kept the original position** (6 per book, one-column and two-column): every fold came back to the exact original CFI, and every unfold showed a page containing it. Re-reading the anchor from the page after each re-layout doesn't work: it creeps exactly as Readium does, because the new page containing the old start usually starts earlier.
  - Readium's own re-layout before our correction is visible (the page jumps twice). Production would hide the navigator until the re-anchor lands.
- **Opening Pride and Prejudice (24 MB):** parse 69–85 ms, first page 2.5 s (Release, simulator, cold process), the same as Alice (63 ms / 2.4 s): the cost is web view and navigator start-up, not book size. Opening P&P straight into a deep CFI: 2.6–4.1 s to the chapter's first page, then the jump. Each `go(to:)` + settle is ~0.5 s; the measured jumps (2.4–2.9 s) tried all three methods.
- **The page after P&P's dedication:** fine. The dedication plate (page 13 from the start) is followed directly by the Preface text, no blank page and no lost position. Readium does show WebKit's double-break blank page after an earlier full-page plate (`i_003`, page 7), but it keeps the position there and the next page turn continues normally. On that blank page the bridge finds nothing to anchor to; production should then report the next content's start (the same fix as the foliate patch).
- **Highlights (BookOrbit annotations are CFI ranges):** reading them is the same resolve step on both ends of the range: `CFI.toRange` with the filter → text quote → a Readium `Decoration` locator (Readium's decorator anchors decorations with the same `TextQuoteAnchor`). Writing them: on selection, `window.getSelection()` → `CFI.fromRange(range, filter)` gives the range CFI. The catch is that both need the chapter's DOM, so highlights resolve per chapter when it loads (or in a background web view), and Readium's decorations API wants Locators up front. Estimate 4–6 days on top of the position layer, including sync of edits and deletes keyed by the CFI.
- **MOBI / AZW3 / FB2:** Readium doesn't read them. It covers EPUB, PDF, CBZ, audiobooks and Readium Web Publications. foliate-js reads MOBI, AZW3, FB2 and CBZ. Picking Readium means dropping those formats or adding converters.
- **Book JavaScript:** **Readium runs them by default, with no switch to turn them off.** A test EPUB (`1c-readium/scripted-test.epub`) with an inline `<script>` and a manifest `.js` file: both ran, in the same page world as Readium's `readium` object and our bridge, so a book could call or replace either, and its DOM changes could shift CFIs. Readium exposes no WebView configuration, no content world and no response headers. What works: a `Publication.Builder` transform (`PublicationOpener.open(…, onCreatePublication:)`, public API) that prepends `<meta http-equiv="Content-Security-Policy" content="script-src 'none'; object-src 'none'">` to every (X)HTML resource. With it, neither script ran, and Readium and the bridge kept working, because they're WKUserScripts, which page CSP doesn't cover. That's about the same protection as the foliate side's CSP. foliate's other two layers (sandboxed book file, main-frame-only message relay) have no direct Readium equivalent: Readium's own message handlers stay reachable from the page world if a book script gets past the CSP.
- **Debug builds:** Alice took 3.6 s to parse and ~10 s to its first page in a Debug build; Release: 63 ms and 2.4 s. Day-to-day development with Readium needs its packages built optimized.

## Licenses

All dependencies are permissive; nothing GPL/AGPL. Three are outside the MIT/BSD/Apache/MPL list: CryptoSwift (zlib-style with a mandatory acknowledgment), minizip inside Zip (zlib), and the two fonts bundled with Readium CSS (SIL OFL 1.1). Details in `THIRD-PARTY-NOTICES.md`. Owner decision if Readium wins.

## Production estimate for the CFI layer

| Piece | Days |
|---|---|
| Position layer: bridge hardening (blank pages → next content, RTL and vertical text, scrolled mode, fixed layout via fraction like BookOrbit, book-script blocking), Swift API behind `ProgressSync`, quote-first navigation with fallback, re-anchoring after fold/unfold and font changes | 5–7 |
| Regression harness: run foliate's resolver headlessly against our CFIs for many positions per book in the corpus, in CI | 2–3 |
| Highlights both ways, plus sync of edits/deletes | 4–6 |
| **Total** | **~2–3 weeks** |

## Recommendation

The main risk the spike set out to retire, exact position sync with BookOrbit, is retired for **both** engines: 2a measured foliate-js at 16/16 and 15/15, this spike measured Readium at 15/15 and 15/15, character-exact. Sync accuracy doesn't decide it. The rest does.

**Recommendation: stay with foliate-js, keep Readium as the documented fallback.**

- Octavo's point is exact BookOrbit sync, highlights included. foliate gives that by construction: the same code as BookOrbit's web reader and Android app, no translation layer. Readium needs a CFI layer we own, written against a second moving target.
- OPDS servers (Calibre in particular) are full of MOBI and AZW3. foliate reads them; Readium doesn't.
- foliate's known problems are small and already understood: the blank-page bug has a vetted patch, the portrait single-column limit is one hard-coded value. Readium's fold drift is also fixable (tested here), but it's one more correction on top of the bridge.
- What Readium would buy, a mature UIKit navigator with selection, decorations, TTS, accessibility and PDF in one package, matters less while the reader is a SwiftUI web view we control anyway.
- If foliate's maintenance becomes a real problem, this branch shows a switch is ~2–3 weeks, not a rewrite.

**Main risk, foliate-js:** upstream maintenance. One maintainer, no releases, an API documented as unstable. We pin a commit, will carry local patches (blank page, portrait columns), and must re-run the CFI round trip on every bump.

**Main risk, Readium:** the CFI layer depends on Readium internals it doesn't promise to keep: the ids of the nodes it injects into `<body>`, serving XHTML as XML, `currentLocation` lagging the web view, how `go(to:)` treats a text quote, how it re-lays out on resize. A Readium update can break sync silently. It would need a regression harness in CI that resolves our CFIs with foliate's own code, plus owner sign-off on the three non-MIT/BSD/Apache licenses and a decision on book scripts.
