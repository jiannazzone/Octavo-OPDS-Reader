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
