# CLAUDE.md — Octavo – OPDS Reader

Context for anyone, human or AI, working in this repo. Read it before writing code.

## What this is

A free, open-source (MPL-2.0) OPDS e-reader for iOS, built first for **iPhone Duo** (Apple's foldable; iOS 27.1 SDK). It has a first-class integration with the self-hosted **BookOrbit** server, and full support for generic OPDS servers (Calibre/COPS, Calibre-Web, Kavita, Komga, etc.).

- App Store name: **Octavo – OPDS Reader** (the short home-screen name is "Octavo").
- Bundle ID: **`com.ianazzone.ereader`**. This is permanent and must not be changed. The spelling matches the owner's other apps on purpose.

## Owner preferences

- Swift / SwiftUI first. Use UIKit only where there's no SwiftUI equivalent.
- Keep external dependencies to a minimum. Well-established engines are fine (see below). Don't add convenience libraries for things Foundation or SwiftUI already does.
- Present a summary and plan before writing significant code. Be direct about trade-offs.
- **All UX/UI decisions need the owner's approval.** Park ideas in `docs/UI-IDEAS.md`.

## Build, test, run

```bash
# Everything a pull request needs (see the rule below)
Scripts/local-tests.sh "<your Duo simulator>"
# App + unit tests (Swift Testing) on the iPhone Duo simulator (iOS 27.1)
xcodebuild test -project Octavo.xcodeproj -scheme Octavo \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' -collect-test-diagnostics never
# OctavoKit (non-UI logic) on macOS, no simulator
cd Packages/OctavoKit && swift test
# Public-domain sample EPUBs → SampleBooks/ (gitignored)
Scripts/fetch-sample-books.sh
# Local BookOrbit v3.6.0 at http://localhost:3300 (Docker; seeding and test accounts in dev/bookorbit/README.md)
cd dev/bookorbit && docker compose up -d && ./seed.sh
# A real device (UDID from `xcrun devicectl list devices`; unlocked, on the same Wi-Fi)
xcodebuild build -project Octavo.xcodeproj -scheme Octavo -destination 'id=<UDID>' -allowProvisioningUpdates
xcrun devicectl device install app --device <UDID> <DerivedData>/Build/Products/Debug-iphoneos/Octavo.app
```

- Real devices reach the local BookOrbit only when it's started with `BOOKORBIT_BIND=0.0.0.0`, at `http://<LocalHostName>.local:3300` (`dev/bookorbit/README.md`, "From a real iPhone"). Name the device and its UDID whenever you install to one, as with simulators.

- Use the simulator named exactly `iPhone Duo`. The `CalcuSplit …` simulators belong to another project.
- Plain `xcodebuild test` clones the simulator for parallel testing and shuts the original down. Add `-parallel-testing-enabled NO` while the app is running on it.
- **Whenever you boot, create, erase or install to a simulator, name it in your message: exact name plus UDID.** Sessions running in parallel each get their own named simulator, because installs of the same bundle ID overwrite each other.
- Drive the fold with **Hinge** (`hinge open|close|half|<deg>`, `sweep`, `posture`, `screenshot <path>`; also the `hinge` skill).
- Layout: `Octavo/` app target and `OctavoTests/` use folder-synchronized groups (new files need no `project.pbxproj` edit). `Packages/OctavoKit` is a local SwiftPM package for models, sources, sync and API clients. `ReaderWeb/` is a folder reference (paths preserved) holding foliate-js, our bridge and the bundled fonts (`fonts/`, #83).
  - `Octavo/Shell/` is the shell: each tab is the system's `NavigationStack` (`TabStack`) whose screens are spreads, with the system's Back and swipe in every posture; Settings is a system sheet from the gear (`SettingsSheet`, a `NavigationSplitView`); setup is a push stack (Adam, 2026-11-08; `docs/notes/split-shell.md`). One navigation system on every device, never one per device.
  - `Octavo/Tour/` is the tour for a new install (`TourFlow`, the steps; `TourController`, when it starts and ends and what the hinge does to it; `TourRecord`, whether it has played; `docs/notes/tour.md`).
  - `Octavo/Reader/` is the reader (`ReaderView` with its controls, footer and progress bar; `WebView`, `octavo://` scheme handler, hinge → layout). `Octavo/Debug/` holds DEBUG-only tooling: `ReaderRemote` lets the check scripts in `docs/notes/` drive the reader through `Documents/spike-command.json` (the spike's file names and commands, kept so the tools run unchanged), plus debug switches for the Settings stand-in. The spike's screens (`Octavo/Spike/`) were deleted in #17.
  - `Config/Octavo-Info.plist` (ATS: local networking plus home-name and 100.64/10 exceptions, `docs/notes/network-trust.md`), `dev/bookorbit/` (local server), `docs/notes/` (engineering notes, indexed in its README).
  - `site/` is the website: the home page, Privacy, Support and 404, in plain HTML and CSS with no build step. Cloudflare Pages serves it (output directory `site`). A push to `main` that changes `site/` deploys it through `.github/workflows/site.yml` and a Cloudflare deploy hook; Cloudflare's automatic production deployments are off, because its watch paths skip merge commits (`docs/notes/ci.md`, "The website").
    - `site/_headers` gives every page a content security policy that allows only the site's own files and no inline script, so scripts go in files of their own and nothing loads from another host (the font is served from `site/fonts/`, not Google Fonts).
    - `site/privacy.html` and `site/support.html` carry the same words as `docs/PRIVACY.md` and `docs/SUPPORT.md`, which version 1.0 and its listing link to: change both.
    - A file cached for a year (`/fonts/*`) carries its version in its name.
- Swift 6, default `MainActor` isolation in the app target, `@Observable` state. Deployment target iOS 27.1, so hinge APIs need no availability guards.
- **Never push to GitHub (`git push`, `gh pr create`) without the owner's explicit OK for that push.** Commit locally and ask. Show the owner every GitHub issue as a draft before creating it.
- **Every pull request: `Scripts/local-tests.sh "<your Duo simulator>"`.** GitHub runs only `swift test`, so the app's tests run here, and `main` requires the "Local tests" status this posts. Commit everything and update from `main` first, or it refuses. Run it before opening a pull request, and again after every push: each commit needs its own pass, and a commit that isn't on GitHub yet can't take the status. Any failure blocks, even one that looks unrelated: fix it or tell the owner. Put its result lines in the pull request. Never post that status any other way.
- On GitHub, `main` is protected by the ruleset "Protect main": changes land only through a pull request with green "CI passed" and "Local tests" checks, as a merge commit, and force pushes and branch deletion are blocked, with no bypass (owner included). `gh pr merge <number> --auto --merge` lands a pull request when the checks pass (not tried on a stacked pull request, so use the merge button there).
- **Branching: GitHub flow.** One short-lived branch per task, cut from `main` and merged back by pull request with a merge commit. The spike's integration branch `spike/scaffold` is retired.
- **CI** (`.github/workflows/ci.yml`, `docs/notes/ci.md`): only `swift test`, on GitHub's `xcode-27` runner, on every pull request and push to `main`, because tests that open a WebKit page stall at random there. For code that shouldn't run on the owner's Mac, the app's tests can run there by hand (`gh workflow run ci.yml --ref <branch>`). Changes to only `docs/`, `site/`, `README.md` or `CLAUDE.md` skip the tests. Neither place runs the Docker checks yet (#19).
- Spike tracker: `docs/SPIKE.md`.

## Architecture decisions

### Rendering
- **EPUB (and MOBI/AZW3/FB2/CBZ): upstream [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT)**, vendored at a pinned commit, running in a **SwiftUI `WebView`** (iOS 26+ WebKit for SwiftUI).
  - Why: BookOrbit's web reader and Android app both use foliate-js and store positions as **EPUB CFI**. Using the same engine gives exact position sync across devices.
  - We write our **own** JS bridge between Swift and foliate-js. Do **not** copy BookOrbit's `bridge.js` or its modified foliate files (see Licensing).
  - foliate-js says its API is unstable. Pin the version and update deliberately.
  - **Confirmed by the spike (2026-10-31).** foliate-js and Readium both synced positions with BookOrbit exactly. foliate-js was kept because it needs no CFI translation, reads MOBI/AZW3/FB2, blocks book scripts and works with SwiftUI. Readium's maturity was the strong counter-argument (see `docs/SPIKE.md`, engine bake-off). Safeguards that come with the choice:
    1. **We own the pinned copy.** Pinned at upstream `6b11e17`. Local changes are a small, numbered patch set listed in `ReaderWeb/foliate-js/PINNED.md`, never in `epubcfi.js`. Today: 0001 keeps the position on blank pages, 0002 lets the host set the column count, 0003 reports going to the other page of a fixed-layout spread, 0004 ignores a render until a section has loaded. Fixes may be offered upstream, but only with the owner's OK.
    2. **Every foliate-js bump re-runs the BookOrbit position round trip** (`docs/notes/sync-spike/`), the fold-continuity check (`docs/notes/duo-spreads/`) and patch 0001's page-by-page comparison (`docs/notes/foliate-blank-page/`), automated in CI once CI exists.
    3. **Escape hatch:** the local branch `spike/readium-eval` keeps a working Readium reader with a CFI bridge (measured 30/30 against BookOrbit). Switching is estimated at 2–3 weeks.
- **Book scripts never run.** Every `octavo://` response carries a CSP that allows scripts only from `bridge.js` and `foliate-js/`; the book file is sandboxed and `nosniff`; foliate's load hook refuses script items; the bridge accepts messages only from the main `octavo://app` frame; external links are cancelled. Keep every layer when changing the bridge or the scheme handler (`docs/notes/reader-spike.md`).
- **Page turns (decisions 27, 28; `docs/notes/page-turns.md`, `docs/notes/curl.md`):** every turn is drawn from `UIView` snapshots of the web view while foliate turns at once underneath (`bridge.js` `turn`). A finger's turn is recognised in UIKit, because WebKit stops passing a touch to the page once a turn starts under it, and holds its relocations until it's let go, so one that falls back is never saved or synced.
  - **Automatic and Curl** (Adam, 2026-11-07): UIKit's own page curl (`ReaderCurl`, a `UIPageViewController` waiting over the page with clear pages), its pan moved beside WebKit and given a page only where there is one: on a spread, UIKit crashes on none once its pan has begun. It runs at UIKit's 60 Hz on the Duo.
  - **Slide and Flip:** Swift's own (`ReaderSwipeRecognizer`, `ReaderTurnView`), moving on a `UIUpdateLink` asking for 120 Hz, not a SwiftUI animation, which mostly ran at 60 on the Duo. Page Turn None leaves turns and swipes to foliate, as before.
- **A closed reader goes away** (`docs/notes/reader-release.md`, `tools/check.py` measures every way out): `ReaderModel.close()` ends the page's say, because its web view leaves the window and takes another size. A Swift call awaiting the bridge holds the model and its web process, and a page off the window draws no frames, so anything in `bridge.js` that a call awaits has to finish without one (`nextFrame`).
- **Leaving the app leaves the page alone** (`docs/notes/reader-background.md`): iOS turns a backgrounded app sideways and back for its snapshots, so `ReaderModel.isInBackground` holds size and hinge changes until it's back. Laying out for those sizes saved a wrong place.
- **PDF: PDFKit.**
- **Comics: native SwiftUI** paging for CBZ/CBR, plus OPDS Page Streaming / BookOrbit `cbz/files/{fileId}/pages` for streamed reading.

### Network trust (#9, D25; `docs/notes/network-trust.md`)
- Every server request goes through OctavoKit's `ServerTransport` (one per server), never a bare `URLSession`. It checks the address before every request and redirect: plain http only to home and VPN addresses, with standard address spellings only (ATS alone lets `http://16843009/` out). It also applies the server's certificate pin and redirect hygiene.
- Self-signed HTTPS: an exact-certificate pin per server host and port. A changed certificate asks again, even if iOS would trust it.
- Secrets live in the Keychain (`ServerCredentials`, `AfterFirstUnlockThisDeviceOnly`), never in saved URLs or logs: a catalog address's key or token (Kavita's and Stump's path keys, credential-named query items and path parameters) is saved as `{key}` (`OPDSURLSecret`, as written in the address so it restores exactly). Remove server calls `ServerCredentials.removeAll(serverID:)`. Sign out and Remove server (`ServerActions`) also end the BookOrbit session on the server (`BookOrbitClient.signOutEverywhere()`, `auth/logout`; `docs/notes/settings.md`).
- At launch (`LaunchSteps`, from `didFinishLaunching`; in `App.init`, `UIApplication.shared` is nil and `isProtectedDataAvailable` reads false), `KeychainSweep` deletes every Keychain item that isn't a saved server's, and a signed-out server's sign-in; it deletes nothing if `Servers.json` (or an older install's `Server.json`) can't be read. The reinstall wipe runs just before it and skips an install with a saved server. `ServerStorageMigration` moves an install from one server to the list (`docs/notes/more-than-one-server.md`). A saved server's transport reads its pin before the first request (`ServerTransport(server:pins:)`); a pin that can't be read or decoded fails the request instead of being dropped (step 16).
- The KOReader sync account is kept like a server: its address and key (the password's MD5, as good as the password) in one Keychain item under its ID (`KeychainKOSyncAccountStore`), its own transport and pin, kept by the sweep through `SavedServers.koreader`. A cross-origin redirect drops `x-auth-user` and `x-auth-key` too (`ServerTransport.credentialHeaders`).
- Changes here need a security review that Adam signs off before merge.

### Parsing and OPDS
- Evaluate **Readium Swift Toolkit (BSD-3)**, specifically the `ReadiumShared`, `ReadiumStreamer` and `ReadiumOPDS` modules (no UI), for OPDS feeds and native metadata/cover extraction. Do **not** use `ReadiumNavigator`. It was evaluated in spike 1c and not chosen; see Rendering above. If Readium is adopted, its non-MIT/BSD/Apache dependencies (CryptoSwift and minizip under zlib-style licenses, SIL OFL fonts) need owner sign-off first.
- If Readium turns out to be overkill, OPDS 1.2 (Atom) parses fine with `XMLParser`, and OPDS 2.0 (JSON) with `Codable`.

### Core abstractions
Keep where books come from separate from where progress goes:

```swift
protocol LibrarySource { /* browse, search, metadata, download */ }
// Implementations: OPDSSource (1.2 + 2.0), BookOrbitSource

protocol ProgressSync { /* pull/push position, annotations, sessions */ }
// Implementations: BookOrbitSync, KOSync. Later: ICloudSync
```

- Users can combine them freely (e.g. Calibre OPDS + kosync, or BookOrbit for both).
- **Internal position model: CFI + percentage (+ page number for fixed layout).**
- **KOReader sync** (built 2026-11-08; `docs/notes/koreader-sync.md`, `docs/notes/koreader-sync-plan.md`): one account in Settings, for Files books and each catalog switched on for it (`SavedServer.koreaderSync`, on the catalog's setup and its page). EPUBs only, matched by KOReader's partial MD5, with places as xpointers (`bridge.js`): a percentage alone can't move KOReader. Another device's place is trusted less (`SyncedPosition.Origin.elsewhere`): it opens only if it moved and is ahead, else the capsule offers it ("KOReader: 62%"). A synced catalog's EPUB shows no place until it's downloaded. The same file on two catalogs shares one place (decision 36).
- Note: OPDS itself has **no** progress sync. Sync always comes from a `ProgressSync` backend.
- **Opening rule** (OctavoKit `Sync/`, `docs/notes/sync-spike.md`): if the server has a CFI and the device has nothing unsent, the server wins. If both moved, the later timestamp wins and the server wins ties. With no server CFI, or if the pull fails, the local position is used, else the server's percentage. Opening a book never pushes. Pushes wait until the reader has been still for 2 s, and closing the reader flushes them.
- **Any number of servers** (decision 36, `docs/notes/more-than-one-server.md`): `LibraryModel.connections`, one per server, with its own client and transport. A book's file, place and bookmarks are kept under its server's ID (`LibraryFile.storageKey(in:)`), since BookOrbit numbers files from 1 on every server. A place goes only to the book's own server.
- **Every place line uses that rule** (`BookPlaces`, step 13, `docs/notes/sync-in-app.md`): a book's screen pulls when it appears and when the app comes back (Home's and Search's rows too, at most once a minute), the reader reuses a pull up to 5 minutes old (so unfolding opens at once), and Home, Search and the book's screen show where the book opens. Every BookOrbit server syncs: setup doesn't offer "Don't sync" for now (`SavedServer.offersSyncChoice`, off; switched on, "Don't sync" also ignores the server's percentage). An open reader asks again when the app comes back, and offers a newer server place in a capsule (Go or ✕) instead of jumping. Places that didn't go are retried while the app is open (launch, return, reconnection; `BookPlaces.retryUnsent`), never in the background.
- **A jump doesn't move your place** (decision 33, `docs/notes/going-back.md`): the scrubber, Contents, a bookmark, a search result, a chapter button or a link in the book starts a trip (`ReaderTrip`), saved per book and only on the iPhone. Nothing is saved as your place or sent until ✕ or 5 turns forward, and Back sends nothing. A trip whose place another reader has moved ends when the book opens. `ReaderModel.goTo`, which the debug remote uses, still saves and pushes.
- **A footnote doesn't move your place either** (decision 34, `docs/notes/footnotes.md`): a note's mark opens a card over the page (`ReaderNote`, `ReaderNoteCard`), from the bridge's `noteAt`. Only the note's words and styles reach Swift, never its markup. Go to Note is a jump.
- **Position format:** push the collapsed start point of the visible page, which is what BookOrbit's web reader stores. Compare positions by resolving them, never as strings.

## BookOrbit integration notes

Learned by reading `bookorbit/bookorbit` (server) and `deranjer/bookorbit-android`. Use these to understand behavior only; don't copy code from them.

- Measured against v3.6.0 in the spike: details in `docs/notes/bookorbit-api.md`.
- REST API at `/api/v1`. **Swagger** is at `/api/docs` (JSON at `/api/docs-json`) but is off by default (`SWAGGER_ENABLED`), and v3.6.0's published schemas are empty. Live responses are the source of truth.
- The server **rejects unknown request fields** (400). Send only documented fields.
- Auth: `POST auth/login` with `clientKind: "native"` (v3.0+) returns access and refresh tokens in the body, with no cookies; refresh with `POST auth/refresh {refreshToken}`. **Refresh tokens rotate on every refresh.** Web mode and pre-3.0 servers use a refresh cookie instead. Login is limited to 5 per minute per IP. OIDC is available (`auth/oidc/{slug}/state`, `auth/oidc/callback`).
- Useful endpoints:
  - Library: `books/query`, `books/search`, `books/{id}`, `libraries`, `collections`, `collections/{id}/books`, `smart-scopes`, `smart-scopes/{id}/books`, `authors`, `series`
  - Files: `books/files/{fileId}/serve`, `books/{id}/cover`
  - Progress: `GET/POST books/files/{fileId}/progress` with body `{cfi, percentage, pageNumber}`. `percentage` is **0–100**, and a POST without `cfi` clears the stored CFI. BookOrbit's web reader writes the same row through `PUT reading-progress`.
  - Sessions: `POST books/files/{fileId}/sessions` with fields `sessionId, startedAt, endedAt, durationSeconds, progressDelta, endProgress, sessionType, source`
  - Annotations/bookmarks: `books/{bookId}/annotations`, `books/{bookId}/bookmarks` (keyed by CFI)
  - Status: `PATCH books/{id}/status`, with what progress does to each value in `docs/notes/bookorbit-api.md`; rating via `books/bulk-set-rating`
  - Sign out: `POST auth/logout {refreshToken}` ends the session (the access token alone ends nothing)
- **Read status** (#120, `docs/notes/book-status.md`): "…" beside Mark finished sets any of BookOrbit's statuses. Keep Reading and the Filter follow BookOrbit's own rules (`LibraryReadStatus`, `LibraryFilter.showing`). Octavo sets no status when you read: the server does, the same for Octavo's progress request as for its web reader.
- **Rating** (#120, `docs/notes/book-rating.md`): the star button beside "…" rates a BookOrbit book 1 to 5 whole stars (`books/bulk-set-rating`), "★ 4" once rated, on the book's screen only. "Rate it" asks once you mark a book Finished, Skimmed or Abandoned there and it isn't rated; no pop-up (decision 22).
- **Fixed-layout books** (`docs/notes/fixed-layout.md`): the web reader opens them by its stored percentage alone, ignoring the CFI, and that percentage (a section's end, in a Postgres `real`) can land it a page late. Octavo opens by the CFI, which is exact, and pushes a percentage just inside the page, so the web reader opens on Octavo's page. The numbers are measured against v3.6.0.
- The API shapes change. The Android client mirrors them by hand. Expect breakage between server versions and handle missing fields tolerantly.
- **CFI compatibility, confirmed by the spike:** BookOrbit v3.6.0's web reader runs foliate-js at the commit we pin, with an identical `epubcfi.js`. Positions matched 31/31 in both directions across four books.

## iPhone Duo

- Use the iOS 27.1 hinge APIs (`onHingeChange` in SwiftUI / `UIHingeInteraction` in UIKit) and the ReservedRegion APIs for layouts that hug the fold.
- Behavior: two-page spread when unfolded, the exact reading position kept when folding or unfolding, and **book mode** when half open (#5, `docs/notes/duo-fold.md`): from 60° to 150°, flat from 160°, lasting until the reader lies flat or folds. Each half of the spread turns its way, a side-column tap calls `ReaderModel.onControlsTap`, and a spine shadow (setting `reader.bookModeShadow`, on by default) sits in the gap. The angles live in `BookModeThresholds`; set them on a real device.
- **Limitation:** apps can't draw on the outer display while the Duo is open. On iOS 27.1, scene accessories only work through `CameraCaptureAccessory`, which needs an active camera session. The "book cover on the outer screen" idea is parked. Don't fake it with a dummy camera session. Feedback has been filed asking for a non-camera scene accessory; revisit when the SDK changes.
- Closest workaround available today: a Live Activity or Lock Screen widget showing the current cover and progress.
- **Measured in spike 2b** (simulator only; `docs/notes/duo-spreads.md`):
  - The hinge is a 40 pt `division` reserved region at the inner display's centre: inactive when flat, active when half open. The camera is an `occlusion` region at the top right.
  - `onHingeChange` fires once on appear, then repeats unchanged values for about half a second after each move, so compare before acting. `.fullyOpen` arrives about 200 ms before the scene resizes.
  - Folding moves the same window between displays and app state survives, so the cover-display flow in `docs/UI-IDEAS.md` is feasible.
  - The page count comes from the hinge (`ReaderLayout`, foliate patch 0002): one page folded, two open or half open, with no text on the hinge. Fixed-layout pages keep foliate's own rule apart from one column meaning one page (`docs/notes/fixed-layout.md`), and a spread's two pages meet on the fold.
  - A fold does one re-layout (#5; it was 10–13 relocations): the page holds its size under a snapshot of itself until the page has resized and the inputs have gone quiet (`FoldBatch`), then `bridge.js` renders once and the snapshot fades out in 0.3 s. The position holds because foliate keeps its anchor through the render, which a foliate update could break (`PINNED.md`, step 4).
  - **The page runs edge to edge** (decision 8, #17; `docs/notes/reader-page.md`): `ReaderView` lays the `WebView` out under the side column, camera and home indicator, and `ReaderLayout` insets the `foliate-view` by the safe area (measured outside the reader's own toolbar, so the controls never re-paginate) and the margin setting. Folded the text runs 27–355 pt, unfolded 139–448 | 503–812 pt, as in frames 07–09.

## Accessibility (#73, `docs/notes/accessibility.md`)

- The App Store's Accessibility Nutrition Labels are answered per device, and a label needs every common task to work with that feature. The note lists the common tasks and what's been checked on what. Claim only what's been checked.
- With Reduce Motion, anything that slides, scales, flips or bounces fades or stops: `@Environment(\.accessibilityReduceMotion)` in views, `UIAccessibility.isReduceMotionEnabled` in models and static animations. A drag still follows the finger, and a Page Turn picked by hand stays (Adam).
- Grey words on glass use `.secondaryOnGlass`, and the words on a filled button use `.onAccent` (`Octavo/Shell/ContrastStyles.swift`): Increase Contrast doesn't reach 4.5:1 on glass, and white on the dark-mode accent is 1.7:1.
- A line or a row that stops fitting at the accessibility text sizes wraps or stacks (`.lineLimit(untilLargerText:)`, `LargerTextStack`, `Octavo/Shell/LargerText.swift`). Book text stays on its own control, up to 200%.
- `docs/notes/accessibility/tools/probe.sh` reads the running app's accessibility tree and runs Apple's audit. It isn't in CI.

## Licensing rules (important)

- This project is **MPL-2.0**.
- **BookOrbit is AGPL-3.0 with additional terms**, which include a mandatory "Powered by BookOrbit" notice for any work containing BookOrbit material. **Never copy code, JS, CSS or assets from BookOrbit or its Android client** into this repo. Calling its REST API is fine.
- Allowed dependencies need MPL-compatible licenses (MIT, BSD, Apache-2.0, MPL). List each one in `THIRD-PARTY-NOTICES.md`. Fonts may also be SIL OFL 1.1, as the reader fonts are (decision 16).
- `THIRD-PARTY-NOTICES.md` is the app's Licences page (bundled, and its list is tested), so it lists only what ships in the app. The website's own assets carry their licences beside them in `site/` (Source Serif 4's in `site/fonts/`).
- No GPL/AGPL dependencies (they conflict with App Store distribution).

## First spike: done (2026-10-31)

All five steps passed in the simulator. BookOrbit sign-in, collection and download work; foliate-js renders in a SwiftUI `WebView`; positions match BookOrbit's web reader 31/31 in both directions; the Duo switches between one and two pages and keeps the position across folds. The tracker, results and decisions are in `docs/SPIKE.md`, and the engineering notes are indexed in `docs/notes/README.md`.

Not covered yet: generic OPDS browsing, PDF, comics, annotations and bookmarks, kosync and iCloud sync, and real devices.
