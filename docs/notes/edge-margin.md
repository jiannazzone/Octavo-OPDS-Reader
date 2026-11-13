# Edge margin: text in the side column (#136)

Investigation only, 2026-11-12, on the iPhone Duo iOS 27.1 simulator ('Octavo Edge Duo', 3FFAC972-…; 'Octavo Edge Duo 2', DD28AEF1-FA13-4D31-97EA-7572B8C09538; both deleted). Nothing here is designed or approved, and the probe code wasn't committed. Moby-Dick at 30%, Medium margins, opened through the DEBUG remote (`openLocal`, `goto`, `controls`). Frames are in `edge-margin/`. The simulator doesn't draw the camera, so no frame shows it.

## Summary

- **Hiding the status bar alone doesn't clear the column.** The clock and battery go, but Back and ⋯ stay in their glass (frames 02, 06).
- **Hiding the reader's toolbar as well clears it** (frames 03, 07): `.statusBarHidden(true)` plus `.toolbarVisibility(.hidden, for: .navigationBar)` while the controls are hidden. Showing the controls brings the toolbar back on glass, and hiding them takes it away again (frames 04, 08, 09).
- **Unfolded and half open, that is already an Edge layout.** The right inset drops from 84 to 0, and today's `ReaderLayout` centres the spread on the whole screen. With Medium the text runs 67–442 | 509–884 instead of 139.5–448.8 | 503.6–813. The controls come and go without moving the text, because the toolbar isn't part of the measured safe area. Back and the group sit on the right page's top right corner, over the text, while they show.
- **Folded, the column empties but the text doesn't move.** The safe area keeps its 84 pt with both hidden: the camera is in the column. So the text still ends at 382 pt (frame 03). Folded Edge needs its own layout that ignores that inset and clears the camera. No frame shows that yet.
- **The camera** (folded) is 37×37 pt at x 399.7–436.7, y 29.3–66.3. foliate's columns are rectangles, so clearing it brings the whole page's top down about 18–34 pt (one or two lines).
- **For the design:** Back and ⋯ are on screen while reading today, and in Edge they'd have to hide. The controls then need another way to come up, because today they come up only from ⋯ (Adam, 2026-11-02). Always show controls and book mode's side-column tap (#5) hit the same question.

## 1. Hiding the status bar and the toolbar

The probe, in `ReaderView`:
- `.statusBarHidden(UserDefaults.standard.bool(forKey: "probeHideStatusBar"))` after the outer `.ignoresSafeArea()`.
- `.toolbarVisibility(probeHideToolbar && !controls.buttonsVisible ? .hidden : .automatic, for: .navigationBar)` after `.toolbar { buttons }`.
- Launched with `-probeHideStatusBar` and `-probeHideToolbar` set to `YES` or `NO`.

The safe area comes from the remote's state file (`ReaderGeometry.safeArea`, via `model.safeAreaChanged`), and the regions from `DebugEvents` (`spike-events.jsonl`).

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
- **The safe area follows the status bar, not the toolbar.** It's measured outside the reader's `NavigationStack`, so the toolbar coming and going changes nothing. In this run the controls went on and off in every posture with the insets unchanged.
- **Controls with both hidden** (04, 08, 09): Back and the group come back in their glass, and the progress bar comes up as usual (split at the hinge half open). Folded they sit in the empty column. Unfolded they sit over the right page's top right: Back at about x 879–927, y 24–71, and the group at x 879–927, y 85–285, where the text runs to 884. Hiding them again leaves the page as it was.
- **Showing the status bar again unfolded would re-paginate**, because it brings back the 84 pt inset. So in Edge the status bar stays hidden the whole time, even while the controls show. Today's five steps can't hide it without reflowing.

## 2. The camera

- **Folded:** a 37×37 pt `occlusion` at x 399.7–436.7, y 29.3–66.3, with no margins. Hidden or not, iOS reports the 84×82 block around it (x 382–466, y 0–82) and keeps the 84 pt safe area.
- foliate's text starts at the view's top inset plus its 48 px margin, so about y 48–51 today. To clear the camera, the page's top inset would be about 18–22 pt (text from ≈ 70 pt). To clear the reported block, 34 pt or more (text from ≈ 86 pt). A line is about 20 pt at the default size, so folded Edge costs one or two lines a page. That's applied to the whole page, because foliate's columns are rectangles and the float workaround is out.
- **Unfolded:** the inner camera is reported *inactive* (58×37 at x 677–735, y 21–58, over the right page). The right page's first line already starts at about y 58, so nothing changes there. Whether "inactive" means the panel draws there on a real Duo is unchecked.
- **Unfolded sideways** wasn't checked. The bar lies along the top there (safe area top 82).

## 3. How `ReaderLayout` could do Edge (a sketch, not a design)

- **Unfolded and half open:** today's `spread` already does it, once the safe area is 0 (frame 07). Edge could hide both bars and leave the layout alone. Or, more robustly, it could set the right inset to 0 itself, so the layout never depends on when the status bar goes.
- **Folded:** its own case. The safe area keeps 84 pt, so `ReaderMargins.underColumn` can't reach far enough. The view would be the screen's width (466), the margin `gap`% of it each side, the top inset taken from the camera's occlusion (section 2), and the bottom inset the home indicator's 34. `ReaderGeometry` would carry the occlusion regions (it has only divisions today), and `ReaderLayoutTests` would get Edge's frames.
- **Status bar:** hidden for as long as an Edge reader is open. Other steps keep it, unchanged.
- **Toolbar:** hidden while the controls are hidden. That includes Back and ⋯, which show today whenever the reader is open.
- **Footer:** follows `textColumns`, so it moves out with the text by itself (07).
- **Progress bar:** `barSpans` keeps 12 pt inside the safe area. Unfolded with the bar hidden that's the whole width (08), and folded it's the column's edge as today (04). Decision 7 lined the bar up with panels, not the text, so nothing has to follow Edge's margins.
- **Panels:** `ReaderPanelFrame` takes `safe.right`, which is right folded and is 0 unfolded. They'd need checking against the buttons in the corner unfolded.
- **Showing the controls:** with ⋯ hidden, they need another way up. Today they come only from ⋯ (no middle tap). **A UX decision.**
- **Always show controls:** it keeps the buttons up, on the text in Edge (08). Either Edge turns it off or the other way round. **A UX decision.**
- **Book mode (#5):** half open, a tap in the side column shows the controls. With the column gone, that tap lands on the right page's margin and turns the page. Edge needs the same answer as the controls.
- **The bookmark ribbon** (`safe.right − 30`) sits at the column's edge folded and at the screen's edge unfolded, beside Back in the corner.

## Open

- **No frame shows folded text under the column.** It needs a probe of the folded Edge layout, with the camera clearance picked.
- **A real Duo:** do the status bar and the toolbar hide in the side column there, does the folded safe area stay 84 pt, and where is the camera? The simulator can't answer what the hardware does.
- The UX questions above, for Adam, with mockups.
