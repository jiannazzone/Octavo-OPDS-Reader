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

## A nicer empty list (raised 2026-11-01)

Adam, while settling #8's start chip: "we definitely need a nicer empty state than just a blank screen". Today an empty list (a chip, a collection, an OPDS feed with nothing in it) shows only "Nothing here yet" under the chips, with no action, and unfolded the right pane stays blank. Decision 22 asks for an invitation with one action. Needs a design: what the message says per kind of list (Keep Reading, On Deck, an empty shelf), its action (Open Home? Browse another chip?), and what the right pane shows unfolded.

## Reader progress: what's left after #17 (parked 2026-11-01)

#17 built each page's footer (chapter, page, percentage) and the glass bar as a scrubber (decision 7, amended). Not designed yet:

- **Back to where you were.** After a scrub, Apple Books offers "Back to page N" for a while. Today a scrub just moves.
- **The scrubber's look.** It's the system slider (round knob); frame 08 draws a thin line with no knob.
- **Real page numbers.** The numbers are foliate's 1,500-character locations, so a page turn doesn't always change them. Counting real pages for the current layout means paginating the whole book after every fold and text change; the Contents panel (#18, "page numbers for the current layout") meets the same question.
- **Footer on or off**, as a Customize setting, if anyone wants the page bare.

## The book-mode readout (Adam, 2026-11-03)

Half open, the bar's right-hand piece shows the chapter's progress: pages left in the chapter over a line through it, and the book's page numbers (`ReaderBarReadout.chapter`). Adam wants it customizable later:

- **Time left** in the chapter and the book. Octavo doesn't measure reading speed yet; it would need to time page turns over a few sessions first.
- **Choosing the readout**: chapter pages, time left, or the book's page numbers (`ReaderBarReadout.pages`), probably in Text and theme or a long press on the piece itself.

## Page-turn animations, with opening and closing a book (Adam, 2026-11-02)

Decided on 2026-11-03: decisions 27 and 28 in `docs/design/direction.md` (folded slides, open flips over the spine, a Page Turn menu in Customize, and a cover that swings open). Still parked:

- **Curl as a Page Turn choice**: the corner peels over, as in Apple Books. Adam was tempted by it for open and left it out for now. It would draw from the same snapshots as the flip (or UIKit's page curl).
- **Opening and closing** (decision 28) may change once Adam has seen it on his Duo. One idea: where Back doesn't land on the book's screen, the cover could shrink into its spot on Home or in a list instead of the reader fading.
- **Leafing through to your place** (Adam, 2026-11-04): opening a book that isn't on page 1, some pages flip over, as if you're leafing through to where you left off. Not looked into yet. To decide: what the flipping pages show, how many there are and how long they take, what happens folded (where a turn slides), and whether it plays on every opening, including unfolding on a cover, which opens at once today.

## An accent colour (Adam, 2026-11-03)

Octavo has no accent colour of its own: no `AccentColor` asset and no tint set app-wide, so buttons, links, the scrubber and progress lines use iOS's default blue (rendered (0, 128, 245) on Paper and (41, 186, 255) on Night's glass). Decided and built 2026-11-03: Ink (decision 31 in `docs/design/direction.md`).

## Covers that aren't 2:3: fill or fit? (Adam, 2026-11-03)

Every cover fills its frame today and is cropped to it (`CoverImage`, `BookCoverArt`, and the cover that swings open in decision 28): 2:3 cells on the shelves and grids, the whole screen folded, the right half unfolded. A cover of another shape, such as a square one or a scanned comic, loses its edges, which can cut off a title or an author's name. Even a 2:3 cover loses about 20 pt top and bottom on the folded screen (466×678 pt).

- **Fill** (today): no empty space, but the crop.
- **Fit**: the whole cover always shows, and the space around it takes the cover's colours, as Apple Music does behind album art: a colour picked from the cover, or a blurred, enlarged copy of it. Core Image finds the colour (`CIAreaAverage`, or the colours along the cover's edges), so no new dependency.
- **In between**: fill when a cover is close to its frame's shape and fit when it isn't; or let grid cells take each cover's own shape, as Apple Books does, with the covers lined up along the bottom.

Decide per place: the small covers on shelves and grids, the large cover page, Home's book, and the cover in the opening motion.

## The reader's left strip (Adam, 2026-11-03)

Blank for now (decision 8), with the door left open. All of these apply only unfolded, and a tap in the strip would still turn back a page, except on the Go back button. Seen as pictures, none chosen:

- **Page edges:** thin lines at the screen's edge that thicken as you read. How far through the book at a glance, with nothing to tap or read.
- **Progress rail:** your place and chapter ticks down the strip. The most exact, but it repeats the glass bar and footer and is always on screen.
- **Go back in the strip:** the "go back" from `docs/PLAN.md`, showing only after a jump or a scrub, with the page it returns to. Empty the rest of the time, and it needs another home when folded. It could go with page edges.
- **Chapter down the side:** the chapter title running sideways, like a book's running head. Sideways text is slow to read.

Turned down:

- **Spreading the pages across the whole width:** the right page's text sits on the crease, and going half open re-lays out.
- **A wider left page, with the divide on the fold** (393 | 309 pt at Medium): Adam's idea, which keeps the fold steady and works in book mode too. foliate's pages are CSS columns, always equal, so it takes a workaround: every column as wide as the left page, with invisible floats blocking the outer 84 pt of each right page. In a throwaway test on macOS WebKit with foliate's column styles (not foliate itself, and not iOS), text came out at exactly those widths with 10-14% fewer spreads across the five sample books, Pride and Prejudice with its floats off. Left on, a book's own floats break it (Pride and Prejudice went from 63 spreads to 111, with blank pages). The book's `clear` rules also have to go, pictures and tables are capped at 309 pt, and boxes with backgrounds run under the column. Adam decided against the workaround.
