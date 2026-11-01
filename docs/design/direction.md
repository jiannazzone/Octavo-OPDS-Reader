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
   - Over the cover: a bottom strip (a glass sheet at its compact height, with a grabber) showing the chapter and percentage, when it last synced, an **Open** button and a progress bar.
   - Swipe up on it for details: the same sheet expands (decision 20).
   - **Unfolding on the cover opens the book at your place immediately**, with no prompt (answers part of duo-spreads §7 question 5).
   - The cover runs under the camera column, which covers its top-right corner; accepted. The tab column stays visible over the cover.
5. **Unfolded: grid | cover page.** The grid sits left of the hinge; the selected book's cover page (same strip and Open button as folded) fills the right half. Nothing sits on the hinge.

### Book details (approved 2026-10-31)

20. **The cover's strip expands into the details.** The progress strip and the details are one Liquid Glass sheet with two heights. Swiping up keeps the strip's top (chapter and percentage, progress bar, last sync, **Open**) and adds the details below; the cover stays behind it. Drag it down or tap the cover to return to the strip; unfolding still opens the book. Unfolded, the same sheet expands inside the right-hand cover pane. Below the strip:
    - Title; author (tap: their books).
    - Actions: **Mark as finished**, **Download / Remove download**.
    - Description (three lines, then More).
    - Series, Collections, File (format, size), From (server), Added.
    - Mark as finished goes to BookOrbit for BookOrbit books and stays on the iPhone for OPDS and imported books (OPDS can't store it). Ratings and editing collections come later.

### Search tab (approved 2026-10-31)

21. **Search** (the tab at the bottom of the column):
    - **Before typing:** the search field ("Title, author, series"), your recent searches (with Clear), and Browse chips that jump into the Library's Authors, Series and Collections lists.
    - **Results** update as you type: **Books** first, as rows with a small cover, author and your progress or a Downloaded mark, from the server and the iPhone together; then **Series** and **Authors** sections when the server supports them (BookOrbit) and there are matches.
    - **An OPDS server without search** shows a short note ("Calibre-Web doesn't offer search. Showing books on your iPhone."), results from the iPhone, and the feed's own lists as Browse chips.
    - **Unfolded:** results left of the hinge, the selected book's cover page (with its compact sheet) right of it, as in the Library.

### Connecting (approved 2026-10-31)

6. **Adding the server: pick the type first.** "BookOrbit" or "OPDS catalog" (Calibre-Web, COPS, Kavita, Komga…), then that type's form (address, sign-in), then where reading progress syncs (this BookOrbit server, iCloud, KOReader sync, or don't sync; v1 offers only BookOrbit, see v1 scope). "Import from Files" sits on the same first screen.
   - **OPDS catalog:** enter the feed address (examples under the field: Calibre-Web `…/opds`, COPS `…/feed.php`, Komga `…/opds/v1.2/catalog`, Kavita: paste the OPDS link from its settings) and tap Connect. The account fields appear only if the server asks for a password ("Found “Calibre-Web”. It asks for a sign-in."); otherwise you land in the Library.
   - **The sync step is skipped for OPDS servers in v1** (only BookOrbit syncs); progress stays on the iPhone. The step returns once iCloud or KOReader sync exists, with iCloud preselected. A BookOrbit server shows it with itself preselected.
   - **No skip on first launch:** the first screen stays until a server is added or a file imported.
   - **A bundled sample book:** a "Read a sample book" row on the first screen opens **Pride and Prejudice** (Standard Ebooks edition, CC0) straight in the reader, so the Duo reader can be tried before any setup (and App Review can test without a server). Leaving the reader returns to the first screen until something is added; afterwards the book stays under On iPhone and can be removed. Credit Standard Ebooks in `THIRD-PARTY-NOTICES.md`.

### Empty and error states (approved 2026-10-31)

22. **One pattern:**
    - **Connection problems** show a banner at the top of the tab: server unreachable ("Can't reach BookOrbit. Showing books on your iPhone." · Retry; the Library switches to On iPhone) and signed out ("BookOrbit signed you out. Reading still works; sync is paused." · Sign in).
    - **Problems with one book** show on the cover's strip, where Open would be: "Couldn't download · Try again"; offline and not downloaded: "Needs a connection to download." (no queueing).
    - **Empty screens** are an invitation with one action ("Nothing in progress · Open Library"; the same for an empty server).
    - **Sign-in errors** appear under the fields ("That username or password didn't work.").
    - **No pop-up alerts**, except to confirm deleting or removing something.
    - A position that didn't sync shows "Not synced yet, will retry" on the strip's sync line.

### Reader and the Duo (approved 2026-10-31)

Answers all six questions in `docs/notes/duo-spreads.md` §7 (question 5's first half is decision 4).

7. **Controls are hidden while you read.** A tap in the middle shows them: Back, Contents, Text and theme, Search in book and Bookmark in the side column, plus a glass progress bar with the chapter and page. Taps on the left and right sides turn pages. A setting, **Always show controls**, keeps them visible; it is off by default.
8. **The page never goes under the side column** (§7 Q3, Q4). Folded, the page stays in the 382 pt content area. Unfolded, the spread stays centred on the hinge and the left edge gives up the same 84 pt, so the margins match. The margin setting runs from wide down to text reaching the column's edge; the gutter on the hinge never drops below the hinge's 40 pt. No foliate patch is needed: the margin setting scales foliate's gap and outer margins together.
9. **Half-open is book mode** (§7 Q1): controls stay hidden, a shadow at the spine, a tap on the left page goes back and on the right page goes forward. The spine shadow, and any page-warp effect, is optional: a switch turns it off.
10. **Unfolding anywhere but a cover keeps the same screen** (§7 Q5): it takes its unfolded layout. Only a book's cover turns an unfold into "open".
11. **Folds cross-fade** (§7 Q6): a snapshot of the old page fades into the settled layout (about 0.3 s), hiding the intermediate re-layouts.
12. **Unfolded and turned sideways, one column runs straight across the fold** (§7 Q2), as the spike does today. Half-opened that way (laptop-style), the text bends over the fold; accepted.

### Text and theme (approved 2026-10-31)

13. **A compact panel, Customize one step in.** The "Aa" button opens a Liquid Glass sheet (where available) so the page shows through while you adjust. Front: the four themes and A−/A+. Customize: font, line spacing, margins, justify, Match Dark Mode, Always show controls. Unfolded, the panel covers the right page and the left page shows each change live.
14. **Settings apply to every book**, not per book.
15. **Themes: Original, Paper, Sepia, Night.** Night follows the iPhone's Dark Mode; "Match Dark Mode" in Customize turns that off.
16. **Fonts:** the book's own font (default), New York, Georgia, Iowan Old Style, Palatino, Charter, SF Pro (all shipped with iOS), plus **Atkinson Hyperlegible and OpenDyslexic**, bundled. Adam signed off on their SIL Open Font License (2026-10-31); list them in `THIRD-PARTY-NOTICES.md` when they're added.

### Contents and bookmarks (approved 2026-10-31)

17. **One panel, two tabs.** The Contents button opens a glass panel with a Contents | Bookmarks switch. Contents opens scrolled to the current chapter, which is highlighted, with page numbers for the current layout. Bookmarks list the chapter, page and the page's first words; swipe to delete. Unfolded, the panel covers the right page like the text panel. The column's bookmark button toggles a ribbon at the top corner of the current page.
18. **Bookmarks on BookOrbit books sync with BookOrbit** (its bookmarks, keyed by CFI like positions), so they appear in its web reader and on other devices. Books from an OPDS server or imported from Files keep bookmarks on the iPhone.

### Search in book (approved 2026-10-31)

19. **Results by chapter, then step through.** The Search button opens a glass sheet: the search field, the match count and results grouped by chapter with their surrounding words. Tapping a result shows the page with the match highlighted and a small bar: ‹ 3 of 128 ›; tapping the count returns to the list, ✕ ends the search. foliate's built-in search supplies the matches, their excerpts and CFIs.

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
| Add an OPDS server (address, optional sign-in) | Designed (frames 27, 28) |
| Where reading progress syncs | Sketched in the brainstorm |
| Home, folded and unfolded | Folded designed (frame 01) |
| Library, folded and unfolded, with chips | Designed (frames 02, 04) |
| Collections, Series, Authors lists (chip drill-ins) | Not designed |
| Book cover page, folded and unfolded | Designed (frames 03, 04) |
| Book details (swipe up from the cover; Mark as finished, download) | Designed (frames 15, 16) |
| Search tab and results | Designed (frames 17–20) |
| Reader: one page folded, spread unfolded, book mode, controls shown | Designed (frames 07, 08, 09, 14) |
| Contents and bookmarks | Contents designed (frame 12); Bookmarks tab sketched |
| Text and theme panel (font, size, spacing, margins, theme, Always show controls) | Designed (frames 10, 11) |
| Search in book | Stepping bar designed (frame 13); results list sketched |
| Settings tab | Contents open |
| Empty and error states (no server yet, server unreachable, signed out, sign-in failed, download failed, offline) | Designed (frames 21–26; sample-book row on frame 05); the downloading-in-progress state is sketched |

Import from Files uses the system document picker; no screen of our own.

## Mockups

Figma: [Octavo-UX](https://www.figma.com/design/ElJJ7OtF8LOuX6dc68qZ23/Octavo-UX), built 2026-10-31 on Apple's iOS and iPadOS 27 kit (`iPhone Duo/Standard/Outer - Portrait` and `Inner - Landscape`, `Tab Bar - iPhone Duo`, Liquid Glass buttons, rows, text fields, kit text styles and colour variables). Covers are the public-domain sample books.

- **Pages by area:** Cover, 1 · Setup, 2 · Home and Library, 3 · Book, 4 · Reader, 5 · Search, 6 · Settings and states (states done, Settings to do), Components, Parked. Sections inside each page group the frames (Folded / Unfolded, or Reading / Panels).
- **Frame names:** `Area / NN Screen · posture`, for example `Reader / 07 Reading · folded`. The numbers below stay stable.
- **Prototype links** work within a page (Figma can't link across pages): Setup (BookOrbit row ↔ sign-in; OPDS row → address → sign-in), Home and Library (Home ↔ Library tabs), Book (cover strip ↔ details, tap or drag), Reader (page ↔ controls, controls → Text and theme / Contents / Search in book and back), Search (field → results, clear → empty). Each page has a flow starting point; links are invisible hotspots named `Hotspot → …`.

| Frame | Shows |
|---|---|
| 01 Home · folded | Continue reading, new on BookOrbit |
| 02 Library · folded | Chips, cover grid, filter button in the side column |
| 03 Book cover · folded | Full-screen cover, the book sheet at its compact height |
| 04 Library · unfolded | Grid left of the hinge, cover page with the compact book sheet right of it (hinge marked) |
| 05 Add your books · folded | Pick BookOrbit or OPDS, or import from Files |
| 06 Sign in to BookOrbit · folded | Address, account, Sign in, SSO (only if offered) |
| 07 Reader · folded | The page alone, controls hidden |
| 08 Reader · folded, controls shown | Column controls and the glass progress bar |
| 09 Reader · unfolded, controls shown | Spread centred on the hinge, clear of the column |
| 10 Text and theme · folded | Compact glass sheet over a Sepia page |
| 11 Text and theme · unfolded | Customize panel over the right page; left page previews |
| 12 Contents · folded | Contents \| Bookmarks switch, current chapter highlighted |
| 13 Search in book · folded | Match highlighted, step bar |
| 14 Book mode · half-open | Spine shadow, no controls, tap zones annotated |
| 15 Book details · folded | The strip expanded into the details sheet, over the cover |
| 16 Book details · unfolded | The same sheet inside the right-hand cover pane |
| 17 Search · folded | Before typing: recent searches, Browse chips |
| 18 Search results · folded | Books, then Series |
| 19 Search · OPDS server without search | The note, results from the iPhone, the feed's lists |
| 20 Search results · unfolded | Results left of the hinge, cover page right of it |
| 21 Server unreachable · folded | Warning banner; Library on On iPhone |
| 22 Signed out · folded | Info banner on Home |
| 23 Download failed · folded | Cover strip: Couldn't download · Try again |
| 24 Offline, not downloaded · folded | Cover strip: Needs a connection to download |
| 25 Nothing in progress · folded | Empty Home: invitation to the Library |
| 26 Sign-in failed · folded | Error under the fields |
| 27 OPDS catalog · folded | Feed address with examples, Connect |
| 28 OPDS sign-in (if asked) · folded | Shown only when the server asks for a password |

The reader frames (second row) set the book text in Charis SIL as a stand-in for the book's own font; Figma has none of the iOS book fonts.

Local components in the file: `Book Cover / …` (one per sample book), `Row / Continue reading` (progress set by the Progress frame's right padding), `Chip` (selected / unselected), `Reader controls (column)` (Back, Contents, Text and theme, Search in book, Bookmark), `Reader progress bar`, `Book sheet` (State = Compact / Expanded, with Place and Synced text properties) used by frames 03, 04, 15, 16, 20, 23 and 24, and `Banner` (Kind = Warning / Info, with Message and Action).

What the kit showed:
- Apple's Duo layout puts toolbar buttons (including back) in a glass group under the vertical status bar, and the tab bar at the bottom of the same column.
- The kit's `Tab Bar - iPhone Duo` has a "Search Role" type that puts Search in its own glass button at the very bottom of the column; adopted (decision 2) and used in the frames.
- The kit's Large Title toolbar renders its title mirrored in Figma, so the frames draw the large title as content instead.

## Open questions

- **Settings contents.** Too early to pin down. Working list from the brainstorm (not approved): Server (edit, sign out, replace, progress sync), Sync accounts (iCloud, KOReader sync), Reading defaults, iPhone Duo, Downloads and storage, About.
- **Plain `http://` servers on a LAN IP or a remote host.** `NSAllowsLocalNetworking` covers `localhost` and `.local` names only (`docs/notes/bookorbit-api.md`). Many self-hosted servers are plain http on a LAN IP.
- **Reaching the controls in book mode.** Taps on the pages turn them, so controls need another way in. Proposed (not approved): tap the side column, which sits outside both pages.
- **Book mode's angle range.** Roughly 60–150°; tune on a real device.
- **The book-mode shadow switch.** Its default (on or off), and whether it lives in Customize or in Settings → iPhone Duo.

## Needs engineering

Spikes before building: MOBI/AZW3/FB2 through foliate, the bridge and the CSP (decides the amber formats); SwiftUI `TabView` on the Duo; the fold cross-fade with batched re-layouts; book-mode posture detection. **No new foliate patch** is needed for these decisions (decision 8 works with foliate's own gap and the bridge's insets); patches 0001 and 0002 stay. The duo-spreads §8 risk still applies: after an unfold the synced position is the spread's start.

- **Tabs in the trailing column.** Apple's iOS 27 kit has a Duo tab bar at the bottom of the trailing column, so the placement is the system's design. Still check that SwiftUI's `TabView` renders it that way on the Duo, folded and unfolded.
- **Library chips from an OPDS feed.** Map the root feed's navigation entries and facets to chips, and decide what happens when a feed has many entries or none.
- **Pull the synced position while the cover shows.** Start the `ProgressSync` pull when the cover page appears, so unfolding opens the reader at once instead of waiting up to the 5 s pull timeout (duo-spreads §6).
- **Full-screen cover.** The cover runs under the trailing system column and the camera; the tab column and back button sit over the artwork, so they need a material that reads on any cover.
- **Page area (decision 8).** Lay out the `foliate-view` with the bridge's left/right insets so the page never reaches the column, map the margin setting onto foliate's gap, and keep the hinge gutter at least the reserved region's width.
- **Fold cross-fade (decision 11).** Show a `WebView` snapshot over the transition and fade it out once the layout settles; also batch the hinge, resize, layout and fold-region inputs into one re-layout (duo-spreads §5 counts 10–13 today).
- **Sample book.** Bundle the Standard Ebooks Pride and Prejudice and re-run the blank-page and fold checks on it (the spike's Gutenberg edition had the blank page after the dedication).
- **Book mode (decision 9).** Detect the half-open range from `onHingeChange`, swap the tap zones, and draw the spine shadow as an overlay outside the book's content.
- **Unfold on the cover → reader.** The spike's handoff already does this from its book screen (about 20 ms). It must compare old and new hinge status, not react to repeated or on-appear callbacks.
