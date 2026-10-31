# First spike — tracker

Goal: prove the stack (BookOrbit API → foliate-js in SwiftUI `WebView` → CFI sync both ways → Duo spreads) in the iPhone Duo simulator. No product UI. See CLAUDE.md "First spike".

**Owner of this file:** the orchestrating session. Sub-sessions report back in their final message / PR; they don't edit this file.

## Environment (verified 2026-10-31)

- Xcode 27.2, iOS 27.1 runtime, `iPhone Duo` simulator (8C35AF6E…).
- **Hinge** (third-party, v0.3.0, also the `hinge` skill) drives the sim's pose: `hinge open|close|half|<deg>`, `sweep <from> <to> [s]`, `posture`, `rotate`, `screenshot <path>` (captures the display hosting the UI). Use it for 2b and any fold-continuity checks.
- SDK has `View.onHingeChange(isEnabled:_:)` → `DeviceHingeContext`, `UIHingeInteraction`, and WebKit's SwiftUI `WebView` / `WebPage` with `URLSchemeHandler`, `callJavaScript`, `userContentController`. Everything the spike needs exists.
- Docker 29, Node 22, gh (jiannazzone) available. No XcodeGen/Tuist.

## Proposed layout

```
Octavo.xcodeproj           plain Xcode project, folder-synchronized groups (no generator)
Octavo/                    app target (SwiftUI, @Observable)
  Spike/                   throwaway debug screens — deleted after the spike
  Reader/                  WebView host + Swift side of the JS bridge
OctavoTests/               Swift Testing
ReaderWeb/                 bundled as a folder reference (keeps paths for ES modules)
  reader.html, bridge.js   ours (MPL)
  foliate-js/              upstream, pinned commit (MIT) + PINNED.md
Packages/OctavoKit/        local SwiftPM package: models, LibrarySource/ProgressSync, BookOrbit client
                           (`swift test` runs on macOS, no simulator)
Scripts/fetch-sample-books.sh   Gutenberg EPUBs → SampleBooks/ (gitignored)
dev/bookorbit/             our own docker-compose for a local BookOrbit
THIRD-PARTY-NOTICES.md
```

The app target and the package are separate folders, so parallel sessions don't collide in `project.pbxproj`.

Sample books (Gutenberg EPUB3): Pride and Prejudice (1342), Alice in Wonderland (11), Frankenstein (84), Moby-Dick (2701), Sherlock Holmes (1661). Not committed; fetched by script.

## Phases

| # | Task | Spike step | Runs in | Depends on | Status |
|---|---|---|---|---|---|
| 0 | Scaffold: project, package skeleton, `ReaderWeb/` folder ref, fetch script, notices, .gitignore; builds on Duo sim | — | this session | approval | committed on `spike/scaffold`, awaiting push OK |
| 1a | **Reader spike**: pin + vendor foliate-js, own bridge, `WebView` + scheme handler, open a local EPUB, relocate → `{cfi, fraction}`, `goTo(cfi)`, restore last CFI on relaunch | 3 | session | 0 | pending |
| 1b | **BookOrbit server + client**: local BookOrbit in Docker seeded with the sample books in a "Spike" collection; `BookOrbitClient` in OctavoKit (login, refresh cookie, collections, collection books, download, GET/POST progress) | 1, 2 | session | 0 | pending |
| 2a | **Integration + CFI round trip**: app logs in → collection → download → read; pull progress on open, push on relocate; verify against BookOrbit's web reader both directions, ≥3 books | 4 | session | 1a, 1b | pending |
| 2b | **Duo spreads**: `onHingeChange` → foliate column count (1 ↔ 2), position kept across fold/unfold | 5 | session | 1a | pending |
| 3 | Retro: record results/decisions in CLAUDE.md, delete `Spike/`, draft GitHub issues for real work, hand off to UI brainstorming | — | this session | 2a, 2b | pending |

1a and 1b run in parallel. 2a and 2b may run in parallel if their files don't overlap; decided when 1a lands.

### Done criteria

- **1a:** on the Duo sim, open Pride and Prejudice, page forward, kill the app, relaunch → same page. Bridge message decoding has unit tests. PR notes the pinned commit and why.
- **1b:** `swift test` passes (stubbed `URLProtocol` tests). An opt-in live test (env var) against the local server logs in, lists "Spike", downloads an EPUB, posts progress and reads it back. `dev/bookorbit/README.md` says how to start/seed/reset the server.
- **2a:** results table per book: app → web and web → app, same spot or documented drift with cause.
- **2b:** fold/unfold via the `hinge` skill switches 1 ↔ 2 columns without losing position; screenshots in the PR. Also confirm (for the cover-display idea in `docs/UI-IDEAS.md`) that app state survives the outer → inner display move, and that an unfold seen on a non-reader screen can trigger navigation into the reader.

## Research folded into 1a

Read BookOrbit's web reader source (behavior only, no copying) to learn (a) which upstream foliate-js commit it's based on — pin the same or nearest, and (b) what its custom document loader changes that could alter CFIs (spine order, element IDs, injected nodes). Report findings; this is the main risk.

## Risks

- **CFI drift** from BookOrbit's custom loader (above). Mitigation: same foliate base, compare CFIs for identical positions early in 2a.
- **ES modules over a custom scheme**: scheme handler must return `text/javascript` MIME types; foliate's `import` paths must resolve under the scheme.
- **Refresh cookie over http://localhost**: if BookOrbit marks it `Secure`, URLSession may drop it on plain http. 1b checks this; may need a local TLS proxy or manual cookie handling.
- **BookOrbit API drift**: decode tolerantly; treat the live server's `/api/docs-json` as truth. Don't commit BookOrbit's schema (AGPL material) — keep any snapshot gitignored.

## Decisions

- **Server:** local BookOrbit in Docker, seeded with the sample books.
- **Minimum iOS:** 27.1. Hinge APIs used without availability guards.
- **Spike UI:** bare system-default debug screens in `Octavo/Spike/` are fine without per-screen approval; deleted after the spike. Any real UI needs owner approval.
- **Git flow:** each session commits on its worktree branch and stops. **Nothing is pushed to GitHub (no `git push`, no `gh pr create`) without the owner's explicit OK for that push.** Once approved, the branch goes up as a PR; orchestrator reviews, owner merges. Scaffold (phase 0) lands the same way, before 1a/1b start.

## Log

- 2026-10-31 — Plan drafted; owner answered server / min iOS / spike UI / git flow.
- 2026-10-31 — Scaffold built: `xcodebuild test` passes on the iPhone Duo sim, `swift test` passes for OctavoKit, app launches (folded, outer display). `ReaderWeb/` lands in the bundle as a folder. Shared model `ReadingPosition {cfi?, fraction 0...1, pageNumber?}` lives in OctavoKit so 1a and 1b agree on it. All five sample books fetched (Pride and Prejudice is the illustrated edition, 24 MB: a useful stress case).
