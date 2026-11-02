# Sync you can see (step 13)

Step 13 of `docs/PLAN.md`, built 2026-11-02. It wires BookOrbit position sync into the app itself, keeps every place line equal to where the book opens, shows when a place last synced, and has unfolding on a cover open the book without waiting on the server.

## What was wrong before

- **The app didn't sync positions with BookOrbit at all.** `ReaderView` made `ReaderModel` with no `ProgressSync` in release builds. Only the debug remote (`ReaderRemote`, books opened by a script) passed one.
- So a BookOrbit book opened at the iPhone's own place, or at the start, while its screen showed the server's percentage from the library list. That is the "server percentage without a position opens at the start" in the plan.
- The cover page had an empty `coverAppeared` hook for the pull.

## How it works now

- **Which books sync.** Every BookOrbit server's books (`LibraryServer.syncsProgress`; the debug connection syncs). `ShellModel.progressSync(for:on:)` hands back a `BookOrbitProgressSync` for the book's readable file. OPDS catalogs and Files keep their place on the iPhone.
- **"Don't sync" isn't offered for now** (Adam, 2026-11-02). Setup skips its Reading progress step and saves the server as syncing; `SavedServer.progressSyncs` also overrides a "Don't sync" an earlier setup saved. The door stays open: set `SavedServer.offersSyncChoice` and the step returns. "Don't sync" then ignores the server's place entirely: `BookOrbitSource(includesProgress: false)` leaves `progress` out of every list, so no screen shows a percentage the book won't open at.
- **`BookPlaces`** (`Octavo/Book/BookPlaces.swift`, owned by `ShellModel.places`) is the one source of truth:
  - `opening(of:)` is `OpeningPosition.choose(local:remote:)`, the reader's own rule. The remote is the last pull or push this session, else the library list's percentage. The book's screen, Home's rows and Search's rows show `progress(of:)`, so they match where the book opens.
  - `refresh(_:)` pulls the server's position. `BookCoverPage` calls it when it appears and when the app comes back to the foreground (not while the reader covers it). If the iPhone's place is unsent and wins under the rule (read offline), it's pushed then.
  - `refreshRow(_:)` does the same for Home's and Search's rows (Adam, 2026-11-02): only for a book with a place to show, and at most once a minute per book (`rowReuseAge`), so switching tabs doesn't fetch again. Home also fetches when its books change, and fetches again (ignoring the minute) when the app comes back.
  - `readerSync(for:)` gives the reader a `SharedProgressSync`. Its `pull()` reuses a pull up to 5 minutes old (`BookPlaces.reuseAge`), or joins the one in flight. Its `push` reports back, so the screen shows the new place after the reader closes.
  - Each pull gives up after `ReaderModel.pullTimeout` (5 s), so the reader never waits longer than before. A pull that started before a push can't put the older position back (`generations`). Another server clears everything (`reset`).
- **The reader** (`ReaderModel`) takes `fallback`, the list's percentage. When there's no pull (no sync, or it failed) it opens at `choose(local, fallback)`, which is what the screen showed: the iPhone's place, else that percentage. Opening at a pulled server position records the sync time. `syncStatus` (debug) now says how long the pull took.
- **Last synced.** `LocalReadingProgress.syncedAt` (OctavoKit) is set when a push lands (`ReadingPositionStore.markPushed(_:forBook:at:)`) and when the book opens at a pulled server position. Later saves keep it. `BookPlaces.status(of:)` gives:
  - `.notSynced`: the iPhone's place is unsent and is where the book opens.
  - `.synced(date)`: the later of `syncedAt` and this session's last pull or push.
  - `nil`: the book doesn't sync, or isn't started anywhere.

## The sync line (Adam, 2026-11-02)

- **On the place's own line, at the right:** "50%" on the left, "Synced just now" on the right. The sheet gets no taller. Unfolded, the right page shows the same.
- Wording: "Synced just now" (under a minute), "Synced 5 minutes ago" or "Synced 3 hours ago" (same day, `RelativeDateTimeFormatter`, full units), "Synced yesterday", then "Synced Oct 28" (locale's day and month). "Not synced yet, will retry" while a place waits (decision 22). A `TimelineView(.everyMinute)` moves "just now" on.
- **Nothing** for a book whose place doesn't sync (OPDS), or when the place line shows a problem or Finished.

## Checked on the simulator

`iPhone Duo` (8C35AF6E-5F3F-48D7-A283-AEE894511947), local BookOrbit v3.6.0, Moby-Dick (file 3). Screenshots are in `sync-in-app/`.

| # | What | Result |
|---|---|---|
| 01 | Reader moved to 50%, closed; cover folded | Server got the app's own push (50.05%, new CFI). Sheet "50% · Synced just now" |
| 02 | Another reader sets the server to 25% (`sync-spike/tools/bo.sh set`); app to the background and back | Sheet follows to "25% · Synced just now", same process |
| 03 | Unfold on the cover | Reader opens two pages at 25%, `openedFrom: server` |
| 04 | Half open on the cover (fresh pull) | Book mode at 25% |
| 05 | Reader closed, unfolded | Cover \| Details, right page "25% · Synced just now" |
| 06 | `-syncFailsPushes 1`: read to 60%, fold | Folding closes the reader; sheet "60% · Not synced yet, will retry". Server still 25% |
| 07 | Relaunched online, cover shown | The cover sent it: server 60.15%, sheet "60% · Synced just now" |
| 08 | Home | Moby-Dick at 60%, as its screen |
| 10 | Server set back to 25% by another reader; Octavo relaunched, Home | Before rows fetched, Home said 60% (the iPhone's place). Now Moby-Dick shows 25% |
| 11 | Another reader sets 60%; app to the background and back on Home | Moby-Dick follows to 60% |

**Unfolding no longer waits on the pull.** With `-syncPullDelay 3` (a 3 s server):

- A book opened straight into the reader (no cover first) waited **3022 ms** for its pull.
- After a fresh launch, the cover shown for 5 s, then an unfold: **0 ms**.
- With the unfold 1 s after the cover appeared (pull still running): **0 ms**. The page load overlaps the rest of the pull.

From the unfold to the opened page takes about 3.7 s on the simulator. That is the web page loading and foliate opening the book, not sync.

The server was put back to 25% afterwards.

**Running the app tests signs the simulator's app out.** They run inside the app on the same simulator, and `KeychainTests` wipes every BookOrbit token while testing the leftovers-after-install cleanup. So sign in again (or launch with `-connectBookOrbit 1`) after a test run. This was true before step 13.

## Coming back with a book open (Adam, 2026-11-02)

Before this, an open reader never asked the server again, and its next page turn replaced whatever another reader had saved meanwhile.

- **When.** The app comes back to the foreground with a book open (`ReaderView` on `scenePhase` `.active`). `ReaderModel.checkServerPlace` pulls with `ProgressSync.pullLatest`, which `SharedProgressSync` never answers from a kept pull.
- **What's offered.** Only a server CFI other than the one the reader knows (`serverCFI`: pulled to open, its own last push, or the last check), and only if it isn't on the visible page (`bridge.js` `onPage`, so two spellings of the same place don't count). A check overtaken by a push that landed meanwhile is dropped (`pushCount`), so a pull of an older push isn't offered back.
- **The capsule** (`ReaderServerPlaceBar`): "BookOrbit: 62% · CHAPTER 80. The Nut.", **Go** and **✕**, in the footer's place like search's step bar, under the right page when unfolded. The percentage is the server's, which another foliate reader computes as the footer does. It waits while a panel, the progress bar or the step bar is up. No alert: decision 22.
- **Go** jumps to the server's CFI. The page it lands on is saved as synced and not pushed, as when a book opens. If a fold or a text change sent this page's place while the capsule showed, Go sends the server's own position back.
- **✕ and reading on** keep this iPhone's place. ✕ sends the page now; turning the page (or jumping anywhere) sends it as any move does. The capsule goes once the page it was offered on is no longer showing (`onPage`), so a fold or a text change keeps it.
- **The pusher forgets its last push** once another reader has moved the server (`DebouncedProgressPusher.backendMoved`). Without that, ✕ on the page last pushed sent nothing, as the pusher skips a repeat.

Checked on `iPhone Duo` (8C35AF6E-5F3F-48D7-A283-AEE894511947), Moby-Dick (file 3): read back to 48%, `bo.sh set` moved the server to 62% (Chapter 80), then Settings and back.

| # | What | Result |
|---|---|---|
| 12 | Back in the app, folded | Capsule "BookOrbit: 62% · CHAPTER 80…", footer hidden |
| — | Turned the page | Capsule gone, footer back, server 48.07% (this page) |
| — | Go | Reader at 62.02% (Chapter 80); server kept its CFI, nothing pushed |
| — | ✕ | Page stayed; server 48.01% (this page, sent again) |
| 13 | Offered folded, then unfolded | Capsule stays, under the right page. The fold sent 47.94%; Go put the server back to its 62% CFI and opened the spread at 61.9% |
| — | Server place on the visible spread | No capsule |

## Debug switches

- `-syncPullDelay <seconds>`: every BookOrbit position pull waits first (a slow server).
- `-syncFailsPushes 1`: pulls work and pushes fail as if offline (`DebugProgressSync` in `ShellModel.swift`).
- `docs/notes/sync-spike/tools/bo.sh set <fileId> <cfi> <percentage>` moves the server's place, like another reader.

## Tests

- App: `BookPlacesTests`. These cover the place before and after a pull, a percentage-only server place, an unsent place sent from the screen (and a failed retry), the offline status, books that don't sync, a book not started, redraw on close, the reader reusing a recent pull and sharing a running one, a stale pull not undoing a push, a server change, which books sync, and the line's wording. `ReadingPositionStoreTests` covers `syncedAt` being kept and recorded.
- OctavoKit: `BookOrbitSourceTests.leavesOutTheServersProgressWhenAsked` and `OpeningPositionTests.aRecordWithoutASyncTimeDecodes`.
- Coming back with a book open: `BookPlacesTests.theReadersCheckNeverReusesAPull`, `ReaderServerPlaceTests`, and `DebouncedProgressPusherTests.sendsThePositionAgainOnceTheBackendMoved`. The capsule's choices were checked by hand (above); `ReaderModel` needs a loaded book to test.

## Not done (follow-ups)

- **Unsent places are retried only** when their book's screen shows or the book opens, not in the background for every book.
- **If "Don't sync" comes back**, decide whether bookmarks follow it (they sync with BookOrbit regardless today).
