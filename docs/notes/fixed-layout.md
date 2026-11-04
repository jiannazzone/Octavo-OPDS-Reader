# Fixed-layout books in the reader

Pre-paginated EPUBs through foliate's `foliate-fxl` renderer, 2026-11-04. Measured on simulator **Octavo Fixed Layout Duo** (`6DAA2481-A83B-498E-B791-AEBA4BA23B14`, iOS 27.1), against BookOrbit v3.6.0 in Docker. The book is `fixed-layout/tools/make-test-book.py`: twelve 1000×1400 pages whose files differ in size, as a real book's do, because foliate's fractions and locations count bytes.

CBZ uses the same renderer, so it was broken the same way and is fixed with it. A six-image test CBZ opened, turned and reopened on the same page, folded and unfolded. The native comic reader in `CLAUDE.md` is still the plan.

## What was wrong

| # | What happened | Cause | Now |
|---|---|---|---|
| 1 | "Couldn't Open" (since 522014f, step 11) | `applyAppearance` called `renderer.setStyles`, which this renderer doesn't have | `setStyles?.()`. Its pages are as the book drew them. |
| 2 | Unfolding threw, and the fold's hold never ended | `applyLayout` called `renderer.render()`, also missing | Setting `zoom` to the `fit-page` it already uses renders it |
| 3 | Each open landed a page further on | See "The position" | The CFI first, like any other book |
| 4 | Bookmarks never lit up, and a server place on this page was offered anyway | `onPage` asks whether a CFI falls in the page's range, and a section's CFI has no range | By section, both pages of a spread |
| 5 | Going to the other page of a spread wasn't saved | foliate reports nothing there | Patch 0003, see below |
| 6 | Tapping the left part of a page turned forward | A frame scaled to fit reports tap coordinates in its own larger pixels | The tap is scaled back |
| 7 | `rendition:spread="both"` put two tiny pages on the folded phone | foliate's rule, from the view's shape and the book's setting | One column means one page: `applyAttributes` sets the renderer's public `spread` |
| 8 | Narrow margins ran the page under the side column | The margin setting reaches under it by the margin, which suits only margins that aren't drawn | These books lay out as Medium, which is the safe area |
| 9 | A bookmark's place had no chapter or words | `describePlace` resolved a range the CFI doesn't have | The section's whole page, its contents entry by index |
| 10 | A CFI naming a page the book doesn't have opened nothing | foliate's renderer returns without a word, and `goTo` still reports success | `goToPoint` checks, so `restore` goes on to the fraction |

## The position

What foliate reports for a page here:

- **The CFI names the section:** `epubcfi(/6/12)`, with no path into the page. The web reader stores the same string.
- **The fraction is the section's end** (`fraction: 0, size: 1`), which is also the next section's start. So `goToFraction` of it lands a page late.

**BookOrbit's web reader never uses the CFI on these books.** It reads `rendition.layout`, skips the CFI on open, and goes by the stored percentage (read from its reader bundle, then measured). That percentage is foliate's section end, in a Postgres `real`, so rounding decides which side of the boundary it falls on:

| Row the web reader saved | Page it was on | Page it reopened on |
|---|---|---|
| `/6/12`, 16.688917 | 6 | 6 (rounded down) |
| `/6/6`, 4.120288 | 3 | **4** (rounded up) |

The web reader doesn't save on opening, so the row stays and it lands late the same way each time.

So:

- **Octavo opens by CFI, then the fraction, then the start.** The earlier "fixed-layout books go by fraction, as BookOrbit does" copied the bug. The CFI is exact, because a spine step can't drift.
- **Octavo saves and pushes a fraction just inside the section** (`fixedPageFraction`: the end less 1e-5 of the book, or half the section if that's smaller; the last page is 1). 1e-5 is far past what a `real` can move (under 1e-7 here). So BookOrbit's web reader opens on Octavo's page.
- **A fraction with no CFI** is taken 1e-6 back first, so a section's end from the web reader, rounded up or down, means that section. It happens when the pull fails and the library list's percentage is all there is.

BookOrbit's own percentage for the book barely changes, as the two differ by 0.001% of it.

### Round trip with the local BookOrbit

- **Web → app:** the row above, `/6/6` at 4.120288, opened on page 3 in the app, where the web reader itself lands on page 4. A row set for page 8 did the same from a fresh launch. Opening pushed nothing.
- **App → server:** pages 1, 2, 3, 8, 9, 10, 11 and 12 pushed `/6/2` at 0.921851, `/6/4` at 2.1951518, `/6/6` at 4.1192875, `/6/16` at 33.452766, `/6/18` at 45.50657, `/6/20` at 60.416534, `/6/22` at 78.48055 and `/6/24` at 100.
- **App → web:** reloading the web reader on the rows for pages 3, 9 and 11, whose section ends round up in a `real`, opened on 3, 9 and 11. The rows for pages 1, 2, 8, 10 and 12, through its own `goToFraction`, landed on 1, 2, 8, 10 and 12.
- **The server's place in an open reader:** moved on by another reader, offered in the capsule folded and unfolded; **Go** went there and the row kept its value; turning the page left the offer and pushed this page; a place on the other page of the spread on screen wasn't offered.
- **A bookmark** on page 8 reached the server as `epubcfi(/6/16)`, titled with its chapter.

The reader reuses a pull up to 5 minutes old (`BookPlaces`), so reopening a book straight after moving it elsewhere opens on the older place, as for any book. The book's screen pulls again, and so does coming back to the app.

## The fold

- **Unfolded, half open and flat** keep the same pages, with no relocations. The two pages meet on the fold's centre: 475.5 pt in a fold of 455.5–495.5, because `ReaderLayout` centres the view on it. They're in the frames 84–475.5 and 475.5–867. This is how a printed spread runs into its gutter, so nothing is moved off the hinge, and the page's inner 20 pt lie in the region half open.
- **Folding from a spread closes the reader** back to the book's screen, as for every book (`ShellModel.hingeChanged`). The spread 6–7, saved as `/6/12`, folded and reopened on page 6. Page 9, saved folded, reopened on 9, and unfolded on 8–9.
- **Which page of a spread is "the place"** is foliate's `#side`: the left after turning forward, the right after turning back. Both show unfolded, and folded the reader opens on that one.
- **Unfolded and turned sideways** it's one page across the fold (597×835 pt), as decision 12 has it for text.
- **Folded and turned sideways, it shows two pages** of 297×416 pt, because foliate's rule goes by the view's shape and has no setting for that. One page there would be 309×432 pt, as height limits both, so I left it, against "one page folded". It's in `docs/UI-IDEAS.md`.
- **A swipe that falls back on a spread** ends on the same two pages with the model's position unchanged, though foliate's `#side` is now the right-hand page. A fold closes the reader and reopens from the model's position, so nothing reads it.

Reopening: four times folded on page 6, three on page 9, three unfolded on 8–9, all exact, and from `cfi` each time. Turning with Page Turn None, and swipes kept and fallen back, folded and unfolded, went to the right pages. With Narrow margins, the page stays out of the side column folded (0–382 pt) and unfolded (84–867 pt).

## Going to a page in the same spread (patch 0003)

`goToSpread` for the spread already open re-renders and stops: no `#side`, no relocation. Measured folded on page 6, going to page 7:

| | Shown | Model's position | Relocations | After a resize |
|---|---|---|---|---|
| Without the patch | Page 7 | `/6/12`, page 6 | 2 → 2 | Back to page 6 |
| With it | Page 7 | `/6/14`, page 7 | 2 → 3 | Stays on page 7 |

## Book scripts

Page 5 of the test book has an inline script and an `onload`, both of which would mark the page. Fixed layout loads each section the same way as the paginator, through `section.load`, so `hardenBook` and the CSP both apply. Using the launch switches from `docs/notes/formats-check.md`:

| Layers | Marked |
|---|---|
| CSP off, hardening off (the positive control) | `onload` ran |
| Hardening alone | Nothing |
| CSP alone | Nothing |
| Both, as shipped | Nothing |

## The footer counts the book's pages

Foliate's locations and fractions count bytes, so a 12-page book said "9 of 80 · 16%" on page 6. Adam approved page numbers on 2026-11-04.

- **Footer, bar, contents, search and bookmarks** count the book's pages: "6 of 12 · 50%" folded, "6–7 of 12 · 58%" on a spread, with the percentage at the end of the last page shown. `fixedPlace` sends them in the relocation, and `sectionFractions` places the contents and search results the same way.
- **The slider moves by pages,** and goes to the page its label names (`goToFraction`, which only the reader's own controls call).
- **What's saved and synced doesn't change:** `Relocation.fraction` still counts bytes, as the web reader needs it to. The footer reads `shownFraction`. So Home, a book's screen and the server-place capsule keep BookOrbit's percentage, which can differ a little on a book whose page files are uneven: page 6 of the test book says 50% in the footer and 16% on Home, and real books should be much closer.
- **A re-layout reports itself:** the renderer says nothing when a fold changes the pages on screen, so `setLayout` posts the relocation again.
- **Section starts are 1e-7 inside the page,** because a page's place is its end, which is otherwise exactly the next page's start, and would name the next chapter on a chapter's last page.
- **Folded and sideways** shows two pages with one column, so the footer says "6 of 12" for 6–7. It's a rare posture and part of the parked question in `docs/UI-IDEAS.md`.

Checked on the simulator: folded, unfolded and half open, a turn in each, the contents panel (Front 1, Middle 4, Back 9, as the book has them), the bar and its slider at 58%. Pushes after the change were the same byte-based percentages as before.

## Not done

- **Search has no highlight on these books:** foliate's fixed-layout renderer has no overlays. Going to a match works.
- **`rendition:spread="none"` unfolded** puts one page straight across the fold, and **the Text panel's text controls** do nothing here. Both are in `docs/UI-IDEAS.md`, for the owner.
- **Real fixed-layout books and a real Duo:** only the test book so far, in the simulator. Downloading one needs the owner's OK.

## Tools

`fixed-layout/tools/`: `make-test-book.py` (the book; `--spread` for the variants), `remote.py` (drives the debug remote, reads which pages show), `bo.sh` (the server's row, or another reader moving it).

The checks themselves are `OctavoTests/ReaderFixedLayoutTests`, which open a real book in a page that's never shown. A hidden page draws no frames, so those tests replace `requestAnimationFrame` with a timer, and turning, folding and tapping on screen are simulator checks.
