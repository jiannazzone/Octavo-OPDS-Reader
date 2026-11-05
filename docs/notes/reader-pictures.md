# Pictures fit their text column (2026-11-04)

Pride and Prejudice's "She is tolerable" ran past the text's right edge and was cut off, its hand-lettered caption reading "She is tolera". Checked on 'Octavo Figures Duo' (33BC3F4F-0ED8-4351-8887-990F0D5F0681, iPhone Duo, iOS 27.1 simulator).

## Summary

- **Cause:** the book, not foliate's sizing as such. Project Gutenberg puts a printed picture in a box as wide as the picture, `<div class="figcenter" style="width: 456px;">`. foliate limits a picture to `max-width: 100%`, which is 100% of that box, not of the column.
- **Fix:** `bridge.js` only, no foliate patch. A box around a picture stays inside its column. Pride and Prejudice went from 30 cut-off pictures folded and 33 unfolded to none.
- **Text doesn't move.** Sections with no pictures keep the same page count in every posture. Sections with a picture that was too big lose a page or two, because the picture is smaller now.
- **Test:** `OctavoTests/ReaderPicturesTests.swift` runs the real bridge and foliate in a page that's never shown.

## 1. The cause

`.figcenter` has `margin: 3% auto` and `text-align: center`, and the inline width is what the picture measures in print (Pride and Prejudice has 34 such boxes, 332–550 px, all wider than the folded column). On a 328 pt column:

- The box stays 456 pt wide, running 128 pt past the column.
- The picture is limited to 100% of the box, so it's up to 456 pt wide too. A smaller picture is centred in the box, which still puts it past the column's edge.
- The printed caption is centred in the same box, so it sits off-centre even when it doesn't get cut off.

On screen the picture stops at the column's edge, so its right side just goes (`screenshots/before-folded.jpg`). A second case came up in the cases book (section 3): foliate keeps a `max-width` that the book already set (`paginator.js`, `setImageSize`), so `max-width: 800px` also runs out of the column.

## 2. The fix

Two pieces, both in `ReaderWeb/bridge.js`.

**The rule, in `BOOK_STYLES`, after the book's own styles:**

```css
body :has(img, svg, video) {
    max-inline-size: -webkit-fill-available !important;
}
```

- `:has` keeps it to boxes around pictures. That's the guarantee for text: no other element matches.
- `-webkit-fill-available`, not `100%`: a box with its own margin or padding would still run out by that much at 100%.
- `max-inline-size`, not `max-width`: it's the column's direction in vertical text too.
- `!important` beats the book's inline style without replacing it, so a box that already fits, or a page wide enough for it, keeps the book's width.

**`limitPicturesToTheirBoxes`, when a section loads:** what the rule can't say, because it depends on the book's own value.

- A picture's limit in points becomes `min(800px, 100%)`. foliate then keeps that, as it keeps any limit. A percentage is left alone, so `max-width: 40%` stays 40%.
- A table box around a picture, a `table` or anything with `display: table`, gets `min(600px, 100%)` as its width, because WebKit ignores `max-width` on a table. A cell or column width needs nothing: a table with no width of its own shrinks them to fit (`<td width>`, `<td style>` and `<col width>` measured).
- **Sizes of 200 pt or less stay in points** (`FITS_ANY_COLUMN`; the narrowest column is 274.5 pt). A percentage can't size a float or an inline-block around the picture, so the box would grow to the column and push the text out from beside it. Without this, a `max-width: 60px` picture in a float had a 328 pt box where the book's is 60 pt. A limit of 0 also stays for foliate, which reads it as none.
- It runs before foliate sizes pictures, so the first layout is already right. The section's `load` event comes first (`paginator.js`, `#display`), and `PINNED.md` lists this among the things to check on an update.
- Fixed-layout books are skipped: their pages place pictures themselves. `ReaderPicturesTests` checks an oversized picture and table in a small box keep the sizes the page gave them.

Both change styles only. The DOM is untouched, so every CFI stays as it was, though page breaks in a section with a picture move, as they do for any layout change.

## 3. Checks

`tools/survey.py` opens every section of a book in the real app, in each posture, and measures every picture and the boxes around it against the column it sits in.

Pride and Prejudice, 165 pictures, Medium margins:

| Posture | Column (pt) | Cut off, before → after | In a box over the column, before → after | Pages, before → after |
|---|---|---|---|---|
| Folded | 328 | 30 → 0 | 34 → 0 | 760 → 756 |
| Unfolded, flat | 309 | 33 → 0 | 34 → 0 | 417 → 412 |
| Half open | 309 | 33 → 0 | 34 → 0 | 417 → 412 |
| Sideways | 575 | 0 → 0 | 0 → 0 | 422 → 422 |

The sections whose page count changed all have pictures. Sideways nothing changed, since every box already fits.

- **Narrow and Wide margins** (columns 364, 371, 607 and 306, 274.5, 535 pt): none over the column in any posture.
- **The other four sample books** have one picture each, an SVG cover that always fit. Every section keeps its page count in every posture:

| Book | Folded | Flat | Half open | Sideways |
|---|---|---|---|---|
| Alice in Wonderland | 196 | 124 | 124 | 113 |
| Frankenstein | 445 | 278 | 278 | 243 |
| Moby-Dick | 1,137 | 633 | 633 | 569 |
| Sherlock Holmes | 553 | 316 | 316 | 279 |

- **The cases book** (`tools/make-cases.py`) tries what the sample books don't. Now inside the column: a wide box with and without margin and padding, a float, an inline-block, nested boxes, a `figure`, a table, a `display: table` box, a paragraph, a picture's own limit in px and em. Already fine, and unchanged: cell and column widths, a table with no width, two pictures side by side, a small picture's limit in a float or an inline-block, a `width` attribute, `width: 100vw`, an SVG, a video, a limit of 0, a percentage limit, plain pictures.
- **Vertical text** (a throwaway book, not in the tools): a 1,400 pt tall box stays within the 506 pt column and breaks across columns, and `max-height: 1400px` on a picture becomes `min(1400px, 100%)`.
- **Cost of the rule:** none measurable. Rewriting the style sheet and laying out took 69 ms with it and 72 ms without, in the one section where the timing caught a whole layout. The others read 0–1 ms both ways, so they may not have re-laid out.
- **Not checked:** a real device, and MOBI, AZW3 and FB2 with pictures. They go through the same rule and function, but the sample folder had none to try.

| | |
|---|---|
| `screenshots/before-folded.jpg`, `before-flat.jpg` | Cut off at "She is tolera", the printed caption off-centre |
| `screenshots/after-folded.jpg`, `after-flat.jpg`, `after-half.jpg`, `after-sideways.jpg` | Whole in each posture |

## 4. The test

`ReaderPicturesTests` opens a small generated EPUB with the real bridge and foliate in a `WebPage` with no window, so the view's size comes from a style sheet, and reads the boxes from the page. It runs folded, unfolded and sideways, and through the size changes an unfold and a turn cause (a fold closes the book, so it never re-lays out an open one).

Control: with `bridge.js` as it was, the fit test fails in all three postures and the size-change test fails at each size (8 issues). The two that guard what must not change (pictures that fit keep their size, a box of text keeps its width) pass with or without the fix, as they should. Against the first version of the fix, which turned every limit into a percentage and looked for the `table` tag, the small-float and `display: table` checks fail (9 issues).

## 5. Left alone

- **A float with a limit above 200 pt, where the column is wider than the limit.** A float with a 400 pt picture has a 575 pt box sideways, not 400, so text that would fit beside it goes below. It's the price of the percentage, and rare: it needs a float with no width and a large limit, and a picture that big leaves little room beside it on the Duo's other columns.
- **A book's `min-width`.** It beats any limit, so `<img style="min-width: 600px">` still runs out. It's rare, and a percentage `min-width` is a real way to ask for a full-width picture, so the book keeps it.
- **A box of text with no picture** that's wider than the column stays as wide: this fix is only for pictures.
- **Drop caps in Pride and Prejudice.** The same before and after. `.letra { float: left; margin-top: -1% }` puts a 100 pt drop cap about 3 pt above its line, and at the top of a page that part lands at the foot of the page before: a faint line, with 18 drop caps affected folded and unfolded and 30 sideways. In the section tried, turning the margin off ended the split (2 of 9 drop caps to none). The survey counts them as "split across columns". Cosmetic, and specific to this book's styles.

## 6. A race, found by CI (2026-11-05)

`picturesStillFitWhenThePageChangesSize` failed now and then in CI, always on the table with no width, always at the sideways size. It reproduced on 'Octavo Flaky Tests Duo' (a throwaway iPhone Duo simulator, iOS 27.1): 1 miss in 150 opens, 1 in 400 and 9 in 700, each time with the table set to `min(328.5625px, 100%)`, the folded column.

- **Cause:** `limitPicturesToTheirBoxes` runs at the section's `load` and counts on no layout having happened (section 2). The paginator makes a section's `View` before the section loads (`#createView`), so a render from its ResizeObserver could reach the new document first. Then `getComputedStyle` answered with that layout's column instead of the table's natural width. In all 9 misses a render with no script behind it came during the open, which is how that observer's call shows in a stack, and the section's root already had `column-width` when the bridge read it.
- **What a reader would see:** after an unfold or a turn to something wider, a table that stays at its first layout's width until the book is opened again. It's narrower than the column, never past it.
- **Fix:** foliate patch 0004. A `View` ignores a render until its `load` has run. A normal open already goes that way, so nothing else changes, and `load` measures the view itself, so a size change in between isn't lost. `bridge.js` is untouched, and the same patch stops a render from reaching a half-parsed section at all.
- **First try, dropped:** reading the table's width with `computedStyleMap`. It passed the tests, but a code review found it took the limit off a table with `width: 150%`, `100vw` or `max-content`, and it changed how some tables looked (a `width: 50%` table, the logo on *Pride and Prejudice*'s title page when sideways). The patch changes neither.
- **Tests:** `picturesStillFitWhenThePageChangesSize` now also runs with a render forced just before foliate sends `load`. Without the patch that case fails, with the table at 328.6 pt in a 575.4 pt column. With the patch it passes, and so did 700 repeats of both cases on 'Octavo Flaky Fixes Duo' (a throwaway simulator too). In the real app, `tools/survey.py` on *Pride and Prejudice* gives the same as section 3: 756, 412, 412 and 422 pages, none over the column. The other sample books, the cases book and vertical text weren't run again, because `bridge.js` didn't change.
- **Still pinned, as before:** a table with no width gets `min(<its natural width>, 100%)`, because `getComputedStyle` answers with a width even in the hidden frame. That's why the logo above is 275 pt sideways and not its own 300 pt, and it's harmless for the rest. It isn't part of this fix.

## Tools

Run headless, with `simctl` and `hinge` only.

```bash
docs/notes/reader-pictures/tools/make-cases.py picture-cases.epub   # the cases book; copy it to the app's Documents
docs/notes/reader-pictures/tools/survey.py <UDID> out.json [book.epub ...]
docs/notes/reader-pictures/tools/shots.sh <UDID> <folder>
```

Folding closes the reader (`page-turns.md`), so the tools open each book folded and only unfold from there. A script that folds and then reads the page gets the closed reader's last state and a Home screenshot.
