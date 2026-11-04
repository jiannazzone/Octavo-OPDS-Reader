# Page turns and opening a book (decisions 27 and 28)

Decisions 27 and 28 in `docs/design/direction.md`. Written 2026-11-03 on 'Octavo Page Turns Duo' (EB8983D2-57C9-4C7D-8847-6E21AB266E3E, iPhone Duo, iOS 27.1 simulator, Xcode 27.2), driven with Hinge 0.3.0, mostly on the bundled Standard Ebooks *Pride and Prejudice* (one chapter per file) and the local BookOrbit's copy for the book's screen. Videos, stills, probe data and tools are in `page-turns/` next to this file. Nothing here has been on a real Duo yet; every speed and wait is the simulator's.

## Summary

- **Folded, a page slides; open, it flips over the spine** (flat and half open alike; in book mode each half turns its own way). Fade and None are the other choices, in **Page Turn** in Customize (below Margins, a menu like Font's), saved as `reader.pageTurn`. Automatic fades with Reduce Motion; a style picked by hand is kept. None is foliate's own instant turn and drag, as before.
- **Swift draws every turn from snapshots of the page**, and foliate turns at once underneath. A snapshot takes 2–5 ms; foliate's next page is on screen 20–70 ms after the turn starts (section 1), so the turn moves the moment a finger does.
- **A swipe drives the turn under the finger**, both ways; let go before halfway without a flick and the page falls back, and nothing is saved or synced for it. Taps, the keyboard and the trackpad play the whole turn: 0.3 s slide, 0.5 s flip, 0.15 s fade.
- **A turn looks the same across a chapter break**: the new chapter is drawn 70–250 ms after the turn starts on this simulator (one run 409 ms). A tap's turn waits up to 100 ms for the new page, so it usually moves in whole; past that it starts over the page's colour and the page fades in when it comes.
- **A book opens like a cover** (provisional): from its own screen, the cover moves onto the right page, rests there while the book loads, and swings over the spine as your left page; folded it swings away to the left. **Back onto the book's screen plays it backwards.** Reduce Motion cross-fades. From anywhere else, and for folds, nothing changed.
- **The reading position and its syncing are unchanged.** A turn is foliate's own `goLeft`/`goRight`; the place holds through unfolding, book mode and back (section 6).
- **No foliate patch.** `bridge.js` changed (section 3), every script-blocking layer untouched, so the BookOrbit round trip, fold-continuity and blank-page re-runs that a patch needs weren't required.

Videos (`page-turns/videos/`, half speed unless named otherwise):

| Posture | What | File |
|---|---|---|
| Flat | A tap's flip | `flip-tap-flat-half-speed.mp4` |
| Flat | A finger lifts the page, puts it back, then turns it | `swipe-lift-putback-turn-flat-half-speed.mp4` |
| Half open (110°) | Flip forward, then back, over the spine shadow | `flip-book-mode-forward-back-half-speed.mp4` |
| Half open | Flips back and forward across a chapter break | `flip-book-mode-chapter-break-half-speed.mp4` |
| Folded | A tap's slide; the slide back | `slide-tap-folded-half-speed.mp4`, `slide-back-folded-half-speed.mp4` |
| Folded | A finger's slide, put back, then on into the next chapter | `slide-swipe-folded-half-speed.mp4` |
| Folded | Fade | `fade-tap-folded-half-speed.mp4` |
| Flat, folded | Opening from the book's screen (real speed) | `open-cover-flat.mp4`, `open-cover-folded.mp4` |
| Flat, folded | Closing with Back (real speed) | `close-cover-flat.mp4`, `close-cover-folded.mp4` |

Stills: `page-turns/screenshots/` (the flip mid-turn flat and in book mode, a flip held by a finger, the cover waiting on the right page, the Page Turn menu, the chapter-break gap).

## 1. Can the next page be ready when a finger lands?

Measured before building, with `TurnProbe` (DEBUG; the remote's `turnProbe`). It snapshots the page five ways, then turns foliate at once (no `animated`) and snapshots the page at 0, 20, 40, 70, 100, 150, 250 and 400 ms, judging each against pictures of the pages before and after. Each turn runs uncovered, under an opaque snapshot of the page, and under a 99% one, within a chapter (from its third page) and across a break (from a chapter's last page). Raw: `page-turns/probe/se-{folded,flat,half}/turn-probe.json`.

| | `snapshotView` of the page | `WebPage.exported` (the fold's) |
|---|---|---|
| Folded | 3–6 ms (first 153) | 26–33 ms (first 1,197) |
| Flat | 2–3 ms (first 11) | 39–45 ms |
| Half open | 3–4 ms (first 35) | 36–86 ms |

When the new page first showed in a snapshot, in ms after the turn was asked for:

| | Same chapter | Next chapter |
|---|---|---|
| Folded | 40–72 (one 152) | 71–251 |
| Flat | 22–72 | 72–409 |
| Half open | 22–100 | 71–73 |

- **A snapshot of the web view (`UIView.resizableSnapshotView`) is fast enough**; the fold's `exported(as: .image)` isn't (it reads the pixels back). A snapshot view is a reference to what the screen shows, so it costs nothing to draw, but it can sit in one place only: each half of a spread that's drawn is its own snapshot.
- **foliate keeps drawing under a cover of itself**, opaque or not.
- **Across a chapter, foliate shows a blank page** while it loads the next file (`page-turns/screenshots/probe-chapter-break-flat.png`): it scrolls to the paginator's padding page first, then loads, lays out and relocates.
- **Preloading the next chapter wouldn't help much** (asked about by Adam). Measured in the page with a temporary hook: loading and hardening the next chapter's file takes 9–12 ms (0 once cached); the new section's `load` event comes 11–21 ms after the turn and its page is drawn 47–67 ms after, the same whether the file was loaded ahead or not (48–50 ms). Laying out the chapter is the cost, and foliate keeps one section laid out at a time, so the chapter can't be laid out ahead without a second paginator. Not built; the 100 ms wait covers the usual case. Adam reports loading is faster on his Duo.

## 2. How a turn works

`ReaderModel+Turns.swift`, `ReaderTurnView.swift`, `ReaderPageSnapshots.swift`, `ReaderPageTurn.swift`.

1. A turn snapshots the page (the pictures each motion needs: the whole page for a slide or fade, each half for a flip) and lays them over the web view as `ReaderTurn`, with each page's footer drawn from its place (the live footer hides meanwhile).
2. It asks the bridge to turn at once (`window.octavo.turn(side, hold)`), which resolves once the new page is drawn: whether it moved (not at the book's start or end) and its relocation, for the new page's footer. Across a chapter that's the new section's relocation, not the blank page's.
3. Swift snapshots the new page (only what's needed: under a flip, just the page on the back of the turning page; the web view shows the rest) and fades it in if the turn is already moving. A second look 100 ms later replaces a snapshot taken a frame too early.
4. The motion plays: `ReaderTurnLeaf` (what moves) over `ReaderTurnBase` (what lies still), the book-mode spine shadow between them. Once it's over and the page is drawn, the pictures go.

- **Sides are physical**: `.right` is the right-hand page going (foliate's `goRight`), forward in a left-to-right book. A tap, ←/→, the trackpad sideways go by side; ↑/↓, Page Up/Down and Space by direction (`forwardSide()` in the bridge).
- **The flip**: the turning half rotates about the spine with `rotation3DEffect` (perspective 0.35), darkening as it stands up; past 90° its back shows, the new page mirrored so the swing shows it the right way round. On one page (Flip picked folded) it turns about the left edge.
- **A finger's flip keeps the page's edge under it**: progress `t` with `pageWidth × (1 − cos πt)` = distance moved (`ReaderTurnDrag.progress`). A slide or fade follows point for point. Letting go: a flick of 0.35 pt/ms or more goes the way it points, else past halfway finishes; the rest plays at the turn's pace, never under 0.12 s.
- **Turns asked for while one is drawing** queue (up to three); once the current one's page is drawn it ends early, so rapid taps keep up.
- **Folding mid-turn** ends the turn where it was going and the fold's own cover takes over.

## 3. Swipes: why UIKit, not the page

The bridge first tracked swipes with touch events and posted their progress. It worked on the first swipe after a page loaded, then the turn stopped following: **once foliate turned under a finger, WebKit stopped passing that touch to the page** (the frame's `touchmove`s kept arriving at a spy listener but no longer at the bridge's, and later swipes on the same page worked). So a finger's turn is recognised in UIKit (`ReaderSwipeRecognizer`): a `UIPanGestureRecognizer` on the web view's superview (WebKit's own gestures don't hold it back there), recognising alongside WebKit and taking the touch once it starts, so the page sees a cancelled touch, not a tap.

- It starts after about 10 pt mostly sideways, measured from where the finger landed (the pan's own translation starts 10–20 pt in, and every swipe read as going back), not after a press held 0.3 s (selecting text), and not while text is selected (the bridge posts `selection` on `selectionchange`).
- The bridge mutes touches for foliate while Swift draws turns (capturing listeners stop them before foliate's drag; moves are prevented as foliate does). With None it's off and foliate drags as before.
- `bridge.js` changes: `turn`/`endTurn`/`setTurnMode`, the `turn` and `selection` messages, taps/keys/trackpad going through `askTurn`, touch muting. The CSP, the hardening layer, the load hook, the frame check and link handling are untouched.

## 4. The reading position

- A tap's turn is foliate's own turn: its relocation is saved and pushed as before (2 s debounce, flushed on close).
- A swipe's turn is held (`hold`): its relocations are kept back until it's let go. Finished, the last one is posted; fallen back, foliate turns back still held and nothing is posted. Checked: a swipe that fell back left the relocation count, the saved place and the last push unchanged; a finished swipe and a tap each moved and pushed once.
- A hold for a fold ends a swipe's hold first (`finishTurnForFold`).

## 5. Opening and closing like a cover

`ReaderCoverMotion.swift`, `ShellModel` (`coverMotion`, `readerClosing`), `AppShell`.

- **Opening.** Open on the book's own screen snapshots the window and lays it over everything (`ReaderCoverMotionView`, pinned to the window's corner: the shell lays it out inside the safe area, 42 pt in and 17 down folded). The reader opens underneath at once. Unfolded, the cover moves from the left page onto the right (0.35 s), the mirror of where it was, rests there until the reader has drawn your place (2–3 s on this simulator, the wait that used to hide under the fade), then swings over the spine with your left page on its back (0.5 s). Folded, the strip and the column's buttons go and the cover swings away to the left (the visible half of a swing, 0.25 s). Unfolding on a cover keeps the fold as its motion.
- **Closing.** Back onto the book's own screen takes pictures of your pages, then the reader goes at once, as before: a reader still on screen, fading out, would be rebuilt by an unfold, which WebKit traps on (`AppShell`'s comment). The motion plays over the live book's screen: your left page swings back as the cover, which lands on the right page and moves back to its place; folded, the cover swings in from the left. Back onto anything else (Home, a list: see `docs/PLAN.md`, To revisit) closes at once as before; so does folding.
- **Reduce Motion** cross-fades (0.3 s) both ways.
- Bugs found on the way: the reader said it had opened only from relocations, which all came while it was still loading (it now also checks when it opens); the move to the right page started in the same frame as the web view was made and was swallowed (it starts 50 ms after the overlay appears); folded, half the swing was off the screen and the page sat still for 0.3 s.

## 6. Checks

- **Every posture**: the videos above. Flips forward and back flat and half open, across chapter breaks; slides both ways folded; fade; None (a tap turned at once, a swipe used foliate's drag).
- **The place through folds**: reading at a watched CFI folded, then unfolded, half open (flip forward and back), flat: the visible page contained it throughout.
- **Page Turn**: picked in the menu, it applied to the next turn; with the simulator's Reduce Motion on, Automatic resolved to a fade and Flip and Slide stayed.
- **Tests**: `ReaderPageTurnTests` (24: the setting and the motion each posture gets, a finger's turn, flicks and pace, the pictures each motion takes, the bridge's messages). App tests 373 passed; OctavoKit 253 passed.

## 7. Follow-ups

- **Set the speeds and the 100 ms wait on a real Duo**, and see the opening and closing there (decision 28 is provisional). Turning back waited 61–192 ms for its page here, forward 56–83 ms.
- **Back lands on the screen the book was opened over**, so the closing plays only when that's the book's screen (Adam's decision, 2026-11-03).
- **A layout change during a held swipe** (a text-size change can't happen mid-swipe, but a late `setLayout` could) would post the held relocation early. Not seen; worth a guard if it ever is.
- **Opening and closing pictures leave out the page's footer**, and the controls vanish as the book closes.
- Once, after many quick open/close cycles driven by the remote, Open did nothing until a relaunch. Not reproduced.
- Curl stays parked (`docs/UI-IDEAS.md`); it would draw from the same snapshots.

## Tools

`page-turns/tools/`: `remote.sh` (send a `ReaderRemote` command: `turn`, `swipe` to hold a turn part way, `turnState`, `pageTurn`, `coverMotion`, `turnProbe`), `film.sh` (record a display while sending commands, then a contact sheet of the frames that change) and `sheet.py`. Set `SIM` to the simulator's UDID. Real finger swipes came from the simulator control's `touch_path`; the Back and Open buttons from its `tap`.
