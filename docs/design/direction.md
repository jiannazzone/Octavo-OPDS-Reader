# Octavo design direction

Status: **draft, in progress** (UI brainstorm with Adam, started 2026-10-31). Only decisions Adam approved are recorded as decisions. Ideas not yet approved stay in `docs/UI-IDEAS.md`.

## Device frame

Measured in spike 2b (`docs/notes/duo-spreads.md`):

- **Folded (outer display):** 466×678 pt. The system keeps an 84 pt column on the trailing edge clear for the camera; the clock, status icons and toolbar buttons sit in it. App content is 382 pt wide.
- **Unfolded (inner display):** 951×669 pt, landscape. The hinge is a 40 pt strip at x 455.5–495.5. App content is 867 pt wide (the same trailing system column). The right half, from the hinge to the system column, is 372 pt wide: almost the folded content width (382 pt).
- A 2:3 book cover nearly fills the folded display (466×699 against 466×678).

## Decisions

### Library (approved 2026-10-31)

1. **Library model: Home + Browse + Search**, as tabs in the trailing system column (the Duo's standard place for tab items), with Settings as a fourth tab at the bottom of the column (decision 5). Nothing sits along the bottom of the screen.
   - **Home:** "Continue reading" across every source (positions from sync), plus what's new on each server.
   - **Browse:** each server in its own structure (BookOrbit libraries, collections, smart scopes, series, authors; an OPDS feed's own navigation tree).
   - **Search:** across every source that supports it (BookOrbit search, OPDS OpenSearch).
   - Rejected: "the server is the library" (switching between servers, weak offline, OPDS servers all look different) and "device shelf" (a second library to curate for BookOrbit users).
2. **Picking a book (folded): full-screen cover.** Tapping a book in the library shows its cover filling the outer display.
   - Over the cover: a bottom strip with the chapter and percentage, a progress bar, when it last synced, and an **Open** button.
   - Swipe up for details: description, series, collections, download, status, rating, file info.
   - **Unfolding on the cover opens the book at your place immediately**, with no prompt (answers part of duo-spreads §7 question 5).
3. **Library unfolded: grid | cover page.** The grid sits left of the hinge; the selected book's cover page (same strip and Open button as folded) fills the right half. Nothing sits on the hinge.
4. **Adding a server: pick the type first.** "BookOrbit" or "OPDS catalog" (Calibre-Web, COPS, Kavita, Komga…), then that type's form (address, sign-in), then where progress for that server's books syncs (this BookOrbit server, iCloud, KOReader sync, or don't sync). "Import from Files" sits on the same first screen.
5. **Settings is a tab**, the fourth in the trailing column, below Home, Browse and Search. Its contents are not decided yet (see Open questions).

## Open questions

- **Settings contents.** Too early to pin down. Working list from the brainstorm (not approved): Servers (edit, sign out, remove, per-server sync, add), Sync accounts (iCloud, KOReader sync), Reading defaults, iPhone Duo, Downloads and storage, About.
- **Default sync choice for an OPDS server.** Proposed (not approved): preselect iCloud once iCloud sync exists, "Don't sync" until then. A BookOrbit server preselects itself.
- **Plain `http://` servers on a LAN IP or a remote host.** `NSAllowsLocalNetworking` covers `localhost` and `.local` names only (`docs/notes/bookorbit-api.md`). Many self-hosted servers are plain http on a LAN IP.

## Needs engineering

- **Tabs in the trailing column.** Check how SwiftUI's `TabView` renders on the Duo folded and unfolded, and whether the trailing-column placement comes from the system or needs a custom tab column.
- **Pull the synced position while the cover shows.** Start the `ProgressSync` pull when the cover page appears, so unfolding opens the reader at once instead of waiting up to the 5 s pull timeout (duo-spreads §6).
- **Full-screen cover.** The cover runs under the trailing system column and the camera; the tab column and back button sit over the artwork, so they need a material that reads on any cover.
- **Unfold on the cover → reader.** The spike's handoff already does this from its book screen (about 20 ms). It must compare old and new hinge status, not react to repeated or on-appear callbacks.
