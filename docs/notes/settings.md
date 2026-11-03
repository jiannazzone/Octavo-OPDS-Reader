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
- **Remove server** (`ShellModel.removeServer(removingBooks:)`), in order: the sign-out above; `ServerCredentials.removeAll(serverID:)` (tokens, password, certificate pin, catalog secret, each tried even if another fails); every download still running is cancelled and leaves no file; the downloads (`serverDownloads`, every book that wasn't imported, since v1 has one server and a file is kept by its book's ID alone, so a book kept from a server removed before shows as downloaded on the one added since). The server's Books on iPhone records go, except the kept books' (some known only from Continue reading, so they're recorded), which Storage keeps listing; with "Remove books too" the files and all its records go. Then the records that can't open without the server (Continue reading, finished marks), its unsent places (`BookPlaces.forget(server:)`), `RemovedServer.json`, `Server.json`, and `LibraryModel.disconnect()`, which shows setup.
- **The next server** (`ShellModel.forgetRemovedServer`, on connect): `RemovedServer.json` holds the removed server's identity (`LibraryServer.identity`: its kind, its full saved address with scheme, port and path, and the account; two servers behind one proxy differ by path). A catalog whose address carries a key (Kavita) never counts as the same server again, since two accounts differ only by their keys and nothing derived from a key is kept outside the Keychain. BookOrbit numbers files from 1 on every server, so another server's book 17 would otherwise find the removed one's file, place and bookmarks, and send that place and those bookmarks to the wrong server. The same server and account coming back (at a new ID) finds its books, places and bookmarks; any other server, or another account, finds none: the removed server's downloads, places, bookmarks and records are deleted then. Imported books are never touched.
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

## Security review (2026-11-02)

An independent review of the Sign out and Remove server path (tokens, Keychain, the logout request, removal order, debug code). Nothing High. **Adam signed it off on 2026-11-02**, with the fixes below.

| # | Severity | Finding | Now |
|---|---|---|---|
| 1 | Medium | Kept books (the default) were taken for another BookOrbit server's books of the same file number: shown as downloaded, opened at the old place, the old server's unsent place and bookmarks sent to the new one | Fixed: `RemovedServer` (above). The full fix, a server in the storage key, waits for a second server |
| 2 | Medium | Remove books too missed downloads still running, which then landed (and could open the reader over setup); a cancel just after the file landed left it | Fixed: `BookOpener.cancelAll`, the shell's pending opens cleared, a file that lands after a cancel is deleted |
| 3 | Low | A refresh in flight during Sign out might leave the session alive on the server | Measured on v3.6.0: logout with the token a refresh just replaced still ends the session (the new refresh and access tokens get 401). No change |
| 4 | Low | Keychain failures: `removeAll` stopped at the first failing item; an OPDS password delete failure kept it in memory; errors are swallowed | `removeAll` tries every item; OPDS sign-out clears memory even if the Keychain can't be. Errors still aren't shown: step 16's launch sweep deletes what's left (`KeychainSweep`, `docs/notes/network-trust.md`) |
| 5 | Low | The logout could be suspended as the app leaves, and `timeoutInterval` doesn't bound the whole request | Fixed: it runs under an expiring activity with a 15 s deadline for the whole request |
| 6 | Low | Records of the server's books without files stayed after Remove books too; places and bookmarks stay | Fixed for the records. Places and bookmarks stay for the same server's return and go when another server is added |
| 7 | Info | Home could ask the old server's source for the new root's list after a switch | Fixed: checked again after the root loads |
| 8 | Info | Test gaps | Added: sign-out during an OPDS password load, a different server after Remove, a running download. The shell's BookOrbit and OPDS branches run only against the stub source in app tests |
| — | Medium (automated check) | The identity was the shown address (host and port) and account, so two BookOrbits behind one proxy, or two Kavita accounts, counted as one | Fixed: kind, full address and account; a catalog with a key never matches (a second automated check flagged a digest of the key written to `RemovedServer.json`, so nothing key-derived is kept). A server reinstalled at the same address with the same account still counts as the same |
| 9 | Info | Kavita's API key, part of the catalog address, can't be revoked from the app; the page's signed-out state follows the banner, which Retry clears until the next failure | Adam (step 16): no extra line in the Remove alert. The key is deleted from the iPhone; like a password it stays valid on the server |

## Tests

- App: `SettingsTests.swift` (navigation folded and unfolded, Back, Remove server keeping and removing books, imported books untouched, kept books staying listed, another server or account finding none of the removed one's books, the same one finding them, a running download stopping, the alert's wording, Sign out, the sort orders and summaries, the notices parser and the bundled file), `BookPlacesTests.countsAndForgetsAServersPendingPlaces`, `BookOpenerTests.removingAllDownloadsEmptiesTheStore`.
- OctavoKit: `BookOrbitAuthTests.signOutEverywhere…` (ends the session with the refresh token, as a cookie before 3.0, signs out here whatever the server says, sends nothing without a session), `OPDSSourceTests.signOutForgetsThePassword` and `signOutDuringAPasswordLoadWins`.
- Running the app tests signs the simulator's app out (`KeychainTests`, as in step 13).

## Not done (follow-ups)

- A Keychain error during Sign out or Remove server is still swallowed, but no longer lasts: step 16's launch sweep deletes a removed server's secrets, and Sign out notes `signedOut` in `Server.json` first, so the next launch deletes a sign-in the Keychain kept (`docs/notes/network-trust.md`, step 16).
- The storage key is the file's ID alone (`StoredBookFiles`): a second server at once needs the server in it, with a migration of downloads, places and bookmarks.
- Downloads made before `BooksOnIPhone` existed and since dropped from Continue reading aren't listed in Storage (nothing names them); Remove all downloads still deletes them. Only old development installs have them.
- Step 15's bundled sample book must stay out of `serverDownloads` (today only imported books, `LibrarySourceID.files`, are excluded).
