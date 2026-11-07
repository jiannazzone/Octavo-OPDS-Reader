# The tour for a new install (step 17)

Decisions 29 and 30 in `docs/design/direction.md`. Built 2026-11-03 on `iPhone Duo` (8C35AF6E-5F3F-48D7-A283-AEE894511947, iOS 27.1 simulator), driven with Hinge and real taps, plus the debug remote's `tour` command. Adam tried a replay on his Duo the same day ("all good"); a true new install on a Duo is still untried, as that means deleting the app and its data. Screenshots are in `tour/screenshots/`, videos in `tour/videos/`.

## What it does

- **Close your iPhone** shows only if a new install first opens unfolded. Closing goes to the cover. **Continue without closing** puts the cover on the left page, which opens as a book's screen does (decision 28), and goes to Turn the page.
- **The cover**, folded: Pride and Prejudice's cover with "Open your iPhone to begin", in a glass capsule centred on the cover, just above its own title. Unfolding opens the book on Chapter I, past page 1, so two leaves go over first (decision 28).
- **The cards**, Liquid Glass at the bottom of the left page (of the one page without a spread), lined up with the text and clear of where the progress bar comes up: Turn the page, Bring up the controls, Make it yours, The page changes as you go · Done, Add your own books · Not now · Add books. Four dots; Make it yours is one step.
- **What to tap shows itself.** On Turn the page the right page lifts a little and settles, every 3.4 s or so until it's turned; with Reduce Motion it stays still. ··· and Aa are blue, in the column at full size and where the card's words name them.
- **Skip** is in the column on every tour screen. While the tour plays it takes Back's place (Adam). Skip or Not now lands on Home with the book under Continue reading; on a replay, back to Settings.
- **Add books** closes the reader for Add your books, setup's first screen with no sample row and with Skip. Its steps end on Home as they always do. **On a replay with a server connected it opens the Files picker** (Adam): Octavo holds one server, so the server choices would replace it.
- **A fold mid-tour** closes the book. The cover then says "Open your iPhone to continue", and unfolding comes back to the same step, with the controls or the panel up again if the step had them.
- **Without a fold** the first two steps drop out and the book opens at Turn the page. The card sits above the Text and theme sheet.
- **Show the tour**, a row above About, plays it from the beginning. Folded it starts on the cover, unfolded on Close your iPhone.

Choices the decisions left open, all Adam's:

- A file opened in Octavo as a new install's first launch lands on the Library with that book and no tour, with the sample book on Home.
- Remove server with the sample book still on the iPhone lands on Home, where Skip does. With no books at all it's setup, as before. The same goes for an existing install with only the sample book.

Choices made while building, for Adam to overrule if he dislikes them on the Duo:

- A tap on the page on Make it yours hides the controls and Aa with them, so the step goes back to Bring up the controls.
- Once the panel has opened, the card stays with Done even if the panel is closed.
- An unfinished tour starts again from the beginning at the next launch.

## How it works

- **`TourFlow`** (`Octavo/Tour/TourFlow.swift`) is the steps and nothing else: a value the shell keeps, with one `handle(_:)`. The views only draw it.
- **The reader's own events drive it.** `ReaderScreen` reports the controls and panels (`.reader(ReaderState)`), on every change and when a step starts, so a step can start already done (Aa opened from looking ahead). `ReaderModel.onPageTurned` fires when a turn really ends: a whole turn in `endTurn`, not a swipe that fell back or a tap at the book's first page. Page Turn None has no turn to watch, so a relocation to a new place counts, which a Contents jump also does; it only matters on a replay with None set.
- **Skip is a picture of the word.** The Duo's column only takes bar buttons with an image. A title or a custom view lands beside the column, over the page (tried on the simulator). `TourSkipButton` renders the word as a template image, with an accessibility label.
- **The page lift** (`ReaderModel.playTurnHint`) is a turn's pictures with nothing turning underneath: foliate doesn't move, nothing is saved, and a real turn asked for meanwhile simply takes over. Its overlays take no touches. It rises about 45° with a soft shadow and hardly darkens (`ReaderTurn.isHint`). Less than that showed no edge, because the page rises towards you and still covers its own place, and with a real turn's shading it read as a flat grey slab. One page slides 6% instead. It uses `Task.sleep`, not an animation's completion, so nothing waits on a view that has gone.
- **Blue ··· and Aa** are the normal buttons with a tint (`Step.litButton`). Tried and dropped: the system's prominent glass style, which fills the button but splits Aa out of its capsule, and a disc drawn as an image, which iOS scales down to 38 pt in a 48 pt button, symbol and all. The card's words use `TourCardWords.emphasized`.
- **Chapter I** (`SampleBook.firstChapter`): the sample book's saved place starts there if it has none, a CFI read off the bundled file. A replay's throwaway place starts there too.
- **The hinge.** `onHingeChange` fires once on appear with the current posture, measured folded and unfolded on the simulator. After 0.75 s with no report the device counts as having no fold. Every later report is checked against the step (`hingeReported`), so the tour follows the hinge even if a change was never reported while the app was away, and a late report still closes the book. `-tourNoFold 1` (DEBUG) is how the no-fold path was checked on a closed Duo; no iPhone without a fold was used.

### Telling a new install apart

`TourRecord` (`tour.state` in `UserDefaults`, which goes with the app): nil, then `new`, `playing`, `played`.

- **It's decided once and kept.** `settle()` runs at launch, ahead of the marker `removeLeftoversAfterInstall` sets: no marker is `new`, a marker is `played`. Kept because iOS can run the app before anyone opens it (prewarming), which would otherwise leave the marker behind and make the first real launch look like a later one. That was the first version's flaw, found while planning the audit.
- **Earlier data also settles it.** A `new` record with `Server.json`, imported books, recents, On iPhone records, `ReadingPositions` or `Bookmarks` becomes `played`. Today this is what protects existing installs, see below.
- **Before the first unlock** nothing is decided, and setup shows for that launch.
- **Unfinished** (`playing`) it starts again. A sample book that couldn't be copied (no room) goes back to `new` and setup shows for now.
- **An install with no data and no marker** plays it, as there's nothing to tell it from a new one. Adam's Duo has places and a server, so it only plays from Settings.

**The launch steps didn't run when this was built.** A probe found them skipped in `App.init` and the marker never written. The tour didn't depend on them: `shouldPlay` settles from `TourController.prepare`, once the app is up. They now run from `didFinishLaunching` (`LaunchSteps`), with `settle()` still just before the marker; the reason and the fix are in `network-trust.md`, "The launch steps never ran".

### A replay touches nothing

- `TourReplayPlace` is a temporary folder per replay, holding its own `ReadingPositionStore` and `BookmarkStore`. `ReaderView` uses them while one exists. It starts empty, so the book opens at its start, and a fold comes back to the same page. It goes when the tour ends.
- The book is the app's bundled copy, opened through `opened(_:)` directly, not `openBook`, so nothing is recorded in Continue reading or On iPhone, and a removed sample book stays removed. A text or theme choice is real and stays, as it's a choice about every book.
- A download finishing mid-tour stays a download and doesn't open (`opened(_:)`).

### The WebKit trap on a fold

The first version crashed on folds mid-tour, inside `_WebKit_SwiftUI`'s `makeViewProvider`: SwiftUI rebuilding a web view whose page is still attached, the trap `AppShell` describes. A fold changes the step in the same transaction that removes the reader, so something still animating in it (the card's fade, or the ring's endless pulse) can keep the leaving reader alive while the scene moves between displays. The reader now leaves with animations off (`closingReaderAtOnce`), for folds and for the tour's end.

- **Before:** it crashed on 2 of 3 folds on steps with a ring. Welcome and the last card, with no ring, passed 6 of 6, so the ring looks the likelier cause. The ring has gone since (below).
- **After:** 14 folds and unfolds in a row across Turn the page, Bring up the controls and both halves of Make it yours, no crash.

The cause is inferred from the fix working, not proven, and these counts are small. A fold in the 0.2 s after a card has just changed isn't covered by the check.

`hingeChanged(.fold)` also drops a cover still opening the book, for every book: it waited for a reader that had gone, and covered the screen for good. This case has a unit test only.

## Independent review

A separate read-only review of the whole branch. Fixed:

| Finding | Fix |
|---|---|
| A download finishing during a replay opened in the tour, with the replay's throwaway place | It stays a download |
| The cover stayed if the iPhone was opened while the app was away | The tour follows every report |
| A file opened on first launch could cut the tour off, or leave no sample book, depending on timing | The tour waits while a file comes in; the sample book is there either way |
| No room for the sample book ended the tour for good | It tries again next launch |
| The debug remote left a replay's folder in use, and the reader under an animation | `TourController.debugEnd` cleans up |
| The test host played the tour on a clean simulator, its animation running through the tests | It doesn't, confirmed on a clean install |

Left as they are:

- A slow import finishing during a replay ends the replay and goes to the Library.
- Page Turn None, above.
- A real Duo's first hinge report later than 0.75 s starts at Turn the page without step 1. If folded, the late report closes the book onto the cover.

## Checked on the simulator

- A true new install (uninstalled first), unfolded and closed, every step with real taps, to Add your books, Skip and Home. `videos/whole-tour-flat.mp4` shows the final tour from a new install up to the Text and theme panel, on a Mac under heavy load, so the first opening is much slower than the 4.4 s below.
- A tap and a swipe both moved Turn the page on.
- Sepia and Night changing the left page live.
- Half open at 110°: book mode, the card on the left page, the spine shadow.
- Reduce Motion: polling the reader during Turn the page saw no lift in 14 polls with it on, against 6 of 14 with it off. This run was on one page; the unit test covers the rule for every Page Turn style.
- One page with `-tourNoFold 1`: Chapter I, the card, the page sliding 6% and back, the card above the sheet.
- Chapter I on a new install, unfolded, as the first screen after the cover opens.
- Six folds and unfolds at different moments on Turn the page, no crash. The lift runs for 0.9 s in every 3.4 s, so not every fold will have caught it.
- A replay turning two pages: the real saved place unchanged, the temporary one written.
- A replay with the local BookOrbit connected: Add books opened the Files picker.

**A tap while the book is still loading** turns the page without counting: foliate turns it itself until Octavo takes over turns (`setTurnMode`), so the step waits for the next tap. Harmless, and left as it is.

**Taps while the cover opens are ignored.** The cover's motion takes touches until it's gone (`ReaderCoverMotionView`), so a tap on the card's place before it shows does nothing. That's probably the one lost tap seen earlier in this work; not proven.

**Slow on the simulator:** the first opening of the book. Continue without closing leaves the cover waiting on the right page for 4.4 s. Unfolding shows a white page with a spinner for 3.8 s (`videos/unfold-opens-it.mp4`). Both measured from one film each. A real Duo should be quicker, but that's unmeasured. If it's still noticeable, loading the reader's page earlier is the obvious fix.

## Tests

`OctavoTests/TourTests.swift`: the steps in order and out of order, a fold at every step, the words and dots, plays once, every launch order in `TourRecord`, Skip and Not now landing, Add books, shared files, a replay's isolation, the hinge following reports. `aReplayNeverSavesAPlace` builds its own `ReaderModel`, so `ReaderView`'s use of the replay's stores is covered only by the simulator check above. App 428/428, OctavoKit 253/253.

`Packages/OctavoKit/.../ServerCredentials.swift` changed by one word: `installedKey` is public, so the tour can read it. Nothing else in network-trust code changed.

## What to try on a Duo

Delete Octavo first, so it's a new install. On Adam's existing install it should not play by itself.

1. Open it unfolded, then close it, then open it: Close your iPhone, the cover, Chapter I.
2. Delete it and open it closed: straight to the cover.
3. Continue without closing: does the cover opening look right from that screen, and how long does the cover wait?
4. Does the page lift read as a page lifting, and are the blue ··· and Aa enough to find them?
5. Fold on any card and unfold. Fold quickly right after a card changes: that's the moment the crash fix doesn't cover.
6. Half open, and with Reduce Motion on.
7. Show the tour with a server connected and with Pride and Prejudice removed.
8. The wording is still a draft for Adam (decision 29).
