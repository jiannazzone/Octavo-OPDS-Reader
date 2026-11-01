# UI ideas — parking lot

Raw ideas for the UI brainstorming session after the spike. Nothing here is approved; all UI needs the owner's sign-off.

## Cover display as the library, inner display as the book (2026-10-31)

- Folded: browse the library on the cover (outer) display.
- Select a book → the cover display shows that book's cover.
- Unfold → the app opens straight to the current page on the inner display.
- Reading on the cover display must also work, but it's expected to be rare.

Technical notes:
- Feasible today. This is the app's own UI on the outer display *while folded*. It is not the parked "cover on the outer screen while open" idea, which the SDK blocks (see CLAUDE.md, iPhone Duo).
- Depends on the app keeping state across the outer → inner display move and reacting to the unfold with navigation. Spike 2b checks this.
- The current page comes from the `ProgressSync` backend, so the unfold should land on the synced position, not just the last local one.

## Several servers (parked 2026-10-31)

v1 is built around one library server (`docs/design/direction.md`). Explored in the design brainstorm and parked for later:

- **A server menu in the Library title** to switch between servers. Each server stays its own library; nothing is merged.
- **A merged library across servers** was explored and dropped as too complicated: OPDS can't be queried, so it needs a local catalog index (crawling every feed, hours for public catalogs like Project Gutenberg, no change detection), metadata reconciliation, deduplication, and per-server "Show in Library" switches.
- If both servers hold the same book, show both covers labelled with their server rather than merging: positions (CFIs) belong to a file, and OPDS gives no way to tell editions or translations apart.
- Public catalogs (Project Gutenberg, Standard Ebooks) as browse-only feeds, separate from your library server.

## Shifting panes one at a time (parked 2026-11-01)

Unfolded, opening a screen from the right pane shifts both panes one level along (decision 23). The shell (#6) uses the system's push slide for that: the whole pair slides in. A closer match to "shift" would slide only one pane: the right pane moves over to the left and the new screen slides in on the right, and Back does the reverse. Adam judges the system slide on screen first; this needs a custom transition if it's wanted.
