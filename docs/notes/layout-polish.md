# Layout polish: the book sheet, the progress bar, text on the hinge (2026-11-03)

Two layouts Adam chose from picture mockups ("A" both times) off the plan's "To revisit" list, and two reader fixes that rode along. Checked on `iPhone Duo` (8C35AF6E-5F3F-48D7-A283-AEE894511947, iOS 27.1 simulator) folded, unfolded and half open, in light and Night.

## Summary

- **The folded book sheet at rest is compact:** the title on one line, the place under it ("48% · Synced just now"), Open as a capsule on the right of both, a thin progress line below. About 95 pt instead of about 170. The author and Mark finished moved into the pulled-up details. Unfolded, the right page is unchanged.
- **The reader's progress bar lines up with the text** (its edges are the text's in every margin setting) and sits just above the home indicator, as tall as its rows plus 12 pt of padding. Half open, each piece lines up with its own page's text.
- **Text on the hinge with Narrow margins was ours, and is fixed.** WebKit keeps a scroll offset in whole points, and foliate's page was 823.66 pt wide, so each page landed up to a point right of the layout. The view and gap are now whole points; every page reads 84–455 | 496–867.
- **The thin light line in Night wasn't reproduced** in any state tried (section 4). It needs a screenshot or the steps from whoever saw it.

## 1. The folded book sheet

`BookSheet` (`Octavo/Book/BookSheet.swift`) now heads with `BookSheetSummary`; the unfolded right page (`BookInfoPage`) keeps `BookSummary` as it was. Both read the place from `BookPlace`, which holds the old place logic: the progress, a problem (a download or Mark finished that went wrong) in the place's stead, and the sync status. `BookAuthorLink` is the author link both use.

- **Row 1:** the title in `.headline`, one line, truncated. Pulled up it may take two lines, as the details' heading.
- **Row 2:** `BookPlace.line(now:)`, the place and the sync on one line ("48% · Not synced yet, will retry"), redrawn each minute.
- **Right of both:** `BookOpenButton` with `fillsWidth: false`, so Open, Download, the ring with Cancel, Try again and the greyed-out Download are all capsules as wide as their labels.
- **Below:** the progress line (`ProgressView`), full for a finished book.
- **Pulled up:** the author link, then Mark finished (full width), then the details as before. Grabber, drag and tap-to-expand are unchanged.
- **Problems wrap.** "Couldn’t download. Check your connection.", "Needs a connection to download." and "This file is DRM-protected and cannot be opened." don't fit beside Try again or Download, so the place line may take two lines when it's a problem, and the sheet grows by a line in those states (Adam, 2026-11-03, from `03-sheet-states.jpg`: it's important information). Every other state is one line.
- **Debug:** `-shellCoverStrip protected` (and the Settings stand-in's "Cover strip" picker) shows the DRM state without a DRM file.

| | |
|---|---|
| `01-sheet-folded.jpg` | At rest: Moby-Dick, 48% · Synced just now, Open |
| `02-sheet-pulled-up.jpg` | Pulled up: the same rows, then Herman Melville ›, Mark finished, the details, Remove download |
| `03-sheet-states.jpg` | Every resting state, top to bottom: Open; downloading (ring, Cancel); Download (not on the iPhone); Not started; Finished; Not synced yet, will retry; Couldn’t download · Try again; Needs a connection · Try again; DRM with Download greyed out |
| `04-cover-unfolded-unchanged.jpg` | Unfolded, the right page as before |

"Not started" and "Finished" are from the sample library (`-sampleLibrary 1`), whose marks stay on the iPhone; the rest are BookOrbit books, "Not synced yet" with `-syncFailsPushes 1`.

## 2. The progress bar

`ReaderLayout.barSpans(in:bookMode:)` gives the bar's stretches from `textColumns(inReaderWidth:)`, the same arithmetic the footer uses: one stretch from the first column's left edge to the last column's right edge, or in book mode one per page. `ReaderLayout.barBottom(in:)` is the top of the bottom safe area (12 pt up on a screen without one). Until foliate's columns are known, the safe area less 12 pt each side, as before.

Measured on the screenshots (Night, the glass's edges on its middle row, against the text edges `layoutReport` gives):

| Posture | Narrow | Medium | Wide | Bottom |
|---|---|---|---|---|
| Folded | 18–382 | 27–355 | 38–344 | 644 |
| Unfolded | 84–867 | 139–812 | 162–789 | 635 |
| Half open | 84–455 · 496–867 | 139–448 · 503–812 | 162–436.5 · 514.5–789 | 635 |

Every edge is the text's to the pixel (Wide's half-points show as 436.33 and 514.67 on the 1/3 pt grid).

- **Padding (Adam, 2026-11-03, after seeing it unfolded):** the bar was a fixed 60 pt, and the flat bar's three rows (chapter, slider, page numbers) are taller, so they ran into its top and bottom edges. It's now as tall as its rows plus 12 pt above and below: 82 pt flat and folded, 66 pt half open, where both pieces take the taller one's height (`10-bar-padding.jpg`: flat, then half open).
- **It now covers about the last line and a half while it shows.** It used to sit 12 pt from the bottom, under foliate's 48 pt bottom margin; just above the 34 pt home-indicator area, its 82 pt reach about 36 pt into the text (20 half open). Only while the controls show.
- The search step bar and the server's-place capsule, which take the footer's place, keep their old placement (the page's safe area, the right page in a spread). Not part of this change.

- **The book-mode readout** (Adam, 2026-11-03, from three mockups: chapter progress, chapter steps, time left): the right-hand piece shows `ReaderChapterProgress`, pages left in the chapter ("6 pages left in this chapter", "1 page left in this chapter", "Last page of this chapter") and the book's pages on one line, over a line through the chapter. The chapter is the contents entry the bar names, running to the next entry; its pages are the footer's, from the contents' placed fractions. Before the first entry it falls back to the page numbers. `ReaderBarReadout` keeps it one readout among others: time left and choosing the readout are parked in `UI-IDEAS.md`. Checked across the end of Moby-Dick's chapter 54 (`11-bar-chapter-readout.jpg`: two pages left, the last page, then chapter 55 with 8 left).

`05-bar-folded-medium.jpg`, `06-bar-folded-narrow.jpg`, `07-bar-unfolded-narrow.jpg`, `08-bar-unfolded-wide.jpg`, `09-bar-half-open-medium.jpg` (05–09 at the old 60 pt; the edges are unchanged), `10-bar-padding.jpg`.

## 3. Text on the hinge (fixed)

`other-ways-in.md` saw Narrow's left page end at 455.8–456.2 pt instead of 455.5 late in a long book, and Moby-Dick's right page start at 495.9. Turning 25 pages of Moby-Dick at 50%, unfolded, Narrow, with the old layout:

| Page | foliate's offset (`page × 823.66`) | Scroll offset | Left page ends | Right page starts | Text ends |
|---|---|---|---|---|---|
| 15 | 12354.84 | 12354 | 456.03 | 496.64 | 867.86 |
| 17 | 14002.16 | 14002 | 455.34 | 495.95 | 867.17 |
| 32 | 26357.00 | 26357 | 455.19 | 495.80 | 867.02 |
| 35 | 28827.97 | 28827 | 456.16 | 496.77 | 867.98 |

The text lands exactly `page × size − scroll` right of where the layout put it (455.19, 495.80, 867.02). foliate scrolls its container to `page × page width`, and WebKit keeps `scrollLeft` in whole points, dropping the fraction. Our layout made the page fractional: the view and gap were shares of the screen (view 864.24 pt, gap 4.7%, page 823.66). So it's ours, not a glyph overhang; it also shifted Medium's text by up to 0.6 pt (448.2–448.8 in `reader-page.md`'s runs), where the gutter hid it, and folded the right edge by up to a point under the side column.

**The fix** (`ReaderLayout.single` and `spread`): the view and the gap are whole points, so the page (the view less the gap) is whole and every scroll lands on it.

- The gap is the setting's share rounded to the point, and in a spread at least the fold plus one point, so the text keeps half a point clear of the hinge each side (Narrow: 41 pt, text 84–455 | 496–867; Medium 55 pt, 139–448 | 503–812, frame 09 exactly; folded Medium 27–355, frame 07).
- foliate takes the gap as a percentage and WebKit truncates lengths to 1/64 pt, so the percentage asks for 1/256 pt more than the whole gap (`ReaderLayout.wholePageGap`), which truncates back to it.
- Insets are rounded to 1/64 pt so a whole view between them stays whole.
- No foliate-js change. `PINNED.md`'s update checks gain step 5: the page must stay whole.

After, the same 25 pages and the section's last 40 (to its page 75): every page 455 | 496, text to 867, foliate's page 824. Every margin, 20 pages from 88%: folded 18–382, 27–355, 38–344 (pages 382, 355, 344); unfolded 84–455 | 496–867, 139–448 | 503–812, 162–436.5 | 514.5–789 (pages 824, 728, 705), one key each.

`ReaderLayoutTests`: foliate's page is whole for every margin folded, flat, half open and sideways (modelling WebKit's 1/64 pt truncation), Narrow's spread, and the bar's stretches.

### Re-running

```bash
export SIM=<udid>
docs/notes/duo-spreads/tools/app.sh '"cmd":"openLocal","name":"moby-dick.epub"'
docs/notes/duo-spreads/tools/js.sh 'await window.octavo.goToFraction(0.5); return 1'
D=$(xcrun simctl get_app_container $SIM com.ianazzone.ereader data)/Documents; rm -f $D/spike-js.json
NOWAIT=1 docs/notes/duo-spreads/tools/app.sh "\"cmd\":\"js\",\"script\":$(jq -Rs . < docs/notes/layout-polish/probe.js)"
sleep 10; cat $D/spike-js.json
```

## 4. A thin light line in Night (not reproduced)

Reported as a thin light line between the page and the side column in Night, unfolded, never investigated. None showed here. Tried, unfolded unless said: Night chosen in light mode and Night from Dark Mode; Narrow and Medium; controls hidden and shown; the Text and theme panel open; half open; the reader opened by unfolding on a cover; and folded with the bar in every margin. Each screenshot was scanned column by column for a line one or two pixels wide that is lighter than both neighbours over a quarter of the screen's height: none, anywhere across the width.

Candidates ruled out by those scans: the edge of foliate's view under the column (Narrow's view ends at 908, Medium's at 867), the scroll sliver the drift left at the container's edges (section 3, now gone), and the side column's toolbar in its shown and hidden states. Still to try with the reporter's steps: a real device, a page turn or fold in progress, another book's own background, Sepia and Paper in Dark Mode with Match Dark Mode off.

## Checks

- App tests 345/345 with `-parallel-testing-enabled NO`, OctavoKit 253/253 (`swift test`).
- The simulator's app was signed back in to BookOrbit afterwards (`-connectBookOrbit 1`).
