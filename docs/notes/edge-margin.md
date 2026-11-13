# Edge margin: text in the side column (#136)

Investigation only, 2026-11-12, on 'Octavo Edge Duo' (3FFAC972-89D0-4102-8AA6-4582FA16CC77, iPhone Duo, iOS 27.1 simulator). Nothing here is designed or approved; the probe code wasn't committed. Moby-Dick at 30%, Medium margins, opened through the DEBUG remote (`openLocal`, `goto`). Screenshots in `edge-margin/`.

## Summary

- **The status bar hides.** `.statusBarHidden(true)` on `ReaderView` (after the outer `.ignoresSafeArea()`) takes the clock and the indicators away folded, unfolded and half open. The route is open, on the simulator. A real Duo hasn't been checked.
- **Folded, the column stays.** The safe area keeps its 84 pt on the right: the camera sits in the column, and iOS keeps the whole strip safe. The column's buttons move up into the clock's place.
- **Unfolded and half open, the column goes.** The right inset drops from 84 to **0**, and the reader as it is re-centres the spread on the whole 951 pt, because `ReaderLayout` takes the column from the safe area. Unfolded, the column is only the status bar. The buttons float in the top right corner, over the page.
- **The camera** (folded) is 37×37 pt at x 399.7–436.7, y 29.3–66.3. Text running under the column would have to start below it. foliate's columns are rectangles, so the whole page's top would come down: about 18–34 pt (one or two lines), depending on whether the text has to clear the camera itself or the 84×82 block iOS reports around it.
- **Two things the design has to settle.** The Back and ⋯ buttons stay on screen while reading (not only with Always show controls), so in Edge they'd sit on the text. Controls come up only from that ⋯ button today (Adam, 2026-11-02), so Edge needs some other way to bring them back.

## 1. Hiding the status bar

The probe: `.statusBarHidden(UserDefaults.standard.bool(forKey: "probeHideStatusBar"))` after `.environment(\.colorScheme, …).ignoresSafeArea()` in `ReaderView`, launched with `-probeHideStatusBar YES` or `NO`. Safe area from the remote's state file (`ReaderGeometry.safeArea`, from `model.safeAreaChanged`); regions from `DebugEvents` (`spike-events.jsonl`).

| Posture | Status bar | Safe area (top, left, bottom, right) | `ReaderLayout` insets (left, right) | Occlusion regions |
|---|---|---|---|---|
| Folded 466×678 | shown | 0, 0, 34, **84** | 0, 84 | camera 37×37 at (399.7, 29.3); 84×174 at (382, 0) |
| Folded | hidden | 0, 0, 34, **84** | 0, 84 | camera 37×37 at (399.7, 29.3); 84×**82** at (382, 0) |
| Unfolded 951×669 | shown | 0, 0, 34, **84** | 84, 84 | 84×124 at (867, 0); inner camera 58×37 at (677.3, 21), inactive |
| Unfolded | hidden | 0, 0, 34, **0** | **0, 0** | inner camera 58×37 at (677.3, 21), inactive |
| Half open | hidden | 0, 0, 34, **0** | 0, 0 | as unfolded; the hinge's division active |

- The second occlusion is the status bar's own area: 84×174 folded and 84×124 unfolded while it shows. Hidden, folded keeps an 84×82 block around the camera, and unfolded loses it.
- **Folded** (frames 01–03): text in the same place (27–356 pt), and the footer too. Back moves up from about y 174 to y 81–130, under the 82 pt block; ⋯ and the open group follow. The glass group and the bar lay out right.
- **Unfolded** (frames 04–05): text moves from 139.5–448.8 | 503.6–813 to **67–442 | 509–884**, with Medium's 7% gap now 67 pt instead of 55. Back and ⋯ sit at x ≈ 879–927, y ≈ 24–71, so they touch the right page's top right corner (its text ends at 884). Nothing else breaks.
- **Half open** (frame 06): the same, with the spine shadow on the hinge. The side column the book-mode tap (#5) uses is gone.
- **So the status bar's visibility changes the page unfolded.** Showing it again (say on a tap) brings back the 84 pt inset and re-paginates the spread. An Edge layout can't follow the live safe area while the bar comes and goes. Today's five steps can't hide the bar either, or they'd reflow too.

## 2. The camera

- **Folded:** a 37×37 pt `occlusion` at x 399.7–436.7, y 29.3–66.3, with no margins. Hidden or not, iOS reports the 84×82 block around it (x 382–466, y 0–82) and keeps the 84 pt safe area.
- foliate's text starts at the view's top inset plus its 48 px margin, so about y 48–51 today. To clear the camera the page's top inset would be about 18–22 pt (text from ≈ 70 pt). To clear the reported block, 34 pt or more (text from ≈ 86 pt). At the default size a line is about 20 pt, so folded Edge costs one or two lines a page at the top. That's applied to the whole page, because foliate's columns are rectangles and the float workaround is out.
- **Unfolded:** the inner camera is reported *inactive* (58×37 at x 677–735, y 21–58, over the right page). The right page's first line already starts at about y 58 today, so nothing changes there. Whether "inactive" means the panel draws there on a real Duo is unchecked.
- **Unfolded sideways** wasn't checked. The bar lies along the top there (safe area top 82), and Edge would be a different question.

## 3. How `ReaderLayout` could do Edge (a sketch, not a design)

- **Its own case, not a smaller gap.** Folded, the safe area keeps 84 pt with the bar hidden, so `ReaderMargins.underColumn` can't reach far enough. Unfolded, the safe area goes to 0 and comes back with the bar. Edge would lay out from the reader's size, the hinge's division and the camera's occlusion, not from `safeArea.right`:
  - Folded: the view as wide as the screen (466), the margin `gap`% of it each side, top inset from the camera (section 2), bottom inset the home indicator's 34.
  - Unfolded and half open: `spread` with `half = min(mid, width − mid)` = 455.5, so the spread is centred on the fold and both outer strips are used. Top inset 0 unless a real Duo says otherwise about the inner camera.
  - `ReaderGeometry` would carry the occlusion regions (it has only divisions today), and `ReaderLayoutTests` would get Edge's frames.
- **Status bar:** hidden for as long as an Edge reader is open, whether or not the controls show, so the layout never moves. Other steps keep it, unchanged.
- **Footer:** follows `textColumns`, so it moves out with the text by itself. The bottom 34 pt (home indicator) stays.
- **Progress bar:** `barSpans` keeps 12 pt inside the safe area. Folded that's the column's edge as today; unfolded with the bar hidden it's the whole width, which is what Edge wants anyway. Decision 7 lined the bar up with panels, not the text, so nothing has to follow Edge's margins.
- **Panels:** `ReaderPanelFrame` takes `safe.right`, which is right folded and is 0 unfolded. They'd need checking against the buttons in the corner unfolded.
- **Column buttons:** Back and ⋯ show while reading today. In Edge they'd sit on the text (folded at x ≈ 393–443 from y 81; unfolded in the corner), so Edge would hide them while reading. That needs another way to bring the controls up, which today come only from ⋯ (no middle tap). **A UX decision.**
- **Always show controls:** it keeps the buttons up, on the text in Edge. Either Edge turns it off or the other way round. **A UX decision.**
- **Book mode (#5):** half open, a tap in the side column shows the controls. With the bar hidden there's no column, so that tap lands on the right page's margin and turns the page. Edge needs the same answer as the column buttons.
- **The bookmark ribbon** (`safe.right − 30`) sits at the column's edge folded and at the screen's edge unfolded. That's probably fine, but the ribbon and Back might meet in the corner unfolded.

## Open

- **A real Duo:** does the status bar hide in the side column there, and does the folded safe area stay 84 pt? The simulator can't answer what the hardware does.
- The UX questions above, for Adam, with mockups.
