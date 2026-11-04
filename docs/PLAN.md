# Build order

One area at a time, in this order. Each step goes to the simulator when it's built, and each phase ends on Adam's Duo for sign-off. The decisions behind each step are in `docs/design/direction.md`; steps marked *needs decisions* get designed with Adam first.

## Phase 1: Library

- [x] **1. Shell.** Three tabs, one stack of screens per tab, each screen a spread across both pages; Back and swipe back; Settings button.
- [x] **2. Library.** Sections as shelves; a section opens over the whole spread (grid of covers, or a list flowing left page → right page).
- [x] **3. A book's screen.** Folded: the cover with a sheet (title, progress, Mark finished, Open or Download; pull up for details). Unfolded: Cover | Details. Unfolding opens a downloaded book.
- [x] **4. Downloads.** A check on downloaded covers and a ring while downloading, everywhere covers show; downloads kept where iOS won't clear them; Remove download; nothing downloads in the background.
- [x] **5. Home.** The book you're reading, large, with your other books in progress beneath (or on the right page).
- [x] **6. Series and authors.** Series as cover stacks, opening in reading order; Authors first name first, filed by last name, with an A–Z strip on long lists.
- [x] **7. Search tab.** The field under the title; Recent and Browse before typing; Books, then Series and Authors, as you type, with books on the iPhone included.
- [x] **8. Adding your server.** Setup before there's a server: BookOrbit (sign in, then where progress syncs) or an OPDS catalog (its address, a sign-in only if it asks), trusting a self-signed certificate on the way; each step a screen across the spread. Signing in again from the signed-out banner.
- [x] **Library on the Duo:** Adam signed off (2026-11-02), then a pull request to `main` (with Adam's OK). Setup touches the Keychain and address handling, so it gets a security review that Adam signs off before the merge.

## Phase 2: Reading

- [x] **9. Reader controls.** A quiet "…" in the side column is the one way to bring the controls up, in every posture; every other tap turns (left of the middle back, right of it and the column forward).
- [x] **10. Page turning.** Taps and swipes in every posture; a hardware keyboard (arrows, Page Up/Down, Space) and a trackpad's two-finger swipe; the place holds through unfolding, half open and flat again (folding closes the book, by design).
- [x] **11. Rendering.** Verse no longer runs off the page, justified text hyphenates instead of opening wide gaps, and chapters no longer start after a blank page (`docs/notes/reader-page.md`, Book styles).
- [x] **12. Panels.** Text and theme, Contents and bookmarks, Search in book.
  - [x] Text and theme: themes, text size, font, line spacing, margins, justify, Match Dark Mode, Book-mode shadow and Always show controls, over the right page unfolded and in a sheet folded.
  - [ ] The bundled fonts, Atkinson Hyperlegible and OpenDyslexic (downloading them waits for Adam's OK).
  - [x] Contents and bookmarks: one panel with a Contents | Bookmarks switch, page numbers that match the footer, a ribbon on bookmarked pages, and BookOrbit books' bookmarks synced with BookOrbit.
  - [x] Search in book: results by chapter as you type, a highlighted match and a ‹ 3 of 252 › bar to step through.
- [x] **Reading on the Duo:** Adam signed off (2026-11-02), then a pull request to `main` (with Adam's OK).

## Phase 3: The rest of v1

- [x] **13. Sync you can see.** BookOrbit positions sync in the app (only the debug remote did before). Setup no longer offers "Don't sync" (Adam; the code stays for later). The book's screen, Home and Search show where the book opens, a server percentage without a position included; the place line says when it last synced ("Synced just now", "Not synced yet, will retry"; nothing for books that don't sync). Unfolding opens at once: the server's position is fetched while the cover shows (`docs/notes/sync-in-app.md`).
- [x] **14. Settings.** The list and the chosen page side by side unfolded (one screen each folded): the server's page (address, account, Synced / Not synced yet / Paused, Sign out and Remove server, each confirmed; Sign out also ends the BookOrbit session), Titles under covers, Books on iPhone (sizes, a sort menu, swipe to remove, Remove all downloads) and About (version, source code, licences). Remove server keeps or removes its books, clears its secrets and unsent places, and opens setup (`docs/notes/settings.md`).
- [x] **15. Other ways in.** Import from Files on the first screen and from a + in the Library, and Open in Octavo from other apps, landing on On iPhone; a note above the books for files that couldn't come in. The bundled Standard Ebooks Pride and Prejudice, read straight from the first screen. On iPhone (downloads and imports, the same book as on its server's shelf) is the Library's last shelf, and the Library itself while there's no server, with Add a server in Settings and a dismissible "Have a server?" card. Removing an imported book always asks. MOBI, AZW3 and FB2 pass the check through foliate, the bridge and both script-blocking layers; DRM files are refused, imported or downloaded (`docs/notes/other-ways-in.md`, `docs/notes/formats-check.md`).
- [x] **16. Security follow-up.** A server isn't local by its name alone: measured with real DNS and Bonjour (`uz`, a spoofed `.local`), names are judged by every address they resolve to, before every request (#9; no change needed). At launch, Keychain items that aren't the saved server's go (a failed Remove server, an abandoned setup), and so does a signed-out server's sign-in; nothing goes if the saved server can't be read. A pin that can't be read fails the request instead of being skipped. Stump's path key and keys or tokens in a catalog address's query join Kavita's in the Keychain; a BookOrbit address drops its query. Adam's wording: no line about the Kavita key after Remove server; "Not encrypted. On other networks, your password could be seen." (`docs/notes/network-trust.md`, step 16).

## Phase 4: First impressions

- [x] **17. The new-install flow.** What someone sees the first time, from opening the app to their first book (Adam, 2026-11-02). Decided 2026-11-03 (decisions 29 and 30 in `docs/design/direction.md`): a short tour in the sample book that opens like a book. Close your iPhone, Pride and Prejudice's cover, unfold onto Chapter I, then a card at the bottom of the left page teaches turning, the controls and Text and theme, and ends on Add your books. Skip lands on Home with the sample book; Show the tour in Settings plays it again. Built 2026-11-03 and tried on Adam's Duo the same day (`docs/notes/tour.md`).

## To revisit

- [x] Page-turn animations, designed together with opening and closing a book (Adam, after step 10). Decided 2026-11-03 (decisions 27 and 28 in `docs/design/direction.md`) and built the same day (`docs/notes/page-turns.md`); opening and closing to be confirmed on Adam's Duo.
- Closing the sample book lands on the Library, not its cover (Adam, 2026-11-03). Today the reader's Back shows whatever screen it was opened over: the sample book read from setup closes onto the Library's On iPhone, a book from Home's Continue reading onto Home. Only folding closes onto the book's own screen (`ShellModel.closeToItsScreen`). Decision 28's closing (the page swings back as the cover, which shrinks into its place) needs the book's screen there, so it plays only where Back already lands on it; elsewhere the reader fades as before. Should Back always land on the book's screen?
- Should Home and the Library share the reader's colours (its theme: Paper, Sepia, Night), or keep the system's light and dark? (Adam, after step 12.)
- The empty strip at the reader's left edge, unfolded (the mirror of the side column, about 84 pt, so the pages split on the hinge). Options: keep it as a margin; a quiet progress rail with chapter ticks; or, with Narrow margins and the Duo flat, let the pages spread across the whole width (text then crosses the crease, and going half open re-lays out). (Adam, after step 12.)
- Graphical glitches in Settings: unfolded, the left column grows or bounces in from the edge as it opens (Adam, 2026-11-03, on his Duo). Not looked into yet.

## What you'll see that isn't right yet

These screens are still the old ones or stand-ins; the step that replaces them is on the right.

| You see | Fixed in |
|---|---|
| Anything in the reader | 9–12 |

Something wrong in a step that's ticked is a bug in that step, fixed before moving on.
