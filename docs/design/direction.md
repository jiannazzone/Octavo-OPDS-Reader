# Octavo design direction

Status: **being redone, area by area** (from 2026-11-01). Adam set aside the 2026-10-31 decisions and is deciding again, one area at a time, starting with the library. **"Library pass" below is the source of truth; where an older decision disagrees, the library pass wins.** The older decisions stay below for reference until each area is redone. Ideas not yet approved, or parked, stay in `docs/UI-IDEAS.md`. The order the areas are built in is `docs/PLAN.md`.

## Device frame

Measured in spike 2b (`docs/notes/duo-spreads.md`):

- **Folded (outer display):** 466×678 pt. The system keeps an 84 pt column on the trailing edge clear for the camera; the clock, status icons, toolbar buttons and tab items sit in it. App content is 382 pt wide.
- **Unfolded (inner display):** 951×669 pt, landscape. The hinge is a 40 pt strip at x 455.5–495.5. App content is 867 pt wide (the same trailing system column). The right half, from the hinge to the system column, is 372 pt wide: almost the folded content width (382 pt).
- A 2:3 book cover nearly fills the folded display (466×699 against 466×678).

## Library pass (decided with Adam, 2026-11-01)

### Shell
- **Apple's tab bar, everything else ours.** The system tab bar stays in the side column; Octavo draws the screens, how they move, and the Back and action buttons at the top of the side column.
- **Three tabs: Home, Library, Search.** Settings is a button at the top of the side column on a tab's top screen, not a tab.
- **One screen, two pages.** Every screen is a spread: content flows from the left page onto the right, and nothing sits on the hinge. Folded, you see one page. Folded or unfolded it is the same stack of screens; a fold only lays the top screen out again.
- **Going deeper replaces the whole spread** (a pushed screen slides in). Back, or a swipe from the left edge, returns.

### The Duo as the book
- **Unfolding on a book's screen opens the book**, if it's on the iPhone. If it isn't, the screen stays as Cover | Details and nothing downloads until you tap Download or Open.
- **A book's screen, folded, has Open** (read on one page) **and Download** (when it isn't on the iPhone yet).
- **Folding while reading closes the book** back to its screen. Default; may become a setting later.
- Unfolding anywhere else just lays the screen out as two pages.

### Home
- **Your book first:** the book you're reading as a large cover, with your other books in progress (from the server and this iPhone, most recent first) beneath, or on the right page unfolded.
- **Only books in progress.** New arrivals live in the Library. A book marked finished leaves Home.
- Built (step 5): the current book's cover is large (190 pt wide folded, 250 pt unfolded) with its title, author and place under it; the others are rows under "Also reading". Unfolded with nothing else in progress, the right page says so and links to the Library.
- Unfolding on Home doesn't open anything; tap a book to see its screen.

### Library
- **Sections as shelves** (All books, Recently added, Collections, Series, Authors, or an OPDS server's own sections): each a heading ("All · 7 ›") that opens the section, over one row of its covers running across both pages, skipping the hinge (three covers folded). A book on a shelf opens its own screen. A section without covers is just its heading. One layout for every server; a chips layout may come later as an option. (Replaced the contents-page rows after seeing them unfolded: the row split at the hinge and the chevron sat mid-screen.)
- Dividers may run across the whole spread, fold included.
- **Each section fills the whole spread** (a grid of covers across both pages, or a list flowing from the left page onto the right).

### Series and authors (Adam, 2026-11-01)
- **Series: cover stacks.** The Series list is a grid across both pages; each series is a small stack of its first covers with its name and book count under it. Opening one shows its books numbered in reading order. On the Library page, a shelf of series (or authors) shows the same tiles, each opening that series. Adam was split between this and rows; built as stacks to judge on the device.
- **Authors: first name first, filed by last name.** "Jane Austen" under A, "H. G. Wells" under W (made from the name when the server's sort name isn't last name first); no chevrons.
- **Each author has a picture** (Adam, 2026-11-02, over a cover each and a grid of tiles): their photo when the server has one (BookOrbit keeps author photos and serves them itself), else their initials on a tint that stays with the name, like Contacts. The name sits over the book count.
- **An A–Z strip** at the trailing edge of the page once an author list reaches 30 names: tap or slide to jump to a letter.
- Library list rows have no chevron: unfolded it sat mid-screen at the left page's edge.

### Titles under covers (Adam, 2026-11-02)
- **A Settings switch, off by default:** Settings → Library → Titles under covers puts up to two lines of each book's title beneath its cover, in every grid of books, for covers that don't make the book clear. Kept on the iPhone. In Settings since step 14.

### Settings (Adam, 2026-11-02; built in step 14)
- **Unfolded: the list left of the hinge, the chosen page right** (frame 37, kept over "a deeper screen replaces the spread": settings pages are short). It opens with the server's page; a tap on the left changes the right page without a slide. Folded: the list, and a row opens its page.
- **The list:** Server (name over "address · account"), Library (Titles under covers), Storage (Books on iPhone "12 · 48 MB"), About. **No Reading progress row in the list**; the status is on the server's page.
- **The server's page** (frame 35): Address, Account, Reading progress, then Sign out and Remove server. Reading progress: Synced; Not synced yet with "N books pending." beneath; Paused with "Sign in again to sync." when signed out, where Sign out becomes Sign in. **An OPDS catalog has no Reading progress row** (Adam's suggestion, as a book's place line shows nothing for it), and no Sign out without a password.
- **Sign out asks first:** "Sign out of BookOrbit?" / "Your downloaded books stay on this iPhone. Reading progress syncs again once you sign in." · Sign out · Cancel. Then the signed-out banner.
- **Remove server as frame 36** (decision 24's wording), and without downloads "Remove BookOrbit?" / "You can add it again any time." · Remove · Cancel. Then setup. Kept books aren't listed anywhere until a server is back; they come back downloaded when the same server is added again.
- **Books on iPhone:** "5 books · 4.4 MB" with a **sort menu** at the header's right (Size, Title, Author, Recently downloaded; remembered, Size first); each book's cover, title, author and size; swipe to remove (the place is kept); Remove all downloads asks first. Empty: "No books on iPhone" / "Books you download show here."
- **About, flat in the list:** Version "0.1 (1)", Source code ↗ (GitHub in Safari), Licences › (one page, each component with its full text), and "Octavo is free software under the Mozilla Public License 2.0."

### Other ways in (Adam, 2026-11-02; step 15)
- **Add your books:** Import from Files is a third choice under BookOrbit and OPDS catalog ("EPUB, MOBI, AZW3 or FB2 files"), and **Read a sample book** is a quiet row with its cover under the choices ("Pride and Prejudice, Jane Austen"). The line under the title: "Octavo reads the books on your own server, or ones you import. Choose where your books are." Unfolded, the choices and the sample row are on the right page, Don't have one yet? on the left.
- **After an import you land on On iPhone,** over the Library tab (Back goes to the Library), newest first, nothing highlighted: one rule for one file or many.
- **On iPhone holds every book whose file is on this iPhone:** server downloads, Files imports and the sample book once read. The same set as Settings › Books on iPhone and what a cover's check means. A downloaded book is the same book on its server shelf and in On iPhone (one file, one place, one sync), not a copy. **Its shelf is the Library's last**, after the server's own sections.
- **No server yet, books imported:** the Library is the grid of the iPhone's books ("Library", "5 books"), not a single shelf. Once a server is added it becomes the server's shelves with On iPhone last.
- **Adding a server later:** Settings' Server section shows one row, Add a server, opening the server choices with Back ("Choose what type of server you have."). The Library's grid also ends with a quiet "Have a server?" card (Add a server) with ✕; dismissed, it never comes back (kept on the iPhone).
- **Importing later:** a **+** above Settings in the Library's column (top screen, with or without a server) opens the Files picker; and **Open in Octavo** from the share sheet of Files, Mail, Safari and other apps for EPUB, MOBI, AZW3 and FB2. Either way the book is copied in and On iPhone opens.
- **Removing an imported book (or the sample book) always asks**, from its details (Remove from iPhone) or a swipe in Books on iPhone, since it's the only copy: "Remove “Moby-Dick” from this iPhone?" / "It was imported from Files, so it can’t be downloaded again. Import it again and it opens where you left it." · Remove · Cancel. The sample book: "Are you sure? This book cannot be recovered." Server downloads stay as they were (a swipe removes at once, the details ask). A downloaded file with DRM is deleted, and its book's screen says "This file is DRM-protected and cannot be opened." with Download greyed out. Remove all downloads and Remove server leave imported books and the sample book alone; their places and bookmarks stay, so the same file imported again opens where you were.
- **A file that can't come in says why, without a pop-up** (decision 22): a warning note above the books on On iPhone (the connection banner's style) when at least one book came in; **when none did, you stay on the Library and the note shows at the top of its first screen** (Adam, 2026-11-02, after trying it: a failed import shouldn't take you to On iPhone; Open in Octavo opens the Library's top screen), "“Kindred.azw3” is protected with DRM, which Octavo can’t open.", one sentence per file ("2 files weren’t imported. …"), with OK. On the first screen, when nothing came in, the same words in red under the choices. The reasons: protected with DRM; "isn’t a book Octavo reads" (PDF, KFX, comics and the rest); "couldn’t be opened; the file may be damaged". A file imported before isn't a problem: it moves to the front.

### Dismissible invitations (Adam, 2026-11-02)
- **A quiet card with ✕ that never returns once dismissed** (remembered on the iPhone) is the pattern for an optional nudge that isn't the screen's point, like "Have a server?" under the Library's grid. Use it elsewhere when a hint or suggestion would otherwise stay on screen for good. It never replaces an empty screen's invitation (decision 22) or a problem's banner.

### A book's screen
- **Folded:** the whole cover on a blurred copy of itself fills the screen (decision 32), with a compact sheet at rest (Adam, 2026-11-03, about half its old height): the title on one line, the place under it ("48% · Synced just now"), **Open** as a capsule on the right of both, and a thin progress line below. A problem takes the place's line and wraps to two lines if it needs to (Adam: it's important information). Pull it up for the author, **Mark finished** and the details.
- **Unfolded:** Cover | Details, the cover on its blur filling the left page and the same details on the right.
- **Open is Download until the book is on the iPhone** (Adam, 2026-11-01): Download, then a ring with Cancel while it downloads, then Open. A problem shows on the place line, with Try again on the button. Downloading doesn't open the book.
- **The place is where the book opens, with when it last synced beside it** (step 13, Adam 2026-11-02): on the place's own line, at the right ("Synced just now", "Synced 5 minutes ago", "Synced yesterday", "Synced Oct 28"), or "Not synced yet, will retry" while a place waits to be sent. A book whose place doesn't sync (an OPDS catalog) shows nothing there.
- **Mark finished** goes to BookOrbit as its `read` status (un-marking sends `reading`, which BookOrbit records as `rereading`); an OPDS server keeps no such mark, so the iPhone keeps it. A finished book's place line says Finished.

### Getting books onto the iPhone
- **A check on downloaded books**, everywhere covers show. A downloading book shows a progress ring on its cover, everywhere. Both sit in a dark disc at the cover's bottom corner.
- **Remove download is at the end of a book's details** (Adam, 2026-11-01), only while the book is on the iPhone, and asks to confirm. The place in the book is kept.
- **A downloaded book stays** until you remove it. Downloads live where iOS won't clear them (Application Support), outside the iPhone's backup.
- **Nothing downloads in the background.**
- **Lists and grids appear at once** with blank cover shapes that fill in; no spinners mid-screen. A server that can't be reached says so in place, with Try again.

### Still to decide in the library pass
Nothing: every library step is decided and built (`docs/PLAN.md`).

## Decisions (2026-10-31, under review)

### Structure and library (approved 2026-10-31)

1. **Any number of library servers** (Adam, 2026-11-05, reversing "one library server in v1"; decision 36). You add the first when you set up the app and more from Settings or the Library's title. Each server stays its own library: a merged catalog index, deduplication and per-server switches were explored and dropped as too complicated (parked in `docs/UI-IDEAS.md`). With one server, every screen is as it was.
2. **Four tabs in the trailing column:** Home, Library and Settings, with Search last, at the very bottom (Apple's "Search Role" tab, the standard layout). The trailing column is the Duo's standard place for tab items, so nothing sits along the bottom of the screen.
   - **Search sits inside the system tab bar** (amended 2026-11-01). On iOS 27.1 the system draws the Search-role tab as the last item in the same glass capsule, not as the separate button Apple's kit and our frames show; UIKit does the same. We use the system's tab bar as it is rather than draw our own (`docs/notes/duo-tabbar.md`).
   - **Home:** "Continue reading" (positions from sync and from the phone), plus what's new on your server.
   - **Library:** your server's books as a grid of covers, with chips across the top. For BookOrbit the chips come from its API (All, Collections, Series, Authors); for an OPDS server they are the feed's own top-level entries (for example Recent, Authors, Series, Shelves on Calibre-Web). An "On iPhone" chip shows downloaded and imported books.
   - **Search:** your server's search (BookOrbit search, or OPDS OpenSearch when the feed offers it) plus the books on the phone.
   - **Settings:** a tab (decision 24).
3. **Books download on first open.** Opening a server book for the first time downloads its file to the device, where it stays. Offline reading needs nothing more.

### Picking a book (approved 2026-10-31)

4. **Folded: full-screen cover.** Tapping a book shows its cover filling the outer display.
   - Over the cover: a bottom strip (a glass sheet at its compact height, with a grabber) showing the title over the percentage and when it last synced, an **Open** capsule beside them and a thin progress line (amended 2026-11-03: the title, not the chapter).
   - Swipe up on it for details: the same sheet expands (decision 20).
   - **Unfolding on the cover opens the book at your place immediately**, with no prompt (answers part of duo-spreads §7 question 5).
   - The cover runs under the camera column, which covers its top-right corner; accepted. The tab column stays visible over the cover.
5. **Unfolded: grid | cover page.** The grid sits left of the hinge; the selected book's cover page (same strip and Open button as folded) fills the right half. Nothing sits on the hinge.
26. **Home unfolded: Home | your current book.** Home sits left of the hinge; the right half shows the first "Continue reading" book's cover page with its compact sheet, ready to Open. Tapping another book on Home switches the right half.

### Library drill-ins (approved 2026-10-31)

23. **Chips switch the Library in place; items open on a new screen.**
    - **Collections** (including BookOrbit smart scopes) and **Series**: a list with three covers, the name and a count. Tapping one opens its books as a grid under its name; a series opens in reading order, numbered.
    - **Authors:** A–Z sections with an index strip to jump, and a book count per author; tapping one opens their books.
    - **OPDS:** the chips are the feed's own entries; entries that lead to more entries show as a list, entries that are books as a grid.
    - **Unfolded, the panes shift one step at a time:** list left of the hinge, its books right; tapping a book shifts to books left, cover right; Back shifts back. Always two adjacent levels, nothing on the hinge.

### Book details (approved 2026-10-31)

20. **The cover's strip expands into the details.** The progress strip and the details are one Liquid Glass sheet with two heights. Swiping up keeps the strip (title, place and last sync, **Open**, progress line; the title may take two lines) and adds the details below; the cover stays behind it. Drag it down or tap the cover to return to the strip; unfolding still opens the book. Unfolded, the right page shows the full summary (title, author, place, **Mark finished | Open**) with the details below it. Below the strip (amended 2026-11-03):
    - Author (tap: their books).
    - **Mark finished**; **Remove download** at the end of the details.
    - Description (three lines, then More).
    - Series, Collections, File (format, size), From (server), Added.
    - Mark as finished goes to BookOrbit for BookOrbit books and stays on the iPhone for OPDS and imported books (OPDS can't store it). Ratings and editing collections come later.

### Search tab (approved 2026-10-31)

21. **Search** (the tab at the bottom of the column):
    - **Before typing:** the search field ("Title, author, series"), your recent searches (with Clear), and Browse chips that jump into the Library's Authors, Series and Collections lists.
    - **Results** update as you type: **Books** first, as rows with a small cover, author and your progress or a Downloaded mark, from the server and the iPhone together; then **Series** and **Authors** sections when the server supports them (BookOrbit) and there are matches.
    - **An OPDS server without search** shows a short note ("Calibre-Web doesn't offer search. Showing books on your iPhone."), results from the iPhone, and the feed's own lists as Browse chips.
    - **Unfolded:** results left of the hinge, the selected book's cover page (with its compact sheet) right of it, as in the Library.
    - **Built (step 7, 2026-11-01), adapted to the shell:**
      - **The field sits under the title on the left page** (Adam chose it over iOS's own field, which the Duo puts top right unfolded and across the top folded, and which would stay over a book's screen opened from the results). It slides away with the Search screen.
      - **A result opens its own screen in the Search tab**, as everywhere else, so unfolded shows Books on the left page and Series and Authors on the right; with neither, the books flow down the left page and on down the right. Before typing, Recent sits on the left page and Browse on the right.
      - **Books show the first 12**, then "All 134 books", which opens every match as a Library list. Series and Authors stay in reach below them folded.
      - **Search starts at two characters** (BookOrbit's minimum), after a short pause in the typing; Return searches at once. A search is kept in Recent (eight at most) on Return or when a result opens.
      - **Books on the iPhone** are the ones downloaded here, matched by title, author or series. Offline they're the results, under the connection banner.

### Connecting (approved 2026-10-31)

6. **Adding the server: pick the type first.** "BookOrbit" or "OPDS catalog" (Calibre-Web, COPS, Kavita, Komga…), then that type's form (address, sign-in), then where reading progress syncs (this BookOrbit server, iCloud, KOReader sync, or don't sync; v1 offers only BookOrbit, see v1 scope). "Import from Files" sits on the same first screen.
   - **OPDS catalog:** enter the feed address (examples under the field: Calibre-Web `…/opds`, COPS `…/feed.php`, Komga `…/opds/v1.2/catalog`, Kavita: paste the OPDS link from its settings) and tap Connect. The account fields appear only if the server asks for a password ("Found “Calibre-Web”. It asks for a sign-in."); otherwise you land in the Library.
   - **The sync step is skipped for OPDS servers in v1** (only BookOrbit syncs); progress stays on the iPhone. The step returns once iCloud or KOReader sync exists, with iCloud preselected. A BookOrbit server shows it with itself preselected.
   - **"Don't sync" isn't offered for now** (Adam, 2026-11-02, step 13): with BookOrbit as the only choice left, setup skips the Reading progress step and every BookOrbit server syncs. The step and the choice stay in the code behind `SavedServer.offersSyncChoice`, for when there's a real choice to make.
   - **No skip on first launch:** the first screen stays until a server is added or a file imported. Replaced by decision 30 (2026-11-03): a new install starts with the tour (decision 29), which can be skipped to Home with the sample book.
   - **Built (step 8, 2026-11-01):**
     - **Each step is one screen across the spread** (Adam chose it over list | detail and over one step on the left page): what it is on the left page under the title, what you do on the right. Steps slide in over each other like the app's other screens, with Back in the column; there's no tab column during setup. Folded, one page: the words, the form, then any help (the OPDS address examples).
     - **Where to get a server:** Add your books has a "Don’t have one yet?" card on its left page (under the choices folded), one quiet grouped card with a row each (Adam chose it over a card each and over side-by-side tiles): BookOrbit, opening its GitHub (Adam), and calibre, opening calibre-ebook.com. Generic symbols, not the projects' logos. Rows open in Safari.
     - **Steps:** Add your books (BookOrbit or OPDS catalog) → Sign in to BookOrbit → Home (the Reading progress step, this BookOrbit server or Don't sync, is off for now; see above). OPDS: the address → Connect → the account fields only if the catalog asks → Home. "Trust this server?" comes in between when a certificate needs it.
     - **Signing in again:** the signed-out banner's Sign in opens a "Sign in again" screen in the same style (the server, the account, a new password), then returns to where you were. The server's page in Settings has the same Sign in when signed out (step 14).
     - **Not yet:** BookOrbit's single sign-on (Octavo can't do it yet). Import from Files and the sample book are built (step 15, Other ways in above).
   - **A bundled sample book:** a "Read a sample book" row on the first screen opens **Pride and Prejudice** (Standard Ebooks edition, CC0) straight in the reader, so the Duo reader can be tried before any setup (and App Review can test without a server). Leaving the reader returns to the first screen until something is added; afterwards the book stays under On iPhone and can be removed. Since decision 29 the tour opens it instead, and the row goes. Credit Standard Ebooks in `THIRD-PARTY-NOTICES.md`.
25. **Plain http and self-signed certificates.**
    - **Plain `http://` is allowed only for home and VPN addresses;** internet addresses need https ("Use https:// for servers on the internet."). An http address shows "Not encrypted. On other networks, your password could be seen." under it (Adam, step 16, over "Octavo uses http:// only at home or over a VPN.").
    - **What counts as home or VPN** is a fixed set of standards-based rules applied to the address's host, not a list anyone maintains: IP addresses in 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 (RFC 1918), 100.64.0.0/10 (RFC 6598, used by Tailscale), 127.0.0.0/8, 169.254.0.0/16, and the IPv6 equivalents (fc00::/7, fe80::/10, ::1); special-use local names (`localhost`, `*.local`, `*.home.arpa`, `*.internal`, `*.lan`); any other name counts only if every address it resolves to is in those ranges (covers `*.ts.net` and split DNS at home).
    - **Checked on every connection,** not only when the server is added: if a saved http server's name resolves to a public address, Octavo refuses rather than send the password or token unencrypted. A home IP address can't be told apart from the same address on someone else's network (hotel Wi-Fi); that residual risk is accepted and mentioned in a short note when an http server is added.
    - **Self-signed HTTPS certificates:** on first connect, a "Trust this server" step shows the certificate's details (issued to, fingerprint); once trusted, only that exact certificate is accepted for that server (pinned). A changed certificate asks again.

### Empty and error states (approved 2026-10-31)

22. **One pattern:**
    - **Connection problems** show a banner at the top of the tab: server unreachable ("Can't reach BookOrbit. Showing books on your iPhone." · Retry; the Library switches to On iPhone) and signed out ("Signed out of BookOrbit. Reading still works; sync is paused." · Sign in; worded for both a server's sign-out and Settings' Sign out, Adam 2026-11-02).
    - **Problems with one book** show on the cover's strip, where Open would be: "Couldn't download · Try again"; offline and not downloaded: "Needs a connection to download." (no queueing).
    - **Empty screens** are an invitation with one action ("Nothing in progress · Open Library"; the same for an empty server).
    - **Sign-in errors** appear under the fields ("That username or password didn't work.").
    - **No pop-up alerts**, except to confirm deleting or removing something.
    - A position that didn't sync shows "Not synced yet, will retry" on the strip's sync line. It's retried while the app is open (Adam, 2026-11-02): at launch, when the app comes back and when the connection does. Not in the background.
    - **Another reader moved on while a book was open** (Adam, 2026-11-02): coming back to the app offers the server's place in a capsule where the footer is, "BookOrbit: 62% · Chapter 80", with Go and ✕. Turning the page or ✕ keeps this iPhone's place. Built: `docs/notes/sync-in-app.md`. With the way back up, both show (decision 33).
    - **Downloading** shows on the strip too: "Downloading · 42%", "Opens when it's done.", a progress bar and Cancel.

### Reader and the Duo (approved 2026-10-31)

Answers all six questions in `docs/notes/duo-spreads.md` §7 (question 5's first half is decision 4).

7. **Controls are hidden while you read.** A tap in the middle shows them: Back, Contents, Text and theme, Search in book and Bookmark in the side column, plus a glass progress bar with the chapter and page. Taps on the left and right sides turn pages. A setting, **Always show controls**, keeps them visible; it is off by default.
   - **Progress, amended 2026-11-01 (#17)**, following the usual e-reader pattern (Apple Books, Kindle): **each page's bottom margin always shows its chapter and page** ("CHAPTER 36. The Quarter-Deck. · 291 of 974 · 30%"; a spread puts the chapter under the left page and the numbers under the right), so it never covers text and needs nothing special half-open. **The glass bar is a scrubber** that comes and goes with the tap, the same in every posture: over the page flat and folded, and half-open split at the hinge (chapter and scrubber on the left page, numbers on the right). **Its edges line up with the text's**, so it follows Narrow, Medium and Wide, and it sits just above the home indicator (Adam, 2026-11-03); half open, each piece lines up with its own page's text. **Half open, the right-hand piece shows the chapter's progress** (Adam, 2026-11-03): "6 pages left in this chapter" over a line through the chapter, with the book's page numbers; time left and choosing the readout come later (`docs/UI-IDEAS.md`).
   - **Always show controls keeps only the column's buttons** (they never cover text); the middle tap still shows and hides the bar. The toggle lives in the Customize panel (decision 13, #18).
   - While the controls show, a tap anywhere on the page hides them (frame 08's hotspot) instead of turning.
   - The column's panels and Bookmark are built (step 12).
   - **Amended 2026-11-02 (step 9, Adam): the column's "…" is the one way to bring the controls up, in every posture**, folded, flat and half open; the middle tap no longer shows them. Every page tap turns: left of the middle goes back, right of it (and the rest of the column) goes forward, the same in every posture. With Always show controls the "…" sits after the buttons and brings up the bar.
   - **‹ is always there, on its own** (Adam, 2026-11-04): a separate glass button above "…", folded, flat and half open, while a book loads and if it can't open. The "…" opens into Contents, Aa, Search and Bookmark in one group below it. While the rest are hidden, ‹ is the same grey as "…"; it goes dark when they come up, and stays dark with Always show controls. A book that can't open now shows only ‹, not the panel buttons, which did nothing there. In the tour, Skip takes its place as before (decisions 29 and 30), and the cards don't name it. "Back to page 312" stays at the bottom of the left page, well away from it.
     - **A stray tap costs little.** ‹ is about 50 pt across and sits at the top of the column (173–223 pt down folded, 123–173 pt open), about 1% of the area that turns the page forward. Closing and reopening landed on the same CFI, and a trip survives it (decision 33). The book's screen has its own ‹ in about the same spot, so a double tap goes one screen further. Measured on the simulator through the debug remote's `back`, without a finger; try it on the Duo.
   - **A keyboard and a trackpad turn pages too** (step 10): ← and → the way the book reads, like the halves of the page; ↑, ↓, Page Up, Page Down and Space (Shift-Space back) through the book; a trackpad's two-finger swipe turns one page, sideways or up and down. A swipe on the page turns as foliate's paginator does.
   - Page numbers are foliate's locations (1,500 characters each, the same 974 the frames use): they stay put across folds and devices, though a page turn doesn't always change the number.
8. **The page never goes under the side column** (§7 Q3, Q4). Folded, the page stays in the 382 pt content area. Unfolded, the spread stays centred on the hinge and the left edge gives up the same 84 pt, so the margins match. The margin setting runs from wide down to text reaching the column's edge; the gutter on the hinge never drops below the hinge's 40 pt. No foliate patch is needed: the margin setting scales foliate's gap and outer margins together.
   - **The page runs edge to edge** (2026-11-01, #17): its colour fills the screen, under the clock and the column's glass buttons as the cover does, and only the text keeps out of the column, the camera and the home indicator. Showing or hiding the controls never re-paginates.
   - **Margins: Narrow 4.6%, Medium 7% (default), Wide 10%** of foliate's gap (2026-11-01). Medium is the frames: 27 pt folded, 55 pt unfolded. Narrow puts the text at the column's edge with an 18 pt margin folded and the hinge's 40 pt gutter unfolded; Wide is 38 pt folded and 78 pt unfolded.
   - **The left strip stays blank for now** (Adam, 2026-11-03; door left open). Unfolded, the 84 pt at the left edge is a plain margin, the mirror of the side column. Text stays out of it: with the divide on the fold, using it would make the left page wider than the right. The ideas he looked at are parked in `docs/UI-IDEAS.md`.
9. **Half-open is book mode** (§7 Q1): controls stay hidden, a shadow at the spine, a tap on the left page goes back and on the right page goes forward. The spine shadow, and any page-warp effect, is optional: **Book-mode shadow** in the Customize panel, on by default.
   - **Controls in book mode** (amended 2026-11-02, step 9): the quiet "…" in the side column brings them up, as in every posture (decision 7); a tap anywhere else in the column turns forward, like the right page. (Before: any tap in the empty column showed them, with nothing to say so.) ‹ stays up above it (decision 7).
   - **Angles:** book mode from about 60° to 150°, flat above about 160°, with buffers between so the mode doesn't flicker near a boundary (the system folds to the outer display below about 35°). Final numbers are set on a real device.
   - **Half-open, every screen splits 50/50 at the hinge** (Apple's guidance for the Duo). The unfolded layouts already divide at the hinge (grid | cover, list | page, the reader's two pages); nothing may span it when half-open.
10. **Unfolding anywhere but a cover keeps the same screen** (§7 Q5): it takes its unfolded layout. Only a book's cover turns an unfold into "open".
11. **Folds cross-fade** (§7 Q6): a snapshot of the old page fades into the settled layout (about 0.3 s), hiding the intermediate re-layouts.
12. **Unfolded and turned sideways, one column runs straight across the fold** (§7 Q2), as the spike does today. Half-opened that way (laptop-style), the text bends over the fold; accepted.

### Page turns and opening a book (Adam, 2026-11-03)

Decided with animated mockups in the planning session (no Figma frames); replaces the idea in `docs/UI-IDEAS.md`.

27. **Folded, a page slides; open, it flips over the spine.** Flat and half open alike, the page swings over the hinge like paper: going forward, the right page lifts and lands as the next spread's left page; going back, the left page swings over to the right. Each half of a book-mode spread turns its own way (decision 9). Folded, the page slides sideways, as in Kindle and Kobo.
    - **A swipe drives the turn under your finger**; let go before halfway, without a flick, and the page falls back. Taps, the keyboard and the trackpad play the whole turn. A turn looks the same across a chapter break.
    - **Page Turn in Customize** (decision 13): a menu below Margins with **Automatic** (the default: slide folded, flip open), **Slide**, **Flip**, **Fade** and **None**. Any choice but Automatic applies in every posture; None is the instant turn Octavo had before.
    - **Reduce Motion:** Automatic fades. A style picked by hand is kept.
    - **Speed:** about 0.3 s for a slide, 0.5 s for a flip and 0.15 s for a fade, set on a real Duo.
    - **Curl** (the corner peels over, as in Apple Books) was weighed for open and left out for now (`docs/UI-IDEAS.md`).
    - **Built (2026-11-03, `docs/notes/page-turns.md`).** Swift draws each turn from snapshots of the page while foliate turns at once underneath; a swipe is recognised in UIKit. Across a chapter break the new page takes 70–250 ms on the simulator: a tap's turn waits up to 100 ms for it, then starts over the page's colour and the page fades in. A swipe that falls back is never saved or synced.
28. **A book opens like a cover** (provisional: Adam decides once he has seen it on his Duo). Opening from a book's screen, the cover moves onto the right page and swings over the spine, landing as the left page of your place: the same motion as a flip. Folded, the cover fills the screen and swings away to the left, uncovering your page. Closing plays it backwards: the page swings back over as the cover, which shrinks back into its place on the book's screen. With no cover on screen, the reader fades in as before.
    - **Reduce Motion** cross-fades instead.
    - **Folding while reading and unfolding on a cover stay as they are**: the fold is already the motion (decisions 10 and 11).
    - **Built (2026-11-03, `docs/notes/page-turns.md`), for Adam to see on his Duo.** The cover rests on the right page until the book has opened, then swings. Closing plays only when Back lands on the book's screen; elsewhere the reader fades. **Back is a normal Back** (Adam, 2026-11-03): it lands on the screen the book was opened from.

### The tour (Adam, 2026-11-03)

Decided with mockups in the planning session (no Figma frames). This is step 17, the new-install flow.

29. **A new install starts with a short tour that opens like a book**, taught in the sample book (Pride and Prejudice) rather than on slides. Reading comes first, then adding your books:
    1. **Close your iPhone**, only if Octavo first opens unfolded: a Duo closing on the left page; "Close your iPhone" / "Octavo opens like a book." on the right. Closing moves the screen to the outer display. **Continue without closing** plays decision 28's cover opening on screen and goes on to step 3, for a phone on a stand or anyone who finds folding awkward.
    2. **The cover, folded:** Pride and Prejudice's cover, with "Open your iPhone to begin" low on it, centred on the cover just above its title (Adam, 2026-11-03: centred on the space left of the column, it looked off). Unfolding opens it, the same gesture as every book afterwards (decision 10).
    3. **Turn the page:** the book opens on Chapter I. "Tap the right page, or swipe. Tap the left page to go back." Moves on when they turn. (Adam, 2026-11-03, after trying it: no Welcome card with Start before this, and not the title page.)
    4. **Bring up the controls:** "Tap ··· whenever you need them." Moves on when the controls open.
    5. **Make it yours:** "Tap Aa for themes, text size and fonts." The real Text and theme panel opens (decision 13) and the left page changes as they choose; the card says "The page changes as you go" / "Come back to Aa any time." · Done.
    6. **Add your own books:** "From your server, or from Files." · Not now · Add books. Add books closes the reader and opens Add your books (decision 6); its steps end on Home as today.
    - **The tour card** is Liquid Glass, at the bottom of the left page (folded, the bottom of the page), in the same place for every step, with dots for how far along it is. A step that asks for something moves on when it's done; only Make it yours and the last card have buttons.
    - **What to tap shows itself** (Adam, 2026-11-03, over the pulsing ring he'd first chosen and didn't like, a tint on the page, and a tip beside the button). The right page lifts a little and settles, every few seconds until it's turned, with a soft shadow and no darkening; with Reduce Motion it stays still. ··· and Aa are blue, in the column at full size and where the card's words name them. A disc behind them was tried and dropped: the column only takes images, up to 38 pt, so it shrank the symbol and couldn't fill the button.
    - **Folding mid-tour closes the book**, as always; the folded cover then says "Open your iPhone to continue", and unfolding picks the tour up at the same step.
    - **Without a fold** (another iPhone, an iPad), steps 1 and 2 drop out and the tour starts at Turn the page.
    - **Left out:** book mode (it turns itself on when half open), Contents, bookmarks and search (they're in the controls step 5 opens), and folding to close a book. Weighed as optional lessons and dropped to keep the tour short.
    - **Add your books loses its Read a sample book row:** the tour opens the sample book, and afterwards it's on Home and in On iPhone.
    - The wording is a draft for Adam to approve.
    - **Built (2026-11-03, `docs/notes/tour.md`), for Adam to try on his Duo.** While the tour plays, Skip takes Back's place in the column (Adam, over showing both): one way out, and Back returns when it ends. The steps are the decision's, in its words; a tap on the page that hides the controls on Make it yours goes back a step, since Aa goes with them. Unfolding after a fold puts back what the step had up (the controls, the panel). On one page the card sits above the Text and theme sheet.
30. **Skipping and seeing it again.** Skip sits in the column on every tour screen. Skip, or Not now on the last card, lands on Home with Pride and Prejudice under Continue reading; the Library's "Have a server?" card and Settings › Add a server stay the ways to add one (step 15). This replaces decision 6's no skip on first launch.
    - **It plays once**, on a new install's first launch.
    - **Show the tour** in Settings, above About, plays it from the beginning and returns to Settings. If the sample book was removed, the tour still opens it but doesn't put it back on the shelf, so "This book cannot be recovered" stays true.
    - **Built (2026-11-03, `docs/notes/tour.md`).** Add your books from the tour is setup's first screen with Skip in the column. On a replay with a server already connected, Add books opens the Files picker (Adam, over a one-choice Add your books): Octavo holds one server, so the server choices would replace it. An unfinished tour starts again at the next launch. A file opened in Octavo as a new install's first launch lands on the Library with that book and no tour (Adam, over the tour next launch or first), with the sample book on Home. Since the sample book counts as a book, Remove server with it still on the iPhone lands on Home, where Skip does (Adam, over Add your books); with no books at all it's setup, as before.

### Colour (Adam, 2026-11-03)

31. **The accent is Ink**: `#34459E` in light mode and `#9FAEFF` in dark, in place of iOS's blue, for buttons, links, the scrubber, progress lines and lit controls. It keeps at least 7:1 on white, Paper, Sepia, Night and black, where iOS's blue falls to 3.2:1 on Sepia. Home, the Library and Settings keep the system's light and dark (decision 13).
    - **Built (2026-11-03).** An `AccentColor` asset, the app's global accent. Switches stay iOS's green. Book links keep the themes' own colours. The signed-out banner uses it too.

### Covers (Adam, 2026-11-04)

32. **Every cover fits on a blur.** A cover shows whole in its frame, on a blurred copy of itself: on a book's screen, folded and unfolded, on Home's current book, and on shelves, grids and rows. Frames stay as they are (the screen, the left page, 2:3 cells), so rows stay even, the check and ring stay in the frame's corner, and nothing moves when a cover loads.
    - **A strip under about 3 pt fills instead:** a sliver that thin looks like a glitch, and the crop doesn't show. In the cells on shelves and grids, that's most ordinary covers.
    - **The opening motion follows:** decision 28 draws the same picture, with the cover and its blur swinging as one. So do series stacks and the tour's cover. Stand-ins for books without artwork (`StandInCover`, `BookTitleCover`) don't change, and neither do authors' photos.
    - **Folded, the sheet and side column still sit over the cover,** as before, so they can hide what's under them, often an author's name.
    - **Turned down:** filling, which cuts a square cover's title; filling covers close to the frame's shape and fitting the rest, a line to tune for no clear gain once seen with the blur; a flat colour from the cover, a heavy block on bright covers; and cells taking each cover's own shape, as Apple Books does, with uneven tops and a check that moves.
    - **Measured:** the frames are 0.687 wide folded (466×678 pt), 0.681 on the left page (455.5×669 pt) and 0.667 in cells. About ten real books run from 0.635 to 0.725, none of them square. The square pictures were real covers cropped to shape. On BookOrbit, Calibre-Web, COPS, Komga and Kavita a thumbnail has its full cover's shape (within 0.005), so a cover doesn't jump when the full one loads. Kavita serves every cover at 320×455 (0.703), so its covers show 4 pt strips in grid cells.
    - **Built (2026-11-04).** `FittedCover`, used by `CoverImage`, `BookCoverArt`, the opening motion and the tour's cover. Checked on the simulator, folded, unfolded and half open, with real covers and test books with covers 0.50 wide, square and 1.33 wide. Adam tried it on the Duo the same day: the covers look right and the blur is smooth, so it stays drawn live rather than cached. Still to check: a real square book or comic.

### Text and theme (approved 2026-10-31)

13. **A compact panel, Customize one step in.** The "Aa" button opens a Liquid Glass sheet (where available) so the page shows through while you adjust. Front: the four themes and A−/A+. Customize: font, line spacing, margins, page turn (decision 27), justify, Match Dark Mode, Book-mode shadow, Always show controls. These reading choices live only here, not in Settings. Unfolded, the panel covers the right page and the left page shows each change live.
    - **Built (step 12, 2026-11-02).** Unfolded and half open, the panel fills the right page from the fold to the column, with Customize shown below the front (there's room for both). Folded, it's a sheet along the bottom, only as tall as what it shows, with Customize one step in. **Opening and closing** (Adam, 2026-11-02): unfolded and half open the panel grows out of the Aa button and shrinks back into it, with a light spring; folded the sheet slides up from the bottom. The column stays up while a panel is open, with Aa lit (the bar goes, as it would run under the panel). Aa again closes it, back to the controls as they were; a tap on the page closes it and the controls together. **A ✕ on every panel** (Adam, 2026-11-04), at its top right in every posture, closes it as Aa does: folded, the page left to tap is small, and a tap meant to close Customize opened Contents. On a panel that scrolls, the ✕ stays put. A panel ends level with the progress bar, on the home indicator's safe area, and the bar is as wide as a panel, whatever the margins (Adam, 2026-11-04). Reduce Motion fades instead. Folding closes the book, panel and all. Text size steps 80–200%; line spacing is a menu, like Font and Page Turn: Book's (the book's own, and the default), then 1.2–1.8 (Adam, 2026-11-03; − and + gave no way back to Book's). Margins are decision 8's three. The themes other than Original set the page and text colours and clear the book's own backgrounds; Original keeps the book's colours on white. **The themes stay in the reader** (Adam, 2026-11-03): Home, the Library and Settings keep the system's light and dark, so opening a themed book still changes colour. Atkinson Hyperlegible and OpenDyslexic come later (`docs/PLAN.md`).
14. **Settings apply to every book**, not per book.
15. **Themes: Original, Paper, Sepia, Night.** Night follows the iPhone's Dark Mode; "Match Dark Mode" in Customize turns that off.
16. **Fonts:** the book's own font (default), New York, Georgia, Iowan Old Style, Palatino, Charter, SF Pro (all shipped with iOS), plus **Atkinson Hyperlegible and OpenDyslexic**, bundled. Adam signed off on their SIL Open Font License (2026-10-31); list them in `THIRD-PARTY-NOTICES.md` when they're added.

### Contents and bookmarks (approved 2026-10-31)

17. **One panel, two tabs.** The Contents button opens a glass panel with a Contents | Bookmarks switch. Contents opens scrolled to the current chapter, which is highlighted, with page numbers for the current layout. Bookmarks list the chapter, page and the page's first words; swipe to delete. Unfolded, the panel covers the right page like the text panel. The column's bookmark button toggles a ribbon at the top corner of the current page.
18. **Bookmarks on BookOrbit books sync with BookOrbit** (its bookmarks, keyed by CFI like positions), so they appear in its web reader and on other devices. Books from an OPDS server or imported from Files keep bookmarks on the iPhone.
    - **Built (step 12, 2026-11-02).** The panel opens like Text and theme: out of its button unfolded, a sheet up from the bottom folded (taller, as it holds a list). Choosing a chapter or a bookmark goes there and closes the panel and the controls. Contents marks the chapter the page is in, nested entries indented, each with the page it starts on as the footer counts. A bookmark marks where the page starts; the list shows its chapter, page and first words, in the book's order. The Bookmark button fills while the page holds one, and a tap on it again removes it. Bookmarks are kept on the iPhone and, for BookOrbit books, sent to BookOrbit at once (under the chapter's name, which its web reader lists); ones made elsewhere arrive when the book opens, and a change that couldn't reach the server goes with the next open.

### Search in book (approved 2026-10-31)

19. **Results by chapter, then step through.** The Search button opens a glass sheet: the search field, the match count and results grouped by chapter with their surrounding words. Tapping a result shows the page with the match highlighted and a small bar: ‹ 3 of 128 ›; tapping the count returns to the list, ✕ ends the search. foliate's built-in search supplies the matches, their excerpts and CFIs.
    - **Built (step 12, 2026-11-02).** The panel opens like the others: out of its button unfolded, a sheet folded, staying above the keyboard. It searches once typing pauses (two letters or more, or anything on Return), ignoring case and accents, and results arrive a chapter at a time, each with its page; it stops at 1,000 matches ("1,000+"). Reopening Search keeps the last search, scrolled to the match shown. The step bar sits under the page (under the right page of a spread, off the hinge) in the footer's place; ✕ clears the search. The matches come from foliate's matcher, but the bridge walks the book itself, so a match is named after its chapter, not its file (`docs/notes/reader-page.md`).

### Going back after a jump (Adam, 2026-11-04)

Decided with pictures in the planning session (no Figma frames). All three are built. The measurements are in `docs/notes/going-back.md` and `docs/notes/footnotes.md`.

33. **Any jump offers the way back, and your place holds until you settle.** Before this, a jump saved the page you landed on as your place and synced it about 2 s later, so a look at a map moved your other devices too.
    - **What starts it:** every jump: the scrubber, Contents, a bookmark, a search result or a link in the book. Not a page turn, a fold, a text size change, or Go on BookOrbit's capsule. A second jump keeps the same way back, to where you were before the first one.
    - **The button:** "Back to page 312" with ✕, in a glass capsule. It stays up with the controls hidden, since they go on the next tap. The number is the footer's.
    - **Where it sits:** at the bottom of the left page in every posture (over the blank strip and the column's button), in the chapter's place in the footer, so the page numbers stay. While the progress bar is up it sits just above the bar, half open above the bar's left piece. It goes while a panel is open, as the other capsules do.
    - **While you're away:** your place doesn't move, on this iPhone or on the server. You can bookmark as usual.
    - **What clears it:** Back, which returns to your place. ✕, which makes this page your place and syncs it. **5 page turns forward** from where you landed, which do the same: turning back doesn't count, and another jump starts the count again. Turning or scrubbing back onto your page. The 5 may change once it's been used on the Duo.
    - **A trip survives closing:** folding, Back, quitting or a crash, and the book reopens where you were looking, with the button still up (Adam, over forgetting the trip, and over closing counting as staying). It's kept on this iPhone only and never syncs. If another reader moves your place meanwhile, the trip ends and the book opens at the new place.
    - **The line shows the trip** (Adam's idea): while you're away the fill runs only from your place to where you are, in either direction, on the scrubber and on the book's screen, using the system slider's own neutral value. Half open it's the bar's left piece. Adam chose this over a dotted trail, which would mean building our own scrubber.
    - **The book's screen says where it opens:** "48% · Opens at 90%", in place of "Synced just now". So every place line still tells the truth. Home's and Search's rows keep showing your place.
    - **With BookOrbit's capsule, both show** (Adam, over one waiting for the other): stacked folded, with Back at the bottom and BookOrbit's capsule above it, covering about two lines until you answer; one under each page unfolded and half open. Back goes to your place and BookOrbit's capsule stays. Go goes to BookOrbit's place and ends the trip. BookOrbit's ✕ keeps your place, and the trip carries on. Back's ✕, or the fifth turn, makes this page your place and answers BookOrbit's capsule too, as reading on does.
    - **With Search's bar:** unfolded and half open, Back under the left page and the bar under the right. Folded there's room for one, so Back waits until the search ends with ✕: stepping through matches is common, and a stack could cover the match.
    - **Fixed-layout books:** the same, going back by the saved CFI, not by fraction. Their own fix is in (#56, `docs/notes/fixed-layout.md`).
    - **Built (2026-11-04).** `ReaderTrip`, `ReaderModel+Trip`. While you're zoomed in on a trip, the fill's start stays where your place sits on the whole line, until you let go. No right-to-left or fixed-layout book has been run through it, or VoiceOver.

34. **A footnote opens where you are, without leaving the page.**
    - **Where:** open (flat or half open), a glass card on the other page from its mark, level with it, so the sentence you're reading stays in view (Adam, over a pop-up by the mark and over a panel like Contents). Folded, along the bottom above the footer, or at the top if the mark is down there.
    - **What it holds:** the whole note, however many paragraphs, in your font, size and theme, with **Go to Note** and **✕** (Adam, over no ✕). A long note grows to the height of the page, then scrolls.
    - **Closing:** ✕ or a tap anywhere else, which doesn't turn the page. A swipe closes it and turns.
    - **It isn't a jump:** your place stays and there's no Back button. Go to Note is a jump, so it opens the note where it sits in the book, with "Back to page 876" (decision 33).
    - **Which links:** the ones a book marks as notes, and unmarked ones that look like a note's mark, to be tuned on real books. Any other link is a jump. A tap near a tiny mark counts, so a near miss doesn't turn the page.
    - **Built (2026-11-05).** `ReaderNote`, `ReaderNoteCard`, `ReaderModel+Notes`, the bridge's `noteAt`, checked with real taps and swipes on Standard Ebooks' *The Count of Monte Cristo* and Project Gutenberg's *Olaudah Equiano* (`docs/notes/footnotes.md`). Open, the note's text is level with its mark; a mark too near the top puts the card at the top of the page. The buttons sit along the card's top, Go to Note on the left and ✕ on the right, as a panel's do, and stay put while a long note scrolls. The way back and BookOrbit's capsule go while a note is open. A note with a picture or a table is a jump, as the card only draws text. A book's own embedded font isn't known outside the page, so the card uses the font it falls back to. No right-to-left or fixed-layout book, or one in another format with notes, has been run through it, or VoiceOver.

35. **Chapter buttons beside the chapter's name, and a scrubber that zooms.**
    - **Where:** ⏮ and ⏭ either side of the chapter's name on the progress bar, so the scrubber keeps its full width (Adam, over beside the scrubber and over a swipe on the page). Half open, in the left piece. Normal-sized targets: Adam caught that being beside the name doesn't make them smaller. The bar stays up, so you can keep tapping.
    - **⏮:** partway through a chapter, to its first page; on the first page, to the chapter before, as in a music player (Adam, over always the chapter before). **⏭:** the next chapter's first page.
    - **A chapter** is any entry in the book's Contents, so a "Part Two" page counts. A button dims when there's nowhere to go, and neither shows for a book with no Contents.
    - **Skipping is a jump:** "Back to page 878" appears (decision 33).
    - **A tick you feel** as the scrubber passes each chapter (Adam). Only a real Duo can check it.
    - **Hold still to zoom** (Adam's idea, kept after a test build on his Duo, over slowing down, dragging up off the bar, a second line and no zoom):
      - **Across the whole book** the knob moves freely, with dots at chapters, kept at least 6 pt apart.
      - **Hold still for a moment** and, with a tick, the line zooms in around your finger. Each dot is now a page, about 8 pt apart, and chapter starts are ink bars that catch the knob with a tick, 3 pt either side.
      - **At the zoomed line's ends** it slides on through the book. **A quick move** zooms back out, and so does letting go.
      - **Letting go** lands on that page, or on a bar, that chapter's first page.
      - The pause (0.35 s), the 8 pt and how quick a move has to be can still change on the Duo.
    - **Detents that were turned down:** iOS's own, which are hard and keep you from pages inside a chapter, and a soft catch across the whole book, which takes 80% or more of the track in a book of 38 chapters or more. Zoomed in, chapters are far enough apart for a catch (`docs/notes/going-back.md`).
    - **Built (2026-11-04).** `ReaderChapterSkip`, `ReaderScrubber`, `ReaderScrubberLine`. No book with nested contents has been run through the buttons since Adam's three went from scratch, nor a fixed-layout book.

### More than one server (Adam, 2026-11-05)

Decided with screenshots of the real app running a throwaway prototype (no Figma frames). With one server, nothing below shows: the Library's title stays "Library", no book names its server, and Search lists 12 books.

36. **Each server is its own library; Home and Search cover them all.**
    - **Library: a menu in the title** (Adam, over a shelf for each server). The title is the chosen server's name with a chevron, in Ink. The menu lists the servers, with a check on the chosen one, then **Add a server**. The chosen server is remembered. That server's shelves are as they were, with On iPhone last. It doesn't open a list of servers first, so a shelf stays one tap away.
    - **Home: the name on every book** (over grouping under each server, and over a name only when the same book is in progress twice). Books in progress from every server and the iPhone, most recent first. The place line reads "14% · BookOrbit", on the current book and on the rows, with no taller rows. Imported books and the sample book have no name.
    - **The same book on two servers shows twice,** each with its own server's name and its own place. A position belongs to a file, and OPDS can't tell editions apart.
    - **Search: every server, always, with a section for each** (Adam asked for cross-library search; over one list with the name on each book). Each section's heading is the server's name, then its first three books and "All 9 books", then its Series and Authors. A section fills in when its server answers, so a slow server doesn't move the rest. Unfolded, one server per page, and a third carries on down the right page. Books only imported from Files come last, under On iPhone.
    - **Before typing,** Recent as before, and "Browse BookOrbit" and "Browse Calibre-Web", each with its own lists.
    - **In a server's Search section, a problem says so in place:** "Can't reach Calibre-Web." · Try again, and "Calibre-Web doesn't offer search."
    - **Settings: Servers,** each row its name over "address · account", with **Add a server** under them. Unfolded, the list on the left and the chosen server's page on the right, as before.
    - **Your own name for a server, kept on the iPhone** (Adam, asked for during this session). A **Name** row at the top of the server's page, tap to change, and an optional **Name** field under Address when adding it (Adam, over only the page), showing the server's own name as its placeholder where that's known. Left empty, it's the server's own name, and a second "Calibre-Web" becomes "Calibre-Web 2". Everything that names a server uses it: the menu, the labels, the headings, the banners, From in a book's details, and BookOrbit's capsule in the reader.
    - **Adding:** Add a server, in Settings or the menu, opens the server choices. You land on the new server's Library. The same address and account twice says "You've already added this server." under the fields. **No limit** on the number of servers.
    - **Removing:** today's alert and choices, for that server only (decision 24). The Library moves to the next server. Removing the last one is as it was: setup, or Home with the books still on the iPhone.
    - **One server's problem** (over both showing on Home). **Signed out** needs you, so it shows on Home and in the Library for that server, one banner per server, and Sign in opens Sign in again for that server and comes back. **Can't reach** shows only in the Library for that server and in its Search section: with a server at home and one on the internet, Home would nag every time you're out. With one server, as before.
    - **Sync: a book's place goes to the server it came from.** BookOrbit's books sync with their BookOrbit server. OPDS and imported books keep their place on this iPhone. BookOrbit can't hold a place for a book that isn't on it, and two copies can't share one. iCloud and KOReader sync come later, as separate tasks (Adam).
    - **The tour's Add books,** on a replay with a server connected, opens the server choices instead of the Files picker, since a new server no longer replaces the old one. This changes decision 30's note.

### Settings (approved 2026-10-31)

24. **A lean Settings tab** (redone with Adam on 2026-11-02, under Settings in the library pass above; Settings is a button, not a tab):
    - **Server:** the server (address, account), reading-progress status; its page has Sign out and Remove server.
    - **Storage:** Books on iPhone (count and size), where downloads can be removed.
    - **Show the tour** (decision 30), above About.
    - **About:** version, source code and licences.
    - Reading choices are not repeated here; they live in the reader's Customize panel (decision 13).
    - **Removing the server asks what to do with its downloaded books:** "Remove BookOrbit? Its 12 downloaded books use 48 MB." · Keep books on iPhone · Remove books too · Cancel. Imported books and the sample book are never affected.
    - **Unfolded:** the list left of the hinge, the chosen page right of it (panes shift as in the Library).

## v1 scope (approved 2026-10-31)

The goal for v1: read your servers' books well on the Duo.

| | v1 | Later |
|---|---|---|
| Sources | BookOrbit and OPDS servers, as many as you add (decision 36), Import from Files | |
| Progress sync | BookOrbit, for its own books | iCloud, KOReader sync (separate tasks; Adam, 2026-11-05) |
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
| Where reading progress syncs | Designed (frame 39) |
| Home, folded and unfolded | Designed (frames 01, 38) |
| Library, folded and unfolded, with chips | Designed (frames 02, 04) |
| Collections, Series, Authors lists (chip drill-ins) | Designed (frames 29–33) |
| Book cover page, folded and unfolded | Designed (frames 03, 04) |
| Book details (swipe up from the cover; Mark as finished, download) | Designed (frames 15, 16) |
| Search tab and results | Designed (frames 17–20) |
| Reader: one page folded, spread unfolded, book mode, controls shown | Designed (frames 07, 08, 09, 14) |
| Contents and bookmarks | Designed (frames 12, 40) |
| Text and theme panel (font, size, spacing, margins, theme, Always show controls) | Designed (frames 10, 11) |
| Search in book | Designed (frames 13, 41) |
| Settings | Designed (frames 34–37), built in step 14 |
| Empty and error states (no server yet, server unreachable, signed out, sign-in failed, download failed, offline) | Designed (frames 21–26, 42; sample-book row on frame 05) |

Import from Files uses the system document picker; no screen of our own.

## Mockups

Figma: [Octavo-UX](https://www.figma.com/design/ElJJ7OtF8LOuX6dc68qZ23/Octavo-UX), built 2026-10-31 on Apple's iOS and iPadOS 27 kit (`iPhone Duo/Standard/Outer - Portrait` and `Inner - Landscape`, `Tab Bar - iPhone Duo`, Liquid Glass buttons, rows, text fields, kit text styles and colour variables). Covers are the public-domain sample books.

- **Pages by area:** Cover, 1 · Setup, 2 · Home and Library, 3 · Book, 4 · Reader, 5 · Search, 6 · Settings and states, Components, Parked. Sections inside each page group the frames (Folded / Unfolded, or Reading / Panels).
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
| 29 Collections · folded | Collections chip: list with covers and counts |
| 30 Collection · Classics · folded | A collection's books |
| 31 Authors · folded | A–Z with an index strip |
| 32 Series · Sherlock Holmes · folded | Reading order, numbered (books 2–3 are stand-in covers) |
| 33 Collections · unfolded | List left of the hinge, the collection's books right |
| 34 Settings · folded | Server, Storage, About |
| 35 Server · folded | Address, account, sync status, Sign out, Remove server |
| 36 Remove server · folded | Keep books on iPhone / Remove books too / Cancel |
| 37 Settings · unfolded | List left of the hinge, server page right |
| 38 Home · unfolded | Home left of the hinge, the current book's cover page right |
| 39 Reading progress · folded | The sync step after BookOrbit sign-in |
| 40 Bookmarks · folded | The Bookmarks tab of the Contents panel |
| 41 Search in book · results · folded | Matches grouped by chapter |
| 42 Downloading · folded | Cover strip: Downloading · 42% · Cancel |

The reader frames (second row) set the book text in Charis SIL as a stand-in for the book's own font; Figma has none of the iOS book fonts.

Local components in the file: `Book Cover / …` (one per sample book), `Row / Continue reading` (progress set by the Progress frame's right padding), `Chip` (selected / unselected), `Reader controls (column)` (Back, Contents, Text and theme, Search in book, Bookmark), `Reader progress bar`, `Book sheet` (State = Compact / Expanded, with Place and Synced text properties) used by frames 03, 04, 15, 16, 20, 23 and 24, `Banner` (Kind = Warning / Info, with Message and Action), and `Row / Collection` (three covers, Name, Count).

What the kit showed:
- Apple's Duo layout puts toolbar buttons (including back) in a glass group under the vertical status bar, and the tab bar at the bottom of the same column.
- The kit's `Tab Bar - iPhone Duo` has a "Search Role" type that puts Search in its own glass button at the very bottom of the column; adopted (decision 2) and used in the frames.
- The kit's Large Title toolbar renders its title mirrored in Figma, so the frames draw the large title as content instead.

## Open questions

None right now; new questions go here as they come up.

## Needs engineering

Spikes before building: MOBI/AZW3/FB2 through foliate, the bridge and the CSP (decides the amber formats); SwiftUI `TabView` on the Duo (done, `docs/notes/duo-tabbar.md`); the fold cross-fade with batched re-layouts; book-mode posture detection. **No new foliate patch** is needed for these decisions (decision 8 works with foliate's own gap and the bridge's insets); patches 0001 and 0002 stay. The duo-spreads §8 risk still applies: after an unfold the synced position is the spread's start.

- **Network trust (decision 25): a thorough security review before it merges** (Adam's requirement, 2026-10-31). In scope: the http allowlist and its host parsing, name resolution and the per-connection re-check, certificate trust and pinning, and how passwords and BookOrbit tokens are handled on http. Also confirm the App Transport Security configuration that allows home-network IP addresses, and the App Review justification it needs.

- **Tabs in the trailing column.** Checked (#6, `docs/notes/duo-tabbar.md`): SwiftUI's `TabView` puts the tab bar at the bottom of the trailing column folded, unfolded and half open, over a full-screen cover and below column controls, with Search inside the same capsule (decision 2). The system doesn't split screens at the hinge; the app shell does.
- **Library chips from an OPDS feed.** Map the root feed's navigation entries and facets to chips, and decide what happens when a feed has many entries or none.
- **Pull the synced position while the cover shows.** Start the `ProgressSync` pull when the cover page appears, so unfolding opens the reader at once instead of waiting up to the 5 s pull timeout (duo-spreads §6). Done in step 13 (`BookPlaces`, `docs/notes/sync-in-app.md`).
- **Full-screen cover.** The cover runs under the trailing system column and the camera; the tab column and back button sit over the artwork, so they need a material that reads on any cover. Done in #14: nothing is drawn behind the column, because the system's own glass capsules (clock, Back, tabs) read on light, dark and busy covers (Adam chose this over a material strip or a dark scrim, 2026-11-01).
- **Page area (decision 8).** Lay out the `foliate-view` with the bridge's left/right insets so the page never reaches the column, map the margin setting onto foliate's gap, and keep the hinge gutter at least the reserved region's width. Done in #17 (`docs/notes/reader-page.md`).
- **Fold cross-fade (decision 11).** Show a `WebView` snapshot over the transition and fade it out once the layout settles; also batch the hinge, resize, layout and fold-region inputs into one re-layout (duo-spreads §5 counts 10–13 today).
- **Sample book.** Bundle the Standard Ebooks Pride and Prejudice and re-run the blank-page and fold checks on it (the spike's Gutenberg edition had the blank page after the dedication). Done in step 15 (`docs/notes/other-ways-in.md`).
- **Page turns (decision 27).** foliate's paginator slides a turn itself (its `animated` attribute), but not across a section break. The flip is ours, drawn from snapshots of the page over the web view, so the next page has to be ready the moment a finger lands. Measure that on a real Duo (snapshot time, turning foliate under a snapshot) before building the flip. Measured on the simulator and built (2026-11-03, `docs/notes/page-turns.md`): snapshots take 2–5 ms and the next page is drawn 20–70 ms after a turn; still to check on a real Duo.
- **The tour (decisions 29 and 30).** The card is SwiftUI over the reader, never inside the book's page. Each step waits for the reader's own events (a turn, the controls, the Text and theme panel), and the posture at launch comes from the hinge (`onHingeChange` fires once on appear). Continue without closing reuses decision 28's opening. A tour replayed from Settings opens the sample book at its start without saving its place.
- **Book mode (decision 9).** Detect the half-open range from `onHingeChange`, swap the tap zones, and draw the spine shadow as an overlay outside the book's content.
- **Unfold on the cover → reader.** The spike's handoff already does this from its book screen (about 20 ms). It must compare old and new hinge status, not react to repeated or on-appear callbacks. Done in #14: `ShellModel.hingeChanged` → `BookOpener`, which downloads the book first if it isn't on the iPhone.
