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
- [x] Back from the reader is a normal Back: it lands on the screen the book was opened from (Adam, 2026-11-03). No code change, it's what the app did already. Only folding closes onto the book's own screen (`ShellModel.closeToItsScreen`).
- [x] Home, the Library and Settings keep the system's light and dark; the reader's themes stay in the reader, as in Apple Books (Adam, 2026-11-03). Opening a themed book still changes colour.
- [x] The empty strip at the reader's left edge, unfolded (the mirror of the side column, about 84 pt, so the pages split on the hinge). Stays blank for now, with the door left open (Adam, 2026-11-03; decision 8). The ideas are parked in `docs/UI-IDEAS.md`.
- [x] Covers that aren't 2:3: every cover fits its frame on a blurred copy of itself, on a book's screen, Home and the shelves and grids, and the opening motion follows (Adam, 2026-11-04; decision 32 in `docs/design/direction.md`). Built the same day, and Adam tried it on the Duo; a real square book or comic is still to check.
- [x] Graphical glitches in Settings: unfolded, the left column grows or bounces in from the edge as it opens (Adam, 2026-11-03, on his Duo). Fixed 2026-11-04: over the last 20 pt of the slide the list's rows stopped at the page's margin and shrank while the rest of the screen carried on, and now they land with it (`docs/notes/settings.md`, The slide in). Measured on the simulator, and Adam tried it on his Duo the same day.
- [x] A way back after a jump or a scrub (Adam, 2026-11-03, on his Duo). The controls' ‹ already closes the book, so it's its own button. Decided 2026-11-04 (decision 33 in `docs/design/direction.md`) and built the same day: "Back to page 312" with ✕ at the bottom of the left page, your place holding until you settle, and a trip that survives closing, shown by the progress line's fill (`docs/notes/going-back.md`). To be tried on Adam's Duo.
- [x] Footnotes without leaving the page (Adam, 2026-11-04). Decided (decision 34) and built 2026-11-05: a card on the facing page, or along the bottom folded, with Go to Note and ✕ (`docs/notes/footnotes.md`).
- [x] Skipping by chapter (Adam, 2026-11-04). Decided (decision 35) and built the same day: ⏮ and ⏭ beside the chapter's name, and a scrubber with dots at chapters and a tick you feel as it passes one. Hold still and it zooms in to one page at a time, with a catch at chapter starts (Adam, after a test build on his Duo). To be tried on Adam's Duo.
- [x] Back always there in the reader (Adam, 2026-11-04). Decided (decision 7) and built the same day: ‹ on its own above ···, grey with it while you read.
- [x] Folded, it needs to be easier to dismiss the Customize pane (Adam, 2026-11-03, on his Duo). A tap on the screen is a small target there, and his opened the table of contents instead of closing the pane. Built 2026-11-04: a ✕ at the top right of all three panels, folded and unfolded (decision 13 in `docs/design/direction.md`).
- [x] More than one server (Adam, 2026-11-05), before the first release: "Someone might have bookorbit and OPDS, for example." Decided and built the same day (decision 36 in `docs/design/direction.md`, `docs/notes/more-than-one-server.md`): a menu in the Library's title, Home and Search across every server, a name you set. Adam tried it on his Duo the same day.
- [x] Empty lists: an invitation, not a blank screen (Adam, 2026-11-01; #30). Decided and built 2026-11-05 (decision 22 in `docs/design/direction.md`, `docs/notes/empty-lists.md`): "No books in this list" with Open Library, and unfolded the server's newest books on the right page.
- iCloud sync and KOReader sync (Adam, 2026-11-05): separate tasks, for later. They'd carry the places of OPDS and imported books, which stay on the iPhone in decision 36.

## What you'll see that isn't right yet

These screens are still the old ones or stand-ins; the step that replaces them is on the right.

| You see | Fixed in |
|---|---|
| Anything in the reader | 9–12 |

Something wrong in a step that's ticked is a bug in that step, fixed before moving on.
