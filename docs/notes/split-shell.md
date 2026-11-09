# The system's split for the shell (2026-11-08)

Adam, 2026-11-08: navigation is the system's, on every device, before 1.0. It replaces the custom `ScreenStack` of 2026-11-01 (`duo-tabbar.md`, `settings.md`, `home-library.md` describe what it did).

## Why

The release pass put the app on an ordinary iPhone for the first time. The custom stack drew its own titles and placed Back with `.topBarTrailing`, which the Duo moves into its side column. Without that column the title sat under the clock, Back was top right, and lists couldn't scroll under the bar. Fixing that inside the custom stack meant rebuilding iOS's navigation, and keeping two navigation systems by device was ruled out (Adam: never two). So: one system navigation, menu → detail.

## What it is

**First built as menu → detail** (each tab a `NavigationSplitView`, commits up to `1dd19ce`). On the open Duo that put the Library and Home in a narrow column and lost the spreads Adam liked ("we lose some of what I liked about the app originally"). **Now each tab is the system's push stack with the spreads kept** (Adam, 2026-11-08):

- **Each tab is a `NavigationStack`** (`TabStack`) over the tab's `ShellPath`. Its screens are the app's spreads, as before the rework: the Library's shelves across both pages, Home with your book's cover on the left page, Search's field on the left page and results flowing across, a book's screen as Cover | Details. Push, Back and swipe-back are the system's in every posture and on every device.
- **Titles are the system's large titles.** On a spread they work because each screen scrolls as one (the title probe below failed only with a scroll view per page). Unfolded with books, Home has no title over your book.
- **Each screen lays itself out by its room** (`measuresSpread`): two pages across the hinge open and half open, one folded and on an iPhone.
- **An iPad held sideways** (no fold, landscape, 1000 pt wide or more) splits only the screens that read as a book, a cover facing its words: Home and a book's screen (`twoPagesWhenWide`, `Spread.widePages`), down the middle with a 40 pt gutter. The Library, Search, setup and the tour run across the room, as shelves split by a gap that isn't a hinge looked broken (Adam chose this, option C of three, 2026-11-08). The Duo always reports its fold, so it never takes the wide split.
- **Buttons** (Settings, the Library's Import from Files and, with several servers, the servers menu) are on each tab's top screen; the Duo puts them in the side column, other iPhones in the bar.
- **Settings is a system sheet from the gear** (`SettingsSheet`, Adam: keep it native), holding the system's split (`TabSplit`): its list, and the chosen page (the server's to start with), where Sign in again and Add a server's steps push. The sheet is compact on the open Duo, so it's one column that pushes its pages (Adam kept it). Adding a server, removing the last one, or an import closes it; Show the tour closes it and a replay brings it back.
- **Setup is the system's push stack** (`SetupStack`), each step a spread unfolded.
- **The reader** is still a layer over the shell. A book's cover (on its screen or Home's left page) reports where it is and whether it's a spread's left page, so the cover's motion starts and ends where the cover is. Unfolding on a book's screen opens it, folding closes it back to its screen, except under Settings' sheet.

## Probes (throwaway, local branch `probe/navstack-duo`)

On "Octavo Probe Duo" (iOS 27.1 simulator), by tapping and the hinge tool:

| Probe | Result |
|---|---|
| `NavigationStack` with spreads, 10 fold changes | Same screen and path, no crash |
| The system's large title on a two-page spread | Follows only the right page's scroll view, then vanishes and drags the left page up; folded, no small title is left |
| The zoom transition from a cover | Works folded and open, from either page |
| `NavigationSplitView`, 10 fold changes on a book | Collapses and expands keeping the pick and the book, no crash |
| Rich shelves as the list | Work; a `List` keeps the folded Back, a `ScrollView` loses it |
| Server menu folded | A title menu on a large title (or `.inlineLarge`) shows no ⌄ and does nothing; a small title with ⌄ works; a button in the side column works (chosen) |
| Unfolding on a cover | Opens the book; unfolding on the list opens nothing |

## Known rough edges

- "No Book Selected" on Settings' empty right column (iPad, where the sheet is wide): wording not approved.
- Not checked yet: iPad, plain iPhones, the Accessibility checks in `accessibility.md` (they ran on the old shell), Reduce Motion with the system's pushes.
