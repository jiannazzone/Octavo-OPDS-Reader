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

**Adam, 2026-11-05: wanted before the first release, and decided (decision 36 in `docs/design/direction.md`).** These earlier notes are where the design started; a merged library and public catalogs as browse-only feeds stay parked.

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

Decided and built 2026-11-05 (#30; decision 22 in `docs/design/direction.md`), so this one's closed. Not chosen: one line naming the list ("Nothing in Keep Reading"), See All Books opening the whole-library list, and the book you're reading or a blank page on the right. Home's and On iPhone's empty screens have the same layout now.

## Reader progress: what's left after #17 (parked 2026-11-01)

#17 built each page's footer (chapter, page, percentage) and the glass bar as a scrubber (decision 7, amended). Not designed yet:

- **Back to where you were.** Decided 2026-11-04: decision 33 in `docs/design/direction.md`. Still parked: **going forward again** after Back, and **a mark for your place on the scrubber** outside a trip (the system slider's tick locks the knob onto it, `docs/notes/going-back.md`).
- **The scrubber's look.** It's the system slider (round knob); frame 08 draws a thin line with no knob.
- **Real page numbers.** The numbers are foliate's 1,500-character locations, so a page turn doesn't always change them. Counting real pages for the current layout means paginating the whole book after every fold and text change; the Contents panel (#18, "page numbers for the current layout") meets the same question.
- **Footer on or off**, as a Customize setting, if anyone wants the page bare.

## Scrubber and notes: ideas not chosen (2026-11-04)

From decisions 34 and 35. Seen as pictures, none chosen:

- **Skipping by a swipe up or down on the page**: no controls to bring up, but nothing shows it's there and it's easy to do by accident. It could be added to the chapter buttons later.
- **Other ways to zoom the scrubber**, if holding still ever needs replacing: slowing down (the slower your finger, the finer), dragging up off the bar, or a second line for the chapter (half open, the chapter line that's already there made draggable).
- **A switch for pop-up notes in Customize**, if anyone would rather always jump. Go to Note covers it for now.

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

Every cover filled its frame and was cropped to it (`CoverImage`, `BookCoverArt`, and the cover that swings open in decision 28): 2:3 cells on the shelves and grids, the whole screen folded, the left page unfolded. A cover of another shape, such as a square one, loses its edges, which can cut off a title or an author's name. A true 2:3 cover loses about 10 pt top and bottom on the folded screen (466×678 pt) and 7 pt on the left page (455.5×669 pt).

Decided 2026-11-04: every cover fits its frame on a blurred copy of itself, on a book's screen, Home and the shelves and grids, and the opening motion follows (decision 32 in `docs/design/direction.md`). Built the same day.

## The reader's left strip (Adam, 2026-11-03)

Blank for now (decision 8), with the door left open. All of these apply only unfolded, and a tap in the strip would still turn back a page, except on the Go back button. Seen as pictures, none chosen:

- **Page edges:** thin lines at the screen's edge that thicken as you read. How far through the book at a glance, with nothing to tap or read.
- **Progress rail:** your place and chapter ticks down the strip. The most exact, but it repeats the glass bar and footer and is always on screen.
- **Go back in the strip:** the "go back" from `docs/PLAN.md`, showing only after a jump or a scrub, with the page it returns to. Empty the rest of the time, and it needs another home when folded. Adam chose the bottom of the left page instead (decision 33), so this one's closed.
- **Chapter down the side:** the chapter title running sideways, like a book's running head. Sideways text is slow to read.

Turned down:

- **Spreading the pages across the whole width:** the right page's text sits on the crease, and going half open re-lays out.
- **A wider left page, with the divide on the fold** (393 | 309 pt at Medium): Adam's idea, which keeps the fold steady and works in book mode too. foliate's pages are CSS columns, always equal, so it takes a workaround: every column as wide as the left page, with invisible floats blocking the outer 84 pt of each right page. In a throwaway test on macOS WebKit with foliate's column styles (not foliate itself, and not iOS), text came out at exactly those widths with 10-14% fewer spreads across the five sample books, Pride and Prejudice with its floats off. Left on, a book's own floats break it (Pride and Prejudice went from 63 spreads to 111, with blank pages). The book's `clear` rules also have to go, pictures and tables are capped at 309 pt, and boxes with backgrounds run under the column. Adam decided against the workaround.

## Fixed-layout books (parked 2026-11-04)

Pre-paginated books open now (`docs/notes/fixed-layout.md`). What they show that hasn't been decided:

- **A book with `rendition:spread="none"`, unfolded:** foliate shows one page in the middle of the screen, straight across the fold. Pairing the pages either side of the fold would keep them off it, and suits portrait pages, but it halves a landscape page that fills the screen across the fold today. BookOrbit's web reader offers the choice as a setting (Page spreads).
- **The Text panel:** font, size, spacing, margins and justify do nothing on these pages, and themes colour only the space around them. BookOrbit's web reader hides the text controls for these books.
- **Search:** going to a match works, but foliate's fixed-layout renderer has nothing to draw its highlight on.
- **Folded and turned sideways:** two pages, by foliate's rule, not the one page text gets. Each is about the size one page would be there (297 pt wide, against 309).

## Closing the Duo while reading (Adam, 2026-11-04)

Folding while reading closes the book back to its screen, the cover (`ShellModel.closeToItsScreen`; `docs/design/direction.md` already says it may become a setting). Adam: keep that as the default, and make it optional. Off, the book would stay open on the folded screen at your place. Not looked into yet. To decide: the setting's name and where it lives, and what the tour does, since it teaches closing the iPhone.

## KOReader sync for OPDS servers (Adam, 2026-11-04)

OPDS servers sometimes run a KOReader sync server alongside them for reading progress. Adam: look into it. It's already on the "Later" list (`docs/design/direction.md`, v1 scope) and has a slot in the design (`KOSync`, percentage only, in `CLAUDE.md`; the server setup's sync step comes back once it exists). Not looked into yet. To find out: how the protocol works, how it matches a book to a file, and how close a percentage lands compared with a CFI.

## Back always there in the reader (Adam, 2026-11-04)

While reading, the side column showed only ···, and ‹ came up with Contents, Aa, Search and Bookmark, in one group. Adam asked for ‹ to stay up on its own, apart from ··· and the rest. Decided and built 2026-11-04: decision 7 in `docs/design/direction.md`, which covers half open, the tour's Skip, "Back to page 312" and stray taps.

## An import that timed out (2026-11-05)

A read that gets no answer in 30 s says "“Book” couldn’t be opened; the file may be damaged." It may be WebKit stalling and not the book, and trying again may work (`docs/notes/ci.md`). `BookInspectionError.timedOut` now tells the two apart, so a different line would be a small change in `BookImporter.reason`. So far it has only been seen on CI's simulators, so it may not be worth a string.

## Font names in their own fonts (Adam, 2026-11-06)

The Font menu in Text and Theme should show each name in its own font. Tried on the simulator on 2026-11-06: it's a native menu (`Picker`, `.menu`), which ignores `.font` on its rows, so every name stays in the system font. It needs a list of our own. Not designed yet.

## Keeping the screen on while reading (Adam, 2026-11-06)

The screen dimmed while reading, because nothing in the app held off Auto-Lock.

Decided 2026-11-06: Keep screen on in Settings, under Reading, for Off or 5, 10 (the default), 15 or 30 minutes after a page turn, with no Always (decision 24). Built the same day (`docs/notes/settings.md`).
