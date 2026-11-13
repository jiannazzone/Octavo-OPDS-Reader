# Read status on BookOrbit books (#120)

Every BookOrbit read status on a book's screen, and the filters and Home that follow them. Measured against the local BookOrbit v3.6.0 on 2026-11-12 and 13 (`bookorbit-api.md`, "Read status"), built 2026-11-13. Rating and collections, the issue's other actions, come next.

## Decided (Adam, 2026-11-12 and 13)

- **Where:** BookOrbit books keep Mark finished, one tap as before, and gain **"…"** (More), a glass circle. Folded it sits beside Mark finished in the pulled-up sheet; unfolded, beside the title, because next to Mark finished and Download it squeezed the label to "Mark fini…". OPDS and Files books keep Mark finished alone. A labelled "… More" was tried and not chosen.
- **The menu:** Reading, Want to read, On hold, Skimmed, Abandoned, Unread, with a tick on the book's. Finished is its own button. Rereading ticks Reading, and a book with no status ticks Unread (BookOrbit's filters treat none as unread). Rate and Add to Collection are to join it.
- **Place line:** a status the place alone would misstate comes first: "On hold · 50%", "Skimmed · 50%", "Abandoned · 50%", "Want to read" (or "Want to read · 12%" once started); with no progress, the status alone. Reading, Rereading and Unread show the place as before, and Finished stays "Finished". Folded, the status takes the sync time's room ("On hold · 50%", not "On hold · 50% · Synced just now"); a place not sent yet still says so.
- **Glyphs** (Adam, 2026-11-13): a status the place line names takes the finished check's place on a cover's badge: Want to read `bookmark`, On hold `pause`, Skimmed `forward`, Abandoned `xmark`, in outline and one image scale smaller than Finished's `checkmark` (at the check's size they looked larger than it and the download arrow); the check as before; Reading and Unread show none. The cover's VoiceOver value says it ("On hold, downloaded"). The menu shows each status's glyph beside its name, Reading as `book` and Unread as `book.closed`. The bookmark is also the reader's ribbon; `clock` was the alternative.
- **Match BookOrbit.** Home's Keep Reading and the Filter follow BookOrbit's own rules:
  - **Keep Reading** is BookOrbit's Continue Reading: started books that are Reading, Rereading, On hold or Want to read. Setting Skimmed, Abandoned, Unread or Finished takes a book off this iPhone's list too, as Mark finished did (`LibraryModel.markedStatus`).
  - **Filter:** Unread is no progress and no status, Unread or Want to read. Reading is Reading or Rereading, or On hold or Want to read once started (0 < progress < 100%). Finished is Read. Skimmed and Abandoned show only under All books. On the server (`BookOrbitBookFilter`), on a series' or an author's books, and on On iPhone (`LibraryFilter.showing`), the rule is the same.
  - **Octavo sets no status itself.** Reading a Want to read or Unread book makes it Reading on the server, through Octavo's progress request as through BookOrbit's web reader (checked end to end below).

## How it's built

- `LibraryReadStatus` (OctavoKit) holds BookOrbit's eight values, BookOrbit's Continue Reading rule (`staysInContinueReading`), and `other` for a value a newer BookOrbit adds. `LibraryFilter.showing(_:progress:)` is the filter rule, used wherever books are filtered on the iPhone. `LibraryBook.readStatus` carries it from lists and the details.
- `LibrarySource.setReadStatus` (`PATCH books/{id}/status`). `tracksReadStatus` says which sources show "…".
- The finished mark became a **read mark** (`ReadMark`: finished, and the status where the server keeps one). `LibraryModel.readMarks`, the iPhone's records (`BooksOnIPhone`, `RecentBooks`) and a list's newer word work as the finished marks did, so a cover, a filter and Home agree whatever copy of the book they hold.
- `BookPage.setStatus` shows the change at once and puts it back if the server refuses ("Couldn't change the status. Check your connection."). Mark finished sets the status too (Read, or Reading when taken off).
- **A status Octavo doesn't know** (a newer BookOrbit's) is kept as `other`: only under All books, as on the server, with nothing ticked in "…" and never sent. Records an older Octavo reads decode it the same way.

## No starting rule

Built first, then taken out (2026-11-13): Octavo set Reading itself when it started a Want to read or Unread book, because the first measurement said its progress request left them and BookOrbit's web reader didn't. Testing it end to end against the local server showed the server had already done it ("reading", `auto`). Measured again on books without the earlier tests' history, both requests do the same: Unread and Want to read become Reading unless the book has been finished before, and then both leave them (`bookorbit-api.md`). So the rule was redundant where BookOrbit acts, and wrong where it doesn't.

## Checked

- OctavoKit: every status sent as BookOrbit's own value, the filter rules against each status and progress, a status Octavo doesn't know.
- App: the page's status and its refusal, Mark finished setting the status, the place lines, the folded line, the menu's tick, marks reaching the iPhone's records and surviving a relaunch, a list's newer status, Home dropping Abandoned and keeping On hold, On iPhone's filter for BookOrbit books.
- End to end against the local BookOrbit: statuses set on the server showing on the book's screen and on covers, Want to read under the server's Unread filter, and reading a Want to read book in the app making it Reading on the server.
- Simulator (iPhone Duo #120, iOS 27.1): the button folded and unfolded in both versions, On hold folded and unfolded. Scripted taps didn't reach the menu, so opening it is checked by hand.

## Not done

- Rating and collections (measured, `bookorbit-api.md`).
- Status on Home's and Search's rows in words. Covers show its glyph.
- Status from the reader or a long press on a cover.
