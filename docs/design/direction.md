# Octavo design direction

Status: **direction set** (UI brainstorm with Adam, 2026-10-31). Only decisions Adam approved are recorded as decisions; screens marked "Not designed" below are still to do. Ideas not yet approved, or parked, stay in `docs/UI-IDEAS.md`.

## Device frame

Measured in spike 2b (`docs/notes/duo-spreads.md`):

- **Folded (outer display):** 466×678 pt. The system keeps an 84 pt column on the trailing edge clear for the camera; the clock, status icons, toolbar buttons and tab items sit in it. App content is 382 pt wide.
- **Unfolded (inner display):** 951×669 pt, landscape. The hinge is a 40 pt strip at x 455.5–495.5. App content is 867 pt wide (the same trailing system column). The right half, from the hinge to the system column, is 372 pt wide: almost the folded content width (382 pt).
- A 2:3 book cover nearly fills the folded display (466×699 against 466×678).

## Decisions

### Structure and library (approved 2026-10-31)

1. **One library server in v1.** You connect one server (BookOrbit, or one OPDS server) when you set up the app, and the app is built around it. Most people run one server; designing for several (a merged catalog index, deduplication, per-server switches, catalogs vs libraries) was explored and dropped as too complicated for v1. A second server comes later, as a menu in the Library title; servers are never merged (parked in `docs/UI-IDEAS.md`).
2. **Four tabs in the trailing column:** Home, Library and Settings in one group, with Search in its own button at the very bottom (Apple's "Search Role" tab bar, the standard layout). The trailing column is the Duo's standard place for tab items, so nothing sits along the bottom of the screen.
   - **Home:** "Continue reading" (positions from sync and from the phone), plus what's new on your server.
   - **Library:** your server's books as a grid of covers, with chips across the top. For BookOrbit the chips come from its API (All, Collections, Series, Authors); for an OPDS server they are the feed's own top-level entries (for example Recent, Authors, Series, Shelves on Calibre-Web). An "On iPhone" chip shows downloaded and imported books.
   - **Search:** your server's search (BookOrbit search, or OPDS OpenSearch when the feed offers it) plus the books on the phone.
   - **Settings:** a tab; its contents are not decided yet (see Open questions).
3. **Books download on first open.** Opening a server book for the first time downloads its file to the device, where it stays. Offline reading needs nothing more.

### Picking a book (approved 2026-10-31)

4. **Folded: full-screen cover.** Tapping a book shows its cover filling the outer display.
   - Over the cover: a bottom strip with the chapter and percentage, a progress bar, when it last synced, and an **Open** button.
   - Swipe up for details: description, series, collections, download, Mark as finished, file info (ratings come later).
   - **Unfolding on the cover opens the book at your place immediately**, with no prompt (answers part of duo-spreads §7 question 5).
   - The cover runs under the camera column, which covers its top-right corner; accepted. The tab column stays visible over the cover.
5. **Unfolded: grid | cover page.** The grid sits left of the hinge; the selected book's cover page (same strip and Open button as folded) fills the right half. Nothing sits on the hinge.

### Connecting (approved 2026-10-31)

6. **Adding the server: pick the type first.** "BookOrbit" or "OPDS catalog" (Calibre-Web, COPS, Kavita, Komga…), then that type's form (address, sign-in), then where reading progress syncs (this BookOrbit server, iCloud, KOReader sync, or don't sync; v1 offers only BookOrbit, see v1 scope). "Import from Files" sits on the same first screen.

### Reader and the Duo (approved 2026-10-31)

Answers all six questions in `docs/notes/duo-spreads.md` §7 (question 5's first half is decision 4).

7. **Controls are hidden while you read.** A tap in the middle shows them: Back, Contents, Text and theme, Search in book and Bookmark in the side column, plus a glass progress bar with the chapter and page. Taps on the left and right sides turn pages. A setting, **Always show controls**, keeps them visible; it is off by default.
8. **The page never goes under the side column** (§7 Q3, Q4). Folded, the page stays in the 382 pt content area. Unfolded, the spread stays centred on the hinge and the left edge gives up the same 84 pt, so the margins match. The margin setting runs from wide down to text reaching the column's edge; the gutter on the hinge never drops below the hinge's 40 pt. No foliate patch is needed: the margin setting scales foliate's gap and outer margins together.
9. **Half-open is book mode** (§7 Q1): controls stay hidden, a shadow at the spine, a tap on the left page goes back and on the right page goes forward.
10. **Unfolding anywhere but a cover keeps the same screen** (§7 Q5): it takes its unfolded layout. Only a book's cover turns an unfold into "open".
11. **Folds cross-fade** (§7 Q6): a snapshot of the old page fades into the settled layout (about 0.3 s), hiding the intermediate re-layouts.
12. **Unfolded and turned sideways, one column runs straight across the fold** (§7 Q2), as the spike does today. Half-opened that way (laptop-style), the text bends over the fold; accepted.

## v1 scope (approved 2026-10-31)

The goal for v1: read your server's books well on the Duo.

| | v1 | Later |
|---|---|---|
| Sources | BookOrbit, one OPDS server, Import from Files | A second server |
| Progress sync | BookOrbit | iCloud, KOReader sync |
| Formats | EPUB; MOBI, AZW3 and FB2 if they pass a check through foliate, the bridge and the script blocking | PDF (PDFKit), comics (CBZ, CBR) |
| Reader | Text and theme, Contents, Search in book, Bookmarks | Highlights and notes |
| Duo | Cover → unfold → read, book mode, fold cross-fade | Lock Screen widget, Live Activity |
| BookOrbit extras | Mark as finished | Ratings, editing collections, reading sessions |

## v1 screens

| Screen | State |
|---|---|
| Add your books (pick BookOrbit or OPDS, or import) | Designed (frame 05) |
| Sign in to BookOrbit | Designed (frame 06) |
| Add an OPDS server (address, optional sign-in) | Not designed |
| Where reading progress syncs | Sketched in the brainstorm |
| Home, folded and unfolded | Folded designed (frame 01) |
| Library, folded and unfolded, with chips | Designed (frames 02, 04) |
| Collections, Series, Authors lists (chip drill-ins) | Not designed |
| Book cover page, folded and unfolded | Designed (frames 03, 04) |
| Book details (swipe up from the cover; Mark as finished, download) | Not designed |
| Search tab and results | Not designed |
| Reader: one page folded, spread unfolded, book mode, controls shown | Sketched in the brainstorm |
| Contents and bookmarks | Not designed |
| Text and theme panel (font, size, spacing, margins, theme, Always show controls) | Not designed |
| Search in book | Not designed |
| Settings tab | Contents open |
| Empty and error states (no server yet, server unreachable, sign-in failed, download failed) | Not designed |

Import from Files uses the system document picker; no screen of our own.

## Mockups

Figma: [Octavo-UX, Page 1](https://www.figma.com/design/ElJJ7OtF8LOuX6dc68qZ23/Octavo-UX?node-id=0-1), built 2026-10-31 on Apple's iOS and iPadOS 27 kit (`iPhone Duo/Standard/Outer - Portrait` and `Inner - Landscape`, `Tab Bar - iPhone Duo`, Liquid Glass buttons, rows, text fields, kit text styles and colour variables). Covers are the public-domain sample books.

| Frame | Shows |
|---|---|
| 01 Home · folded | Continue reading, new on BookOrbit |
| 02 Library · folded | Chips, cover grid, filter button in the side column |
| 03 Book cover · folded | Full-screen cover, glass progress strip with Open |
| 04 Library · unfolded | Grid left of the hinge, cover page right of it (hinge marked) |
| 05 Add your books · folded | Pick BookOrbit or OPDS, or import from Files |
| 06 Sign in to BookOrbit · folded | Address, account, Sign in, SSO (only if offered) |

Local components in the file: `Book Cover / …` (one per sample book), `Row / Continue reading` (progress set by the Progress frame's right padding), `Chip` (selected / unselected).

What the kit showed:
- Apple's Duo layout puts toolbar buttons (including back) in a glass group under the vertical status bar, and the tab bar at the bottom of the same column.
- The kit's `Tab Bar - iPhone Duo` has a "Search Role" type that puts Search in its own glass button at the very bottom of the column; adopted (decision 2) and used in the frames.
- The kit's Large Title toolbar renders its title mirrored in Figma, so the frames draw the large title as content instead.

## Open questions

- **Settings contents.** Too early to pin down. Working list from the brainstorm (not approved): Server (edit, sign out, replace, progress sync), Sync accounts (iCloud, KOReader sync), Reading defaults, iPhone Duo, Downloads and storage, About.
- **The sync step for an OPDS server in v1.** With only BookOrbit sync in v1, an OPDS server has nothing to choose. Proposed (not approved): skip the step for OPDS servers until iCloud or KOReader sync exists, then preselect iCloud. A BookOrbit server preselects itself.
- **Plain `http://` servers on a LAN IP or a remote host.** `NSAllowsLocalNetworking` covers `localhost` and `.local` names only (`docs/notes/bookorbit-api.md`). Many self-hosted servers are plain http on a LAN IP.
- **OPDS feeds with no search.** Search then covers only the books on the phone; how the Search tab says so is undecided.
- **Reaching the controls in book mode.** Taps on the pages turn them, so controls need another way in. Proposed (not approved): tap the side column, which sits outside both pages.
- **Book mode's angle range.** Roughly 60–150°; tune on a real device.

## Needs engineering

Spikes before building: MOBI/AZW3/FB2 through foliate, the bridge and the CSP (decides the amber formats); SwiftUI `TabView` on the Duo; the fold cross-fade with batched re-layouts; book-mode posture detection. **No new foliate patch** is needed for these decisions (decision 8 works with foliate's own gap and the bridge's insets); patches 0001 and 0002 stay. The duo-spreads §8 risk still applies: after an unfold the synced position is the spread's start.

- **Tabs in the trailing column.** Apple's iOS 27 kit has a Duo tab bar at the bottom of the trailing column, so the placement is the system's design. Still check that SwiftUI's `TabView` renders it that way on the Duo, folded and unfolded.
- **Library chips from an OPDS feed.** Map the root feed's navigation entries and facets to chips, and decide what happens when a feed has many entries or none.
- **Pull the synced position while the cover shows.** Start the `ProgressSync` pull when the cover page appears, so unfolding opens the reader at once instead of waiting up to the 5 s pull timeout (duo-spreads §6).
- **Full-screen cover.** The cover runs under the trailing system column and the camera; the tab column and back button sit over the artwork, so they need a material that reads on any cover.
- **Page area (decision 8).** Lay out the `foliate-view` with the bridge's left/right insets so the page never reaches the column, map the margin setting onto foliate's gap, and keep the hinge gutter at least the reserved region's width.
- **Fold cross-fade (decision 11).** Show a `WebView` snapshot over the transition and fade it out once the layout settles; also batch the hinge, resize, layout and fold-region inputs into one re-layout (duo-spreads §5 counts 10–13 today).
- **Book mode (decision 9).** Detect the half-open range from `onHingeChange`, swap the tap zones, and draw the spine shadow as an overlay outside the book's content.
- **Unfold on the cover → reader.** The spike's handoff already does this from its book screen (about 20 ms). It must compare old and new hinge status, not react to repeated or on-appear callbacks.
