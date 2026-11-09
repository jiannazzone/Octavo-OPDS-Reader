# The system's split for the shell (2026-11-08)

Adam, 2026-11-08: navigation is the system's, on every device, before 1.0. It replaces the custom `ScreenStack` of 2026-11-01 (`duo-tabbar.md`, `settings.md`, `home-library.md` describe what it did).

## Why

The release pass put the app on an ordinary iPhone for the first time. The custom stack drew its own titles and placed Back with `.topBarTrailing`, which the Duo moves into its side column. Without that column the title sat under the clock, Back was top right, and lists couldn't scroll under the bar. Fixing that inside the custom stack meant rebuilding iOS's navigation, and keeping two navigation systems by device was ruled out (Adam: never two). So: one system navigation, menu → detail.

## What it is

- **Each tab is a `NavigationSplitView`** (`TabSplit`): the tab's list on the left, what's picked from it on the right, where further screens push in a `NavigationStack`. Folded, and on an iPhone, the system collapses it to one stack with its own Back and swipe. Open on the Duo, the list is the system's 320 pt column (Adam: standard Duo design); half open, the system moves the divide to the hinge itself.
- **The list is a `List` whose selection is the pick** (`ShellModel.pickBinding`). That's what gives the folded stack its Back: a list in a plain scroll view collapsed with none (probed). Rows are the app's own: the Library's shelves of covers, Home's book and the others in progress, Search's field and results.
- **The tab's state is its `ShellPath`**: the pick, then what's pushed over it. `ShellModel.pick(_:in:)` from the list, `push(_:)` from everywhere else.
- **Home's right column shows your current book** with nothing picked (decision 26, `ShellModel.defaultPick`). It isn't picked, so folding still lands on Home, and a push from it keeps it underneath.
- **Buttons.** Open, the Duo's side column holds the right column's buttons; folded, the list's. So each tab's buttons (Settings, and in the Library Import from Files and, with several servers, the servers menu) go on whichever column is on screen. The system sidebar button stays (Adam): it hides the list, and a book's screen then spans the hinge as Cover | Details.
- **Spreads still apply inside a column**: each column measures its own room (`measuresSpread`), so a book's screen is one page in the right column and Cover | Details with the list hidden.
- **Settings is a system sheet from the gear** (`SettingsSheet`, Adam: keep it native), with its own screens: pages, Sign in again and Add a server's steps push inside it. The system makes the sheet compact on the open Duo, so it's one column that pushes its pages there, as on an iPhone (Adam kept it). Adding a server, removing the last one, or an import closes it; Show the tour closes it and a replay brings it back.
- **Setup is the system's push stack** (`SetupStack`), each step laid out as a spread unfolded.
- **The reader** is still a layer over the shell. A book's cover reports whether it's drawn as a spread's left page, so the cover's motion starts and ends where the cover really is. Unfolding on a book's screen opens it, folding closes it back to its screen, except under Settings' sheet.

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

- Hiding the list jumps a book's screen from cover-over-sheet to Cover | Details in one frame (Adam wants it smooth): animate the spread change in `measuresSpread`, and keep the cover one view across both layouts.
- "No Book Selected" on an empty right column: wording not approved.
- Not checked yet: iPad, plain iPhones, the Accessibility checks in `accessibility.md` (they ran on the old shell), Reduce Motion with the system's pushes.
