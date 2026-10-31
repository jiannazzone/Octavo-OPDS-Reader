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

## Build, test, run

```bash
# App + unit tests (Swift Testing) on the iPhone Duo simulator (iOS 27.1)
xcodebuild test -project Octavo.xcodeproj -scheme Octavo \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' -collect-test-diagnostics never
# OctavoKit (non-UI logic) on macOS, no simulator
cd Packages/OctavoKit && swift test
# Public-domain sample EPUBs → SampleBooks/ (gitignored)
Scripts/fetch-sample-books.sh
```

- Use the simulator named exactly `iPhone Duo`. The `CalcuSplit …` simulators belong to another project.
- Drive the fold with **Hinge** (`hinge open|close|half|<deg>`, `sweep`, `posture`, `screenshot <path>`; also the `hinge` skill).
- Layout: `Octavo/` app target and `OctavoTests/` use folder-synchronized groups (new files need no `project.pbxproj` edit). `Packages/OctavoKit` is a local SwiftPM package for models, sources, sync and API clients. `ReaderWeb/` is a folder reference (paths preserved) holding foliate-js and our bridge.
- Swift 6, default `MainActor` isolation in the app target, `@Observable` state. Deployment target iOS 27.1, so hinge APIs need no availability guards.
- **Never push to GitHub (`git push`, `gh pr create`) without the owner's explicit OK for that push.** Commit locally and ask.
- Spike tracker: `docs/SPIKE.md`.

## Architecture decisions

### Rendering
- **EPUB (and MOBI/AZW3/FB2/CBZ): upstream [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT)**, vendored at a pinned commit, running in a **SwiftUI `WebView`** (iOS 26+ WebKit for SwiftUI).
  - Why: BookOrbit's web reader and Android app both use foliate-js and store positions as **EPUB CFI**. Using the same engine gives exact position sync across devices.
  - We write our **own** JS bridge between Swift and foliate-js. Do **not** copy BookOrbit's `bridge.js` or its modified foliate files (see Licensing).
  - foliate-js says its API is unstable. Pin the version and update deliberately.
- **PDF: PDFKit.**
- **Comics: native SwiftUI** paging for CBZ/CBR, plus OPDS Page Streaming / BookOrbit `cbz/files/{fileId}/pages` for streamed reading.

### Parsing and OPDS
- Evaluate **Readium Swift Toolkit (BSD-3)**, specifically the `ReadiumShared`, `ReadiumStreamer` and `ReadiumOPDS` modules (no UI). Do **not** use `ReadiumNavigator` (it's UIKit, and positions would need translating to foliate CFIs).
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

## BookOrbit integration notes

Learned by reading `bookorbit/bookorbit` (server) and `deranjer/bookorbit-android`. Use these to understand behavior only; don't copy code from them.

- REST API at `/api/v1`. **Swagger** is at `/api/docs`, with JSON at `/api/docs-json`. Treat a live server's schema as the source of truth.
- Auth: `POST auth/login` returns `{accessToken, user}`. Refresh uses a cookie via `POST auth/refresh`. OIDC is available (`auth/oidc/{slug}/state`, `auth/oidc/callback`).
- Useful endpoints:
  - Library: `books/query`, `books/search`, `books/{id}`, `libraries`, `collections`, `collections/{id}/books`, `smart-scopes`, `smart-scopes/{id}/books`, `authors`, `series`
  - Files: `books/files/{fileId}/serve`, `books/{id}/cover`
  - Progress: `GET/POST books/files/{fileId}/progress` with body `{cfi, percentage, pageNumber}`
  - Sessions: `POST books/files/{fileId}/sessions` with fields `sessionId, startedAt, endedAt, durationSeconds, progressDelta, endProgress, sessionType, source`
  - Annotations/bookmarks: `books/{bookId}/annotations`, `books/{bookId}/bookmarks` (keyed by CFI)
  - Status: `PATCH books/{id}/status`; rating via `books/bulk-set-rating`
- The API shapes change. The Android client mirrors them by hand. Expect breakage between server versions and handle missing fields tolerantly.
- **Known risk:** BookOrbit uses a custom document loader around foliate-js. Stock foliate-js *may* produce different CFIs for some books. The first spike must confirm that CFIs round-trip with the BookOrbit web reader.

## iPhone Duo

- Use the iOS 27.1 hinge APIs (`onHingeChange` in SwiftUI / `UIHingeInteraction` in UIKit) and the ReservedRegion APIs for layouts that hug the fold.
- Planned behavior: two-page spread when unfolded, a "book" layout when half-folded, and keeping the exact reading position when folding or unfolding.
- **Limitation:** apps can't draw on the outer display while the Duo is open. On iOS 27.1, scene accessories only work through `CameraCaptureAccessory`, which needs an active camera session. The "book cover on the outer screen" idea is parked. Don't fake it with a dummy camera session. Feedback has been filed asking for a non-camera scene accessory; revisit when the SDK changes.
- Closest workaround available today: a Live Activity or Lock Screen widget showing the current cover and progress.

## Licensing rules (important)

- This project is **MPL-2.0**.
- **BookOrbit is AGPL-3.0 with additional terms**, which include a mandatory "Powered by BookOrbit" notice for any work containing BookOrbit material. **Never copy code, JS, CSS or assets from BookOrbit or its Android client** into this repo. Calling its REST API is fine.
- Allowed dependencies need MPL-compatible licenses (MIT, BSD, Apache-2.0, MPL). List each one in `THIRD-PARTY-NOTICES.md`.
- No GPL/AGPL dependencies (they conflict with App Store distribution).

## First spike (proves the main risk)

1. Log in to a BookOrbit server from Swift (access token + refresh cookie).
2. List a collection and download an EPUB.
3. Render it with upstream foliate-js in a SwiftUI `WebView`.
4. `POST` a CFI position, open the same book in BookOrbit's web reader and confirm it lands on the same spot. Then test the reverse direction.
5. On the Duo simulator, switch between single-page and two-page spreads as the hinge angle changes.

If step 4 works, the main technical risk is retired.
