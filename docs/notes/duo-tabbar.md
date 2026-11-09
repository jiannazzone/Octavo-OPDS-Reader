# SwiftUI `TabView` on the Duo

> Superseded 2026-11-08 for navigation: each tab is the system's push stack (`split-shell.md`). What's below about the side column still holds.

Step 1 of #6 (app shell). Written 2026-10-31 on 'Octavo Shell Duo' (185ADEDA-2C89-415C-9EA0-3A5C582944C8, iPhone Duo, iOS 27.1 simulator, Xcode 27.2), driven with Hinge 0.3.0. Screenshots are in `duo-tabbar/`, at 1× (466×678 folded, 951×669 unfolded). The probe that made them is `duo-tabbar/TabBarProbe.swift` (not in the app target; see Reproducing).

## Summary

- **Yes: a plain `TabView` with `Tab(role: .search)` puts the tab bar at the bottom of the trailing system column**, folded, unfolded and half-open, with no Duo-specific code. Home, Library, Settings, then Search, top to bottom.
- **One difference from Apple's kit:** Search is the last item **in the same glass capsule**, not a separate glass button below the group as the kit's "Search Role" tab bar (and our Figma frames) show. UIKit's `UITabBarController` with `UISearchTab` renders the same single capsule, so it's the system's current rendering, not a SwiftUI gap. Nothing we tried separates it (below).
- **Over a full-screen cover (D4):** works. The tab capsule floats over the artwork and its glass takes the cover's colours. The cover runs under the camera column, as decided.
- **Next to side-column controls (D7):** works. Toolbar items go into the column under the status bar (Back in its own glass circle, the rest in one glass group), the tab bar stays at the bottom. Folded, Back + 4 controls + 4 tabs fit in the 678 pt column with little room to spare. (The reader frames have no tab bar, so this matters for tab screens with buttons, such as Library's filter or the cover's Back and More.)
- **The system doesn't split content at the hinge.** A `List` unfolded or half-open runs straight across the hinge. `NavigationSplitView` doesn't split at it either (its sidebar is a fixed 320 pt). The shell has to do the two panes itself.
- **How the shell should split:** one `NavigationStack` per tab whose unfolded screens are *pairs of panes*, left and right of the division region. Both panes' toolbar items and the system Back button then land in the column, as in the Figma frames. Two side-by-side `NavigationStack`s don't: only the right one's toolbar reaches the column; the left one gets its own top bar.
- **Don't present modally on an unfold.** A `fullScreenCover` presented when the hinge reports the unfold stays laid out for the outer display, on its side (§6). The shell shows the reader as a layer over the tabs instead.

## 1. Tab bar placement

| Posture | Content area (SwiftUI) | Tab bar |
|---|---|---|
| Folded (0°) | 382×562, safe area top 82, bottom 34, trailing 84 | Bottom of the trailing column |
| Unfolded (180°) | 867×553, same insets; `division` region x 455.5, width 40, inactive | Bottom of the trailing column |
| Half-open (90°) | Same as unfolded; region active | Same as unfolded |

`duo-tabbar/1-tabs-folded-half-open.png`: folded and half-open.

- The tab content's frame is the window's (top-left at 0,0, trailing 84 pt left to the column), so reserved regions read in a tab's `GeometryReader` are already in pane coordinates.
- Selection, the selected tab's tint and the glass capsule are all the system's. Labels aren't shown (icons only), as in the kit.

## 2. Search: one capsule, not two

Tried, all folded, all with the same result (Search inside the one capsule, at the bottom):

| Variant | Result |
|---|---|
| `TabView` default style, `Tab(value:role: .search)` | one capsule |
| + `.searchable` on the `TabView` instead of inside the tab | one capsule |
| `.tabViewStyle(.sidebarAdaptable)` | one capsule (no sidebar on this size class) |
| `.tabViewStyle(.tabBarOnly)` | one capsule |
| UIKit `UITabBarController` + `UISearchTab` | one capsule (`duo-tabbar/4-uikit-search-tab.png`) |

Workarounds, if the separate button matters:
1. **Accept the system's capsule (recommended).** Same order and position, Search still last and bottom-most; it follows Apple automatically if a later iOS separates it.
2. **Draw our own tab column**: hide the system tab bar and put a glass group plus a separate Search button in the column. That means re-implementing selection, VoiceOver, keyboard focus and the column placement, and it won't follow system changes. Not worth it for a visual detail.

Also seen: with `.searchable` inside the Search tab's `NavigationStack`, no search field showed when the tab was selected. The Search tab is #15; check where the field goes there.

## 3. Full-screen cover (D4)

`duo-tabbar/2-cover-folded-unfolded.png`: a gradient stand-in with `.ignoresSafeArea()` and a glass strip at the bottom, navigation bar hidden. The tab capsule sits over the artwork; the strip sits in the content area, left of the column. Unfolded, the stand-in spans the whole inner display (the real cover page goes in the right pane, decision 5).

## 4. Column controls next to the tabs (D7)

`duo-tabbar/3-column-controls-folded-unfolded.png`: `.toolbar` with a leading Back and four trailing buttons (Contents, Text and theme, Search in book, Bookmark), plus a `.bottomBar` item.

- Back gets its own glass circle; the four buttons share one glass group; both sit under the status bar. The tab capsule stays at the bottom.
- A `.bottomBar` item becomes a glass pill at the bottom of the content area, not in the column.
- `toolbarVisibility(.hidden, for: .tabBar)` hides the capsule (for the reader, which has no tabs).

## 5. Two panes

| Approach | Unfolded | Screenshot |
|---|---|---|
| `NavigationSplitView` | Sidebar 320 pt, detail 547 pt: the division doesn't line up with the hinge. The sidebar's buttons sit in its own top bar; the detail's go to the column. Folded, it collapses to a stack. | `5-split-view.png` |
| Two `NavigationStack`s in an `HStack`, split at the division region | Splits at the hinge. The right stack's toolbar (Back, More) goes to the column; the left stack's (Filter) sits in its own top bar and pushes its large title down. | `6-two-stacks-unfolded-half-open.png` |
| **One `NavigationStack`; each screen is a pair of panes** split at the division region, each pane with its own large title drawn as content | Splits at the hinge. Both panes' toolbar items share one glass group in the column; on a pushed pair the system Back button appears above them. | `7-pane-pairs-root-pushed.png` |

The third matches the Figma frames (04, 33, 37, 38: titles in both panes, the filter button in the column, nothing on the hinge), keeps the system Back button and swipe-back, and works the same flat and half-open. The shell uses it (`Octavo/Shell/PaneStack.swift`). Once Back appears the bar gets taller and pushes the panes down about 35 pt, so the pairs ignore the top safe area and place their titles themselves, level with the folded large title.

## 6. Presenting during an unfold (found while building the shell)

The shell first showed the reader with `fullScreenCover`. Unfolding on a cover opens the book, and the hinge reports the unfold about 200 ms before the scene moves to the inner display (`duo-spreads.md` §1). A cover presented in that window stays laid out for the outer display: on the inner display its content is turned on its side (`duo-tabbar/8-full-screen-cover-after-unfold.png`: the stand-in reader's text runs top to bottom). The spike's handoff pushed the reader onto a `NavigationStack` instead and never hit this.

The shell now shows the reader as a layer over the tabs in the same view hierarchy, which resizes with the scene like everything else. For #17: keep the reader in the hierarchy (a layer or a push), or wait for the scene's new size before presenting anything modal on a fold.

## 7. A stack stuck wider than its space (2026-11-07)

On Adam's Duo, unfolded, Home and Settings were laid out 951 pt wide (the whole inner display) instead of the 867 pt beside the side column, and centred: about 42 pt cut off on the left and 42 pt under the side column.

- **Cause:** `ScreenStack` read its spread from its own size, and its screens take fixed widths from that spread. The stack was as wide as its screens, so once one reading said 951 pt, the screens kept the stack 951 pt wide, centred in the 867 pt space, and every later reading said the same: left page 497.5 pt, right page 413.5 pt, the hinge still in its place on screen. Only a fold (a new width) got it out.
- **Reproduced** on 'Octavo Width Duo' (FBA38A69-1855-4A69-9F35-A0261162F9ED, iOS 27.1 simulator): one forced 951 pt reading gave Adam's screenshot exactly, and laying the stack out without the side column for its first 1.5 s left it wide for good. What gives a real Duo that reading isn't known. Likely moments are an unfold where the side column arrives after the new size, and the sideways layouts iOS makes for the app switcher (`reader-background.md` §1). In the simulator, going to the background and folding both held the stack at its old width for a moment (867 pt in a 382 pt space) before it let go.
- **Fix:** `onSpreadChange` (`Spread.swift`) reads the spread from a frame that takes exactly the width it's offered, `.frame(minWidth: 0, maxWidth: .infinity)` (`maxWidth` alone grows with what's inside). A reading is now always of the space, so the next layout replaces a wrong one, and pages still too wide for a moment hang off the trailing edge, not both. `ScreenStack` and the tour's Close your iPhone step, which measured its pages the same way, both use it. `SpreadTests.readsTheRoomNotItsPages` fails without it.
- **Also:** a stack's first reading is 0 pt wide (84 pt before the fix), the layout before its real one. It made the real reading look like a fold, so a tab opening for the first time went from one page to two in view, and it set the other tabs' fallback spread to 0. `ScreenStack` now ignores readings narrower than a page.
- **Checked** against `main` on the same simulator, by screenshots: Home, Settings, Library, Search, a book's cover page, the reader, setup and the tour, flat, folded and half open, match apart from the clock and a book downloaded between runs. The slide's distance (the width plus the side column) is unchanged. Not checked on a real Duo.

## Reproducing

The probe was `Octavo/Shell/TabBarProbe.swift` (DEBUG), shown instead of the spike library when launched with `-probe 1`. To run it again, copy it back into `Octavo/`, switch `ContentView` to `TabBarProbe()` while `UserDefaults.standard.bool(forKey: "probe")`, build, and launch with launch arguments:

```bash
xcrun simctl launch <udid> com.ianazzone.ereader -probe 1 -probeStyle automatic -probeTab library -probePage pairs
```

- `-probeStyle automatic|sidebarAdaptable|tabBarOnly|uikit`, `-probeSearchOnTabView 1`, `-probeTab home|library|settings|search`.
- `-probePage list|cover|reader|split|twopane|pairs` (Library tab), `-probePushed 1` (pairs: start one level in).
- Launch folded, wait for the first frame (launches took up to 10 s on a busy host), then `hinge open` / `hinge half` and `hinge screenshot`.
