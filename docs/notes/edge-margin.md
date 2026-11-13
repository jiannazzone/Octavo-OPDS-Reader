# Edge margin: text in the side column (#136)

Investigation only, 2026-11-12, on the iPhone Duo iOS 27.1 simulator ('Octavo Edge Duo', 3FFAC972-…; 'Octavo Edge Duo 2', DD28AEF1-…; 'Octavo Edge Duo 3', 9661F7B7-0B13-4B73-901F-6EB74F87ACB9; all deleted). Nothing here is designed or approved, and the probe code wasn't committed. Moby-Dick at 30%, opened through the DEBUG remote (`openLocal`, `goto`, `controls`). Frames are in `edge-margin/`.

## Summary

- **Recommendation: a top bar instead of an Edge step.** iOS 27.1 has a supported switch, `toolbarVerticalBehavior(.disabled)` (UIKit `preferredVerticalBarBehavior`). It moves the clock, Back and ⋯ out of the side column into a horizontal band at the top, in every posture, and the column's inset goes away (section 5).
  - With foliate's top margin overlapping the band, folded Narrow holds about 13% more text a page than with the column. Hiding the column (Edge) gets about 17%.
  - Nothing is hidden: the clock, Back and ⋯ keep their tap, and Always show controls and book mode work as before.
  - Apple's header asks for it to be "a stable choice", so it fits as a setting: buttons on the side or on top (Adam, 2026-11-12).
- **Edge, the issue's idea, works but costs UX** (sections 1–4).
  - Hiding the status bar alone leaves Back and ⋯ in the column. With the toolbar hidden as well, the column clears.
  - Unfolded, the layout then spreads across the whole screen by itself. Folded, the 84 pt inset stays because of the camera, so Edge needs its own layout.
  - Edge rendered folded: text 18–448 pt, below the camera.
  - The controls need a new way up. Adam ruled out a middle tap (ambiguous). A ⋯ at the end of the footer worked.
- **The camera** (folded) is 37×37 pt at x 399.7–436.7, y 29.3–66.3. Edge's first line, at about 73 pt, clears it. In top-bar mode the camera sits in the band.

## 1. Hiding the status bar and the toolbar

The probe, in `ReaderView`:
- `.statusBarHidden(…)` after the outer `.ignoresSafeArea()`.
- `.toolbarVisibility(hide && !controls.buttonsVisible ? .hidden : .automatic, for: .navigationBar)` after `.toolbar { buttons }`.

The safe area comes from the remote's state file (`ReaderGeometry.safeArea`, via `model.safeAreaChanged`), and the regions from `DebugEvents` (`spike-events.jsonl`). Medium margins.

| Posture | Hidden | Safe area (top, left, bottom, right) | `ReaderLayout` insets (left, right) | Occlusion regions | Column on screen |
|---|---|---|---|---|---|
| Folded 466×678 | nothing | 0, 0, 34, **84** | 0, 84 | camera 37×37 at (399.7, 29.3); 84×174 at (382, 0) | clock, Back, ⋯ (01) |
| Folded | status bar | 0, 0, 34, **84** | 0, 84 | camera; 84×**82** at (382, 0) | Back, ⋯ moved up (02) |
| Folded | both | 0, 0, 34, **84** | 0, 84 | as above | **empty**, text unchanged (03) |
| Unfolded 951×669 | nothing | 0, 0, 34, **84** | 84, 84 | 84×124 at (867, 0); inner camera 58×37 at (677.3, 21), inactive | clock, Back, ⋯ (05) |
| Unfolded | status bar | 0, 0, 34, **0** | **0, 0** | inner camera, inactive | Back, ⋯ in the corner over the page (06) |
| Unfolded | both | 0, 0, 34, **0** | 0, 0 | as above | **empty**, text full width (07) |
| Half open | both | 0, 0, 34, **0** | 0, 0 | as above; the hinge's division active | empty; controls in 09 |

- **The second occlusion is the status bar's own area:** 84×174 folded and 84×124 unfolded while it shows. With the bar hidden, folded keeps an 84×82 block around the camera, and unfolded loses it.
- **The safe area follows the status bar, not the toolbar.** It's measured outside the reader's `NavigationStack`, so the toolbar coming and going changes nothing.
- **Controls with both hidden** (04, 08, 09): Back and the group come back in their glass. Unfolded they sit over the right page's top right, where the text runs to 884. Hiding them again leaves the page as it was.
- **Showing the status bar again unfolded re-paginates**, because the 84 pt inset comes back. So Edge would keep the status bar hidden the whole time.

## 2. The camera

- **Folded:** a 37×37 pt `occlusion` at x 399.7–436.7, y 29.3–66.3, with no margins. iOS reports the 84×82 block around it (x 382–466, y 0–82) and keeps the 84 pt safe area with the status bar hidden. The simulator tool (`mcp__Claude_Code_iOS_Simulator__control` screenshot) draws the camera, and `simctl`/`hinge` screenshots don't (frame 11 against 10).
- **Unfolded:** the inner camera is reported *inactive* (58×37 at x 677–735, y 21–58, over the right page). Whether that means the panel draws there on a real Duo is unchecked.

## 3. Edge folded, rendered (frames 10, 11)

The probe was a `ReaderLayout.single` case: the view the screen's width, Narrow's 18 pt margin, and a top inset of 22 pt, so text starts about 70 pt down. The status bar and toolbar were hidden while the controls were, and a ⋯ sat at the end of the footer line in the bottom margin, with the numbers moved 24 pt left.

- Text runs 18–448 pt, against Narrow's 18–364. The first line, at about 73 pt, clears the camera. That's about 26 lines of ~67 characters, against Narrow's 27 of ~55: roughly 17% more text a page.
- A real tap on the footer ⋯ brought the controls up (frame 11), and they hide again cleanly.
- With the controls up, Back and the group sit over the right end of the top lines. The progress bar still stops at the column's edge, because the safe area keeps 84 pt there.
- **UX costs** (Adam, 2026-11-12):
  - Back and ⋯ hidden while reading.
  - A new way up for the controls. A middle tap is out as ambiguous, and edge swipes all belong to the system. A long press belongs to text selection.
  - Always show controls and book mode's column tap (#5) need answers.

## 4. Edge layout sketch (if it's ever picked)

- Unfolded and half open: today's `spread` already does it once the safe area is 0 (frame 07). Better to set the right inset to 0 itself, so the layout never depends on when the status bar goes.
- Folded: its own case, as in section 3, with `ReaderGeometry` carrying the occlusion regions (it has only divisions today).
- The footer follows `textColumns`. `barSpans` and `ReaderPanelFrame` take `safe.right`, so they'd need Edge's width folded.

## 5. Top bar: `toolbarVerticalBehavior(.disabled)` (frames 12–15)

The SwiftUI modifier (`ToolbarVerticalBehavior`, iOS 27.1) and UIKit's `preferredVerticalBarBehavior` return `.disabled` to opt out of the vertical bar. Apple's header says bar content then falls back to the horizontal top and bottom bars, the status bar turns horizontal, and the column's safe-area inset goes. It asks for "a stable choice", not one toggled as you navigate or with a view's state. The probe put it on the reader's stack content (after `.toolbar { buttons }`), Narrow margins.

- **Safe area:** top 82, left 0, bottom 34, right 0, folded, unfolded and half open, with the controls up or not. `ReaderLayout` copes as it is, because that's the shape it already handles sideways. The text runs full width, 18–448 pt folded, and the spread is centred on the fold unfolded.
- **The band:** the clock and the indicators on the right, and Back and ⋯ (or the whole group with the controls up) to their left, ending near y 72. Unfolded, they sit over the right page.
- **The gap below the band** (frame 12): the 82 pt band plus foliate's own 48 pt top margin, so text started near 130 pt. Overlapping that margin with the band (top inset 82 − 46 = 36 pt) brings the first line to about 90 pt, some 16 pt below the buttons (frames 13, 15). That's the same idea as Narrow's margin under the column.
- **Folded, with the margin overlapped:** about 25 lines of ~67 characters, about 13% more text a page than Narrow with the column (frame 13).
- **Unfolded and half open:** the spread runs full width, and the group stays clear above the first line (frame 14). The bar splits at the hinge as usual.
- **Not checked:**
  - Opening and closing a book: the shell keeps its column, and the system animates the change between the two layouts.
  - The tour, whose cards point at the column's buttons.
  - Sideways, where the band is already at the top.
  - A real Duo.

## How a top-bar setting could be built (a sketch, not a design)

- A setting such as "Buttons: Side / Top" in Customize. The reader's stack takes `.toolbarVerticalBehavior(top ? .disabled : .automatic)`, and only the reader, so the shell keeps its column.
- `ReaderLayout` lets foliate's 48 pt top margin overlap the top safe area by what the band leaves empty below the buttons. That needs the band's height (82) and where the buttons end, measured, not fixed numbers.
- The footer, the bar's spans (`barSpans`, from the safe area) and the panels (`ReaderPanelFrame`) follow the safe area, which has no right inset in this mode. The panels' anchor moves from the column's buttons to the band's.
- The bookmark ribbon (`safe.right − 30`) would sit at the screen's edge, under the band's buttons. It needs a look.

## Open

- Adam's call on the top-bar setting, with mockups or the probe in the live panel.
- A real Duo: does the top bar behave the same, and where does the camera sit in the band?
