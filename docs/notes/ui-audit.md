# UI audit (2026-11-07)

An audit of the UI layer at `cf680e7` (after #96 and #97): the shell, every screen, and the reader's SwiftUI chrome. Nothing was changed. The question was whether the UI is structurally sound or a house of cards.

## Verdict

**It's sound underneath, with a few weak joints.** It isn't a house of cards.

The foundations hold:
- Posture reaches the screens one way, from the hinge's reserved region (`Spread`).
- State that has to survive a fold already lives in models (`BookPage`, `SearchModel`, `SetupModel`, `BookOpener`).
- The reader's geometry (`ReaderLayout`, `ReaderHinge`, `FoldBatch`) is pure, central and tested.
- No screen measures itself and then sets its own size. #96 was the only loop of that kind, and it's fixed.
- No Duo numbers are hard-coded outside comments.

The fragility is in a few places where one feature reached into shared code instead of getting its own seam:
- **Settings.** Two routes are drawn as one screen when unfolded, and the generic stack and `ShellModel` carry Settings-only branches for it.
- **Home's title.** The rule for when it shows is written twice.
- **The cover motion.** The newest piece. It builds itself from window snapshots and guesses the posture from a frame's width. Nothing clears it when the Duo unfolds, and it has no time limit.
- **The reader's bottom strip.** Who holds it is decided by booleans that keep gaining exceptions.
- **The two-page layout.** It's hand-written in six screens, and one has already been missed.

`ShellModel` (1,197 lines) holds navigation, tour, imports, server removal and animation set-up together, which is why so many fixes touch it.

None of this needs a rewrite. About eight small or medium fixes would remove most of the repeat-patch pressure.

Checked in the simulator *Octavo Audit Duo* (`BF0C61A9-4EC0-40E7-825C-A5FCBEB4017A`, iOS 27.1), headless, against the local BookOrbit and COPS:
- folded, unfolded and half open
- larger text, dark mode
- two servers, the tour, setup and Settings

Code was read by area, with two parallel reviews (screens; reader chrome) whose findings were then checked against the code here.

### What the severities mean

- **Reproduced bug:** seen in the simulator without a scripted fold.
- **Simulator only, needs a real Duo:** seen only with `hinge` driving the fold. Per the house rule, it isn't a bug until a real Duo shows it.
- **Structural risk:** found by reading code. Nothing is broken today, but the next change in that area is likely to break something.
- **Inconsistency:** the same job done two ways.
- **Polish:** small.

Sizes are rough: **S** is under half a day, **M** is one to two days, **L** is more.

### Evidence

Screenshots are in the shared notes folder, `side-session-notes/local_350307f1-…/ui-audit/`. They use only public-domain sample covers. Working captures are in this session's scratchpad (`…/scratchpad/shots/`).

## What held up in the simulator

These all worked, and are worth knowing before reading the problems.

**The tour:**
- folded → unfold → reader → Skip → Home

**Opening and closing a book:**
- Home → a book's screen → Download
- unfold on that screen opens the book at its place
- folding closes it back to that screen
- Back from the reader

**Navigation:**
- Settings unfolded: pick a page, then Back to Home in one step
- Library → All → swipe back from the left edge, unfolded
- Search unfolded: Books on the left page, Series on the right
- two servers: names on Home, the Library title menu, Search's sections per server

**Appearance:**
- dark mode across Home, the reader, its controls and Text and Theme
- Library and Home folded at larger text

**Accessibility audit:**
- Library: clean
- Home: only the known `.secondary` contrast note (`accessibility.md`)
- `CoverBadge`'s "End" label in the tree is `accessibilityHidden`, so VoiceOver doesn't read it.

## The shell (`Octavo/Shell/`)

### 1. Settings is two routes drawn as one screen when unfolded
**Structural risk · M**

**Where:**
- `ShellModel.swift:544-553` (`back(_:twoPages:)` pops 2)
- `ShellModel.swift:572-584` (`openSettingsPage` replaces instead of pushing, and silently does nothing if the top isn't `.settings`)
- `ScreenStack.swift:146-162` (`isListUnderItsPage` hides the list with opacity; `back()` passes the posture)
- `SettingsScreen.swift:23-36` (a different view tree per posture)
- `ShellPath.swift:30` (`pop(_ count:)` exists only for this)

**What:**
- The route stack means different things folded and unfolded, and the view passes its posture into navigation.
- The generic stack has to know about Settings to hide the screen underneath.

**Evidence:** code path. It works today: unfolded, picking a page then Back went to Home in one step.

**Sturdier:**
- Keep the chosen Settings page as model state, as `BookPage` keeps its sheet.
- Push `.settingsPage` only when folded.
- Let `SettingsScreen` draw list | page from that state.

This removes `pop(2)`, `twoPages:` and `isListUnderItsPage`.

### 2. Screen-specific flags in `ScreenFrame`
**Structural risk · S**

**Where:**
- `ScreenStack.swift:139` (`isLibraryRoot`, `isHomeRoot`)
- `ScreenStack.swift:216-234`
- `LibraryModel.swift:99-102` (`homeShowsBooks`)
- `HomeView.swift:15-46`

**What:** Home's states are decided twice:
- in `HomeView`'s if/else chain
- in `homeShowsBooks`, which the shared frame reads to hide the title

A new Home state needs both edits, or the title lands on the cover page or disappears from the invitation. The Library's server menu takes the same route through a flag.

**Evidence:** code path. Both arrived in 6cf94d3; they agree today.

**Sturdier:** let a root screen supply its own title, as Settings already does with `ScreenTitle`. Alternatively, keep one `HomeState` enum on `LibraryModel` that both read.

### 3. The cover motion learns where the cover is through side channels
**Structural risk · M**

**Where:**
- `ShellModel.swift:685-738`
- `ShellModel.swift:700-701` (`spread: frame.width < size.width * 0.75`)
- `ShellModel.swift:708-718` (`spot.stripTop > spot.page.minY`, "the strip's measured")
- `ShellModel.swift:740` (`keyWindow`)
- `HomeView.swift:187-213` (writes `shell.homeCover`)
- `BookCoverPage.swift:114` (writes `page.coverFrame`)
- `ReaderCoverMotion.swift:232, 252, 284` (reads `ShellModel.keyWindow`)

**What:**
- Two screens push global rectangles into untracked properties on the shell.
- The shell builds the motion from `UIWindow` snapshots, guesses the posture from a frame's width, and guesses whether Home's numbers are ready from their order.
- A Reader type depends on the Shell's window lookup.

**Evidence:** code path. These lines were patched in #97 and its review (e98972d, a3b98b9).

**Sturdier:**
- One anchor preference (cover frame plus image) that the stack collects.
- The posture passed in from the `Spread` the stack already has.
- The window size handed to the motion, not looked up.

### 4. `ShellModel` does too many jobs
**Structural risk · M–L, can be done in steps**

**Where:** `ShellModel.swift`. It holds:
- tabs and paths
- setup
- sign-in
- imports
- server removal
- navigation
- opening books
- the cover motion's set-up
- sync wiring
- the hinge
- the tour (about 250 lines)
- debug launch arguments

**What:** every UI fix touches this file: 35 commits since 2026-10-31, second only to `ReaderView.swift` with 41. The tour's flags (`tourWaitsForHinge`, `addsBooksAfterTour`) reach into `needsSetup`, `importBooks` and `opened`.

**Sturdier:** split by job, not all at once. Start with:
1. **ReaderPresenter:** `reading`, the cover motion, and every way to close.
2. **TourController:** the tour.
3. **ServerActions:** sign-in, sign-out, remove.

`ShellModel` keeps navigation. Each move is mechanical, and tests already cover most of it.

### 5. A timer stands in for "this iPhone has no hinge"
**Structural risk · S**

**Where:** `AppShell.swift:85-89`. After 0.75 s, `hingeStayedSilent()` assumes no fold.

**What:**
- On a Duo whose first `onHingeChange` arrives later than 0.75 s (a slow cold launch), a new install's tour would start in its no-fold version.
- After that it never switches, because `startTourIfHingeKnown` is guarded by `tourWaitsForHinge`.

**Evidence:** code path. Not seen. In the simulator the hinge reported in time.

**Sturdier:** ask the scene or device whether it has a hinge, if iOS 27.1 offers that. Otherwise, let a late first hinge report restart the tour's first step while it's still showing.

### 6. Swipe-back offset is `@State`, not `@GestureState`
**Structural risk · S**

**Where:** `ScreenStack.swift:35` and `:170-201`

**What:**
- `swipe` is only reset in `onEnded`.
- A drag that the system cancels (a fold, an incoming call, Control Center) doesn't call `onEnded`.
- The top screen would then stay pulled sideways until the next swipe.

**Evidence:** code path. A cancelled drag can't be scripted headless. Normal swipes worked.

**Sturdier:** track the live offset with `@GestureState`, which resets on cancel, and keep `@State` only for the committed slide-out.

### 7. Smaller shell items

**Inconsistency (S):**
- `leafStyle` reads the appearance from `UserDefaults.standard` but the margins from the injected `defaults` (`ShellModel.swift:675-680`, `:746`).
- `ScreenStack` measures its spread, then also stores it in a shared, unobserved `lastSpread` (`ShellModel.swift:73-75`, `ScreenStack.swift:109-125`). It's a deliberate fallback for a tab's first layout, but it's a second copy of the posture.

**Polish (S):**
- The tour's cover motion hard-codes `author: "Jane Austen"` (`ShellModel.swift:994`).
- Unfolded, a swipe back needs 35% of the spread's width (about 300 pt) instead of a page's (`ScreenStack.swift:176`).

## Screens

### 8. No building block for "left page | hinge | right page"
**Structural risk · M**

**Where:**
- The same `HStack { left; Color.clear.frame(width: pages.hingeWidth); right }` is written by hand in six places: `HomeView.swift:83-90`, `EmptyListViews.swift:82-89`, `BookCoverPage.swift:33-41`, `SettingsScreen.swift:24-31`, `SetupViews.swift:17-29`, `TourScreens.swift:56-64`.
- `.frame(width: spread.pages?.leftWidth)` appears 17 times.

**What:** a screen that forgets the frame silently runs across the hinge. That has already happened once (item 9). The empty-states fixes ffb6927 → 99812f3 → c83706c were three passes at the same thing.

**Sturdier:** a `SpreadPages(left:right:)` container and an `.onLeftPage()` modifier, next to `SpreadRow` and `SpreadGrid`, used by all six.

### 9. The Library's own failure screen runs across the hinge
**Structural risk, likely bug · S**

**Where:** `LibraryView.swift:19-39`, the `library.root == nil` branch.

**What:**
- Its banners are only padded, not framed to the left page.
- The "Couldn't load your library" invitation isn't wrapped in `EmptyPages`.
- Unfolded, both centre across the hinge.
- The same gap exists in `LibraryNotConnected` (`LibraryView.swift:535`) and in `NoLibraryInvitation` on Home and Search, which are rarely reached.

**Evidence:** code path. The 99812f3 pass moved Home, On iPhone and the feeds onto `EmptyPages` and missed this branch. Not reproduced: it needs a server whose top list fails, and the dev servers were left running.

**Sturdier:** wrap it in `EmptyPages(server: nil)`, put the banners on the left page, or fix it with item 8.

### 10. Folding swaps the view tree, and small `@State` goes with it
**Simulator only, needs a real Duo · S each**

**Where:**
- `ServerSettingsPage.swift:14, 36, 90-92`
- `SettingsScreen.swift:23-36`
- `BookSheet.swift:443-444, 504` (Remove download's confirmation)
- `SetupViews.swift:16-37` (the keyboard)

**What:** `if let pages = spread.pages { HStack… } else { … }` gives each stateful child a new identity on a fold.

**Evidence:**
- Settings → the server's page, folded. Type into Name, then unfold.
- The unfolded page and the list show the old name. Back, by contrast, kept a typed name.
- Screenshot: `ui-audit/server-name-lost-on-unfold.png`.
- Setup's typed values survive a fold, because they live in `SetupModel`; only the keyboard closes.

**Sturdier:**
- Keep the draft name in a model, as setup does.
- Or keep each child at the same place in the tree in both postures. Item 1 would do that for Settings.

### 11. Two "push a route" buttons that draw text differently
**Reproduced bug (Larger Text) and inconsistency · S**

**Where:**
- `ShellLink`, which uses the system button style (`ScreenStack.swift:271-302`)
- `OpenButton`, which uses `.plain` (`LibraryComponents.swift:10-24`)
- `EntryRow` uses `ShellLink` (`LibraryComponents.swift:181`)

**What:** at accessibility text sizes, an `EntryRow` title that wraps is centred, its detail line too, and the three covers squeeze to a sliver. Book rows beside it stay left-aligned.

**Evidence:**
- Search for "the" at Accessibility XL, unfolded: the series row in `ui-audit/larger-text-series-row-centred*.png`.
- The same row draws the Library's collection, series and author lists. Not checked there.

**Sturdier:** one push-a-route button with `.plain` style and `.multilineTextAlignment(.leading)`. `ShellLink` and `OpenButton` become the same component.

### 12. Search: a retry can bring back the old query's results
**Structural risk, likely bug with several servers · S**

**Where:** `SearchModel.swift:121-128` (`retry` starts its own `Task`), `:236-241` (`finish` doesn't check the query).

**What:** with several servers, Try again in one section followed by typing can land the old query's results in that section.

**Evidence:** code path.

**Sturdier:** in `finish`, `guard results.query == searchText`, or run the retry inside the cancellable `task`.

### 13. Sign in again reads from disk on every redraw and pops the tab that's showing
**Structural risk · S**

**Where:** `SetupViews.swift:568` (`shell.servers.load()` in `body`), `:615` (`shell.pop(shell.tab)`).

**What:** it decodes `Servers.json` on every keystroke. On success it pops whatever tab is showing, not its own. That's safe only because leaving the tab cancels the attempt.

**Sturdier:** read `library.server(id)`, and let `ScreenStack` give each screen its own tab in the environment.

### 14. Smaller screen items

**Inconsistency (S):**
- The tour's Close your iPhone screen keeps its own `@State` spread with none of `ScreenStack`'s first-layout handling (`TourScreens.swift:48, 77`). It was patched in both #96 commits.
- `BookOpenButton` falls back to `opener.open` directly when no `openBook` closure is set, which skips Continue reading (`BookSheet.swift:383, 393`). Only previews reach that path.
- The debug `coverStrip` override sits in shipping button logic without `#if DEBUG` (`BookSheet.swift:360-366`).
- "No books on iPhone" is an `EmptyInvitation` with Import in one place and a bare `ContentUnavailableView` in another (`OnIPhoneViews.swift:32-35` vs `BooksOnIPhonePage.swift:24-27`).
- Search rows pull places on appear only; Home also pulls when the app comes back (`SearchView.swift:541` vs `HomeView.swift:68-71`). CLAUDE.md says both should.

**Polish (S):**
- Folded at Accessibility XL, "Recently added" wraps and its count floats beside the second line (`ui-audit/larger-text-folded.png`).
- Tour Skip is a fixed 14 pt picture, so it ignores Dynamic Type (`TourCard.swift:107-115`).
- `BookPages` drops book screens in creation order, not last use (`BookPage.swift:188-197`).
- `AlsoReadingPage` sizes rows from a header measured at 0 on first show (`HomeView.swift:388-463`).
- Setup's Return in Address submits the form rather than moving to the next field (`SetupViews.swift:461-462`).

## The reader's chrome

### 15. The cover motion survives an unfold, and a closing motion survives a fold

**Fixed** (`page-turns.md` §5).

**Simulator only, needs a real Duo · S**

**Where:**
- `ShellModel.swift:813-818`: the unfold case returns early while reading and leaves `coverMotion` alone.
- `ShellModel.swift:819-823`: the fold case clears it only while reading.
- `ReaderCoverMotion.swift:110-134`: the motion's size, frame and posture are fixed when it's made.

**Evidence:**
- Folded, on Alice's screen: tap Open, then unfold straight away.
- For about 0.75 s the folded book screen sits in the top-left of the open display, then a narrow folded-size cover swings at the left edge.
- The remote's `coverMotion` state still reported `window (466.0, 678.0) spread false` after the unfold.
- Screenshots: `ui-audit/cover-motion-survives-unfold.png` (frames 1–2).

**Sturdier:** drop or fade the motion on any change of fold, both ways, as the tour's fold already does (`ShellModel.swift:961-963`).

### 16. The opening cover blocks every touch and has no time limit

**Fixed** (`closeReader`, the motion dropped on any fold, an 8 s limit; `page-turns.md` §5). The page load that throws still only logs.

**Structural risk · S**

**Where:**
- `ReaderCoverMotion.swift:447` (`.contentShape(.rect)` over the window)
- `ReaderView.swift:44-55` (it ends only on open plus a relocation, or `.failed`)
- `ReaderModel.swift:258-263` (a page load that throws is only logged, so the phase stays `.loading`)
- `ReaderCoverMotion.swift:201-204` (`start()` sets `slid` without `swingIfReady()` on the folded and Reduce Motion paths)

**What:**
- If the reader page itself fails to load, the cover never leaves. Folded there's no way out but relaunching.
- The `start()` ordering is hidden today by a 50 ms vs 150 ms race.

**Evidence:** code path. The trigger is rare: the reader page is local.

**Sturdier:**
- Call `swingIfReady()` there.
- Fade the cover after a few seconds whatever happens.
- Set `.failed` when the page load throws.

### 17. Closing the reader takes different paths

**Fixed** (`page-turns.md` §5).

**Structural risk · S**

**Where:**
- `closingReaderAtOnce` (`ShellModel.swift:1030-1038`) is used at `:964`, `:1044` and `:1077`.
- It isn't used at `:335` (import), `:834` (the ordinary fold close) or `AppShell.swift:50` (Back).
- All of these sit under `.animation(.default, value: model.reading)` (`AppShell.swift:90`).
- `:335` also leaves `coverMotion` set.

**What:** the comment explains the risk: a reader still animating out keeps its web page attached, and an unfold then traps WebKit. One root cause is guarded in three places, and three other ways out aren't guarded.

**Sturdier:** one `closeReader()` that every way out uses: no animation, clear the motion, flush. It fits naturally in item 4's ReaderPresenter.

### 18. Who holds the strip along the bottom of the page is decided by booleans
**Structural risk · M**

**Where:**
- `ReaderView.swift:365-381`, `:518-528` (`backBarIsUp`, `stacksOverBackBar`, `showsFooter`, `footerBar`)
- the same offsets re-derived as literals at `:187`, `:386`, `:853`, `ReaderNote.swift:78`, `TourCard.swift:28`
- `TourCard.swift:15, 30` guesses the bar's height (`barClearance = 96`), while `ReaderScreen` measures it

**What:** each new occupant (footer, search bar, server capsule, back bar) added an exception: c5e7b9c, 7b9a0a0, e1f3aea, eade193, 4bca8d9. `ReaderView.swift` is the most-patched file (41 commits).

**Sturdier:** one pure `ReaderChromeLayout` that says who holds the slot and returns every frame, tested like `ReaderLayout`.

### 19. Closing a panel in book mode brings the bar back without its buttons
**Simulator only, needs a real Duo · S**

**Where:**
- `ReaderProgress.swift:160-163`: `hide()` doesn't reset `barBeforePanel`.
- `ReaderView.swift:350-352`: entering book mode hides the controls and leaves a panel open.

**Evidence:**
- Unfolded, open Text and Theme, then half open: the panel stays and the column shows only Back.
- ✕: the progress bar comes back with no Contents, Text and Theme, Search or Bookmark buttons, and no ⋯ to show them.
- Screenshot: `ui-audit/book-mode-panel-close.png`.

**Sturdier:** reset `barBeforePanel` in `hide()`, or close the panel when book mode starts.

### 20. During a fold the chrome pairs the new size with the old layout
**Structural risk · S–M**

**Where:**
- `ReaderModel.swift:330-337`, `:645-655`: geometry updates at once.
- `ReaderModel.swift:381-386`, `:469-470`: `layout` waits for `endFold`.
- The overlays read both: the back bar (`ReaderView.swift:150-151`), the footer (`:172-173`), the panel (`:194`), the bar (`:611-613`) and the tour card (`:226-228`).

**What:** for the length of a fold batch (about 120 ms or more), panels and bars can sit at the wrong x or size, then jump. The fold snapshot is under them, so it doesn't hide this.

**Evidence:** code path. A fold in the simulator is too coarse to judge this; it needs a real Duo.

**Sturdier:** let `layout` carry the geometry it was computed for, and have the chrome read only that pair.

### 21. Tour hooks are threaded through the shared reader chrome
**Structural risk · M**

**Where:** about 30 references in `ReaderView.swift`, including `:122-135`, `:206`, `:226-232`, `:284-304` and `:366-444`. `ReaderScreen` reads `shell.tour` and `shell.coverMotion` directly.

**What:** every chrome change has to be checked against the tour, and the tour's states (seeded `@State`, a measured `sheetHeight`) live in the reader.

**Sturdier:** a small tour context value injected into the reader, nil outside the tour.

### 22. Waits that stand in for a signal

**Documented, and the reasons hold, but there are two definitions of "settled" (M):**
- `ReaderView.swift:44-50`: 150 ms of quiet before "opened".
- `ReaderModel+Trip.swift:141-150`: 60 ms of quiet with a 500 ms cap.
- **Sturdier:** one helper, or a `settled` message from the bridge.

**Documented, works by luck (M):**
- `ReaderCoverMotion.swift:451-454`: a 50 ms sleep before the slide, so building the web view doesn't swallow it. The leaves already solve this properly on a `UIUpdateLink` clock (`:279-321`).
- **Sturdier:** run the slide and swing on the same clock, and drop the second copy of the swing curve (`:267` vs `:315-316`).

**Undocumented (S–M):**
- `ReaderView.swift:699-705`: a 2 s timeout clears a stale scrubber knob, because `jump` doesn't say when it lands.
- `ReaderView.swift:695`, `ReaderScrubber.swift:360-372`: `.id` rebuilds the slider to redraw its fill, and then a touch in progress has to be cancelled.

### 23. Smaller reader items

**Structural risk (S):**
- The posture is mapped from `DeviceHingeContext` twice, in the reader (`ReaderWebView.swift:32-36, 78-87`) and the shell (`AppShell.swift:81-84`, `HingeTransition.swift:33-41`), and their order is unspecified. They agree today.
- `opensByUnfold` leaks into the next Open if `openBook` returns early (`ShellModel.swift:591, 817`). That's rare: it needs the book's server to be gone.

**Polish (S):**
- `.fixedSize()` cancels the back bar's `minimumScaleFactor` (`ReaderView.swift:153`, `ReaderTrip.swift:84`).
- The note card's header is a fixed 58 pt (`ReaderNoteCard.swift:51, 65`).
- `columnButtonFrame` finds a toolbar button by walking `UINavigationBar` (`ReaderView.swift:556-571`).

## Files that keep getting patched

From `git log --since=2026-10-31` on the UI folders:

| File | Commits | Repeat fixes for the same thing |
|---|---|---|
| `Reader/ReaderView.swift` | 41 | The bottom strip's occupants (item 18). Which controls show (Adam's decisions, not bugs). |
| `Shell/ShellModel.swift` | 35 | Grows with every feature (item 4). The cover motion (#97 and its review). |
| `Shell/ScreenStack.swift` | 20 | How a stack gets its spread: 4356d1a, 0f39a7b, cf680e7, 15b867f. Settings list margins mid-slide: 89fd3c1 → 5d1eb4f, 90 minutes apart. |
| `Home/HomeView.swift` | 17 | The unfolded left page and the cover's geometry: 6cf94d3 → e98972d → a3b98b9. |
| `Reader/ReaderCoverMotion.swift` | 8 | 76da9a0, 3ebe134, dd8260d, e98972d, a3b98b9, 928d064. Three motions in one class, switched by five flags. |
| Empty states | — | ffb6927 → 99812f3 → c83706c, and item 9 is still open. |
| WebKit trapping on a rebuilt web view | — | One cause, guarded in three places (item 17). |

`BookSheet`, `SetupViews` and `LibraryComponents` changed often too, but that was feature growth (several servers, accessibility), not repeat fixes.

## Recommended order

These need no UX decision; they keep today's look and behaviour.

1. **Close the reader one way** (item 17), and **clear the cover motion on any fold change, with a time limit** (items 15, 16). S. **Done.**
2. **Settings' chosen page as state** (item 1). This removes Settings from the shell. M.
3. **`SpreadPages` and `.onLeftPage()`** (item 8). Fix the Library failure branch with it (item 9). M.
4. **One push-a-route button** (item 11). It fixes the Larger Text rows. S.
5. **Home's state in one place, or Home draws its own title** (item 2). S.
6. **Cover position by anchor preference, posture passed in** (item 3). Do it before the next cover-motion change. M.
7. **`ReaderChromeLayout`** (item 18), then the tour context (item 21). M each.
8. **Split `ShellModel`** (item 4), starting with ReaderPresenter, which item 1 above begins. M–L, in steps.

The small fixes go in whenever their area is next touched: items 6, 10, 12, 13, 19, 20 and the smaller items.

**Needs Adam's eyes:** none of the above changes what you see, except two places where the fix could go either way:
- **Item 10:** whether a fold should keep a Remove confirmation open.
- **Item 19:** whether book mode should close an open panel or keep it.
