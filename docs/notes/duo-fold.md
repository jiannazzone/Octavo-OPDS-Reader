# Duo fold: one re-layout per fold, cross-fade, book mode (#5)

Issue #5, decisions 9 and 11 in `docs/design/direction.md`. Written 2026-11-01 on 'Octavo Fold Duo' (387F2531-EF32-4A5A-9987-8431E2D55A91, iPhone Duo, iOS 27.1 simulator, Xcode 27.2), driven with Hinge 0.3.0. Raw data, tools and videos are in `duo-fold/` next to this file.

## Summary

- **One re-layout per fold** (was 4–5). foliate re-renders once, and Swift gets one relocation instead of 11–13. Open ↔ half-open still costs nothing.
- **No wrong layout on screen.** Before, unfolding showed the old page, then a single column across the whole inner display for about 0.8 s, then the spread; folding flashed old content for about 45 ms. Now the page holds still under a snapshot of itself and fades into the settled layout in 0.3 s.
- **Positions unchanged.** The same CFIs as before in every measured move; the fold-continuity runs are in section 5.
- **Book mode** (decision 9): from 60° to 150°, flat from 160° up, and once in book mode it lasts until the reader lies flat or folds. Each half of the spread turns its way; a tap in the side column asks for the controls (the hook for #17). A spine shadow, on by default, sits in the gap between the pages.
- **Bug fixed on the way:** after a cold launch the model laid out for SwiftUI's frame instead of the page's size, so an unfolded spread came up 84 pt off-centre until the first fold (section 6).
- No foliate patch. `bridge.js` relies on three foliate internals, now listed in `ReaderWeb/foliate-js/PINNED.md`.

## 1. What a fold cost before

Moby-Dick at 30%, eight hinge moves, counted in the page (`duo-fold/tools/instrument.js`: foliate renders, relocations, resizes, layout attributes, painted states) and in the app (`spike-events.jsonl`). Raw: `duo-fold/runs/main.jsonl`.

| | Renders | Relocations (foliate) | Relocations reaching Swift |
|---|---|---|---|
| Unfold | 4 | 11 | 11 |
| Fold | 4–5 | 11–13 | 11–13 |
| Open ↔ half-open | 0 | 0 | 0 |

Where they came from (`duo-fold/tools/timeline.py`):

- **Unfold.** The hinge reports `.fullyOpen` first; the reader is still the outer display's size, so the layout stays one page. The page then resizes to 951×493, and foliate's own `ResizeObserver` renders one wide column (painted: the inner display shows it). Swift then sends the spread: `max-inline-size` changing renders, the explicit `render()` renders, and the `ResizeObserver` renders once more. Each render re-scrolls to the anchor two or three times.
- **Fold.** The hinge reports `.closed` while the reader is still on the inner display, so Swift sends one page immediately: two renders of one column 951 wide on the inner display. Then the page resizes to 466×502 and foliate renders twice more.

## 2. What it costs now

Raw: `duo-fold/runs/prototype.jsonl` (spike) and `duo-fold/runs/build.jsonl` (this build, instant moves and 1 s sweeps).

| | Renders | Relocations (foliate) | Relocations reaching Swift |
|---|---|---|---|
| Unfold, fold, half-open → fold; instant or a 1 s sweep | 1 | 3 | 1 |
| Open ↔ half-open | 0 | 0 | 0 |

Timings from the hinge report: on a quiet simulator the page resizes after 100–300 ms, the snapshot is ready after 25–160 ms, and the layout goes in 120 ms after the resize; then the 0.3 s fade. The final run was made with a load average of 13–21 (other projects' simulators): resizes after 112–2108 ms, snapshots after 67–643 ms, still one render each. Videos at half speed: `duo-fold/videos/unfold-before-after.mp4`, `fold-before-after.mp4`, and `unfold-sweep-after.mp4` (a 1 s hinge sweep, where the cross-fade shows best). The simulator lights the inner display with its own fade from black, which hides most of an instant unfold.

## 3. How

- **The hinge starts a batch** when it moves between folded and not folded (`ReaderModel.beginFold`). The model asks the page to hold (`bridge.js` `hold`: the `foliate-view` keeps its pixel size, so the window's resize doesn't reach foliate, and relocations are kept back), and takes a snapshot of the page (`WebPage.exported(as: .image(afterScreenUpdates: false))`).
- **`FoldBatch`** (pure, tested in `FoldBatchTests`) decides when to lay out: once the page has reported its new size and 120 ms have passed with no other input, or 5 s after the hinge regardless. Each input moves the deadline. A hinge that moves back before the page has resized ends the batch at once (nothing changed, so nothing renders); moving across again after a resize waits for the next one. The 5 s cap only covers a display that never changes; both numbers are marked for tuning on a real device. (The spike's cap was 2 s. On the loaded simulator, with a load average around 20 from other projects' simulators, 1 s sweeps moved the scene up to 3.5 s after the hinge, so the batch laid out early: 3 renders and one wide column on screen. Hence 5 s, and the immediate end on a flap instead of relying on the cap.)
- **`setLayout` renders once.** foliate re-renders by itself on a `max-inline-size` change and on its `ResizeObserver`; `applyLayout` shadows `render` on the paginator instance with a no-op while it sets the attributes and size, waits a frame for the `ResizeObserver`, then renders once. It then waits for the paginator to stop relocating (`settle`) and posts only the last relocation.
- **The cover** (`ReaderFoldCover`, `ReaderFoldCoverView`) draws the snapshot at its own size at the page's top-left corner, over the page's background colour (sampled from the snapshot), and fades out over 0.3 s once `setLayout` resolves. Unfolding, the old page sits on the left half and the spread fades in around and over it; folding, the outer display shows the spread's left part, which fades into the single page. Mid-fade, the old lines show faintly through the new ones. Approved as is (decision 11).
- **Races handled:** a snapshot that arrives after the layout is dropped (the layout waits up to 300 ms for it); folding back while a layout is still settling keeps the new hold in place and lets that fold fade the cover.

## 4. Book mode

`ReaderHinge` (pure, tested in `ReaderHingeTests`) tracks the posture, the angle and book mode; `BookModeThresholds` holds the numbers in one place, marked for tuning on a real device.

| From | Angle | Result |
|---|---|---|
| Flat | ≤ 150° | Book mode |
| Book mode | 150°–160° | Stays (buffer, no flicker) |
| Book mode | ≥ 160° | Flat |
| Book mode | below 60°, down to the fold | Stays (Adam, 2026-11-01: book mode lasts until the phone folds) |
| Opening from folded | 60°–150° | Book mode |
| Any | folded, or no hinge | Not book mode |

- Repeated hinge reports change nothing: `ReaderWebView` skips callbacks whose old and new values are equal, and `ReaderHinge.update` returns an empty change for a repeat.
- **Taps** (`bridge.js` `setTapMode`, sent by Swift as `ReaderTapMode`): in book mode a tap left of the spine goes back and right of it goes forward (foliate's `goLeft`/`goRight`, so a right-to-left book turns the natural way); a tap in the side column, where the page runs under it (x ≥ SwiftUI's width, 867 pt unfolded), posts `tap` with zone `column`. Flat keeps 30% / 40% / 30%. Taps outside the section's frame (the page margins and the column) are now detected too; before, they did nothing.
- **Controls hook:** `ReaderModel.onControlsTap(zone)` is called for a middle tap (flat) and a column tap (book mode). #17 shows the controls from it.
- **Spine shadow** (`ReaderSpineShadow`): a SwiftUI gradient over the gap between the pages (66.6 pt on the Duo), darkest at the fold, drawn only in book mode and only over the page, never in the book's own content. Setting `reader.bookModeShadow` (`ReaderSettings`), on by default; the Customize toggle is #18. Screenshot: `duo-fold/screenshots/book-mode-90.png`.
- Checked in the simulator at 90°: taps at 430 pt and 520 pt (both in the middle zone when flat) went back and forward; a tap at 910 pt posted `column` and didn't turn the page. Video (real time, idle stretches cut): `duo-fold/videos/book-mode.mp4`: a 1 s sweep from flat to 90° (the shadow appears as the angle passes 150°), a tap on each half, a column tap (the debug strip shows `controls: column`), and the sweep back to flat.

Simulator observations (angles must be set on a device anyway):

- Angles come in uneven steps of 1.9–4.7° (requested 150, 155, 158, 162 read 146.7, 151.4, 154.2, 158; 58, 60, 62 read 59.8, 61.7, 63.6).
- **Closing**, the reader stays on the inner display down to 33.3°, so book mode holds all the way down.
- **Opening in small steps** (5° every 3 s from 0°), the status stays `.closed` and the reader stays on the outer display up to 156°, switching at about 165° (flat, so no book mode until closed back to 150°). A jump from 62° to 120° switched straight away. Whatever angle the switch happens at, book mode follows the posture and angle at that moment.

## 5. Position across folds

The 2b fold-continuity runs (`duo-spreads/tools/fold-run.py`, eight moves each: open, close, half, close, open, half, open, close) with this build. Raw: `duo-fold/runs/continuity/`.

Nine runs, 72 hinge moves, five books: the eight origins of 2b plus the P&P dedication page. Totals: **exact 27, contains 30, contains (CFI only) 10, lost 5**, the same picture as 2b (exact 21, contains 30, CFI only 5, drift 3, lost 5):

| | Folds back to one page | Opens / half-opens |
|---|---|---|
| Moby-Dick 30%, 90%; P&P 50%; Frankenstein 50%; Alice 60%; P&P PREFACE | exact, 18 of 18 | contains, 30 of 30 (by CFI and first words) |
| Sherlock 85% | exact, 3 of 3 | contains by CFI, 5 of 5 (the origin's first line is the spread's last, as in 2b) |
| P&P dedication (an illustration, no text) | exact, 3 of 3 | contains by CFI, 5 of 5 |
| P&P blank page after the dedication | exact, 3 of 3 (2b: one page early) | the dedication spread, 5 of 5, which doesn't reach the PREFACE (as in 2b) |

- No creep: each origin's CFI is identical after every fold, and every unfold of a run shows the same spread.
- The blank page anchors by its page fraction (patch 0001), as 2b explains; its unfolds land on the dedication spread as before. Its folds now come back exactly, where 2b came back one page early, probably because the fraction is now mapped once instead of through several intermediate layouts (not verified further).
- No text touched the fold region in any of the 35 open or half-open states with text (the left page's text ends at x 442–443, the right page's starts at 509–510, around the fold at 455.5–495.5).
- The 2b scripts reach the P&P origins by page turns from the section start: 9 turns now land on the dedication, 10 on the blank page and 11 on the PREFACE (one more than 2b's counts; not investigated, since the origins themselves match 2b's CFIs).
- **The simulator stuck once:** during the first attempt, after a long series of small hinge steps (section 4), the hinge reported 0° while the inner display stayed on, so the scene never moved and the last fold of the first run measured nothing. Rebooting the simulator fixed it; all nine runs above are from after the reboot.

`duo-fold/runs/continuity/table.md` has every move.

### Patch 0001's page-by-page comparison

Re-run as `PINNED.md` asks, although this branch changes no foliate-js file. Upstream `6b11e17` (with its demo reader) against upstream plus our patches (applying `patches/*.patch` reproduces our `paginator.js` byte for byte), every linear section's first 10 pages of the five books and the test EPUB, at 390×844, in WebKit (a macOS `WKWebView`) and headless Chrome: 1,609 pages. The output is **identical to `foliate-blank-page/compare.txt`, byte for byte**: no CFI differs on a page with content, no layout differs. It took about an hour, mostly the Chrome runs, which had to go one at a time on the loaded Mac.

## 6. Cold launch into the reader

After a cold launch straight back into the reader, the model laid out for SwiftUI's frame (867×411 unfolded) instead of the page (951×493): the spread came up with an 84 pt left inset and its gap off the hinge, until the next fold. Folded, the model had 382×420 against the page's 466×502 (harmless there: one column).

Cause, traced in the page: WebKit lays the page out at its full size from the start (the root element is 951×493 at t = 8 ms), but `innerWidth` still reports the SwiftUI frame's 867×411, and 25 ms later corrects it with only a `visualViewport` resize, no window `resize`. The bridge read `innerWidth` on load and on `resize`, so Swift never heard the real size. The bridge now reports the root element's size (which the `foliate-view`, fixed to the viewport, fills) and watches it with a `ResizeObserver`. Checked: cold launches unfolded (twice) and folded now lay out at 951×493 and 466×502, the spread centred on the hinge, no text in the fold region.

The #4 session also saw a cold launch where the reader got no hinge and no geometry at all (`posture: noHinge`, `geometry: null`) until the next hinge move, on its own simulator with `main`'s code. Not reproduced here: in six cold launches (folded and unfolded) the hinge and geometry arrived within 0.5 s of the reader appearing, after the scene became active. The likely cause is the scene not reaching the foreground (both callbacks come from SwiftUI on screen); it needs exact steps to chase further.

## 7. Open risks

- **foliate internals** (listed in `PINNED.md`, step 4): the paginator calls `this.render()` from its `ResizeObserver` and `attributeChangedCallback`; a render re-scrolls to the anchor without replacing it; relocations after a render carry `reason: 'anchor'`. An update that changes these breaks the single render (more re-layouts, still correct) or, for the anchor, the position across folds.
- **Simulator only.** The 120 ms quiet time, the 5 s cap and the book-mode angles need a real device. On the loaded simulator the scene moved up to 3.5 s after the hinge; if a move ever takes longer than the cap, the batch lays out early (extra re-layouts and a wrong layout briefly on screen, no wrong position).
- **The synced position still drifts on unfold** (`duo-spreads.md` §8): the one relocation after an unfold is the spread's start, which is saved and pushed. Batching made it one save instead of several, but it is still the spread's start.
- **Taps in the margins** now turn pages or show the controls, following the zones. Before, a tap outside the section's frame did nothing.

## Reproducing

All on 'Octavo Fold Duo' (387F2531-EF32-4A5A-9987-8431E2D55A91), sample books in the app's Documents (see `duo-spreads.md`, Reproducing).

```bash
export SIM=387F2531-EF32-4A5A-9987-8431E2D55A91
docs/notes/duo-spreads/tools/install.sh                 # build, install folded, launch
docs/notes/duo-spreads/tools/js.sh "$(cat docs/notes/duo-fold/tools/instrument.js)"   # with a book open
docs/notes/duo-fold/tools/measure.py build open close half close sweep:0:180:1 > run.jsonl
docs/notes/duo-fold/tools/timeline.py run.jsonl open    # page and app events of one move, in order
docs/notes/duo-fold/tools/record.sh unfold.mov LCD-1 open   # one display per recording: LCD-1 inner, LCD outer
docs/notes/duo-fold/tools/sheet.py unfold.mov unfold.png inner
```
