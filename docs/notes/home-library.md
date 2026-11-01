# Home and Library (#13)

Built 2026-11-01 on the simulator 'Octavo Shell Duo' (iOS 27.1) against the local BookOrbit v3.6.0, and approved by Adam on screen. Screenshots: `home-library/1-folded.png` (frames 01, 02, 29–32), `2-unfolded.png` (04, 33, a pane shift, 38, half open), `3-states.png` (25, 22, 21, no library, the Settings debug section).

## Decisions (Adam, one at a time)

1. **A book remembers its library.** `SourcedBook { source: LibrarySourceID, book: LibraryBook }` is what a cover route, the reader and the iPhone's records carry; `ShellRoute.feed(LibraryEntry, from: LibrarySourceID)` is a list. `LibrarySourceID` is opaque: a server's is a UUID made when it's added (#12 stores it), so records from a removed or replaced server never point at another server's books. Imported files use `"files"`.
2. **Debug connection until first run (#12):** a "Debug server" section in the Settings stand-in (Connect local BookOrbit, Use sample library, Disconnect) and the launch arguments `-connectBookOrbit 1` and `-sampleLibrary 1|empty`. Tokens stay in memory until #9, so each launch signs in once; BookOrbit allows 5 a minute.
3. **Continue reading** is BookOrbit's own list (`LibraryRoot.continueReading`, see `bookorbit-api.md`) merged with the books opened on this iPhone (`RecentBooks`), one row per book, newest first by `LibraryBook.lastReadAt` and the open date. An OPDS server has no such list, so only the iPhone's half shows.
4. **Five rows at most**, no See all.
5. **New on the server:** one row of covers that scrolls sideways, the newest 20.
6. **Unfolded, the right pane starts on the list's first item, selected:** a book's cover page for a grid (frame 04), a collection's books for a list (frame 33).
7. **The filter button in frame 02 is left out**, parked in `docs/UI-IDEAS.md`.

## How it fits together

- `LibraryModel` (environment) holds the server, its chips, Home's lists and one `FeedModel` per list, so a fold, which rebuilds the views, shows them without loading again. `source(for:)` resolves a `LibrarySourceID`.
- One screen shows every list by what it holds (decision 23): entries as rows, authors A–Z with the system index strip (`sectionIndexLabel`), books as a cover grid (numbered for a series), rows above a grid when an OPDS feed mixes them. The Library root is the same screen with the chips on top.
- Connection failures (`URLError`, `LibraryError.signedOut`) become the tab's `ConnectionBanner`; other failures stay with the list that failed ("Couldn't load this list · Try again"). Retry reloads what failed.
- `SampleLibrarySource` (DEBUG) is made-up data with no network for screenshots, previews and tests.

## Things that bit

- **`UIImage.byPreparingForDisplay()` blanks the whole window on the iOS 27.1 simulator**, tab bar included, for as long as the prepared images are on screen. Plain `UIImage(data:)` renders. Covers decode that way for now; check on a real device before adding pre-decoding back.
- **A filled image grows its view.** `Image.resizable().scaledToFill()` reports a frame larger than it was offered unless it sits in an overlay of a view that keeps the offered size (`CoverImage`). Otherwise anything aligned to it, such as the cover's strip, moves off screen.
- **A reused view keeps its `.task(id:)`.** Switching chips hands the same `FeedContent` another list, so its load task is keyed on the list's identity, not only on what kind of list it is.
- **Plain `List` section headers** sit far apart; the A–Z letters are small rows inside each section instead, which still feed the index strip.
- **Sideways scroll views reach under the side column**; the new-books row is clipped to the content's edge.
- **Pane titles:** the folded large title's ink starts at 37.3 pt and the unfolded panes' at 35.3 pt with #6's 28 pt offset, so `PaneStack.titleTop` is now 30 (measured from screenshots; both 37.3 pt after the change).

## Not done here

- **On iPhone** chip, and switching to it when the server is unreachable: needs downloads (#10).
- The place line is a percentage; the chapter ("Chapter 36 · 30%") needs the reader (#17).
- The cover page is #6's stand-in until #14's is wired into `ShellScreen`.
- `SpikeLibraryView` stays: the fold, sync and formats tools drive it with `-spike 1` through `SpikeRemote` (`signin`, `open`, `detail` by BookOrbit file id). Moving them to the real Library needs the real reader (#17), downloads (#10), and a way for `SpikeRemote` (or its replacement) to open a `SourcedBook`'s cover and reader in the shell.
