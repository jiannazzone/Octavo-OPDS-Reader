# Covers on the iPhone

Every launch used to fetch every cover again: `ServerTransport` has no URL cache on purpose, and `CoverCache` was memory only. On a real library of 191 books that was 13.8 MB a launch. Covers now stay on the iPhone (`CoverFiles`), and read from there off the main thread. This is about network use and how soon covers appear, not the scrolling jitter in #82.

## How it works

- **Where:** `Caches/Covers/<server ID>/`, out of the backup. iOS can clear it when it needs the room, and the covers are fetched again.
- **Names:** a SHA-256 of the cover's key. An OPDS cover's key is an address, and an address can hold a secret (`OPDSURLSecret`).
- **What's kept:** the bytes the server sent, thumbnails and full covers alike. Imported books' covers aren't copied.
- **Decoding:** `CoverCache.decoded`, off the main thread with ImageIO, at most 600 pixels a side for a thumbnail and 2400 for a full cover. `UIImage(data:)` would decode as it first draws, mid-scroll, and `byPreparingForDisplay()` blanks the window on the iOS 27.1 simulator.
- **Priority:** a grid's covers load at `.utility`, set on the view's `.task`, since awaiting a lower-priority `Task` raises it to the waiter's. A full cover stays at `.userInitiated`. Covers already scrolled away still finish.

## When a kept cover goes or changes

- **A changed cover, with a version** (`LibraryCover.version`): the key changes, so it's a new file.
- **No version** (every OPDS cover, and some BookOrbit ones): the kept one shows at once, and if its file is over a day old it's fetched again in the background. The new one shows when the cover is next drawn. If that fetch fails, the old one stays.
- **Remove server:** its folder goes (`LibraryModel.remove`). A fetch under way then keeps nothing: `CoverCache.keep` checks before writing and again after.
- **Sign out:** covers stay, like the server's books.
- **Clear covers,** in Settings' Storage section (Adam): the files and the memory cache go, and each cover is fetched when it's next shown. It doesn't ask, since nothing is lost. A cover already on a screen stays until that screen draws it again.
- **Over 500 MB in all:** at launch the covers written longest ago go first (`CoverFiles.trim`). A version's old files leave this way too. There's no age limit, because a cover deleted by age can't come back while the server is unreachable.

## Checked

On a simulator against the local BookOrbit: the second launch showed the covers and rewrote none of the 7 files, and Remove server left no files. `CoverFilesTests` covers the rest. The check after the write has no test, since it needs a removal landing during the write. Not checked on a real device or with a real library.
