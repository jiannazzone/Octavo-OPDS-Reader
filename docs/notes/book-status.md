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
  - **Octavo sets no status itself, except where BookOrbit's own reader would.** Starting a book whose status is Unread or Want to read makes it Reading, as BookOrbit's web reader does (below).

## How it's built

- `LibraryReadStatus` (OctavoKit) holds BookOrbit's eight values, BookOrbit's Continue Reading rule (`staysInContinueReading`) and what starting a book does (`whenStarted`). `LibraryFilter.showing(_:progress:)` is the filter rule, used wherever books are filtered on the iPhone. `LibraryBook.readStatus` carries it from lists and the details.
- `LibrarySource.setReadStatus` (`PATCH books/{id}/status`). `tracksReadStatus` says which sources show "…".
- The finished mark became a **read mark** (`ReadMark`: finished, and the status where the server keeps one). `LibraryModel.readMarks`, the iPhone's records (`BooksOnIPhone`, `RecentBooks`) and a list's newer word work as the finished marks did, so a cover, a filter and Home agree whatever copy of the book they hold.
- `BookPage.setStatus` shows the change at once and puts it back if the server refuses ("Couldn't change the status. Check your connection."). Mark finished sets the status too (Read, or Reading when taken off).
- **Starting a book:** `BookOrbitProgressSync` takes the book's id when its copy shows it not started with a status that starting changes. The first push between 0 and 100% reads the status again (the copy may be old), sets Reading if it's still Unread or Want to read, and tells the app (`ShellModel.progressSync(for:on:started:)`), which marks the library and an open book screen. A failure is tried again with the next push.

## Why the starting rule

BookOrbit's web reader writes progress through `PUT reading-progress`; Octavo writes through `POST books/files/{id}/progress`. Starting a book, the first moves Unread, Want to read and On hold to Reading; the second leaves Unread and Want to read alone. Without the rule, a Want to read book read in Octavo stayed "Want to read · 60%" on every device. Switching Octavo's progress path was ruled out: it's the sync core, measured 31/31 against BookOrbit, and the batched endpoint has semantics of its own.

## Checked

- OctavoKit: every status sent as BookOrbit's own value, the filter rules against each status and progress, the starting rule (Want to read starts, Abandoned stays, 0% and 100% don't start, a failure is tried again).
- App: the page's status and its refusal, Mark finished setting the status, the place lines, the folded line, the menu's tick, marks reaching the iPhone's records and surviving a relaunch, a list's newer status, Home dropping Abandoned and keeping On hold, On iPhone's filter for BookOrbit books.
- Simulator (iPhone Duo #120, iOS 27.1): the button folded and unfolded in both versions, On hold folded and unfolded. Scripted taps didn't reach the menu, so opening it is checked by hand.

## Not done

- Rating and collections (measured, `bookorbit-api.md`).
- Status on Home's and Search's rows in words. Covers show its glyph.
- Status from the reader or a long press on a cover.
