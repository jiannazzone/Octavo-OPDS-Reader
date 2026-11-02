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

**Unfolding no longer waits on the pull.** With `-syncPullDelay 3` (a 3 s server):

- A book opened straight into the reader (no cover first) waited **3022 ms** for its pull.
- After a fresh launch, the cover shown for 5 s, then an unfold: **0 ms**.
- With the unfold 1 s after the cover appeared (pull still running): **0 ms**. The page load overlaps the rest of the pull.

From the unfold to the opened page takes about 3.7 s on the simulator. That is the web page loading and foliate opening the book, not sync.

The server was put back to 25% afterwards.

## Debug switches

- `-syncPullDelay <seconds>`: every BookOrbit position pull waits first (a slow server).
- `-syncFailsPushes 1`: pulls work and pushes fail as if offline (`DebugProgressSync` in `ShellModel.swift`).
- `docs/notes/sync-spike/tools/bo.sh set <fileId> <cfi> <percentage>` moves the server's place, like another reader.

## Tests

- App: `BookPlacesTests`. These cover the place before and after a pull, a percentage-only server place, an unsent place sent from the screen (and a failed retry), the offline status, books that don't sync, a book not started, redraw on close, the reader reusing a recent pull and sharing a running one, a stale pull not undoing a push, a server change, which books sync, and the line's wording. `ReadingPositionStoreTests` covers `syncedAt` being kept and recorded.
- OctavoKit: `BookOrbitSourceTests.leavesOutTheServersProgressWhenAsked` and `OpeningPositionTests.aRecordWithoutASyncTimeDecodes`.

## Not done (follow-ups)

- **An open reader doesn't re-pull** when the app returns to the foreground. If another device moved on meanwhile, the reader stays put until it's reopened.
- **Unsent places are retried only** when their book's screen shows or the book opens, not in the background for every book.
- **If "Don't sync" comes back**, decide whether bookmarks follow it (they sync with BookOrbit regardless today).
- Home's and Search's rows use a pull only once the book's screen has been seen this session. Before that, they show the iPhone's place, else the list's percentage, as the book's screen does before its pull lands.
