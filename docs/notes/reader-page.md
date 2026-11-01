# Reader: page area and controls (#17)

Issue #17, decisions 7, 8 and 12 in `docs/design/direction.md` (amended 2026-11-01), frames 07–09 and 14. Written 2026-11-01 on 'Octavo Reader Duo' (8465F9D3-DCB5-4B77-91B4-2815674F589D, iPhone Duo, iOS 27.1 simulator, Xcode 27.2). The spike's reader (`SpikeReaderView`) and the rest of `Octavo/Spike/` are gone; the check tools drive the real reader.

## Summary

- **`ReaderView`** (`Octavo/Reader/ReaderView.swift`) is the reading layer over the tabs (`AppShell`), never a `fullScreenCover` (`duo-tabbar.md` §6). Back closes it.
- **Edge to edge.** The `WebView` fills the screen, under the side column, the camera and the home indicator; the page colour runs under the clock and the glass buttons like the cover does. `ReaderLayout` insets the `foliate-view` so the text never reaches them. Text lands where the frames put it: folded 27–356 pt (frame 07: 27–355), unfolded 139.5–448.8 | 503.6–813 pt (frame 09: 139–448 | 503–812).
- **Controls** (decision 7, approved on screen 2026-11-01): a middle tap shows the column's buttons (Back; Contents, Text and theme, Search in book and Bookmark greyed out until #18) and the glass bar; the next tap anywhere hides them. **Always show controls** keeps only the buttons. Half-open, a tap in the side column shows them (#5's hook) and the bar splits at the hinge.
- **Progress:** each page's bottom margin shows the chapter and page (`ReaderFooter`), and the bar is a scrubber through the whole book. Numbers are foliate's locations.
- **Margins:** Narrow 4.6%, Medium 7% (the frames), Wide 10% of foliate's gap; Narrow puts the text at the column's edge.
- **Sideways unfolded:** one column straight across the fold, clear of the top band where the system column moves.
- **The current chapter** is `ReaderModel.chapter` and is saved with each position (`ReadingPositionStore.chapter(forBook:)`, `LocalReadingProgress.chapter`) for the cover strip and Home's place line (#11 wires them).
- No foliate-js change; `bridge.js` gains top/bottom insets, tap zones measured within the content, a `dismiss` tap, the contents with fractions, and `location.next`.

## 1. Where the page draws

The open question from spike 2b (`duo-spreads.md` §7 Q3): `WebView` already drew under the trailing and bottom safe areas while SwiftUI's frame stopped at them. Adam chose **edge to edge** over keeping the web view inside the safe area (which would leave the column the app's white or black beside a Sepia or Paper page, and would re-paginate whenever the toolbar changed the safe area).

- `ReaderScreen` applies `.ignoresSafeArea()` to the `WebView`, so its frame is the page (466×678 folded, 951×669 unfolded) and the hinge's region frames are in page coordinates as they are.
- **The safe area is measured outside the reader's `NavigationStack` and outside `ignoresSafeArea`.** A view laid out inside the safe area reports how far in it sits (`proxy.safeAreaInsets`: trailing 84, bottom 34 folded); a view that ignores it reports zero. Measured inside the stack it would include the reader's own toolbar, and showing the controls would move the text.
- **The keyboard is left out of it** (`.ignoresSafeArea(.keyboard)` around the measurement). Without that, the keyboard raised the measured bottom inset from 34 to 304 pt and the page re-paginated (3 relocations up, 3 down); with it, the inset and the page stay put folded and unfolded. Nothing in #17 shows a keyboard; #18's Search in book will, and the DEBUG `keyboard` command (`ReaderRemote`) checks it without one.

| Posture | Safe area (top, left, bottom, right) | `foliate-view` |
|---|---|---|
| Folded | 0, 0, 34, 84 | x 0–382, y 0–644 |
| Unfolded, flat or half open | 0, 0, 34, 84 | x 84–867 (centred on the hinge at 475.5), y 0–635 |
| Unfolded, turned sideways | 82, 0, 34, 0 | x 0–669, y 82–917 |

`ReaderInsets` are physical (left/right), converted from SwiftUI's leading/trailing with the layout direction.

## 2. Margins and the gutter

foliate keeps its outer margins and the gap between two pages equal, `gap`% of its view's width (`paginator.js`: the grid's half-gap columns plus the columns' own padding). So one number sets both, and the view's insets decide where the text can go.

- **Medium (default), Wide:** the view is the content area (folded) or the widest span centred on the hinge that the content allows (unfolded: the left edge gives up the column's 84 pt). Medium is foliate's 7%: 26.7 pt folded, 54.8 pt unfolded.
- **Narrow:** the view reaches under each edge that borders the system's area by its own margin, so the text meets that edge. Folded the margin is 18.4 pt and the text ends at 382; unfolded the gap is raised just enough to cover the hinge (4.7% after rounding up: a 40.6 pt gutter) and the text runs 84–455.5 | 495.5–867.
- **The gutter never drops below the hinge's 40 pt**: the gap is the larger of the setting and the fold's share, rounded up to 0.1%.
- Top and bottom: the view's top and bottom insets are the safe area's; foliate's own 48 px top and bottom margins hold the running space, and the footer sits in the bottom one.

`ReaderLayout.textColumns(inReaderWidth:)` reproduces foliate's arithmetic for the footer and the tests (`ReaderLayoutTests`: frames 07 and 09 within 0.5 pt, every margin step folded and unfolded, sideways).

## 3. Controls and taps

`ReaderControls` (pure, `ReaderControlsTests`) holds what shows; `ReaderModel.coversPage` tells the bridge when a tap should only hide them.

| Tap | Flat or folded | Book mode (half open, two pages) |
|---|---|---|
| Left / right 30% of the page outside the system's areas | previous / next page (the way the book reads) | left / right of the spine: previous / next |
| Middle 40% | show or hide the controls (with Always show controls: the bar) | — |
| Side column | counts as the right side (next page) | show or hide the controls |
| Anywhere while the bar shows | hide the controls | hide the controls |

- Book mode now also needs two pages: half open sideways (one column across the fold) reads like flat (`ReaderModel.isBookMode`). Starting or ending book mode hides the controls (decision 9).
- The buttons are the system toolbar (`ToolbarItemGroup(placement: .topBarTrailing)`): folded and unfolded the system puts them in one glass group in the column under the clock; sideways, in a glass bar along the top next to the clock.
- A book that fails to open keeps Back up.
- VoiceOver: an accessibility action "Show Controls" on the page.

## 4. Progress: footer and scrubber

- **Footer** (`ReaderFooter`): in foliate's bottom margin, one line per page; a spread puts the chapter under the left page and the numbers under the right. Hidden while the bar shows. Drawn by SwiftUI over the page, under the fold's cross-fade, outside the book's content.
- **Bar** (`ReaderProgressBar`): glass, 60 pt, 12 pt from the screen's edges and clear of the column (over the home indicator, as frame 08 draws it). Chapter, a system `Slider` through the whole book, "Page 291 of 974 · 30%" ("Pages 291–292" on a spread). While dragging, the chapter and page under the thumb show (`ReaderPlace(fraction:toc:total:)`, from the contents' section fractions that `bridge.js` sends with `opened`); letting go calls `goTo(fraction:)`, which re-anchors on the page (`anchorToPage`, spike 2b). Half open, the bar splits at the hinge.
- **Numbers:** foliate's locations (`SectionProgress`, 1,500 characters each). `location.current` is where the page starts, `location.next` where it ends; shown from 1. A folded page holds about 1,100 characters, so a page turn doesn't always change the number (parked in `UI-IDEAS.md` with real page numbers). The percentage rounds down, so 100% means the end.

## 5. Cold launch into the reader

The #4 session saw a cold launch straight back into the reader get no hinge and no geometry until the hinge moved; #5 couldn't reproduce it. Neither could this session:

- **The spike's reader** (before it was deleted; its library reopened the last book): 9 cold launches. All 7 that had opened the book by the time of the read (12–20 s) had the hinge and the page's size: 4 folded at 466×502, 3 unfolded at 951×493 with the spread. The other 2, the first launches after an install, hadn't opened the book yet at 12 s.
- **The new reader** through the shell (`-connectBookOrbit 1 -shellReading 1`, which opens the first Continue reading book once signed in): 3 cold launches, 2 unfolded and 1 folded, all laid out right: the spread centred on the hinge (text 138.9–448.2 | 503.0–812.3) or one page in the 382 pt area (27.1–355.6). Once, the DEBUG state file wasn't written until the first page turn, though the screen was right. A state file read straight after a cold launch can lag the screen, which may be what #4 saw.

Nothing in the app reopens a book on launch except the debug `-shellReading 1`.

Hardening anyway: with no hinge reported, `ReaderLayout` now makes a spread from the fold's region even when it's inactive (flat), so a missing hinge report can't put text on the fold unfolded. Folded there's no region and foliate decides (one column, the page is portrait).

## 6. Bug found: close, reopen, unfold

Opening a book, closing it, opening one again and then unfolding crashed the app (`EXC_BREAKPOINT` in `_WebKit_SwiftUI`, under `PlatformViewRepresentableAdaptor.makeViewProvider`: SwiftUI making a `WebView`). Found by the fold-continuity run, whose `home` + `openLocal` does exactly that; reproduced three times (twice with the same book reopened, once with another book), and gone with the fix in three runs (the same repro twice, and a mix of fast reopens, folds and a close while unfolded).

- Cause: the reader layer faded out on close (`.transition(.opacity)` under `.animation(.default, value: reading)`, from #6). The closing reader stayed in the hierarchy with its `WebPage` attached, and an unfold had SwiftUI rebuild its `WebView`, which WebKit traps on. Without the fade the first reader's model is freed and nothing crashes. `main` had the same fade on `ReaderPlaceholder`, so the crash probably predates #17.
- Fix: the reader fades in and leaves at once (`.transition(.asymmetric(insertion: .opacity, removal: .identity))`).
- Also fixed on the way: the closures the reader hands its model (`onControlsTap`, `onBookModeChange`) captured the view, so every closed reader's model and web page stayed alive. They capture a binding now.

## 7. Checks

All on 'Octavo Reader Duo' with this build (margins Medium), 2026-11-01.

**Fold continuity** (`duo-spreads/tools/fold-run.py`, the 2b/#5 origins and eight moves each: open, close, half, close, open, half, open, close; raw in `reader-page/runs/continuity/`). 9 runs, 72 moves:

| | Folds back to one page | Opens / half-opens |
|---|---|---|
| Moby-Dick 30%, 90%; P&P 50%; Frankenstein 50%; Alice 60%; Sherlock 85%; P&P PREFACE | exact, 21 of 21 | contains by CFI and first words, 35 of 35 |
| P&P dedication (an illustration, no text) | exact, 3 of 3 | contains by CFI, 5 of 5 |
| P&P blank page after the dedication | exact, 3 of 3 | contains by CFI, 5 of 5: the spread now opens on the PREFACE, which holds the blank page's anchor |

- **Totals: exact 27, contains 45 (35 by words too), lost 0.** #5 had exact 27, contains 30, CFI only 10, lost 5 (all five on the P&P blank page, whose unfolds landed on the dedication spread). The blank page's unfolds now land on the spread holding the PREFACE.
- No text touched the fold region in any of the 45 open or half-open states: left pages end at 448.2–448.8 pt, right pages start at 503.0–503.6 pt, the hinge is 455.5–495.5.
- P&P still reaches the dedication in 9 page turns from section 1, the blank page in 10 and the PREFACE in 11, as in #5.
- The first attempt found the crash in section 6 (its `home` + `openLocal` between runs); these runs are after the fix.

**Patch 0001's page-by-page comparison** (`foliate-blank-page/`): re-run as `PINNED.md` asks, although no foliate-js file changed. Output **byte-identical to `compare.txt`**: 1,609 pages, 1,546 same CFI, 63 blank in upstream, 0 CFI differences on pages with content, 0 layout differences. About 13 minutes. The exact steps and batch inputs are now in `foliate-blank-page-upstream.md` ("Reproducing this") and `foliate-blank-page/tools/dump-*.txt`.

**BookOrbit position round trip** (`sync-spike.md` method, against BookOrbit v3.6.0's web reader at 375×812 on `reader17.localhost:3300`, user `octavo`; raw in `reader-page/runs/roundtrip/`): the five books at 50% + 2 pages app → web, and 75–80% + 2 pages web → app, through the real pull and push (`open` attaches BookOrbit sync). **10 of 10**: every web page held the app page's first 8 words, and every app page held the web page's (`check.py`). The app's pushes and the web's saves landed in the same progress row both ways.

**Unit tests:** app 163/163 (`xcodebuild test`, `-parallel-testing-enabled NO`), OctavoKit 98/98 (`swift test`).

**Again after syncing with `main`** (`17ffad9`: #8 OPDS, #9 network trust, the icon) and the keyboard fix (section 1), same simulator: fold continuity 72 moves, exact 27/27, contains 45/45 (35 by words), lost 0, no text in the fold region (`reader-page/runs/continuity-main/`); patch 0001's comparison byte-identical again; BookOrbit round trip 10 of 10 (the same app positions, web positions at 70% + 2 pages; `reader-page/runs/roundtrip-main/`); app tests 171/171, OctavoKit 195/195.

## 8. Check tools after the spike

`Octavo/Debug/ReaderRemote.swift` (DEBUG only) replaces `SpikeRemote` with the same files (`Documents/spike-command.json`, `spike-ack.json`, `spike-state.json`, `spike-js.json`, `spike-events.jsonl`) and commands, so the tools in `duo-spreads/`, `duo-fold/`, `sync-spike/` and `formats-spike/` run unchanged except that no `-spike 1` launch argument is needed.

- `openLocal` (`name`): a book in the app's Documents straight into the reader (no sync).
- `signin`: `LibraryModel.connectLocalBookOrbit` (one login; 5 per minute per IP).
- `open` (`fileID`): the BookOrbit book holding that file, through `ShellModel.openBook` (download, Continue reading), with a `BookOrbitProgressSync` for that file. Only books a script opens sync; the app's own sync is #11.
- `detail` (`fileID`): the book's cover page in the Library tab, for `handoff.sh`. BookOrbit books only: a book in Documents has no cover page, so `handoff.sh`'s local-book form no longer works.
- `keyboard` (`on`): shows or hides the keyboard over the reader through a hidden text field.
- `home`, `close`, `goto`, `next`, `prev`, `shape`, `layout`, `watch`, `js` as before. The state file adds `location` and `margins`.
- `DebugEvents` (was `SpikeEvents`) logs hinge, region, safe-area and scene events for the shell and the reader.
- The Settings stand-in has a DEBUG "Reader" section (Always show controls, Margins, Book-mode shadow) until the Customize panel (#18); same keys.

## 9. What the reader needs from the shell

Written for the custom shell that replaces `PaneStack` after #17 (Adam, 2026-11-01). The reader asks for one optional book and a way to close it; it handles its hinge, book mode, layout, controls and insets itself.

1. **A layer over everything** for `ShellModel.reading`, in the same view hierarchy: never a modal presentation (an unfold leaves one on its side, `duo-tabbar.md` §6), `.id(book.reader)`, and no fade-out on close (section 6).
2. **The whole window, side column included, while reading.** The reader's controls live in the column and its page takes taps there (book mode). No shell view may draw over it, take taps over it or claim the column; a custom tab column or toolbar goes under the reading layer or hides.
3. **Its own column controls.** They are the system toolbar of the reader's `NavigationStack`. If the shell's buttons go custom, either leave the reader's as they are or give it the same component (vertical glass group under the clock, show/hide, disabled states, VoiceOver, a sideways placement).
4. **The window's frame and safe area**, untouched: the reader measures the safe area and the hinge's regions itself, so no padding, `safeAreaInset`, offset or transform around the layer, and the column must stay a trailing safe area (or its width must reach the reader another way).
5. **The unfold hook:** `.onHingeChange` → `ShellModel.hingeChanged` → the selected tab's deepest route's book → `openBook` → `reading`. The hinge reports about 200 ms before the scene moves, so the folded screen's book must still be known then.
6. **Little work under the reader on a fold**, and the screen beneath unchanged, so the reader's single re-layout per fold holds and Back after a fold lands where the book opened.
7. **The DEBUG hook's API:** `reading`, `openBook(_:)`, `tab`, `[path:].routes`, and `ReaderRemote.run(shell:)` started by the shell.

## 10. Open risks

- **The column's width comes from the safe area.** If a later iOS stops reporting the side column as a trailing safe area on the Duo, the text would run under it. Checked only on the iOS 27.1 simulator.
- **foliate internals:** `textColumns` mirrors foliate's grid and padding arithmetic for the footer; a foliate update that changes it misplaces the footer (not the text). Add it to `PINNED.md`'s update checks if it moves.
- **Simulator only**, as for #5.

## Reproducing

```bash
export SIM=8465F9D3-DCB5-4B77-91B4-2815674F589D
docs/notes/duo-spreads/tools/install.sh                       # build, install folded, launch
docs/notes/duo-spreads/tools/app.sh '"cmd":"openLocal","name":"moby-dick.epub"'
docs/notes/duo-spreads/tools/fold-run.py moby-mid moby-dick.epub --fraction 0.3 > run.jsonl
```

Launch arguments for looking at the settings: `-reader.margins narrow|medium|wide`, `-reader.alwaysShowControls 1`.
