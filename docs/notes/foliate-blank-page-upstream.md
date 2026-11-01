# foliate-js: blank pages lose the reading position (upstream vetting)

Independent check of the bug that task 1a found (`reader-spike.md`, "Bug found"), done before proposing anything upstream. Written 2026-10-31. Nothing has been posted anywhere. The draft issue and PR text at the end are for Adam to review and send.

## Verdict

**The bug is real and it's in upstream foliate-js. It isn't caused by Octavo or by WebKit. Confidence: high.**

When the current page has no visible node, `getVisibleRange()` in `paginator.js` falls back to the start of the section's `<body>` (`const from = nodes[0] ?? doc.body`, line 128 at upstream `main` `78914ae`). That one fallback causes two problems:

1. **Wrong location.** The `relocate` event carries the bare section CFI (for example `epubcfi(/6/4!/4)`). An app that saves `lastLocation.cfi` and restores it later lands on the section's first page.
2. **Wrong anchor.** `#afterScroll` stores the same range as the paginator's `#anchor`. The next `render()` or `expand()` calls `#scrollToAnchor(#anchor)` and jumps to the section's first page. Triggers include a container resize, a body resize (late image or font load), `setStyles()`, or a host UI change.

Reproduced with upstream's own demo (`reader.html`, unmodified) at `main` and at our pin `6b11e17` (`paginator.js` is identical at both). It happens in Chrome 156, macOS WebKit (Safari 27.0.1) and iOS 27.1 Safari, on a synthetic EPUB and on Pride and Prejudice. A ~50-line patch fixes both problems in both engines and leaves CFIs on non-blank pages byte-identical (see "No-regression check").

**Not reported or fixed upstream.** Checked foliate-js and the GNOME Foliate app (all issues, PRs, comments and discussions), plus Readest's fork.

### What 1a got right, and what it got wrong

| 1a claim | Result |
|---|---|
| `getVisibleRange` falls back to `doc.body` on an empty page | **Confirmed.** |
| The relocate range becomes the body start and `#afterScroll` stores it as `#anchor` | **Confirmed.** |
| The next `expand()` scrolls to the section's first page | **Confirmed.** `render()` (resize) does the same. |
| The P&P blank column comes from "the dedication image plus the `.blk` bottom margin overflowing" | **Wrong.** Measured in WebKit: the dedication `.blk` is 278px tall in a 748px column. WebKit treats `page-break-after: always` on `.blk` and `page-break-before: always` on the next `h2` as **two** column breaks, which leaves an empty column between them. Chromium merges them into one, so Chromium has no blank page there. |
| "~70 ms later it jumps to the section start, and paging forward again loops" | **Octavo-specific trigger, not upstream behavior.** In the upstream demo, nothing re-lays out the page after a page turn, so the reader stays on the blank page until something else does (a resize, or a style or font change). The spike's debug strip shows the CFI in up to 3 lines above the `WebView`. The blank page's short CFI shrinks the strip, the `WebView` grows, the paginator's `ResizeObserver` calls `render()`, and the reader jumps. Simulating that strip in the upstream demo reproduces the loop exactly (see "Host-triggered loop"). I didn't rebuild Octavo to confirm it in the app. |
| "BookOrbit's web reader most likely behaves the same" | Plausible (same `getVisibleRange`, and BookOrbit's web reader also collapses the relocate range to a point). **Not tested.** |

## 1. Prior art

A subagent searched read-only with `gh` and the GitHub API. It did not post anything.

- **foliate-js:** all 160 issues and PRs plus all 352 comments, discussions, and the PRs that touch `paginator.js` (18, each patch read).
- **Foliate (GNOME):** all 1,578 issues and PRs, comments since 2023, discussions.
- **Readest** (a foliate-js fork): keyword search.
- **Upstream history:** `git log -S'nodes[0] ?? doc.body'` shows the fallback has been there since the first upload (`5fc72d1`, 2022-10-18). `getVisibleRange` last changed in `59bb647` (2024-09-24, a Firefox fix). `paginator.js` is unchanged between `6b11e17` and `main` `78914ae` (2026-05-01).

Closest items, none of them this bug:

| Item | Relation |
|---|---|
| [foliate#1179](https://github.com/johnfactotum/foliate/issues/1179) (closed, fixed by foliate-js `b0a869b`) | A page break at the start of a chapter cut off the end of the chapter (a section-size calculation problem). John noted WebKit gives "a blank page at the start". **Related cause of blank pages, different bug.** |
| [foliate-js#11](https://github.com/johnfactotum/foliate-js/pull/11) (closed, unmerged) | A stale `#anchor` jumped back to the first page when content changed during the scroll animation. **Same symptom family, different trigger.** |
| [readest/readest#7153](https://github.com/readest/readest/issues/7153) (open, undiagnosed) | Readest's TTS reaches a `<figure>` and "jumps to start of chapter". **Possibly the same mechanism.** Readest's fork has the same fallback. Unconfirmed. |
| foliate-js #150, #166, #142, #97, #149, #40 | ResizeObserver null guards, turn lock, CFI offsets. **Unrelated.** |

## 2. Reproduction without Octavo

### Setup

- Upstream foliate-js cloned into the scratchpad. `main` = `78914ae`, plus a worktree at `6b11e17`. Served with a plain static server. No Octavo code.
- **Driver:** an outer page loads the **unmodified demo** (`reader.html?url=<book>`) in a same-origin iframe of a fixed size. It drives the demo only through what the demo exposes (`globalThis.reader.view`): `goTo`, `next`, `prev`, `renderer.render()`, the `relocate` and `load` events, and the iframe size. It logs results to the server.
- **Viewport:** 390×844 iframe (portrait, so one column; the column is 335×748). iOS: 382×556 (the whole Safari viewport on the folded Duo).

| Engine | Version | Host |
|---|---|---|
| Chromium | Google Chrome 156.0.8078.74, `--headless=new` | macOS 27.0.1 |
| WebKit (macOS) | Safari/WebKit 27.0.1 (`AppleWebKit/605.1.15`), plain `WKWebView` with inactive throttling off | macOS 27.0.1 (26A434) |
| WebKit (iOS) | Mobile Safari, `Version/27.0` | iPhone Duo simulator, iOS 27.1 |
| Firefox 151 | **Not tested.** Its content processes can't start inside this session's sandbox. | — |

### Pride and Prejudice (Gutenberg 1342, `.epub3.images`)

The section index is 1 (`/6/4`). Pages at 390×844:

| | Chrome 156 | macOS WebKit | iOS Safari (382×556) |
|---|---|---|---|
| Page after the dedication | p11 has text (PREFACE). No blank page. | **p11 blank**, CFI `epubcfi(/6/4!/4)` | **p11 blank**, CFI `epubcfi(/6/4!/4)` |
| `renderer.render()` on that page | stays (normal page) | **jumps to p1** | **jumps to p1** |
| Window resize by 1px and back | stays | **jumps to p1** | **jumps to p1** |
| Restore the saved CFI | stays | **opens p1** | **opens p1** |

Same results at `6b11e17` (WebKit, P&P p11: blank, `epubcfi(/6/4!/4)`, every disturbance goes to p1).

### Synthetic EPUB, every engine

The same steps on the test EPUB (next section) jump the same way in Chrome and WebKit. See the `main` rows in the table under "Fix verification".

## 3. Minimal trigger

`Scripts/make-blank-page-epub.py` writes `blank-page-test.epub`. It contains only placeholder text written for this test (CC0) and is deterministic (byte-identical on every run, SHA-256 `9a3c8c2d…49c10`).

| Section (index) | Markup | Blank page at 390×844 |
|---|---|---|
| 0 `control` | plain paragraphs | none (control) |
| 1 `tall-block` | text, then `<div style="height: 3000px"></div>`, then text | **p2–p4, Chrome and WebKit** |
| 2 `double-break` | `.blk { page-break-after: always }` followed by `h2 { page-break-before: always }` (P&P's pattern) | **p3, WebKit only.** Chrome merges the two breaks. |
| 3 `vh-title` | `.titlepage { height: 100vh }` followed by `h2 { page-break-before: always }` | **p2, Chrome and WebKit** |
| 4 `control-end` | plain paragraphs | none |

**So the cause is general: any page with no visible node.** The position loss doesn't depend on P&P or on WebKit. Only whether a blank page appears in the first place depends on the book and the engine. There are several ordinary sources:

- **A block that spans whole columns with nothing else in them.** A tall spacer or fixed-height block, for example. Every engine.
- **`height: 100vh` title or cover blocks.** foliate rewrites `vh` to `innerHeight`, which is taller than a column (by the paginator's top and bottom margins). The block's tail then gets a column of its own if the next element has a forced break. Every engine. (This rewrite is a separate small foliate quirk. It's mentioned here, not reported.)
- **Adjacent forced breaks in WebKit.** `page-break-after` on one block plus `page-break-before` on the next sibling leaves an empty column. All eight variants of that markup in `blank-page-variants.epub` reproduce it in WebKit and none do in Chrome, so neither the image, the margin nor the page-number spans matter. Project Gutenberg's ebookmaker CSS (`h2 { page-break-before: always }` plus `.blk`/`.chapter` blocks with `page-break-after`) produces this all the time. Any WebKit-based reader will hit it. That probably includes GNOME Foliate on WebKitGTK, but I haven't tested it.
- **A leading forced break in WebKit.** This one is benign. WebKit gives every Alice chapter a blank first page. On page 1 the body fallback happens to be correct, so there's no position loss. This is the case foliate#1179 mentions.

Two gotchas from building the trigger:

- foliate rewrites `page-break-*` to `-webkit-column-break-*` **only in CSS files**, not in `<style>` elements or `style` attributes. Inline page breaks do nothing in columns.
- In portrait the paginator shows one column per page, so a single empty column is a blank page. In a two-column spread both columns must be empty. At 1280×800, spread 2 of the tall-block section is fully blank in both engines, and it's tested below.

## 4. Mechanism (upstream `main` `78914ae`, `paginator.js`)

1. `getVisibleRange()` (lines 94–151) walks the section and accepts elements that are entirely inside the page and text nodes that intersect it. On a blank page it accepts nothing: the only boxes there are fragments of blocks that span several columns, plus `<body>` itself (the walker root, never tested). So `from = nodes[0] ?? doc.body` (line 128) gives a collapsed range at `(body, 0)`.
2. `#afterScroll()` (line 952) stores that range in `this.#anchor` (line 957) and dispatches `relocate` with it. `view.js` turns it into the CFI `epubcfi(/6/N!/4)`.
3. `View.expand()` ends with `onExpand` → `#scrollToAnchor(this.#anchor)` (line 673), and `Paginator.render()` (line 754) ends with `#scrollToAnchor(this.#anchor)`. The `uncollapse()` helper turns `(body, 0)` into the body's first child, `getClientRects()[0]` is on the section's first page, and the view scrolls there.

`expand()` runs from the body's `ResizeObserver` (line 211), on `fonts.ready` (lines 278 and 1116) and on `setStyles()`. `render()` runs from the container's `ResizeObserver` (line 430) and on attribute changes. Any of them while you're on a blank page moves you to the section start.

### Host-triggered loop

To check the 1a explanation, the driver can add a relocate listener that shrinks the iframe by 14px per 24 characters of CFI, from 1 to 3 lines, the way the spike's debug strip does. With that:

| Run | `main` | patched |
|---|---|---|
| WebKit, P&P section 1, 13 page turns from p1 | p10 → blank p11 → **back to p1** within one turn, then p2, p3… again. You can never page past the dedication. This is exactly the 1a symptom. | p10 → p11 (blank, stays) → p12 PREFACE → p13 → p14 |
| Chrome, test EPUB, tall-block, 8 page turns | every turn: p1 → blank p2 → **back to p1**. It never gets past p1. | p2, p3, p4 (blank, each stays) → p5 → p6 → p7 → next section |

So the loop needs nothing Octavo-specific, only a host whose layout depends on the location. That's common: status lines, progress labels, and toolbars that change size.

## 5. The fix

Two changes, both only on pages where nothing is visible:

- **Location:** report a collapsed range at the start of the first node after the page, which is where reading resumes, instead of the section start. If nothing follows (a blank last page), use the end of the last element. Restoring that CFI opens the next page that has content.
- **Anchor:** anchor to the page itself as a fraction. This is exactly the inverse of what `#scrollToAnchor()` already does with a number. There's no content on the page to anchor to, and anchoring to the next node would move the reader one page on every re-layout. With a host like the spike strip above, that would make paging *backward* across a blank page bounce forward again.

Pages with any visible node take exactly the same code path as before, and their range is identical.

One side effect: when paging past a section's last page, the paginator first scrolls onto its trailing padding page and fires a `relocate` (fraction 1) before it loads the next section. That transient event used to carry the old section's bare `<body>` CFI. With the patch it carries the end of the section's last element. It's replaced right away either way.

```diff
diff --git a/paginator.js b/paginator.js
index 7980c20..309560d 100644
--- a/paginator.js
+++ b/paginator.js
@@ -124,9 +124,12 @@ const getVisibleRange = (doc, start, end, mapRect) => {
     for (let node = walker.nextNode(); node; node = walker.nextNode())
         nodes.push(node)
 
+    // nothing is visible, e.g. on a blank page left by column breaks
+    if (!nodes.length) return null
+
     // we're only interested in the first and last visible nodes
-    const from = nodes[0] ?? doc.body
-    const to = nodes[nodes.length - 1] ?? from
+    const from = nodes[0]
+    const to = nodes[nodes.length - 1]
 
     // find the offset at which visibility changes
     const startOffset = from.nodeType === 1 ? 0
@@ -150,6 +153,35 @@ const getVisibleRange = (doc, start, end, mapRect) => {
     return range
 }
 
+// for blank pages: a collapsed range at the start of the first node after
+// `end`, or at the end of the last element if there is nothing after it
+const getRangeAfter = (doc, end, mapRect) => {
+    const acceptNode = node => {
+        const name = node.localName?.toLowerCase()
+        if (name === 'script' || name === 'style') return FILTER_REJECT
+        if (node.nodeType === 1) {
+            const { left, right } = mapRect(node.getBoundingClientRect())
+            if (right <= end) return FILTER_REJECT
+            if (left >= end) return FILTER_ACCEPT
+        } else if (node.nodeValue?.trim()) {
+            const range = doc.createRange()
+            range.selectNodeContents(node)
+            if (mapRect(range.getBoundingClientRect()).left >= end) return FILTER_ACCEPT
+        }
+        return FILTER_SKIP
+    }
+    const node = doc.createTreeWalker(doc.body, filter, { acceptNode }).nextNode()
+    const range = doc.createRange()
+    if (node) {
+        range.setStart(node, 0)
+        range.collapse(true)
+    } else {
+        range.selectNodeContents(doc.body.lastElementChild ?? doc.body)
+        range.collapse()
+    }
+    return range
+}
+
 const selectionIsBackward = sel => {
     const range = document.createRange()
     range.setStart(sel.anchorNode, sel.anchorOffset)
@@ -943,18 +975,28 @@ export class Paginator extends HTMLElement {
         await this.#scrollToPage(newPage + 1, reason)
     }
     #getVisibleRange() {
-        if (this.scrolled) return getVisibleRange(this.#view.document,
-            this.start + this.#margin, this.end - this.#margin, this.#getRectMapper())
+        const doc = this.#view.document
+        const mapRect = this.#getRectMapper()
         const size = this.#rtl ? -this.size : this.size
-        return getVisibleRange(this.#view.document,
-            this.start - size, this.end - size, this.#getRectMapper())
+        const [start, end] = this.scrolled
+            ? [this.start + this.#margin, this.end - this.#margin]
+            : [this.start - size, this.end - size]
+        const range = getVisibleRange(doc, start, end, mapRect)
+        return range ? { range } : { range: getRangeAfter(doc, end, mapRect), blank: true }
+    }
+    // the inverse of what `#scrollToAnchor()` does with a fraction
+    #getPageFraction() {
+        if (this.scrolled) return this.start / this.viewSize
+        const textPages = this.pages - 2
+        return textPages > 1 ? (this.page - 1) / (textPages - 1) : 0
     }
     #afterScroll(reason) {
-        const range = this.#getVisibleRange()
+        const { range, blank } = this.#getVisibleRange()
         this.#lastVisibleRange = range
         // don't set new anchor if relocation was to scroll to anchor
         if (reason !== 'selection' && reason !== 'navigation' && reason !== 'anchor')
-            this.#anchor = range
+            // a blank page has no content to anchor to, so anchor to the page
+            this.#anchor = blank ? this.#getPageFraction() : range
         else this.#justAnchored = true
 
         const index = this.#index
```

Applies cleanly to `6b11e17` (Octavo's pin), where `paginator.js` is byte-identical to `main`.

Alternatives considered:

- **Fall back to the previous or next node for both the CFI and the anchor.** Simpler, but every re-layout moves one page, and host-triggered re-layouts loop (above).
- **Keep the previous anchor.** Same one-page drift. And after a `goTo` straight onto a blank page, the "previous" anchor is unrelated.
- **CSS normalization only** (rewrite `-webkit-column-break-*: always` to `break-*: column`, the 1a experiment). That fixes WebKit's leading blank column but not the double break. It can't help tall blocks or `100vh` titles, and it doesn't fix the anchor. It's still worth doing in Octavo to reduce blank pages, but separately.

## 6. Fix verification

### Disturbing a blank page

Land on the blank page by paging forward from the section start, then do one disturbance, then read the page and CFI. `STAYED` means same section and page. "Restore" means saving `lastLocation.cfi`, going to another section, then `goTo(cfi)`.

| Case | Engine | Version | Landed CFI | render() | resize 1px | body resize | restore CFI | next, prev, render |
|---|---|---|---|---|---|---|---|---|
| tall-block p2 | Chrome | main | `/6/4!/4` | p1 | p1 | p1 | p1 | p1 |
| tall-block p2 | Chrome | patched | `/6/4!/4/10[after-spacer]` | stayed | stayed | stayed | p5 (next text) | stayed |
| tall-block p2 | WebKit | main | `/6/4!/4` | p1 | p1 | p1 | p1 | p1 |
| tall-block p2 | WebKit | patched | `/6/4!/4/10[after-spacer]` | stayed | stayed | stayed | p5 (next text) | stayed |
| vh-title p2 | Chrome | main | `/6/8!/4` | p1 | p1 | p1 | p1 | p1 |
| vh-title p2 | Chrome | patched | `/6/8!/4/4[after-title]` | stayed | stayed | stayed | p3 (next text) | stayed |
| vh-title p2 | WebKit | main | `/6/8!/4` | p1 | p1 | p1 | p1 | p1 |
| vh-title p2 | WebKit | patched | `/6/8!/4/4[after-title]` | stayed | stayed | stayed | p3 (next text) | stayed |
| double-break p3 | WebKit | main | `/6/6!/4` | p1 | p1 | p1 | p1 | p1 |
| double-break p3 | WebKit | patched | `/6/6!/4/8[next-heading]` | stayed | stayed | stayed | p4 (next text) | stayed |
| P&P p11 | WebKit | main | `/6/4!/4` | p1 | p1 | p1 | p1 | p1 |
| P&P p11 | WebKit | patched | `/6/4!/4/22` (the PREFACE `h2`) | stayed | stayed | stayed | p12 (PREFACE) | stayed |
| P&P p11 (has text in Chrome) | Chrome | main and patched | identical range CFI | stayed | stayed | stayed | stayed | stayed |
| P&P p11 (382×556) | iOS Safari | main | `/6/4!/4` | p1 | p1 | p1 | p1 | p1 |
| P&P p11 (382×556) | iOS Safari | patched | `/6/4!/4/22` | stayed | stayed | stayed | p12 (PREFACE) | stayed |
| P&P p11 | WebKit | pin `6b11e17` | `/6/4!/4` | p1 | p1 | p1 | p1 | p1 |
| tall-block spread 2 (1280×800, two columns) | Chrome and WebKit | main | `/6/4!/4` | p1 | p1 | p1 | p1 | p1 |
| tall-block spread 2 (1280×800, two columns) | Chrome and WebKit | patched | `/6/4!/4/10[after-spacer]` | stayed | stayed | stayed | p3 (next text) | stayed |
| tall-block, `flow="scrolled"`, viewport inside the spacer | WebKit | main | `/6/4!/4` | top of section | top | top | top | top |
| tall-block, `flow="scrolled"`, viewport inside the spacer | WebKit | patched | `/6/4!/4/10[after-spacer]` | stayed | stayed | stayed | next text | stayed |

- "Body resize" appends and removes a 1px `div`, which is what a late image or font load does to the body.
- In every run, "next" from the blank page goes to the next page and "prev" comes back, in both versions. Plain paging works upstream; only re-layout and restore lose the position.
- Chrome logs "ResizeObserver loop completed with undelivered notifications" during the resize test with both versions. It's benign, not related, and appears whether or not the patch is applied.

### No-regression check

For every linear section of the five sample books and the test EPUB: `goTo(section)`, then the first 10 pages (`next()`). The CFI is recorded on each page, for `main` and for the patched build, in Chrome and WebKit at 390×844. Pages are paired by section and step.

| Book | Engine | Pages compared | Same CFI | Blank in `main` | CFI differs | Layout differs |
|---|---|---|---|---|---|---|
| Alice | Chrome | 127 | 127 | 0 | 0 | 0 |
| Alice | WebKit | 131 | 119 | 12 (each chapter's p1) | 0 | 0 |
| Frankenstein | Chrome | 260 | 260 | 0 | 0 | 0 |
| Frankenstein | WebKit | 270 | 241 | 29 (each chapter's p1) | 0 | 0 |
| Moby-Dick | Chrome | 121 | 121 | 0 | 0 | 0 |
| Moby-Dick | WebKit | 121 | 121 | 0 | 0 | 0 |
| Pride and Prejudice (+ first 40 pages of section 1) | Chrome | 81 + 40 | 121 | 0 | 0 | 0 |
| Pride and Prejudice (+ first 40 pages of section 1) | WebKit | 81 + 40 | 120 | 1 (s1 p11) | 0 | 0 |
| Sherlock Holmes | Chrome | 135 | 135 | 0 | 0 | 0 |
| Sherlock Holmes | WebKit | 135 | 123 | 12 (each story's p1) | 0 | 0 |
| Test EPUB | Chrome | 33 | 29 | 4 | 0 | 0 |
| Test EPUB | WebKit | 34 | 29 | 5 | 0 | 0 |
| **Total** | | **1,609** | **1,546** | **63** | **0** | **0** |

**Every page that had visible content got a byte-identical CFI with the patch: 1,546 of 1,546.** Each of the 63 blank pages changed from the bare section (`/6/N!/4`) to the next element, for example `/6/6!/4/2[pgepubid00003]`, the chapter heading after WebKit's leading blank column. Page counts are identical in all pairs, so the patch doesn't change layout. (The 40-page P&P runs overlap the first 10 pages of the general P&P run.)

## 7. What would falsify this

- **The maintainer considers falling back to the section start intended.** Unlikely: `#anchor` exists to keep the position across re-layouts, and on blank pages it does the opposite.
- **If real books rarely produced blank pages, the bug would matter less.** Measured here: P&P in WebKit, every Alice chapter in WebKit (benign page 1), plus generic patterns (tall blocks, `100vh` titles) that occur in every engine.
- **A result that only holds in my driver.** It uses only the public API of the demo's `reader.view`. The same jumps show with a real window resize. Steps a maintainer can repeat by hand are in the draft issue.
- **Engines.** Firefox wasn't tested. Its `getBoundingClientRect` quirks are handled elsewhere in `getVisibleRange`, and the new helper uses the same rect calls, but this is unverified.
- **Not tested:** RTL and vertical writing modes (the new helper uses the same `mapRect` as `getVisibleRange`). Scrolled mode and two-column spreads were tested only on the synthetic tall block.

## 8. What this means for Octavo (owner decisions)

- Carrying the patch locally means `ReaderWeb/foliate-js` is no longer unmodified. `PINNED.md` would need to record the patch, and the "byte-identical" claim would change. It's the only way to fix the spike loop and the CFI before upstream merges something.
- Even with the patch, the spike's debug strip re-lays out the reader on every relocate. Pin the strip's height, or move it out of the reading area, before judging paging behavior.
- With the patch, blank pages report the next content's CFI, which is fine to sync. Without it, don't push bare `/6/N!/4` CFIs to BookOrbit.
- Separately, Gutenberg books will show blank pages in WebKit (the double break, and the leading break on every chapter). Normalizing CSS in the bridge reduces them; it's a reading-quality issue, not a position-loss one.

## 9. Draft issue (for Adam to review and post)

> **Title:** Paginator: on a blank page the location falls back to the section's `<body>`, so a re-layout or a restore jumps to the section's first page

When no node is visible on the current page, `getVisibleRange()` falls back to `doc.body` (`const from = nodes[0] ?? doc.body`, [paginator.js#L128](https://github.com/johnfactotum/foliate-js/blob/78914aef4466eb960965702401634c2cb348e9b1/paginator.js#L128)). The resulting collapsed range at the start of `<body>` is used in two places:

1. It's sent with `relocate`, so `view.lastLocation.cfi` is the bare section, e.g. `epubcfi(/6/4!/4)`. An app that saves it and restores it later opens the section's first page.
2. `#afterScroll()` stores it as `#anchor`. The next `render()` or `expand()` calls `#scrollToAnchor()`, which scrolls to the section's first page. That happens on a resize, `setStyles()`, `fonts.ready`, or the body's `ResizeObserver` (late image loads).

So if you're on a blank page and you resize the window, or anything else makes the paginator re-lay out, you jump back to the start of the chapter.

**Where blank pages come from.** All three are in the attached EPUB:

- A block that spans whole columns with nothing else in them, e.g. a tall empty block. Any engine.
- A `height: 100vh` title block followed by a forced break. The paginator rewrites `vh` to `innerHeight`, which is taller than a column, so the block's tail gets a column of its own. Chromium and WebKit.
- In WebKit only: `page-break-after: always` on one block and `page-break-before: always` on the next sibling leave an empty column between them. Chromium merges the two breaks into one. Project Gutenberg's CSS does this a lot. In the illustrated *Pride and Prejudice* (Gutenberg #1342), the page after the dedication is blank in Safari (single-column layout).

**Steps** (demo reader at 78914ae; Chrome 156 or Safari 27)

1. Serve the repo and open `reader.html?url=blank-page-test.epub` in a portrait window of about 390×844, so you get one column.
2. Open "Tall empty block" from the TOC and turn one page. The page is blank.
3. In the console, `reader.view.lastLocation.cfi` is `epubcfi(/6/4!/4)`.
4. Resize the window slightly, or run `reader.view.renderer.render()`. The view jumps to the first page of "Tall empty block".
5. Or go to another chapter and run `reader.view.goTo('epubcfi(/6/4!/4)')`. That also opens the first page, not the blank page.

**Expected:** the view stays on the blank page, and the reported location is next to it.

I see the same results in Chrome 156, Safari/WebKit 27.0.1 on macOS, and Safari on iOS 27.1 (Simulator), at `main` and at 6b11e17.

This isn't #11 (a stale anchor while content changes) or johnfactotum/foliate#1179 (a blank first page; fixed in b0a869b), though both are nearby.

I have a small patch for this and can open a PR if you'd like one.

*Attachment: `blank-page-test.epub` (5 KB, placeholder text only, CC0). It's generated by a short Python script, which I can share too.*

## 10. Draft PR (for Adam to review and open)

> **Title:** paginator: keep the position on blank pages

Fixes #<issue>.

When nothing is visible on the current page, `getVisibleRange()` used to return a collapsed range at the start of `<body>`. That range became both the reported location and the anchor, so a re-layout or a restore went back to the section's first page.

This PR changes three things:

- `getVisibleRange()` now returns `null` when no node is visible.
- In that case, `relocate` reports a collapsed range at the start of the first node after the page, which is where reading resumes. If nothing follows, it uses the end of the last element. Restoring that CFI opens the next page that has content.
- The paginator anchors to the page itself, as a fraction (`#getPageFraction()`, the inverse of what `#scrollToAnchor()` does with a number). There's no content on a blank page to anchor to. So `render()` and `expand()` now keep the blank page.

I didn't anchor to the next node because then every re-layout would move the reader forward by a page. And if a host re-lays out on every `relocate` (say a status line whose height depends on the location), paging backward across a blank page would keep bouncing forward.

Pages with any visible node go through the same code as before and get the same range. One side effect: when you page past the end of a section, the paginator briefly scrolls onto its trailing padding page and fires a `relocate` (fraction 1) there. That event now carries the end of the section's last element instead of `<body>`.

**Testing**, with the demo reader in Chrome 156 and WebKit 27.0.1 (macOS), plus iOS 27.1 Safari for one book:

- On blank pages in the attached EPUB and in Pride and Prejudice (WebKit), I tried `render()`, a 1px window resize, a body resize, and `goTo(lastLocation.cfi)` from another section. Before this patch each one jumped to the section start. With it, the first three stay on the blank page, and the restore opens the next page with content.
- I compared CFIs before and after on the first 10 pages of every section of five Project Gutenberg books and the test EPUB, in both engines. Every one of the 1,546 pages that had visible content got a byte-identical CFI. Only the 63 blank pages changed.

**Not tested:** Firefox, RTL and vertical writing modes. The new helper uses the same rect mapper as `getVisibleRange()`, so I'd expect them to behave the same.

## Reproducing this

The scratch tooling (driver page, static server, WKWebView runner, summarizers) and the page-by-page comparison (`compare.txt`) are in `docs/notes/foliate-blank-page/`. Re-run it to re-check patch 0001 when foliate-js is updated. `Scripts/make-blank-page-epub.py` regenerates the EPUBs: `--variants` writes the eight double-break variants. The raw results log (600 KB) was not committed.

**The page-by-page comparison, step by step** (worked out and run in #17, 2026-11-01: byte-identical to `compare.txt` in about 13 minutes). `R` is the repo, `SP` a new, empty scratch folder outside it:

```bash
mkdir -p $SP/books $SP/out $SP/tools $SP/driver
git clone https://github.com/johnfactotum/foliate-js $SP/main
git -C $SP/main checkout 6b11e1744346f60504b727984f7d42f0fef3ab54
rsync -a --exclude .git $SP/main/ $SP/patched/
for p in $R/ReaderWeb/foliate-js/patches/*.patch; do patch -s -p1 -d $SP/patched < $p; done
cmp $SP/patched/paginator.js $R/ReaderWeb/foliate-js/paginator.js      # must match
cp $R/docs/notes/foliate-blank-page/tools/{*.py,batch.sh,wkrun.swift} $SP/tools/
cp $R/docs/notes/foliate-blank-page/tools/driver/* $SP/driver/
cp $R/SampleBooks/*.epub $SP/books/
python3 -I $R/Scripts/make-blank-page-epub.py $SP/books/blank-page-test.epub   # pass a path: the default writes into SampleBooks/
swiftc -O $SP/tools/wkrun.swift -o $SP/tools/wkrun
python3 -I $SP/tools/server.py $SP 8765 $SP/out/log.jsonl &               # serves main/, patched/, books/, driver/
# WebKit: a book's main and patched lines together, books one after another.
# Chrome: one line at a time (run.py stops when its label appears in the log).
for book in $(cut -d' ' -f2 $R/docs/notes/foliate-blank-page/tools/dump-wk.txt | sed 's/wk-[a-z]*-dump-//' | sort -u); do
  grep -- "-dump-$book " $R/docs/notes/foliate-blank-page/tools/dump-wk.txt | $SP/tools/batch.sh
done
while read -r line; do echo "$line" | $SP/tools/batch.sh; done < $R/docs/notes/foliate-blank-page/tools/dump-chrome.txt
python3 -I $SP/tools/compare.py $SP/out/log.jsonl > $SP/out/compare.txt
cmp $SP/out/compare.txt $R/docs/notes/foliate-blank-page/compare.txt
```

`dump-wk.txt` and `dump-chrome.txt` hold the exact labels and queries (`interval=150`, `per=10`, and the P&P deep run `from=1&to=2&per=40`). Labels must stay as they are for a byte-identical result: `compare.py` prints them, and two Chrome labels (`frankenstein2`, `pp-s1-deep2`) keep the original run's retry names. `wkrun` opens visible windows while it runs.
