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
# App + unit tests (Swift Testing) on the iPhone Duo simulator (iOS 27.1)
xcodebuild test -project Octavo.xcodeproj -scheme Octavo \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' -collect-test-diagnostics never
# OctavoKit (non-UI logic) on macOS, no simulator
cd Packages/OctavoKit && swift test
# Public-domain sample EPUBs → SampleBooks/ (gitignored)
Scripts/fetch-sample-books.sh
# Local BookOrbit v3.6.0 at http://localhost:3300 (Docker; seeding and test accounts in dev/bookorbit/README.md)
cd dev/bookorbit && docker compose up -d && ./seed.sh
```

- Use the simulator named exactly `iPhone Duo`. The `CalcuSplit …` simulators belong to another project.
- Plain `xcodebuild test` clones the simulator for parallel testing and shuts the original down. Add `-parallel-testing-enabled NO` while the app is running on it.
- **Whenever you boot, create, erase or install to a simulator, name it in your message: exact name plus UDID.** Sessions running in parallel each get their own named simulator, because installs of the same bundle ID overwrite each other.
- Drive the fold with **Hinge** (`hinge open|close|half|<deg>`, `sweep`, `posture`, `screenshot <path>`; also the `hinge` skill).
- Layout: `Octavo/` app target and `OctavoTests/` use folder-synchronized groups (new files need no `project.pbxproj` edit). `Packages/OctavoKit` is a local SwiftPM package for models, sources, sync and API clients. `ReaderWeb/` is a folder reference (paths preserved) holding foliate-js and our bridge.
  - `Octavo/Reader/` is the reader core (`WebView`, `octavo://` scheme handler, hinge → layout). `Octavo/Spike/` holds the spike's throwaway debug screens, the only place for those; delete them when real screens replace them.
  - `Config/Octavo-Info.plist` (ATS: local networking plus home-name and 100.64/10 exceptions, `docs/notes/network-trust.md`), `dev/bookorbit/` (local server), `docs/notes/` (engineering notes, indexed in its README).
- Swift 6, default `MainActor` isolation in the app target, `@Observable` state. Deployment target iOS 27.1, so hinge APIs need no availability guards.
- **Never push to GitHub (`git push`, `gh pr create`) without the owner's explicit OK for that push.** Commit locally and ask. Show the owner every GitHub issue as a draft before creating it.
- On GitHub, `main` is protected by the ruleset "Protect main": changes land only through a pull request, and force pushes and branch deletion are blocked, with no bypass (owner included).
- **Branching: GitHub flow.** One short-lived branch per task, cut from `main` and merged back by pull request with a merge commit. The spike's integration branch `spike/scaffold` is retired.
- Spike tracker: `docs/SPIKE.md`.

## Architecture decisions

### Rendering
- **EPUB (and MOBI/AZW3/FB2/CBZ): upstream [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT)**, vendored at a pinned commit, running in a **SwiftUI `WebView`** (iOS 26+ WebKit for SwiftUI).
  - Why: BookOrbit's web reader and Android app both use foliate-js and store positions as **EPUB CFI**. Using the same engine gives exact position sync across devices.
  - We write our **own** JS bridge between Swift and foliate-js. Do **not** copy BookOrbit's `bridge.js` or its modified foliate files (see Licensing).
  - foliate-js says its API is unstable. Pin the version and update deliberately.
  - **Confirmed by the spike (2026-10-31).** foliate-js and Readium both synced positions with BookOrbit exactly. foliate-js was kept because it needs no CFI translation, reads MOBI/AZW3/FB2, blocks book scripts and works with SwiftUI. Readium's maturity was the strong counter-argument (see `docs/SPIKE.md`, engine bake-off). Safeguards that come with the choice:
    1. **We own the pinned copy.** Pinned at upstream `6b11e17`. Local changes are a small, numbered patch set listed in `ReaderWeb/foliate-js/PINNED.md`, never in `epubcfi.js`. Today: 0001 keeps the position on blank pages, 0002 lets the host set the column count. Fixes may be offered upstream, but only with the owner's OK.
    2. **Every foliate-js bump re-runs the BookOrbit position round trip** (`docs/notes/sync-spike/`), the fold-continuity check (`docs/notes/duo-spreads/`) and patch 0001's page-by-page comparison (`docs/notes/foliate-blank-page/`), automated in CI once CI exists.
    3. **Escape hatch:** the local branch `spike/readium-eval` keeps a working Readium reader with a CFI bridge (measured 30/30 against BookOrbit). Switching is estimated at 2–3 weeks.
- **Book scripts never run.** Every `octavo://` response carries a CSP that allows scripts only from `bridge.js` and `foliate-js/`; the book file is sandboxed and `nosniff`; foliate's load hook refuses script items; the bridge accepts messages only from the main `octavo://app` frame; external links are cancelled. Keep every layer when changing the bridge or the scheme handler (`docs/notes/reader-spike.md`).
- **PDF: PDFKit.**
- **Comics: native SwiftUI** paging for CBZ/CBR, plus OPDS Page Streaming / BookOrbit `cbz/files/{fileId}/pages` for streamed reading.

### Network trust (#9, D25; `docs/notes/network-trust.md`)
- Every server request goes through OctavoKit's `ServerTransport` (one per server), never a bare `URLSession`. It checks the address before every request and redirect: plain http only to home and VPN addresses, with standard address spellings only (ATS alone lets `http://16843009/` out). It also applies the server's certificate pin and redirect hygiene.
- Self-signed HTTPS: an exact-certificate pin per server host and port. A changed certificate asks again, even if iOS would trust it.
- Secrets live in the Keychain (`ServerCredentials`, `AfterFirstUnlockThisDeviceOnly`), never in saved URLs or logs. Remove server calls `ServerCredentials.removeAll(serverID:)`.
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
// Implementations: BookOrbitSync, KOSync (percentage only), ICloudSync
```

- Users can combine them freely (e.g. Calibre OPDS + kosync, or BookOrbit for both).
- **Internal position model: CFI + percentage (+ page number for fixed layout).** Percentage-only backends such as kosync sync from the percentage.
- Note: OPDS itself has **no** progress sync. Sync always comes from a `ProgressSync` backend.
- **Opening rule** (OctavoKit `Sync/`, `docs/notes/sync-spike.md`): if the server has a CFI and the device has nothing unsent, the server wins. If both moved, the later timestamp wins and the server wins ties. With no server CFI, or if the pull fails, the local position is used. Opening a book never pushes. Pushes wait until the reader has been still for 2 s, and closing the reader flushes them.
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
  - Status: `PATCH books/{id}/status`; rating via `books/bulk-set-rating`
- The API shapes change. The Android client mirrors them by hand. Expect breakage between server versions and handle missing fields tolerantly.
- **CFI compatibility, confirmed by the spike:** BookOrbit v3.6.0's web reader runs foliate-js at the commit we pin, with an identical `epubcfi.js`. Positions matched 31/31 in both directions across four books. Fixed-layout books restore by fraction, not CFI.

## iPhone Duo

- Use the iOS 27.1 hinge APIs (`onHingeChange` in SwiftUI / `UIHingeInteraction` in UIKit) and the ReservedRegion APIs for layouts that hug the fold.
- Behavior: two-page spread when unfolded, the exact reading position kept when folding or unfolding, and **book mode** when half open (#5, `docs/notes/duo-fold.md`): from 60° to 150°, flat from 160°, lasting until the reader lies flat or folds. Each half of the spread turns its way, a side-column tap calls `ReaderModel.onControlsTap`, and a spine shadow (setting `reader.bookModeShadow`, on by default) sits in the gap. The angles live in `BookModeThresholds`; set them on a real device.
- **Limitation:** apps can't draw on the outer display while the Duo is open. On iOS 27.1, scene accessories only work through `CameraCaptureAccessory`, which needs an active camera session. The "book cover on the outer screen" idea is parked. Don't fake it with a dummy camera session. Feedback has been filed asking for a non-camera scene accessory; revisit when the SDK changes.
- Closest workaround available today: a Live Activity or Lock Screen widget showing the current cover and progress.
- **Measured in spike 2b** (simulator only; `docs/notes/duo-spreads.md`):
  - The hinge is a 40 pt `division` reserved region at the inner display's centre: inactive when flat, active when half open. The camera is an `occlusion` region at the top right.
  - `onHingeChange` fires once on appear, then repeats unchanged values for about half a second after each move, so compare before acting. `.fullyOpen` arrives about 200 ms before the scene resizes.
  - Folding moves the same window between displays and app state survives, so the cover-display flow in `docs/UI-IDEAS.md` is feasible.
  - The page count comes from the hinge (`ReaderLayout`, foliate patch 0002): one page folded, two open or half open, with no text on the hinge.
  - A fold does one re-layout (#5; it was 10–13 relocations): the page holds its size under a snapshot of itself until the page has resized and the inputs have gone quiet (`FoldBatch`), then `bridge.js` renders once and the snapshot fades out in 0.3 s. The position holds because foliate keeps its anchor through the render, which a foliate update could break (`PINNED.md`, step 4).
  - `WebView` draws under the camera column and the bottom toolbar, so the page reports its own size to Swift. Whether to keep that is an open UX question.

## Licensing rules (important)

- This project is **MPL-2.0**.
- **BookOrbit is AGPL-3.0 with additional terms**, which include a mandatory "Powered by BookOrbit" notice for any work containing BookOrbit material. **Never copy code, JS, CSS or assets from BookOrbit or its Android client** into this repo. Calling its REST API is fine.
- Allowed dependencies need MPL-compatible licenses (MIT, BSD, Apache-2.0, MPL). List each one in `THIRD-PARTY-NOTICES.md`.
- No GPL/AGPL dependencies (they conflict with App Store distribution).

## First spike: done (2026-10-31)

All five steps passed in the simulator. BookOrbit sign-in, collection and download work; foliate-js renders in a SwiftUI `WebView`; positions match BookOrbit's web reader 31/31 in both directions; the Duo switches between one and two pages and keeps the position across folds. The tracker, results and decisions are in `docs/SPIKE.md`, and the engineering notes are indexed in `docs/notes/README.md`.

Not covered yet: generic OPDS browsing, PDF, comics, annotations and bookmarks, kosync and iCloud sync, and real devices.
