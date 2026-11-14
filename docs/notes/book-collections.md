# Collections on BookOrbit books (#120)

Putting a BookOrbit book into your collections, and making one, from its screen. Decided with Adam and built on 2026-11-14, after the read statuses (`book-status.md`) and rating (`book-rating.md`). It finishes #120. The server's side is measured in `bookorbit-api.md`, "Read status, rating and collections".

## Decided (Adam, 2026-11-14)

- **Where:** the details' Collections row, where the book's collections already show, gains a chevron and opens a Collections screen (`ShellRoute.bookCollections`), pushed with Back like any screen. Not chosen: an "Add to Collection" item in "…", which is Apple Books' place but would put an action into the status picker.
- **The row:** as many names as fit on one line, then how many more: "Classics · Spike +3". "—" for none. Not chosen: every name wrapping, which pushes the details down; a count alone, which hides the names even for one.
- **The screen:** your collections, each with a tick if the book is in it; a tap adds or removes it at once. "New collection" at the end turns into a name field, and Return makes the collection with the book in it. No pop-up (decision 22).
- **Only your own book collections:** other users' shared collections and podcast collections aren't listed. Adding to a shared one isn't measured (no second account with a known password).

## How it's built

- OctavoKit: `LibrarySource.tracksCollections`, `collections(of:)` (`GET collections?bookIds=`, one request, `memberCount` saying which hold the book), `setCollection(_:contains:for:)` (`POST`/`DELETE collections/{id}/books`) and `newCollection(named:with:)` (`POST collections`, then adding the book). `LibraryBookCollection` is a collection as the book's details list it, plus whether the book is in it.
- **The icon:** BookOrbit requires one, a Lucide icon's name, which only its web app shows. Octavo sends `Library` (books on a shelf).
- **The row follows the book's details,** which also name other users' shared collections the book is in, in their order. Your collections as last loaded or changed here (`BookPage.collectionMarks`) are laid over them: one taken out goes, one put in joins at the end. So a visit to the list neither drops shared collections nor reorders the row, and the list, loaded later than the details, corrects them for yours.
- A change shows at once and is put back if the server refuses ("Couldn’t change the collections. Check your connection."); a tap while that collection's last change is on its way does nothing.
- **A new name:** trimmed; empty puts the row back. One you have already, case aside, ticks that collection instead of making another. The server's 409 says "You already have a collection called “…”."; any other failure "Couldn’t make the collection. Check your connection." and keeps the name to try again. If the collection is made but adding the book fails, it's listed unticked, to tick, with "Couldn’t add it to “…”. Check your connection."
- `BookCollectionsScreen` is a spread: the book's cover on the left page (without reporting a cover spot, so the reader doesn't open from it), the list on the right, named "Collections" on the page itself, as the book's screen names itself. Folded, the list fills the screen.
- OPDS and Files books keep the plain Collections row. Every details row is one layout (`BookDetailsRow`), the label over the value at the accessibility text sizes; there the Collections row names every collection, wrapping.

## Checked

- OctavoKit: the membership request and its filter (own book collections only), adding and removing, making one with its icon and then adding the book, and the 409.
- App: loading, a load that fails, ticking and unticking, a refusal put back, a new collection, one made without the book, a name you have, an empty name, the 409 and other refusals, the row's names and count, and the row after a visit (shared collections kept, the details' order, yours corrected).
- End to end on iPhone Duo #120 against the local BookOrbit: ticking Spike, making "Book club" (with the book, icon `Library`), unticking, and the row with five collections ("Book club · Spike +3"), unfolded and folded; the details at the accessibility text sizes. The server was put back afterwards, checked against a snapshot of its collections.

## Not done

- Removing or renaming a collection, and shared collections.
- A collection made here shows in the Library's collections the next time that list loads, not checked.
