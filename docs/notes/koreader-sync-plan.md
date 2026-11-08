# KOReader sync: implementation plan

Written 2026-11-06 for after launch, from the measurements in `docs/notes/koreader-sync.md`; built 2026-11-08, chunk by chunk below. Read that note first.

**Scope:** one KOReader account in Settings, for EPUBs from Files and from each OPDS catalog switched on for it (question 2). BookOrbit keeps its own sync. Kavita and Komga are plain OPDS: nothing is built for them, and they aren't promised or tested. MOBI, AZW3 and FB2 stay on the iPhone.

**Rules:** no KOReader or BookOrbit code gets copied (AGPL). Every request goes through `ServerTransport`. Secrets go in the Keychain. UI wording and UX go to Adam first. Don't push without his OK. Network-trust code needs a security review he signs off before merge.

## Chunk 0: test on real KOReader (the gate)

**Done 2026-11-08 on the sample books: go.** Results and the counting rules are in `docs/notes/koreader-sync.md` ("On real KOReader"); `docs/notes/koreader-sync/tools/run.sh` re-runs it. Decided from it (technical): Octavo **writes paragraph-level places** (`…/p[9].0`, 150/150), not word level (149/150). A word-level place that doesn't resolve sends the other device to page 1, and a paragraph costs at most part of a page. It **reads word level**, falling back to the paragraph when the words don't resolve. Revisit writing word level after the modern books.

**Still open before chunk 2:** the same run on two or three of Adam's modern EPUBs, kept off the repo. The plan was:

Against KOReader's release build, or a device, on the five sample books and a couple of his modern EPUBs (never committed):

1. What it does with an empty string, a garbage string and a missing element in `progress`: stay, or go to the start?
2. Which path form it writes and accepts: `[1]` on first siblings (DOM 20260812 always writes it), `.0` endings, `/text().N` and `/text()[2].N`, and elements a browser doesn't see (`autoBoxing`, `floatBox`).
3. Whether a path built from the browser's DOM lands on the same words. Try element-only first, as Kavita stores them, and text offsets only if that's too coarse. 30 places per book, both ways, like the BookOrbit check (31/31).
4. How far KOReader's percentage is from foliate's at the same words.

**Done when:** a go or no-go, plus the path format to write. On no-go, stop and go back to Adam.

## Chunk 1: protocol (OctavoKit, no UI)

**Done 2026-11-08.** `Sync/KOSyncClient.swift` (with `KOSyncKey`, `KOSyncProgress`, `KOSyncError`), `Sync/KOSyncDocument.swift`, `dev/kosync/`, and tests: `KOSyncClientTests`, `KOSyncDocumentTests`, `KOSyncLiveTests` (5/5 against `dev/kosync`). Also from chunk 6's list, since the client needs it: `ServerTransport.credentialHeaders` drops `x-auth-user` and `x-auth-key` on a redirect to another server, tested (`redirectsToAnotherHostLoseAKOReaderAccount`, which fails without it). It's network-trust code, so it's in the review Adam signs off. As planned:

- `Sync/KOSyncClient.swift`: `authorize()`, `progress(document:)`, `update(...)`. `Accept: application/vnd.koreader.v1+json` on every call. Takes any `HTTPTransport`.
- Tolerant reading: unknown document (200 `{}`, 400, 404), `timestamp` as number, string or negative, `percentage` missing or out of 0...1. Ignore PUT bodies; only 200 counts. Errors sort into temporary (offline, 5xx) and permanent (401, or a refused document), so a permanent one can stop retrying.
- `Sync/KOSyncDocument.swift`: the partial MD5, from `docs/notes/koreader-sync.md` (`Insecure.MD5`, CryptoKit), read off the main actor. Lowercase hex.
- Credentials: `KOSyncKey` (username, MD5 hex of the password) that never prints the key, like `PasswordCredentials`. The password itself is never kept.
- `dev/kosync/`: compose file on 127.0.0.1:3350 (plain) and 3351 (self-signed), registration on, seed script, README. Runs the published image only.
- Tests: `Tests/OctavoKitTests/Sync/KOSyncClientTests`, with every shape from the note's table. `KOSyncDocumentTests`, with files under 1 KiB, between samples, and exactly on a sample's edge, plus Kavita's stored hash for a sample book. `KOSyncLiveTests` behind `OCTAVO_KOSYNC_LIVE=1`.

## Chunk 2: positions (bridge and model)

**Done 2026-11-08, on the sample books.** `bridge.js` `xpointerOf`, `resolveXPointer` and `xpointerAt`. `open` takes `xpointer` and `koreaderPlaces`. Relocations carry `xpointer`, and so does `ReadingPosition`. `ProgressSync.wantsXPointers` (off by default, forwarded by `SharedProgressSync` and `DebugProgressSync`) switches it on for an EPUB. Tests: `ReaderXPointerTests` (28 cases in a real web view). Against real KOReader through the bridge itself (`tools/bridge-check.sh`): Octavo → KOReader 149/150, KOReader → Octavo 1,016/1,021, where every miss is a cover or a table's spacing (`docs/notes/koreader-sync.md`). The modern EPUBs are still to run through `run.sh` and `bridge-check.sh`. As planned:

- `ReadingPosition.xpointer: String?`. Optional, so saved files still read.
- `ReaderWeb/bridge.js`, inside the file so the CSP doesn't change:
  - `xpointerOf(index, range)`: the paragraph (the range's nearest block element) as `…/p[9].0`, with the element rule from the note. `onRelocate` adds it to its message for reflowing books only, when the open options ask for it.
  - `resolveXPointer(string)`: `{cfi, fraction, chapter}` or `null`. Parse with a strict regex (offset optional, `[1]` optional) and walk the DOM by hand; never give the string to `document.evaluate`. Count text nodes and offsets by the note's rules, and convert offsets to UTF-16. Load an unopened section the way `describePlace` does. Words that don't resolve fall back to their element; a missing element gives `null`, never a guess.
- `open` takes `xpointer`. If it doesn't resolve, it's the fraction, then the local place.
- No foliate patch.
- Tests: round trip in the real web view, in `OctavoTests`, as the reader's other bridge tests do. A check script in `docs/notes/koreader-sync/tools/` over the sample books through `ReaderRemote`.

## Chunk 3: the rule

**Done 2026-11-08.** As built, which differs from the plan below in three places:

- **`SyncedPosition.origin`:** `.exact` (BookOrbit, the default) or `.elsewhere(Change)`, where `Change` is `.first`, `.unchanged` or `.moved`.
- **`OpeningPosition.choose` for `.elsewhere`:** with no local place it opens there (at the start if the place has neither an xpointer nor a percentage). Otherwise it opens there only if the place `.moved`, is ahead (`isAhead`: a later spine item, else `aheadMargin`, 1 point, further in the same one) and nothing is unsent. Everything else opens locally, for the reader to offer. **Differs:** the "same section, no timestamp" row went. `isAhead` already keeps a section-start place from moving you back, and Komga is plain OPDS now.
- **`OpeningPosition.mayPush`:** the book's screen and `retryUnsent` send an unsent place only over a KOReader place this iPhone has seen (`.unchanged`). `BookPlaces.pushUnsent` uses it, and BookOrbit's behaviour is unchanged.
- **`Sync/KOSync.swift`:** `KOSync` (one per book, reading its file's document when needed) and `KOSyncPlaces` (one per account, a file named by a digest, so Kavita's key in an address isn't written; `forget()` for sign-out). **Differs:** the baseline isn't recorded at the first pull, or the screen would later push over a place nobody saw. It's recorded when a push is read back, or when the reader adopts the place (`ProgressSync.adopted`, called in chunk 4). The very start (percentage 0) is no place: Kavita answers that for a book never read.
- **The first push since launch** asks the server first, and an unseen place throws `KOSyncError.serverMoved`, a temporary error that leaves the place unsent. **Differs:** later pushes don't ask. Reading on past an offered place keeps yours, as with BookOrbit's capsule.
- **Tests:** `OpeningPositionElsewhereTests`, `KOSyncTests` (against a server that rewrites places as Kavita does), one more in `KOSyncLiveTests`, and two in `BookPlacesTests`.
- **Left for chunk 4:** `ReaderModel.didOpen` still pushes an unsent local place when it opens. It has to use `mayPush` as the screen does, call `adopted` when it opens at, or goes to, a KOReader place, and offer `.first` and `.moved` places in the capsule.

As planned:

`OpeningPosition.choose` stays as it is for BookOrbit. It trusts the server, which is wrong here.

- `SyncedPosition` gains a kind: `.exact` (BookOrbit, the default) or `.elsewhere(moved:)`.
- `Sync/KOSync.swift`: `ProgressSync`, one per book. `KOSyncLastSaid` keeps what the server last said per book, per account, beside the reading positions.
- For `.elsewhere`, in `OpeningPosition.choose`, so every place line and the reader still agree:

| Situation | Opens at |
|---|---|
| No local place | The server's |
| First pull, no last-said yet | Local; the capsule offers the server's if it differs |
| Server unchanged since last said | Local |
| Moved, ahead of local, nothing unsent | The server's |
| Moved, behind local or something unsent | Local; the capsule offers it |
| Same section, no timestamp | Local |

- Ahead or behind compares the section first (`DocFragment[n]` against the CFI's spine step, step ÷ 2 = n), then the percentage. The two engines' percentages don't match, so they only decide within a section.
- **No push before a pull has succeeded this session.** Else it stays unsent. A push that finds the server moved fails and leaves it to `catchUp`, so nothing overwrites another device.
- **After each push, read back** and store that as last-said. It costs one GET, and any server that rewrites places then can't look like another device.
- Places from before signing in have no xpointer and can't go until the book next opens. That's fine: they go then, after the first-pull rule.
- Tests: `OpeningPositionTests`, one per row above, and `BookPlacesTests`. A KOReader place must never overwrite a local one silently except in the "ahead" row.

## Chunk 4: wiring (no Settings yet)

**Done 2026-11-08.** As built:

- **The account:** `Octavo/Shell/KOReaderConnection.swift`. `KOReaderConnection` (`ShellModel.koreader`) holds one `KOReaderAccount`: client, `KOSyncPlaces` beside the reading positions, and a device ID made once per install. For now only DEBUG's `-connectKOSync 1` sets it, to `dev/kosync`.
- **Which books:** `ShellModel.koreaderSync(for:on:account:file:)`. EPUBs on the iPhone from an OPDS catalog or Files, with an account, not the sample book. BookOrbit's books never; `progressSync` decides those first.
- **The reader:** `didOpen` pushes an unsent place only if `mayPush` allows it, and calls `adopted` when it opens at the server's place. A KOReader place the book didn't open at (`.first`, or `.moved` and not ahead) is offered (`offer`, shared with `checkServerPlace`). The bridge finds it (`resolveXPointer`) and places it, since the server's percentage is another engine's. **Go** adopts it. A position KOReader can't take (a fixed-layout page, with no xpointer) isn't sent, and isn't left as unsent (`sends`).
- **The capsule:** `ReaderServerPlace.source`, "KOReader" for now, so "KOReader: 75% · CHAPTER X…" (`koreader-sync/app/`). The device's name instead is question 6 below.
- **The sync line:** "Synced" only from a push that landed or a pull that agrees: not an empty pull, and not beside a KOReader place this iPhone hasn't seen. Unchanged for BookOrbit.
- **A failure about the book** (`KOSyncError.isAboutTheBook`: the server doesn't have the file, or won't take its place) stops `retryUnsent` for that book. It goes again when the book opens. What the line says then is question 5. A wrong password stays unsent, since signing in again fixes every book.
- **After review (chunks 3 and 4):** another reader's place offered drops a position still waiting to go (`DebouncedProgressPusher.backendMoved`), so closing the reader doesn't send it over the place unanswered. The sync line says nothing beside an unseen KOReader place even after an earlier push. A place read back from another device (another `device_id`, in another section) isn't recorded as this iPhone's. Go after a fold sends KOReader's place back with its CFI. A bridge call that fails while finding KOReader's place is tried again next time, and only a place the book doesn't have is set aside. The file is looked for last when choosing a book's backend. Not changed: books KOReader first opened before 2024 (`koreader-sync.md`, "On real KOReader"), and re-hashing the file per sync (11 KB read, and a cache would have to notice a re-download).
- **Debug:** `-connectKOSync 1`. Remote `importLocal` imports a book from Documents as Files does, and `serverPlace` reads the capsule and presses Go or ✕. `tools/ko.sh` reads or moves a book's place on `dev/kosync`, as another device.
- **Tests:** `BookPlacesTests` (which books, the sync line), and `ReaderKOReaderPlaceTests` (offered, followed, taken by Go, an unsent place waits, a seen place isn't offered).
- **Checked end to end** with `tools/app-check.sh` on Octavo KOReader Duo (DB637399-E7C7-4899-9F8B-47DB476C17F4): your place reaches the server as `…/p[59].0`; another device's move ahead is offered, not jumped to; Go takes it without sending anything back; a move back doesn't move you and is offered; ✕ sends yours; offline nothing goes, and back online it does.
- **Seen there, by design:** reopening straight into the reader reuses a pull up to 5 minutes old (`BookPlaces.reuseAge`, so unfolding opens at once). From the book's screen, which pulls when it appears, the reader has the fresh place. Coming back to the app asks again too.
- **Still to do:** keep unsent places by account, and clear them and `KOSyncPlaces` on sign-out (chunk 5, with the account).

As planned:

- `ShellModel.progressSync(for:on:)`: BookOrbit as today. Otherwise, with an account and the book's EPUB on the iPhone (`BookOpener.localFile(for:)`), a `KOSync`. Not the sample book (`BookImporter`). A book not downloaded has no backend.
- `BookPlaces.status`: "Synced" only after a push landed or a real place came back, not after an empty pull (`remotes[key].position != nil`). Check this doesn't change BookOrbit's line.
- `BookPlaces`: keep unsent places and last-said by account. Clear both on sign-out or a new account. A permanent failure stops retrying.
- `ReaderModel`: `checkServerPlace` and the capsule take an xpointer, resolve it through the bridge, and use the bridge's fraction, not the server's (Kavita's differs by up to 20 points).
- The capsule says "KOReader" (question 6), replacing the book's server name and the `"BookOrbit"` fallback in `ReaderView`.
- DEBUG: `-connectKOSync 1`, like `-connectOPDS`. Debug remote: read and move the server's place, like `sync-spike/tools/bo.sh`.
- **Checked on:** a simulator named for this work, against `dev/kosync`, with the sequence from `docs/notes/sync-in-app.md`: another reader moves it, offline, relaunch, first sync, moving backward. Name it and its UDID.

## Chunk 5: Settings (after Adam's answers below)

- `SavedServers.koreaderAccount: SavedKOSyncAccount?` (ID, address, username), optional so saved files still read. Secrets under its ID: a new `koSyncKeyService` in `ServerCredentials.allServices`, and the pin under `pinService`.
- `KeychainSweep`: keep the account's ID, or it's deleted at the next launch. Test it.
- A page in `SettingsScreen` (`SettingsPage`): address through `ServerAddress.parse`, username, password, Sign in, Sign out, and the "Trust this server" step. That step lives inside `SetupModel`, so factor it out rather than copy it.
- Signing in tests `users/auth` and stores nothing on failure.
- A per-catalog switch (question 2), saved on the `SavedServer` and optional so saved files still read: in `CatalogSetup` with the account fields inline while there's no account, and on the catalog's server page. `ShellModel.koreaderSync` checks it. Files books need only the account.
- From the answers below: an EPUB on a synced catalog that isn't downloaded has no place row, bar or Search place, and a download pulls at once (4). The toggle's footer and the account page state the limits (5). The capsule says "KOReader" (6).

**Done (2026-11-08), checked on Octavo KOReader Duo against `dev/kosync` and the local COPS:**
- The account (`KOSyncAccount`: address and key) is one Keychain item under its ID (`KeychainKOSyncAccountStore`); `Servers.json` keeps only `koreader.id`, since a Kavita address or a Komga username can be a key. The sweep keeps it. A list that names an account the Keychain no longer has forgets it at launch.
- Sign in and Sign out are `ServerActions` (`signInToKOReader`, `signOutOfKOReader`), with the "Trust this server" step shared with setup (`TrustStep`, out of `SetupModel`). Sign out forgets the account's places file, the places waiting to go and what it said; each catalog's switch stays.
- Settings' row and page (`KOReaderSettingsPage`); the toggle on catalog setup, with the fields inline and Connect signing in first (`ShellModel.connectCatalog`); the toggle on a catalog's page, with the fields under it while there's no account.
- `ShellModel.waitsForDownload`: a synced catalog's EPUB that isn't downloaded has no place row, bar or Search place; downloading it pulls (`BookCoverPage`).
- Also checked: "Trust this server" for the self-signed `dev/kosync` (port 3351), then signed in; after a relaunch, over that pinned connection, a downloaded COPS book's screen shows the place another device left ("42% · Synced just now"). The pull right as a download finishes is the same `refresh`, not watched separately.

## Chunk 6: review and docs

- Security review, for Adam's sign-off:
  - **Redirects: found while planning.** `TaskGuard` strips only `Authorization` and `Cookie` on a cross-origin redirect, so `x-auth-user` and `x-auth-key` would follow a GET to another server. Give `ServerTransport` a list of headers to strip, or refuse redirects for this client. Test it.
  - The MD5 is equivalent to the password on this protocol: Keychain only, `AfterFirstUnlockThisDeviceOnly`, never logged.
  - Its own `ServerTransport`, a pin per account, a small `maximumDataSize`.
  - Everything from the server is untrusted: `progress` length and format, `device`, `percentage` clamped, `timestamp` bounded.
  - Reading places and a file's hash go to the account's server.
- Docs: `CLAUDE.md`, `docs/PRIVACY.md` (the place and a file's hash), `README.md` "Not yet", decisions 6 and 36 in `docs/design/direction.md`, `docs/app-store/listing.json` with the limits stated, this note.
- `Scripts/local-tests.sh "<your simulator>"`. New sims need the 27.1 runtime. Then ask Adam before pushing.

## Questions for Adam, before chunk 5

One at a time, each with a picture. My recommendation is first.

1. **Where's the account?** A "KOReader sync" row in a new Reading progress section in Settings. Hidden for someone with only BookOrbit?
   **Adam, 2026-11-08: always shown.** "KOReader sync", value Off or the account, in a section of its own under the servers, footer "Syncs your place with KOReader for books from catalogs and Files."
2. **Setup:** skip it and opt in from Settings, or bring back the sync step for catalogs (decision 6)? Skipping keeps setup short, but people may not find it.
   **Adam, 2026-11-08: a toggle on each catalog,** on its setup screen under the address and name, not a step of its own. Switched on with no account, the KOReader fields (sync server, username, password) appear below it, and Connect checks both servers, with each error under its own fields. With an account, no fields, only "As adam on sync.example.com." One account for the whole app, kept in Settings: every catalog switched on, and Files books, use it, and changing it there changes it everywhere. The same toggle is on each catalog's server page. Signing out stops sync for all of them and leaves each toggle as it was.
3. **The place line** for a place from another device: the server's percentage until the book opens, or the chapter? It depends on chunk 0's gap.
   **Adam, 2026-11-08: the percentage,** "62% · Calibre", as every other line. KOReader's own server is within a point or two of foliate's, farther only where pictures fill pages; Octavo's own replaces it once the book opens.
4. **Not downloaded:** no place shown until it's downloaded, since sync needs the file.
   **Adam, 2026-11-08: hide it.** On a catalog that syncs with KOReader, an EPUB that isn't downloaded has no place row or bar on its screen and no place on its Search row, not even an iPhone place from before the file was removed. They appear once it's downloaded and pulled, so a download pulls straight away. Catalogs without sync, BookOrbit, and books that can't sync (not EPUB) are as today.
5. **A book that won't sync** (MOBI, or a file nobody else has): say so on its screen, or say nothing? Nothing can detect a different copy of the file, so the footer has to state that.
   **Adam, 2026-11-08: once, in the toggle's footer.** Shown: "EPUB books only. Your other devices need the same file, such as one downloaded from this catalog." The account page in Settings says the same for Files books. A book's screen says nothing about sync, as for any book that doesn't sync.
6. **The capsule's name:** "Kindle: 62%" from the device field, or always "KOReader: 62%"?
   **Adam, 2026-11-08: always "KOReader".** KOReader sends its model code by default ("Kobo_daylight", "kindlepw2"; `kosync_hostname` overrides it), which means little to most people. Its Progress sync menu also has "Device hostname" for a name of one's own.
7. **Decision 36:** the same file on two catalogs shares one place on the account. Accept it and amend the decision.
   **Adam, 2026-11-08: accepted,** one place for one file is the point. Decision 36 kept servers apart because BookOrbit numbers files from 1 on each; a KOReader match is the same file. Bookmarks stay per catalog, and switching a catalog's sync off keeps its copy apart. Amend decision 36 in chunk 6.
8. **KOReader's own settings:** auto sync is off by default. A line in the account page's footer?
   **Adam, 2026-11-08: leave it out.** Anyone already syncing KOReader devices has turned it on or pulls by hand.

## Later, not in this plan

iCloud would become a choice beside KOReader sync in that one place. Build nothing for it now.
