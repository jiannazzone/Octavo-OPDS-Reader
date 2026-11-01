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

## Tab bar over the cover (parked 2026-11-01)

On the cover page (#14) the side column has no backing of its own: the system's glass capsules (clock, Back, the tabs) read on light, dark and busy covers, so Adam chose system glass only over a material strip or a dark scrim. He asked whether the tab bar could also collapse while it isn't in use, to show more of the cover.

- iOS 26+ has `tabBarMinimizeBehavior(.onScrollDown)`, which minimizes the tab bar while content scrolls. The cover doesn't scroll, so it would never trigger there. Whether it works in the Duo's side column at all is unchecked.
- Hiding the tab bar on the cover (`toolbarVisibility(.hidden, for: .tabBar)`) would change decision 4 ("the tab column stays visible over the cover"), and it's a shell-wide behaviour.

## The Library's filter button (parked 2026-11-01)

Frame 02 puts a filter button in the side column over the Library, but no decision says what it offers, so #13 leaves it out. Candidates: sort the All grid (Title, Author, Recently added; BookOrbit supports all three, while OPDS feeds keep their own order, so the button would hide there), and later filters such as Unread, In progress and Finished (needs BookOrbit's read status in OctavoKit). Design it before building.

## Reader progress: what's left after #17 (parked 2026-11-01)

#17 built each page's footer (chapter, page, percentage) and the glass bar as a scrubber (decision 7, amended). Not designed yet:

- **Back to where you were.** After a scrub, Apple Books offers "Back to page N" for a while. Today a scrub just moves.
- **The scrubber's look.** It's the system slider (round knob); frame 08 draws a thin line with no knob.
- **Real page numbers.** The numbers are foliate's 1,500-character locations, so a page turn doesn't always change them. Counting real pages for the current layout means paginating the whole book after every fold and text change; the Contents panel (#18, "page numbers for the current layout") meets the same question.
- **Footer on or off**, as a Customize setting, if anyone wants the page bare.
