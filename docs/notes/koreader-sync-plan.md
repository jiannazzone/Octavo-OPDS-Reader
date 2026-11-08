# KOReader sync: implementation plan

Not started. Written 2026-11-06 for after launch, from the measurements in `docs/notes/koreader-sync.md`. Read that first.

**Scope:** one KOReader account in Settings, for EPUBs from OPDS catalogs and Files. BookOrbit keeps its own sync. Kavita and Komga are plain OPDS: nothing is built for them, and they aren't promised or tested. MOBI, AZW3 and FB2 stay on the iPhone.

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

**Done 2026-11-08, on the sample books.** `bridge.js` `xpointerOf`, `resolveXPointer` and `xpointerAt`. `open` takes `xpointer` and `koreaderPlaces`. Relocations carry `xpointer`, and so does `ReadingPosition`. `ProgressSync.wantsXPointers` (off by default, forwarded by `SharedProgressSync` and `DebugProgressSync`) switches it on for an EPUB. Tests: `ReaderXPointerTests` (26 cases in a real web view). Against real KOReader through the bridge itself (`tools/bridge-check.sh`): Octavo → KOReader 149/150, KOReader → Octavo 1,016/1,021, where every miss is a cover or a table's spacing (`docs/notes/koreader-sync.md`). The modern EPUBs are still to run through `run.sh` and `bridge-check.sh`. As planned:

- `ReadingPosition.xpointer: String?`. Optional, so saved files still read.
- `ReaderWeb/bridge.js`, inside the file so the CSP doesn't change:
  - `xpointerOf(index, range)`: the paragraph (the range's nearest block element) as `…/p[9].0`, with the element rule from the note. `onRelocate` adds it to its message for reflowing books only, when the open options ask for it.
  - `resolveXPointer(string)`: `{cfi, fraction, chapter}` or `null`. Parse with a strict regex (offset optional, `[1]` optional) and walk the DOM by hand; never give the string to `document.evaluate`. Count text nodes and offsets by the note's rules, and convert offsets to UTF-16. Load an unopened section the way `describePlace` does. Words that don't resolve fall back to their element; a missing element gives `null`, never a guess.
- `open` takes `xpointer`. If it doesn't resolve, it's the fraction, then the local place.
- No foliate patch.
- Tests: round trip in the real web view, in `OctavoTests`, as the reader's other bridge tests do. A check script in `docs/notes/koreader-sync/tools/` over the sample books through `ReaderRemote`.

## Chunk 3: the rule

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

- `ShellModel.progressSync(for:on:)`: BookOrbit as today. Otherwise, with an account and the book's EPUB on the iPhone (`BookOpener.localFile(for:)`), a `KOSync`. Not the sample book (`BookImporter`). A book not downloaded has no backend.
- `BookPlaces.status`: "Synced" only after a push landed or a real place came back, not after an empty pull (`remotes[key].position != nil`). Check this doesn't change BookOrbit's line.
- `BookPlaces`: keep unsent places and last-said by account. Clear both on sign-out or a new account. A permanent failure stops retrying.
- `ReaderModel`: `checkServerPlace` and the capsule take an xpointer, resolve it through the bridge, and use the bridge's fraction, not the server's (Kavita's differs by up to 20 points).
- The capsule's name comes from where the place came from (`device`, length-limited, plain text; else "KOReader"), replacing the book's server name and the `"BookOrbit"` fallback in `ReaderView`.
- DEBUG: `-connectKOSync 1`, like `-connectOPDS`. Debug remote: read and move the server's place, like `sync-spike/tools/bo.sh`.
- **Checked on:** a simulator named for this work, against `dev/kosync`, with the sequence from `docs/notes/sync-in-app.md`: another reader moves it, offline, relaunch, first sync, moving backward. Name it and its UDID.

## Chunk 5: Settings (after Adam's answers below)

- `SavedServers.koreaderAccount: SavedKOSyncAccount?` (ID, address, username), optional so saved files still read. Secrets under its ID: a new `koSyncKeyService` in `ServerCredentials.allServices`, and the pin under `pinService`.
- `KeychainSweep`: keep the account's ID, or it's deleted at the next launch. Test it.
- A page in `SettingsScreen` (`SettingsPage`): address through `ServerAddress.parse`, username, password, Sign in, Sign out, and the "Trust this server" step. That step lives inside `SetupModel`, so factor it out rather than copy it.
- Signing in tests `users/auth` and stores nothing on failure. Signing in is the opt-in; there are no per-server settings.

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
2. **Setup:** skip it and opt in from Settings, or bring back the sync step for catalogs (decision 6)? Skipping keeps setup short, but people may not find it.
3. **The place line** for a place from another device: the server's percentage until the book opens, or the chapter? It depends on chunk 0's gap.
4. **Not downloaded:** no place shown until it's downloaded, since sync needs the file.
5. **A book that won't sync** (MOBI, or a file nobody else has): say so on its screen, or say nothing? Nothing can detect a different copy of the file, so the footer has to state that.
6. **The capsule's name:** "Kindle: 62%" from the device field, or always "KOReader: 62%"?
7. **Decision 36:** the same file on two catalogs shares one place on the account. Accept it and amend the decision.
8. **KOReader's own settings:** auto sync is off by default. A line in the account page's footer?

## Later, not in this plan

iCloud would become a choice beside KOReader sync in that one place. Build nothing for it now.
