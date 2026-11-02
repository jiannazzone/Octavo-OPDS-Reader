# Settings (step 14)

Step 14 of `docs/PLAN.md`, built 2026-11-02. Settings replaces the stand-in that opened from the gear at the top of the side column: the server and its page (Sign out, Remove server), Library's one switch, Books on iPhone, and About. The design questions were decided with Adam from picture mockups (`docs/design/direction.md`, Settings in the library pass). Screenshots are in `settings/`.

## What it looks like

- **The list** (frame 34, without its Reading progress row): Server (the name over "address · account"), Library (Titles under covers, moved from the stand-in), Storage (Books on iPhone "12 · 48 MB", or "None"), About (Version "0.1 (1)", Source code ↗ opening GitHub in Safari, Licences ›, and "Octavo is free software under the Mozilla Public License 2.0."). The debug sections stay at the bottom in debug builds.
- **Unfolded: the list on the left page, the chosen page on the right** (frame 37). Settings opens with the server's page there; a tap on the left changes the right page without a slide, and the chosen row is tinted. Folded, the list and each page are screens of their own. A fold keeps the page that was chosen on top (Back then shows the list). Back, or a swipe from the edge, leaves Settings in one step when unfolded.
- **The server's page** (frame 35): Address, Account, Reading progress, then Sign out and Remove server. Reading progress says Synced; Not synced yet with "N books pending." under it; or Paused with "Sign in again to sync." when signed out, where Sign out becomes Sign in (the Sign in again screen). An OPDS catalog has no Reading progress row, as a book's place line shows nothing for it, and no Sign out unless it has a password.
- **Sign out** asks first ("Sign out of BookOrbit?" / "Your downloaded books stay on this iPhone. Reading progress syncs again once you sign in." · Sign out · Cancel; a catalog's message has only the first sentence). The server stays; the tabs show the signed-out banner, reworded for both causes: "Signed out of BookOrbit. Reading still works; sync is paused." The Sign in again screen starts the same way.
- **Remove server** (frame 36): "Remove BookOrbit?" / "Its 12 downloaded books use 48 MB. Remove them too, or keep them on this iPhone?" · Keep books on iPhone (the default) · Remove books too · Cancel. Without downloads: "You can add it again any time." · Remove · Cancel. Then setup, as on a new install.
- **Books on iPhone**: "5 books · 4.4 MB" over the books (cover, title, author, size), with a sort menu at the header's right (Size, Title, Author by last name, Recently downloaded; remembered, Size first). A swipe removes one, keeping its place, as the details' Remove download does; Remove all downloads asks first ("Remove all downloads?" / "5 books · 4.4 MB. Your places in them are kept."). Empty: "No books on iPhone" / "Books you download show here." Rows open nothing.
- **Licences**: Octavo's line, then each component from `THIRD-PARTY-NOTICES.md` (bundled with the app) with its licence and full text, the 80-column lines joined back into paragraphs.

## How it works

- **Routes.** `.settings` and `.settingsPage(SettingsPage)` (`server`, `storage`, `licences`). `SettingsScreen` lays either out: folded, the list or the page; unfolded, both. `ShellModel.openSettingsPage(_:twoPages:)` pushes folded and replaces the top page unfolded (no animation). `ShellModel.back(_:twoPages:)` pops the page and the list together unfolded, which the Back button and the edge swipe both use. `ScreenStack` hides the list's own screen while its page covers it unfolded, so a swipe uncovers the tab. Every screen now fills the spread, so `fillsSpread` is gone.
- **Titles.** Settings draws a title on each page with `ScreenTitle`, the view `ScreenFrame` now uses for every screen's title.
- **The server's details** come from `LibraryServer` (`address`, `username`, `signsIn`; `detail` is made from them). Sign in again updates the account shown.
- **Sync status.** `BookPlaces.pendingCount(on:)`: the books on that server in `UnsentPlaces` whose saved place still needs a push.
- **Sign out** (`ShellModel.signOut`): shows the banner at once, then BookOrbit's `BookOrbitClient.signOutEverywhere()` forgets the tokens (memory and Keychain, dropping a refresh in flight) and then sends `POST auth/logout {refreshToken}` (the refresh cookie before 3.0) through the server's `ServerTransport`, without waiting for it (15 s timeout; a failure leaves the session to lapse on the server). Measured on v3.6.0: that revokes the session, so the refresh and access tokens both get 401; a bearer-only logout with no body revokes nothing. An OPDS catalog's `OPDSSource.signOut()` deletes the password from the Keychain and from the client's in-memory cache; a load still reading the store can't put it back (`CredentialCache.generation`).
- **Remove server** (`ShellModel.removeServer(removingBooks:)`), in order: the sign-out above; `ServerCredentials.removeAll(serverID:)` (tokens, password, certificate pin, catalog secret); the downloads (`serverDownloads`, every book that wasn't imported, since v1 has one server and a file is kept by its book's ID alone, so a book kept from a server removed before shows as downloaded on the one added since). With "Keep", each kept book gets a Books on iPhone record so Storage still lists it; with "Remove books too", its file and that record go. Then the records that can't open without the server (Continue reading, finished marks), its unsent places (`BookPlaces.forget(server:)`), `Server.json`, and `LibraryModel.disconnect()`, which shows setup. Reading positions and bookmarks stay on the iPhone (they're keyed by file), so a book opens where it was if the server comes back.
- **A server's late answers are dropped.** `LibraryModel` ignores roots, Home lists and errors that arrive after another connect or disconnect (`connection`), so the old server's failure (signed out, after Remove server) can't show its banner on the new one. Found when a debug connect followed a saved server whose tokens a test run had wiped.

## Checked on the simulator

`iPhone Duo` (8C35AF6E-5F3F-48D7-A283-AEE894511947), local BookOrbit v3.6.0 and the local OPDS servers.

| # | What | Result |
|---|---|---|
| 01 | Settings folded | Server, Library, Storage, About as approved |
| 02 | Unfolded | List left of the hinge with the server chosen, the server's page right |
| 03 | Books on iPhone tapped unfolded | Right page changed in place, row tinted, sizes largest first |
| 04 | Sorted by Author, half open | Austen, Carroll, Doyle, Melville, Shelley, Wells; same split half open |
| 05 | Folded again | Books on iPhone on top; Back showed the list |
| 06 | Licences unfolded | Each component one block, full text |
| — | Back and edge swipe unfolded | Straight to Home |
| 07 | Sign out | Alert, then Paused + Sign in; Home banner "Signed out of BookOrbit…". BookOrbit's `auth_sessions` row for "Octavo (debug)" got `revoked_at` the same second |
| — | Sign in from the page (saved server) | Sign in again screen, back to the page, Synced |
| 08 | Remove server, Keep | Frame 36's alert; session revoked; files kept; unsent places cleared; setup shown |
| — | Remove server, no downloads | "You can add it again any time." · Remove · Cancel |
| — | Remove server, Remove books too | Its files deleted; Storage then empty (10) |
| 09 | Calibre-Web and COPS | No Reading progress row; Sign out only for Calibre-Web (password) |
| 11 | Calibre-Web Sign out | Alert without the sync sentence; Sign in in its place |
| — | Swipe a book in Storage | Removed, total updated |

## Tests

- App: `SettingsTests.swift` (navigation folded and unfolded, Back, Remove server keeping and removing books, imported books untouched, kept books staying listed, the alert's wording, Sign out, the sort orders and summaries, the notices parser and the bundled file), `BookPlacesTests.countsAndForgetsAServersPendingPlaces`, `BookOpenerTests.removingAllDownloadsEmptiesTheStore`.
- OctavoKit: `BookOrbitAuthTests.signOutEverywhere…` (ends the session with the refresh token, as a cookie before 3.0, signs out here whatever the server says, sends nothing without a session) and `OPDSSourceTests.signOutForgetsThePassword`.
- Running the app tests signs the simulator's app out (`KeychainTests`, as in step 13).

## Not done (follow-ups)

- A Keychain error during Remove server is swallowed, so a secret could stay until a reinstall; the launch clean-up planned in step 16 would cover it.
- Downloads made before `BooksOnIPhone` existed and since dropped from Continue reading aren't listed in Storage (nothing names them); Remove all downloads still deletes them. Only old development installs have them.
- Step 15's bundled sample book must stay out of `serverDownloads` (today only imported books, `LibrarySourceID.files`, are excluded).
