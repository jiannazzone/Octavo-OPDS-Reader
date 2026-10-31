# Spike 2b: Duo spreads and fold continuity

Spike step 5. Written 2026-10-31 on 'Octavo Sync Duo' (32DEFF1F-1885-4884-8DAF-2FC92AE08FC2, iPhone Duo, iOS 27.1 simulator, Xcode 27.2), driven with Hinge 0.3.0. Raw data is in `duo-spreads/` next to this file.

## Summary

- **Columns follow the hinge.** Folded: one page. Open or half open: two pages, with the gap between them centred on the hinge and wider than the hinge's reserved region. No text box touched the fold region in any of 40 open or half-open states. Screenshots: `duo-spreads/screenshots/`.
- **Position across folds: no lost reading position.** 8 runs, 64 hinge moves (open, close, half-open), 5 books:
  - Every fold back to one page returned to the **exact original CFI** (21 of 21), except on P&P's blank page (3 moves, see below).
  - Every open or half-open spread **contained the original page's start** (35 of 35), except on that blank page (5 moves). In 5 of the 35 (Sherlock), the start is the spread's last line, so the page's first words run onto the next spread.
  - **The one loss, explained:** on P&P's blank page after the dedication, the reader comes back one page early (the dedication). The page has no text, and the cause is patch 0001 anchoring a blank page by page fraction.
  - The first round found a real bug: after a jump by **fraction**, foliate anchors to the fraction, and a fold moved the reader a spread ahead (4 of 8 runs). It's fixed in `bridge.js`.
- **Cover-display handoff works.** Folded on a book's screen, unfolding opens the reader on the inner display within about 20 ms. It lands at the saved position (local book) or the pulled BookOrbit position (synced book), and nothing is pushed. The same scene, process and in-memory sign-in carry over.
- **Patches:** 0001 (the vetted blank-page fix) and 0002 (a `max-column-count-portrait` attribute, two lines). `epubcfi.js` is untouched.
- Tests: `xcodebuild test` 47/47 on 'Octavo Sync Duo', `swift test` 48/48. New `OctavoTests/ReaderLayoutTests.swift` covers the hinge → layout mapping.

## 0. foliate-js patches

Both are in `ReaderWeb/foliate-js/patches/` and listed in `ReaderWeb/foliate-js/PINNED.md`. Applying them to upstream `6b11e17`'s `paginator.js` reproduces ours byte for byte (checked). `epubcfi.js` is untouched.

| # | What | Why | Checked |
|---|---|---|---|
| 0001 | Blank pages keep their position | The vetted fix from `docs/notes/foliate-blank-page-upstream.md` (branch `claude/foliate-blank-page-vetting-1aa980`, section 5), applied unchanged. Without it, a fold on a blank page jumps to the section start. | P&P folded (466×502): the blank page after the dedication is page 10 of section 1 and now reports `epubcfi(/6/4!/4/22)` (the PREFACE heading) instead of the bare `epubcfi(/6/4!/4)`. 1a's restore still works: kill and relaunch on a normal page (`/4/24/2/3:468`) reopens it exactly, and on the blank page reopens on the next page with text (PREFACE), as the patch intends. Fold runs on the blank page: section 5. |
| 0002 | `max-column-count-portrait` attribute | foliate switches to an internal portrait column count (1) whenever its area is taller than wide, and no attribute reaches it. Needed so the column count comes from the hinge, not the aspect ratio. | A 400×493 view asked for two columns (`max-column-count=2`, `max-inline-size=200px`): 1 column without the patch, 2 with it. No effect unless the attribute is set. |

The bridge's old `isBlankPage` check (a range starting at `<body>`) can no longer trigger with 0001; it stays as a guard in case the patch is ever dropped.

## 1. What the hinge APIs give (iOS 27.1)

Two separate APIs, both public in the iOS 27.1 SDK (Xcode 27.2's SDK is 27.2; nothing below needs more than 27.1):

| API | What it gives | Notes |
|---|---|---|
| `View.onHingeChange(isEnabled:_:)` → `(old, new: DeviceHingeContext)` | `context.hinge: DeviceHinge?` with `status` (`.closed`, `.partiallyOpen`, `.fullyOpen`) and `angle: Angle` | Fires once on appear (`hinge` nil → current), then on every change. While the hinge settles it repeats **unchanged values ~30 times a second** for about half a second, so handlers must compare. UIKit equivalent: `UIHingeInteraction` (`UIHinge.status`, `.angle` in radians). |
| `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` → `[ReservedRegion]` | `kind` (`.division`, `.occlusion`), `frame` (in the view's coordinates, **including** `margins`), `margins: EdgeInsets`, `isActive` | Use `.includeInactive` to see the hinge when flat. Works inside `onGeometryChange(for:)`, which re-fires when regions change. UIKit equivalent: `UIView.reservedRegions(kind:options:)`. No region-change notification exists beyond geometry changes. |

Measured on the simulator (`duo-spreads/events/probe.jsonl`):

| Posture (`hinge`) | `status`, `angle` | Scene's screen | `division` region (view coordinates, inner display) | `occlusion` regions |
|---|---|---|---|---|
| closed (0°) | `.closed`, 0° | outer, 466×678 | none | camera column at the top right: 84×174 at x 382 (plus a 37×37 lens inside it) |
| open (180°) | `.fullyOpen`, 180° | inner, 951×669 | x 455.5, width 40 (hinge line at 475.5, the screen's centre, plus 20pt margins each side), full height, **inactive** | camera at the top right: 84×124 at x 867 |
| half (90°) | `.partiallyOpen`, 90° | inner, 951×669 | same frame, **active** | same |
| 150° | `.partiallyOpen`, 146.7° | inner | active | same |
| 30° | `.closed`, 33.3° | outer (switches at about this angle) | none | as closed |

- Angles come in steps of about 3.3° (146.7, 33.3).
- The hinge reports `.fullyOpen` about 200 ms **before** the scene takes the inner display's size, and on a fold the region briefly reports the inner display rotated (a horizontal division at y 373.5) while the view is already the outer display's width. Layout code must tolerate both transients (it does: see `ReaderLayout`).
- The same `UIWindowScene` (same session and object) moves between the displays: only `screen.bounds` changes. Nothing is torn down (section 6).
- The system safe area keeps the camera column clear on both displays: SwiftUI content is 382 wide folded and 867 wide unfolded. That puts the inner display's content **off-centre from the hinge** by 42pt. `WebView`, however, draws the page under the trailing and bottom safe areas, so the web page itself is 466×502 folded and 951×493 unfolded, centred on the hinge, with the same top-left corner as SwiftUI's frame. Region frames are therefore already in page coordinates, but the page's size has to come from the page (`viewport` message), not from SwiftUI.

## 2. Columns by posture

**foliate on its own already does two columns unfolded**: the page is 951×493 (landscape) and foliate's default `max-inline-size` (720px) fits two. With `ReaderLayout.automatic` (no attributes) the unfolded Moby-Dick page measured 2 columns, folded (466×502, portrait) 1 column. So the aspect-ratio rule alone gives the right answer on the Duo in its normal grip. It's set explicitly anyway, so the answer doesn't depend on the reader area's shape (a toolbar, a sidebar, or rotation could change it):

- `ReaderWebView` maps `DeviceHingeContext` to `ReaderPosture` (`closed`, `halfOpen`, `open`, `noHinge`) and reads the `division` regions with `onGeometryChange`.
- `ReaderLayout(posture:geometry:)` (pure, unit-tested in `OctavoTests/ReaderLayoutTests.swift`) decides:

| Posture | Fold region | Layout |
|---|---|---|
| closed | any | 1 column, foliate's spacing |
| open / half-open | runs top to bottom with ≥200pt each side (active or not) | 2 columns, gap on the fold (section 3) |
| open / half-open | runs across (device turned) | 1 column. Owner: likely the default; could become a setting. |
| open / half-open | none reported, landscape | 2 columns around the middle |
| open / half-open | none reported, portrait | 1 column (covers the moment during an unfold when the hinge says open but the page is still the outer display's size) |
| no hinge reported | active vertical region | 2 columns on it |
| no hinge reported | otherwise | `automatic`: foliate decides (other iPhones, iPad) |

- `bridge.js` `setLayout` applies it with foliate's own attributes (`max-column-count`, `max-column-count-portrait` from patch 0002, `gap`, `max-inline-size`) and the `foliate-view`'s `left`/`right`, then calls `renderer.render()`. The paginator re-renders around its anchor, so the position is kept (section 5). The layout is also passed to `open()`, so a book opened unfolded is laid out once, not twice.
- The model only sends a layout when it changes, so the hinge's repeated callbacks and angle changes within one posture cost nothing.

Screenshots: `duo-spreads/screenshots/folded-1-column.png`, `duo-spreads/screenshots/unfolded-2-columns.png`.

## 3. Gap at the hinge

foliate centres its column gap in the middle of the `foliate-view`, and with its equal-spacing rule the gap is exactly `gap`% of the view's width (the outer margins match it). So:

- **Centre:** the view is trimmed on the far side so its middle is the fold's middle (`leftInset`/`rightInset`). On the Duo the page is 951 wide with the hinge at 475.5, so both insets are 0. They matter if the page isn't centred on the hinge (for example, if a future layout keeps the reader out of the camera column; SwiftUI's own content area is 867 wide, 42pt off-centre).
- **Width:** `gap` = max(foliate's 7%, the region's width ÷ view width, rounded up to 0.1%). The Duo's region is 40pt (the hinge line plus 20pt margins), 4.2% of 951, so foliate's 7% (66.6pt) already covers it.
- **Text width:** `max-inline-size` = half the view (476px), so foliate fits exactly two columns and never caps the text width (a capped width would still be centred, but the gap would no longer equal `gap`%).

Measured from the visible text's boxes (`bridge.js` `layoutReport`) in all 40 open and half-open states of the runs: the left page's text ends between x 442.3 and 443.2, and the right page's starts between x 508.8 and 509.7, around a fold region of 455.5–495.5. **No text box touched the fold region** (section 5 table; the 5 P&P blank-page states show an illustration, no text). The gap is 66.6pt wide and centred within 1pt of the hinge line at 475.5.

## 4. Half-open

At `hinge half` (90°) `DeviceHingeContext` reports `.partiallyOpen` and 90°, and the division region becomes **active** (same frame as flat). The scene stays on the inner display at 951×669, so the page doesn't resize: going open ↔ half-open changes nothing on screen, and the reader keeps the same two pages split at the hinge. Every half-open step in the runs shows the same page as the open step before it.

Screenshot: `duo-spreads/screenshots/half-open-2-pages.png`.

Anything beyond "two pages split at the hinge" is a UI decision (section 7).

## 5. Position continuity

**Method** (`duo-spreads/tools/fold-run.py`): open a book folded, go to a position, record that page as the origin (start CFI, first 8 words), then 8 hinge moves: open, close, half, close, open, half, open, close. After each move, once the page has the right size and posture and two reads 1.5 s apart agree, record:
- the start CFI and first words;
- `exact`: after a fold, the start CFI equals the origin's;
- `contains`: after an unfold, the visible page contains the origin's start, by foliate's own CFI ordering (`bridge.js` `locate`), and its text contains the origin's first 8 words;
- where the text sits against the fold (`layoutReport`).

Five books, eight origins: mid-chapter (Moby-Dick 30%, P&P 50%, Frankenstein 50%), late (Alice 60%, Sherlock 85%, Moby-Dick 90%), and P&P around the dedication: the blank page itself (section 1, page 10 folded) and the PREFACE page right after it. Origins were reached by `goto` (fraction or CFI), plus page turns for the two P&P ones. Raw data: `duo-spreads/runs/*.jsonl`.

**Results** (after the fix below):

| | Folds back to one page | Opens / half-opens |
|---|---|---|
| Exact / contains | 21 of 21 | 30 of 35 by CFI and words, 5 of 35 by CFI only (start on the spread's last line) |
| P&P blank page | 3 moves: one page early (the dedication) | 5 moves: the dedication spread, which doesn't reach the PREFACE |

- **No creep.** Outside the blank page, each origin's CFI is identical after the 1st, 2nd and 3rd fold, and every unfold of a run shows the same spread (on the blank page, the one-page drift is the same each time). The paginator re-scrolls to its anchor (the origin page's range) on every re-layout instead of re-reading where it is.
- **Open ↔ half-open changes nothing**: same page size, no re-render (0 relocations).
- **Sherlock (5 "CFI only")**: the spread ends 33 characters into the origin page (`/334/1:152` against the origin's `/334/1:119`). The reader shows the spread holding the start, but the origin's first line is the spread's last, the same "straddles a page end" case 2a counted as a hit. Folding back is exact.
- **P&P blank page (the only loss).** With patch 0001 a blank page has no text to anchor to, so the paginator anchors it by its fraction through the section. A fold maps that fraction onto the other layout's page count, which shifts while P&P's illustrations re-flow (154 → 98 → 81 → 82 pages in one unfold). It lands within a page: in the counted run, on the dedication spread unfolded and on the dedication page folded (one page early). In a repeat by hand it came back exactly. No text is skipped either way: the reader sits next to an empty page. Anchoring a blank page to the next content instead was rejected in the vetting (it makes every host re-layout move a page forward). The PREFACE page right after it is exact in every move.

**Bug found and fixed: jumps by fraction.** The first round (`duo-spreads/runs/before-reanchor/`) had 25 unfolds that didn't contain the origin. In 4 of 8 runs, every unfold showed the spread *after* the origin's start. Cause: after `goToFraction`, foliate keeps the fraction itself as the paginator's anchor (`view.js` passes a number, and `'navigation'` scrolls don't replace it). A fold then maps the fraction onto the new layout and can land a spread away. Moby-Dick passed by luck, and the P&P PREFACE run passed because a page turn re-anchors on the text. `bridge.js` now re-anchors on the visible page's own range after any fraction jump (`anchorToPage`), as a page turn would. This also covers a slider jump or a restore by fraction in real use. Folds back were exact even before the fix (same fraction, same layout), which hid it.

**Cost of a fold:** every fold or unfold fires 10–13 relocations (the hinge, the page's resize, the new layout and the fold region arrive separately, and each re-render re-scrolls 2–3 times). The page always ends where it should, but it's visible work (section 7, question 6). Only the final position is saved, and only if it changed.

| Run | Book | Move → posture | Cols | Start CFI | First words | Verdict | Fold gap (x, pt) |
|---|---|---|---|---|---|---|---|
| **moby-mid** | moby-dick.epub | origin | 1 | `epubcfi(/6/10!/4/44/1:202)` | that he made, now at the main-mast and | origin | |
| | | open → open | 2 | `epubcfi(/6/10!/4/36[pgepubid00040])` | CHAPTER 36. The Quarter-Deck. (Enter Ahab: Then, all.) | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | close → closed | 1 | `epubcfi(/6/10!/4/44/1:202)` | that he made, now at the main-mast and | exact |  |
| | | half → halfOpen | 2 | `epubcfi(/6/10!/4/36[pgepubid00040])` | CHAPTER 36. The Quarter-Deck. (Enter Ahab: Then, all.) | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | close → closed | 1 | `epubcfi(/6/10!/4/44/1:202)` | that he made, now at the main-mast and | exact |  |
| | | open → open | 2 | `epubcfi(/6/10!/4/36[pgepubid00040])` | CHAPTER 36. The Quarter-Deck. (Enter Ahab: Then, all.) | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | half → halfOpen | 2 | `epubcfi(/6/10!/4/36[pgepubid00040])` | CHAPTER 36. The Quarter-Deck. (Enter Ahab: Then, all.) | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | open → open | 2 | `epubcfi(/6/10!/4/36[pgepubid00040])` | CHAPTER 36. The Quarter-Deck. (Enter Ahab: Then, all.) | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | close → closed | 1 | `epubcfi(/6/10!/4/44/1:202)` | that he made, now at the main-mast and | exact |  |
| **moby-late** | moby-dick.epub | origin | 1 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | origin | |
| | | open → open | 2 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | close → closed | 1 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | exact |  |
| | | half → halfOpen | 2 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | close → closed | 1 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | exact |  |
| | | open → open | 2 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | half → halfOpen | 2 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | open → open | 2 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | contains | clear: text to 443, fold 455.5–495.5, text from 510 |
| | | close → closed | 1 | `epubcfi(/6/22!/4/388[pgepubid00132])` | CHAPTER 126. The Life-Buoy. Steering now south-eastward by | exact |  |
| **pp-preface** | pride-and-prejudice.epub | origin | 1 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | origin | |
| | | open → open | 2 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | exact |  |
| | | half → halfOpen | 2 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | exact |  |
| | | open → open | 2 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | half → halfOpen | 2 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | open → open | 2 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/4!/4/22)` | Walt Whitman has somewhere a fine and just | exact |  |
| **pp-blank** | pride-and-prejudice.epub | origin | 1 | `epubcfi(/6/4!/4/22)` |  | origin | |
| | | open → open | 2 | `epubcfi(/6/4!/4/20)` |  | lost | crossing 0 |
| | | close → closed | 1 | `epubcfi(/6/4!/4/20)` |  | drift |  |
| | | half → halfOpen | 2 | `epubcfi(/6/4!/4/20)` |  | lost | crossing 0 |
| | | close → closed | 1 | `epubcfi(/6/4!/4/20)` |  | drift |  |
| | | open → open | 2 | `epubcfi(/6/4!/4/20)` |  | lost | crossing 0 |
| | | half → halfOpen | 2 | `epubcfi(/6/4!/4/20)` |  | lost | crossing 0 |
| | | open → open | 2 | `epubcfi(/6/4!/4/20)` |  | lost | crossing 0 |
| | | close → closed | 1 | `epubcfi(/6/4!/4/20)` |  | drift |  |
| **pp-mid** | pride-and-prejudice.epub | origin | 1 | `epubcfi(/6/10!/4/88/1:116)` | judgment alone, he was to determine and direct | origin | |
| | | open → open | 2 | `epubcfi(/6/10!/4/66)` | “What is it you mean?” “It is a | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/10!/4/88/1:116)` | judgment alone, he was to determine and direct | exact |  |
| | | half → halfOpen | 2 | `epubcfi(/6/10!/4/66)` | “What is it you mean?” “It is a | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/10!/4/88/1:116)` | judgment alone, he was to determine and direct | exact |  |
| | | open → open | 2 | `epubcfi(/6/10!/4/66)` | “What is it you mean?” “It is a | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | half → halfOpen | 2 | `epubcfi(/6/10!/4/66)` | “What is it you mean?” “It is a | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | open → open | 2 | `epubcfi(/6/10!/4/66)` | “What is it you mean?” “It is a | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/10!/4/88/1:116)` | judgment alone, he was to determine and direct | exact |  |
| **frankenstein-mid** | frankenstein.epub | origin | 1 | `epubcfi(/6/40!/4/2[pgepubid00019]/42/1:309)` | the mind of youth expanded and gained knowledge, | origin | |
| | | open → open | 2 | `epubcfi(/6/40!/4/2[pgepubid00019]/36/1:614)` | of the same nature as man. I was | contains | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/40!/4/2[pgepubid00019]/42/1:309)` | the mind of youth expanded and gained knowledge, | exact |  |
| | | half → halfOpen | 2 | `epubcfi(/6/40!/4/2[pgepubid00019]/36/1:614)` | of the same nature as man. I was | contains | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/40!/4/2[pgepubid00019]/42/1:309)` | the mind of youth expanded and gained knowledge, | exact |  |
| | | open → open | 2 | `epubcfi(/6/40!/4/2[pgepubid00019]/36/1:614)` | of the same nature as man. I was | contains | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | half → halfOpen | 2 | `epubcfi(/6/40!/4/2[pgepubid00019]/36/1:614)` | of the same nature as man. I was | contains | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | open → open | 2 | `epubcfi(/6/40!/4/2[pgepubid00019]/36/1:614)` | of the same nature as man. I was | contains | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/40!/4/2[pgepubid00019]/42/1:309)` | the mind of youth expanded and gained knowledge, | exact |  |
| **alice-late** | alice-in-wonderland.epub | origin | 1 | `epubcfi(/6/20!/4/2[pgepubid00010]/116)` | “A cat may look at a king,” said | origin | |
| | | open → open | 2 | `epubcfi(/6/20!/4/2[pgepubid00010]/100/1:52)` | voice. “Not at all,” said Alice: “she’s so | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/20!/4/2[pgepubid00010]/116)` | “A cat may look at a king,” said | exact |  |
| | | half → halfOpen | 2 | `epubcfi(/6/20!/4/2[pgepubid00010]/100/1:52)` | voice. “Not at all,” said Alice: “she’s so | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/20!/4/2[pgepubid00010]/116)` | “A cat may look at a king,” said | exact |  |
| | | open → open | 2 | `epubcfi(/6/20!/4/2[pgepubid00010]/100/1:52)` | voice. “Not at all,” said Alice: “she’s so | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | half → halfOpen | 2 | `epubcfi(/6/20!/4/2[pgepubid00010]/100/1:52)` | voice. “Not at all,” said Alice: “she’s so | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | open → open | 2 | `epubcfi(/6/20!/4/2[pgepubid00010]/100/1:52)` | voice. “Not at all,” said Alice: “she’s so | contains | clear: text to 442, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/20!/4/2[pgepubid00010]/116)` | “A cat may look at a king,” said | exact |  |
| **sherlock-late** | sherlock-holmes.epub | origin | 1 | `epubcfi(/6/26!/4/2[pgepubid00015]/334/1:119)` | over here again before evening.” It was obvious | origin | |
| | | open → open | 2 | `epubcfi(/6/26!/4/2[pgepubid00015]/306)` | “But perhaps it may grow lighter as we | contains (CFI only) | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/26!/4/2[pgepubid00015]/334/1:119)` | over here again before evening.” It was obvious | exact |  |
| | | half → halfOpen | 2 | `epubcfi(/6/26!/4/2[pgepubid00015]/306)` | “But perhaps it may grow lighter as we | contains (CFI only) | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/26!/4/2[pgepubid00015]/334/1:119)` | over here again before evening.” It was obvious | exact |  |
| | | open → open | 2 | `epubcfi(/6/26!/4/2[pgepubid00015]/306)` | “But perhaps it may grow lighter as we | contains (CFI only) | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | half → halfOpen | 2 | `epubcfi(/6/26!/4/2[pgepubid00015]/306)` | “But perhaps it may grow lighter as we | contains (CFI only) | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | open → open | 2 | `epubcfi(/6/26!/4/2[pgepubid00015]/306)` | “But perhaps it may grow lighter as we | contains (CFI only) | clear: text to 443, fold 455.5–495.5, text from 509 |
| | | close → closed | 1 | `epubcfi(/6/26!/4/2[pgepubid00015]/334/1:119)` | over here again before evening.” It was obvious | exact |  |

Totals: contains 30, contains (CFI only) 5, drift 3, exact 21, lost 5

Earlier run totals, before the re-anchor fix: exact 21, drift 3, contains 15, lost 25.

## 6. Cover-display handoff

The spike's library now opens a bare **book screen** (`Octavo/Spike/SpikeBookDetailView.swift`: file, source, saved position, Read button). While that screen shows, an `onHingeChange` from `.closed` to anything else opens the reader (`duo-spreads/tools/handoff.sh`).

| | Local book (Frankenstein) | BookOrbit book (file 2, Frankenstein) |
|---|---|---|
| Folded screen | `screenshots/handoff-local-folded.png` | `screenshots/handoff-bookorbit-folded.png` (signed in folded) |
| Unfold → reader appears | 22 ms after the hinge event | 15 ms after the hinge event |
| Opened from | saved local CFI (`restoredFrom: cfi`, `openedFrom: local`) | server: pulled `epubcfi(/6/54!/4/2[pgepubid00026],/12/1:117,/18/1:61)` → `openedFrom: server` |
| Spread contains that position | yes (`locate` true, first words visible) | yes (`locate` true) |
| Pushed on open | — | nothing (`lastPushedCFI` null) |
| Unfolded screen | `screenshots/handoff-local-unfolded.png` | `screenshots/handoff-bookorbit-unfolded.png` |

**App state across the outer → inner move** (`events/handoff-*.jsonl`):
- Same process, same `UIWindowScene` session and object. Only its `screen.bounds` change (466×678 → 951×669).
- No screen is rebuilt. The library and detail screens keep their probe instance IDs, and the only disappear is the detail screen going under the reader.
- The `NavigationStack` path (library → book → reader), `@State`, and the BookOrbit client's in-memory tokens all carry over. The pull after the unfold used the sign-in made while folded.

The reverse (reader open, fold to the outer display) is what every fold run does: same process, reader stays open.

**What makes it harder than it looks:**
- The hinge says open about 200 ms before the scene has the inner display's size. The reader is created at the outer display's size and re-laid out once more. Harmless, because the layout follows geometry and the anchor holds, but it's an extra re-render.
- `onHingeChange` repeats unchanged values for about half a second, and fires once on appear with `hinge == nil`. The trigger must compare old and new statuses (`closed` → not `closed`), or an appearing screen or a repeat would navigate.
- With sync, the reader opens only after the pull (up to the 5 s timeout), so on a slow server the unfold shows a spinner. Pulling while the book screen shows, folded, would hide that.
- An unfold that wasn't meant as "read now" also navigates. Whether that should be automatic is a product call (section 7, question 5).
- Only screens that observe the hinge can react. A sheet or another app on top won't hand off.

## 7. Questions for the owner

UI and product calls the spike stopped at. Nothing here is built beyond the spike screens.

1. **Half-open "book" posture.** Today it's the same two pages as flat. Options:
   - (a) Leave it as flat.
   - (b) A "book mode" at about 60–150°: chrome hidden, a tap on either half turns the spread, optional page-curl or shadow at the spine.
   - (c) Turn one page at a time across the spread (the right page slides to the left), which reads more like a physical book but is a foliate change (it turns a whole spread now).
   - (d) Held sideways like a laptop (fold across): reading on the top half, controls on the bottom half.
2. **Unfolded but turned sideways** (fold across the page): one column now, per your note; a setting later. Should the column avoid the fold line (two half-height pages, top and bottom), or run straight across it?
3. **Where the reader may draw.** `WebView` currently lets the page run under the camera column and under the floating bottom toolbar (text sits under the spike's toolbar buttons). That keeps the page centred on the hinge. Keeping the reader inside the safe area instead puts the page 42pt off-centre, so either the left side gives up 84pt to stay symmetric or the outer margins become unequal (another foliate patch).
4. **Gap and margins.** foliate ties the outer margins to the centre gap (66pt each on the Duo). A narrower outer margin with a wider spine gutter needs a foliate patch. Worth it?
5. **Cover-display handoff.** Open the reader automatically on unfold (what the spike does), or ask first? Only from a book's screen, or also from the library with the last book? Should it be a setting?
6. **The re-layout on fold.** A fold or unfold fires 10–13 relocations as the hinge, the page's resize, the new layout and the fold region arrive separately. The page ends in the right place, but the intermediate layouts can show as a flicker. A cross-fade or a snapshot over the transition is a visual choice; batching the inputs into one re-layout is an engineering follow-up.

## 8. Open risks

- **Position across folds relies on a foliate internal**: the paginator keeps its `#anchor` through re-renders (`reason === 'anchor'` doesn't replace it). A foliate update could change that. `PINNED.md` now says to re-run these fold runs on every bump.
- **Saved and synced positions drift on relaunch, not in a session.** After an unfold, the reader saves (and with sync, pushes) the spread's start, which can be up to one folded page before where the reader was. In the session, folding back returns to the exact page (the anchor), but after a relaunch or on another device the reader opens at the spread's start. A fix is to keep the pre-fold position when a relocation comes only from a re-layout. Not done in the spike.
- **`WebView` draws outside SwiftUI's frame** (under the trailing and bottom safe areas). The layout takes the page's size from the page and assumes the page and SwiftUI share a top-left corner, which holds in the Duo's portrait grip (checked against the `WKWebView`'s window frame). With a leading safe area (rotated, other devices) the region would need converting; unverified.
- **Simulator only.** Real hinge timing, angle steps and how fast the scene moves can differ. Hinge 0.3.0 is third-party.
- **Blank pages anchor by page fraction** (patch 0001). After an unfold, a fraction lands on the matching page of the new layout, which is approximate; see the P&P blank-page run.
- **Process: `xcodebuild test` shuts the simulator down.** Parallel testing clones the device ('Clone 1 of Octavo Sync Duo'), which needs the source shut down. Use `-parallel-testing-enabled NO` when a session's app is running on the same simulator.

## Reproducing

All on 'Octavo Sync Duo' (32DEFF1F-1885-4884-8DAF-2FC92AE08FC2) with the sample books copied into the app's Documents folder (`Scripts/fetch-sample-books.sh`, then `cp SampleBooks/*.epub "$(xcrun simctl get_app_container 32DEFF1F-1885-4884-8DAF-2FC92AE08FC2 com.ianazzone.ereader data)/Documents/"`).

```bash
docs/notes/duo-spreads/tools/install.sh        # build (Debug), reinstall folded, launch
docs/notes/duo-spreads/tools/fold-run.py moby-mid moby-dick.epub --fraction 0.3 > docs/notes/duo-spreads/runs/moby-mid.jsonl
docs/notes/duo-spreads/tools/summarize.py docs/notes/duo-spreads/runs/*.jsonl
```

- `app.sh` drives the DEBUG spike screens through `Documents/spike-command.json` (`Octavo/Spike/SpikeRemote.swift` lists the commands) and prints `spike-state.json`, which now includes the posture, hinge angle, geometry, layout, a `layoutReport` (text edges against the fold) and `watched` (whether the page contains a given CFI).
- `Documents/spike-events.jsonl` logs every hinge, region, scene-phase and appear/disappear event per screen (`Octavo/Spike/SpikeProbe.swift`).
- Run `xcodebuild test` with `-parallel-testing-enabled NO` while the app is in use on the same simulator, or xcodebuild shuts it down to clone it.
