# Octavo design direction

Status: **draft, in progress** (UI brainstorm with Adam, started 2026-10-31). Only decisions Adam approved are recorded as decisions. Ideas not yet approved, or parked, stay in `docs/UI-IDEAS.md`.

## Device frame

Measured in spike 2b (`docs/notes/duo-spreads.md`):

- **Folded (outer display):** 466×678 pt. The system keeps an 84 pt column on the trailing edge clear for the camera; the clock, status icons, toolbar buttons and tab items sit in it. App content is 382 pt wide.
- **Unfolded (inner display):** 951×669 pt, landscape. The hinge is a 40 pt strip at x 455.5–495.5. App content is 867 pt wide (the same trailing system column). The right half, from the hinge to the system column, is 372 pt wide: almost the folded content width (382 pt).
- A 2:3 book cover nearly fills the folded display (466×699 against 466×678).

## Decisions

### Structure and library (approved 2026-10-31)

1. **One library server in v1.** You connect one server (BookOrbit, or one OPDS server) when you set up the app, and the app is built around it. Most people run one server; designing for several (a merged catalog index, deduplication, per-server switches, catalogs vs libraries) was explored and dropped as too complicated for v1. A second server comes later, as a menu in the Library title; servers are never merged (parked in `docs/UI-IDEAS.md`).
2. **Four tabs in the trailing column:** Home, Library, Search, and Settings at the bottom of the column. The trailing column is the Duo's standard place for tab items, so nothing sits along the bottom of the screen.
   - **Home:** "Continue reading" (positions from sync and from the phone), plus what's new on your server.
   - **Library:** your server's books as a grid of covers, with chips across the top. For BookOrbit the chips come from its API (All, Collections, Series, Authors); for an OPDS server they are the feed's own top-level entries (for example Recent, Authors, Series, Shelves on Calibre-Web). An "On iPhone" chip shows downloaded and imported books.
   - **Search:** your server's search (BookOrbit search, or OPDS OpenSearch when the feed offers it) plus the books on the phone.
   - **Settings:** a tab; its contents are not decided yet (see Open questions).
3. **Books download on first open.** Opening a server book for the first time downloads its file to the device, where it stays. Offline reading needs nothing more.

### Picking a book (approved 2026-10-31)

4. **Folded: full-screen cover.** Tapping a book shows its cover filling the outer display.
   - Over the cover: a bottom strip with the chapter and percentage, a progress bar, when it last synced, and an **Open** button.
   - Swipe up for details: description, series, collections, download, status, rating, file info.
   - **Unfolding on the cover opens the book at your place immediately**, with no prompt (answers part of duo-spreads §7 question 5).
5. **Unfolded: grid | cover page.** The grid sits left of the hinge; the selected book's cover page (same strip and Open button as folded) fills the right half. Nothing sits on the hinge.

### Connecting (approved 2026-10-31)

6. **Adding the server: pick the type first.** "BookOrbit" or "OPDS catalog" (Calibre-Web, COPS, Kavita, Komga…), then that type's form (address, sign-in), then where reading progress syncs (this BookOrbit server, iCloud, KOReader sync, or don't sync). "Import from Files" sits on the same first screen.

## Open questions

- **Settings contents.** Too early to pin down. Working list from the brainstorm (not approved): Server (edit, sign out, replace, progress sync), Sync accounts (iCloud, KOReader sync), Reading defaults, iPhone Duo, Downloads and storage, About.
- **Default sync choice for an OPDS server.** Proposed (not approved): preselect iCloud once iCloud sync exists, "Don't sync" until then. A BookOrbit server preselects itself.
- **Plain `http://` servers on a LAN IP or a remote host.** `NSAllowsLocalNetworking` covers `localhost` and `.local` names only (`docs/notes/bookorbit-api.md`). Many self-hosted servers are plain http on a LAN IP.
- **OPDS feeds with no search.** Search then covers only the books on the phone; how the Search tab says so is undecided.

## Needs engineering

- **Tabs in the trailing column.** Check how SwiftUI's `TabView` renders on the Duo folded and unfolded, and whether the trailing-column placement comes from the system or needs a custom tab column.
- **Library chips from an OPDS feed.** Map the root feed's navigation entries and facets to chips, and decide what happens when a feed has many entries or none.
- **Pull the synced position while the cover shows.** Start the `ProgressSync` pull when the cover page appears, so unfolding opens the reader at once instead of waiting up to the 5 s pull timeout (duo-spreads §6).
- **Full-screen cover.** The cover runs under the trailing system column and the camera; the tab column and back button sit over the artwork, so they need a material that reads on any cover.
- **Unfold on the cover → reader.** The spike's handoff already does this from its book screen (about 20 ms). It must compare old and new hinge status, not react to repeated or on-appear callbacks.
