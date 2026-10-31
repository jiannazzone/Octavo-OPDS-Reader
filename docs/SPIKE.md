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
| 0 | Scaffold: project, package skeleton, `ReaderWeb/` folder ref, fetch script, notices, .gitignore; builds on Duo sim | — | this session | approval | done, local only on `spike/scaffold` (owner: keep local for now) |
| 1a | **Reader spike**: pin + vendor foliate-js, own bridge, `WebView` + scheme handler, open a local EPUB, relocate → `{cfi, fraction}`, `goTo(cfi)`, restore last CFI on relaunch | 3 | `reader-spike` | 0 | **done**, merged locally into `spike/scaffold` (incl. later CSP/script-blocking commits `dd70c7b`, `9c86e0f`) |
| 1b | **BookOrbit server + client**: local BookOrbit in Docker seeded with the sample books in a "Spike" collection; `BookOrbitClient` in OctavoKit (login, refresh cookie, collections, collection books, download, GET/POST progress) | 1, 2 | `bookorbit-client` | 0 | **done**, merged locally into `spike/scaffold` |
| 1c | **Readium bake-off** (owner request): Readium Swift navigator + our CFI translation layer (foliate's `epubcfi.js`), measured against BookOrbit's web reader with the same table as 2a. Own BookOrbit user and own simulator. Evaluation branch, merged only if Readium wins | 4 (Readium) | `readium-spike` | 1b | **done**: 30/30 hits, `144ea99` on `claude/spike-1c-readium-c401b9`, local, evaluation only |
| 2a | **Integration + CFI round trip**: app logs in → collection → download → read; pull progress on open, push on relocate; verify against BookOrbit's web reader both directions, ≥3 books | 4 | `sync-roundtrip` | 1a, 1b | **done**: 31/31 hits, merged locally into `spike/scaffold` |
| 2b | **Duo spreads**: `onHingeChange` → column count (1 ↔ 2), position kept across fold/unfold | 5 | `duo-spreads` | engine choice | in progress (branch from `spike/scaffold`): blank-page patch 0001, hinge-driven columns, gap at hinge, half-open, continuity, cover-display handoff; sim 'Octavo Sync Duo' |
| 3 | Retro: record results/decisions in CLAUDE.md, delete `Spike/`, draft GitHub issues for real work, hand off to UI brainstorming | — | this session | 2a, 2b | pending |

1a and 1b run in parallel. 2a and 2b may run in parallel if their files don't overlap; decided when 1a lands.

### Done criteria

- **1a:** on the Duo sim, open Pride and Prejudice, page forward, kill the app, relaunch → same page. Bridge message decoding has unit tests. PR notes the pinned commit and why.
- **1b:** `swift test` passes (stubbed `URLProtocol` tests). An opt-in live test (env var) against the local server logs in, lists "Spike", downloads an EPUB, posts progress and reads it back. `dev/bookorbit/README.md` says how to start/seed/reset the server.
- **2a:** results table per book: app → web and web → app, same spot or documented drift with cause.
- **2b:** fold/unfold via the `hinge` skill switches 1 ↔ 2 columns without losing position; screenshots in the PR. Also confirm (for the cover-display idea in `docs/UI-IDEAS.md`) that app state survives the outer → inner display move, and that an unfold seen on a non-reader screen can trigger navigation into the reader.

### Position-match protocol (2a and 1c)

Five books × ≥3 positions (early, middle, late; ≥2 mid-chapter), both directions (app → BookOrbit web reader, web reader → app). Compare by visible text, not CFI strings, since the two sides paginate differently. Browser at a phone-sized viewport.

| Book | Position | Direction | Source first visible words (~8) | Target page contains them? | Verdict | Notes |
|---|---|---|---|---|---|---|

Verdict: **hit** (target page contains the source's first visible words), **near** (within one page), **miss**, **failed**.

## Research folded into 1a

Read BookOrbit's web reader source (behavior only, no copying) to learn (a) which upstream foliate-js commit it's based on — pin the same or nearest, and (b) what its custom document loader changes that could alter CFIs (spine order, element IDs, injected nodes). Report findings; this is the main risk.

## Risks

- **CFI drift** from BookOrbit's custom loader (above). Mitigation: same foliate base, compare CFIs for identical positions early in 2a.
- **ES modules over a custom scheme**: scheme handler must return `text/javascript` MIME types; foliate's `import` paths must resolve under the scheme.
- **Refresh cookie over http://localhost**: if BookOrbit marks it `Secure`, URLSession may drop it on plain http. 1b checks this; may need a local TLS proxy or manual cookie handling.
- **BookOrbit API drift**: decode tolerantly; treat the live server's `/api/docs-json` as truth. Don't commit BookOrbit's schema (AGPL material) — keep any snapshot gitignored.

## Phase 1 findings (2026-10-31)

**1a reader** (details: `docs/notes/bookorbit-foliate.md`, `docs/notes/reader-spike.md` on the 1a branch)
- Pinned upstream foliate-js **`6b11e17`** (2025-11-29): the exact commit BookOrbit's web reader is built on, and unchanged through BookOrbit v3.6.0. Orchestrator verified the vendored files are byte-identical to upstream.
- **CFI risk: low** for reflowable LTR books. `epubcfi.js` is untouched; BookOrbit's loader rewrites attributes/CSS only, never adds or removes nodes. One shape difference: BookOrbit's web reader stores a collapsed point CFI (`epubcfi(/6/2!/4/2)`), stock foliate reports a range. Both resolve to the same page, so **2a must compare by resolving, not by string**. Residual risk: vertical/RTL, fixed-layout, malformed OPFs.
- ES modules, `fetch` and foliate's `blob:` iframes all work over the `octavo://` scheme handler. Scheme handler must be `nonisolated` (app is MainActor by default). Taps need pointer events, not `click`.
- P&P (24 MB) opens in ~4 s (whole-zip unzip in JS); small books ~1.3 s. 3–4 relocate events per page turn → debounce persistence later.
- **Bug: blank pages lose position.** P&P's CSS leaves an empty page after the dedication; foliate reports the whole chapter there and snaps back on re-layout, so paging forward loops. `goTo(cfi)` still works. Same paginator code in BookOrbit. A clean fix needs a foliate patch → owner decision.
- **2b warning:** foliate forces one column when the reader area is portrait (hard-coded). If the unfolded Duo's reader area is portrait, two-page spreads need more than settings.

**1b BookOrbit** (details: `dev/bookorbit/README.md` on the 1b branch)
- BookOrbit **v3.6.0** (`ghcr.io/bookorbit/bookorbit:3.6.0`, upstream `a96ff0c`) on `localhost:3300`, still running. Dev login `octavo` / `OctavoDev1`; on a fresh seed book id = file id (1–5).
- Native login: `POST auth/login` with `clientKind: "native"` returns `refreshToken` in the body; `auth/refresh` takes `{refreshToken}`. Refresh tokens rotate (client serializes refreshes). Cookie fallback for older servers. 5 logins/min/IP rate limit.
- Server rejects unknown request fields (400). Collection books are `{items,total,page,size}` with plain author names; `books/{id}` has author objects.
- **Progress `percentage` is 0–100.** Never-opened books return `percentage: 0` with nulls, not 404. POST replaces: omitting `cfi` clears it. Server keeps ~7 significant digits.
- Cookie over http://localhost is fine (no `Secure` flag on http). App needs `NSAllowsLocalNetworking` for 2a.
- `/api/docs` is off by default and lists routes without shapes; shapes came from live responses.
- Suggested shapes: `LibrarySource` node-based (`root`, `entries(in:page:)`, `search`, `book`, `download`, `cover`); `ProgressSync` = `pull(for:) -> SyncedPosition?` / `push(_:for:)` with server `updatedAt` for newer-wins. `ReadingPosition` unchanged.
- FYI: BookOrbit ships its own iOS app; its v3.6.0 release notes mention iPhone Duo support.

Orchestrator check: file sets of the two branches don't overlap (clean merge). `swift test` re-run on 1b: 33 pass. `xcodebuild test` re-run on 1a (iPhone Duo): passes.

## Phase 2 findings (2026-10-31)

**2a foliate-js ↔ BookOrbit** (details and screenshots: `docs/notes/sync-spike.md` on the 2a branch). **Main spike risk retired for foliate-js.**

| Direction | Hit | Near | Miss | Failed |
|---|---|---|---|---|
| App → web | 16 | 0 | 0 | 0 |
| Web → app | 15 | 0 | 0 | 0 |

- Five books at ~12%, 50% and 88–94%, plus one extra P&P row; 28 of 31 mid-chapter. Two web → app hits straddle a page end (the first words start on the last line); they're counted as hits but listed separately.
- **Push the collapsed point CFI** at the start of the visible page, which is what BookOrbit's web reader stores. Range CFIs also hit 5/5, so the shape doesn't change where a book opens. The string can differ slightly at block starts (`/102[id]` vs `/102[id]/1:0`), but both open the same page.
- **Rule when device and server disagree:** server CFI with nothing unsent locally → server wins. Both moved → later timestamp wins, ties go to the server. Server has no CFI, or the pull fails → local position. Opening a book never pushes (that would creep the position backward); pushes are debounced 2 s and flushed on close.
- New in OctavoKit: a minimal `ProgressSync` protocol, `BookOrbitProgressSync`, `DebouncedProgressPusher`. `BookOrbitClient` unchanged. ATS via `Config/Octavo-Info.plist` (`NSAllowsLocalNetworking`).
- The BookOrbit v3.6.0 web reader writes through `PUT /api/v1/reading-progress` (it also sends Kobo location fields); we use `books/files/{id}/progress`. Same record, but the Kobo fields are untested.
- **Blank-page bug:** with the debug strip at a fixed height, P&P no longer loops past the dedication. That supports the vetting session's theory that our overlay's height change triggered it, not foliate alone. A blank end-of-chapter page in Moby-Dick slipped past the blank-page check (an empty element counted as visible), but it still landed correctly.
- **Process problem:** the built-in browser's cookies are shared across sessions. One 2a action landed on 1c's `octavo-readium` account (Alice set to 13.49% at 19:30:51Z; 1c was told). 2a's counted results all use `octavo` on a separate host (`sync2a.localhost:3300`).
- Simulator: 'Octavo Sync Duo' (32DEFF1F-1885-4884-8DAF-2FC92AE08FC2). Orchestrator re-ran `swift test` (48 pass) and `xcodebuild test` (pass) on it. foliate-js is unchanged on the branch.

### Engine bake-off: 1c Readium vs 2a foliate-js

Full write-up: `docs/notes/readium-spike.md` on the 1c branch.

| | foliate-js (2a) | Readium 3.11.1 (1c) |
|---|---|---|
| Positions → BookOrbit web | 16/16 hit | 15/15 hit, character-exact |
| BookOrbit web → positions | 15/15 hit | 15/15 hit, character-exact (text-quote navigation) |
| CFI translation layer | none: same code as BookOrbit | ours: foliate's `epubcfi.js` injected, quote-based `go(to:)`. ~2–3 weeks to production incl. highlights, plus a CI regression harness |
| Fold/unfold position | paginator keeps an anchor | Readium drifts backward (to chapter start in one run); our re-anchor fix kept 12/12 |
| Unfolded two columns | reader area is 951×517 pt (wider than tall), so foliate's portrait single-column rule shouldn't apply (2b to confirm) | needs `columnCount: .two` set from the hinge; `.auto` stays one column |
| Formats | EPUB, MOBI, AZW3, FB2, CBZ | EPUB, PDF, CBZ, audiobooks; no MOBI/AZW3/FB2 |
| Book JavaScript | blocked (CSP, sandboxed book, main-frame-only messages) | runs by default; a CSP meta injected via a `Publication` transform blocks it, but Readium's handlers stay reachable |
| Licenses | MIT, BSD-3 | also zlib-style (CryptoSwift, minizip) and SIL OFL fonts → owner sign-off needed |
| Dev loop | fast | Debug builds ~10× slower to open a book |
| Project maturity | one maintainer, no releases, unstable API | foundation-backed, releases, migration guides |
| UI stack | SwiftUI `WebView` | UIKit view controller wrapped for SwiftUI |

**Orchestrator and 1c both recommend foliate-js**, with Readium as the documented fallback (switch cost ~2–3 weeks; the 1c branch shows how). Sync accuracy is a tie, so it doesn't decide anything. foliate wins on parity by construction, formats, script isolation, resize anchoring and the SwiftUI stack. Readium's real advantage is project maturity. **Owner decided: foliate-js with safeguards** (see Decisions).

**Blank-page bug, vetted** (`docs/notes/foliate-blank-page-upstream.md` on the `foliate-blank-page` branch, `e1946c0`): the bug is real and in upstream foliate-js (`getVisibleRange` falls back to `<body>` on an empty page). Reproduced in Chrome, macOS WebKit and iOS Safari, and not reported upstream. The P&P blank page itself is a WebKit double column break. The loop in Octavo was triggered by the debug strip resizing the `WebView`. A ~50-line patch leaves CFIs byte-identical on 1,546 non-blank pages. Draft issue and PR text are ready for owner review; nothing has been posted.

## Decisions

- **Server:** local BookOrbit in Docker, seeded with the sample books.
- **Minimum iOS:** 27.1. Hinge APIs used without availability guards.
- **Spike UI:** bare system-default debug screens in `Octavo/Spike/` are fine without per-screen approval; deleted after the spike. Any real UI needs owner approval.
- **Git flow:** each session commits on its worktree branch and stops. **Nothing is pushed to GitHub (no `git push`, no `gh pr create`) without the owner's explicit OK for that push.** Once approved, the branch goes up as a PR; orchestrator reviews, owner merges. Scaffold (phase 0) lands the same way, before 1a/1b start.

- **Engine (2026-10-31):** foliate-js, with safeguards: (1) we own the pinned copy plus a numbered patch set, starting with the vetted blank-page fix, and never patch `epubcfi.js`; (2) the BookOrbit round trip re-runs on every foliate bump, in CI once CI exists; (3) Readium kept as the escape hatch on local branch `spike/readium-eval` (`144ea99`). Readium's non-UI modules are still candidates for OPDS and metadata. The owner weighed Readium's maturity heavily; MOBI/AZW3/FB2 support and parity by construction decided it.
- **foliate patches:** allowed under the rules above (this answers the earlier patch-policy question). Upstream issues and PRs need the owner's OK.

## Log

- 2026-10-31 — Plan drafted; owner answered server / min iOS / spike UI / git flow.
- 2026-10-31 — Started 1a (`reader-spike`) and 1b (`bookorbit-client`) in their own worktrees, cut from local `spike/scaffold`. Neither may push.
- 2026-10-31 — Scaffold built: `xcodebuild test` passes on the iPhone Duo sim, `swift test` passes for OctavoKit, app launches (folded, outer display). `ReaderWeb/` lands in the bundle as a folder. Shared model `ReadingPosition {cfi?, fraction 0...1, pageNumber?}` lives in OctavoKit so 1a and 1b agree on it. All five sample books fetched (Pride and Prejudice is the illustrated edition, 24 MB: a useful stress case).
- 2026-10-31 — 1a and 1b done and verified (tests re-run, foliate-js byte-identical to upstream). Both branches local and unmerged; awaiting owner OK to merge locally and start phase 2.
- 2026-10-31 — Owner asked whether another engine could replace foliate-js. Started 1c (`readium-spike`): Readium bake-off against BookOrbit, same table as 2a. 2b on hold until the engine is chosen; foliate patch policy deferred with it.
- 2026-10-31 — Owner OK'd local merge: 1a and 1b merged into `spike/scaffold` (no push). Merged tree passes `xcodebuild test` (iPhone Duo) and `swift test` (33). Started 2a (`sync-roundtrip`) alongside 1c. Asked 1c to also report whether Readium runs book JavaScript and if it can be disabled (foliate side blocks it via CSP since `dd70c7b`).
- 2026-10-31 — 2a done: 31/31 hits, both directions; verified (tests re-run). Branch local, unmerged. 1c still measuring.
- 2026-10-31 — 1c done: Readium 30/30, character-exact. Both engines sync exactly, so the bake-off comes down to everything else. Recommendation: foliate-js, with Readium as fallback. Blank-page vetting done; patch and upstream drafts await owner review. Not re-run by orchestrator: 1c's tests (evaluation branch, not for merge).
- 2026-10-31 — Owner chose foliate-js with safeguards. Readium branch kept as `spike/readium-eval`. 2a merged locally; merged tree passes `swift test` (48) and `xcodebuild test` on 'Octavo Sync Duo' (32DEFF1F…). Started 2b (`duo-spreads`).
- 2026-10-31 — Prep for closing finished sessions: the BookOrbit server's data moved from 1b's worktree to `dev/bookorbit/data/` in the main checkout (gitignored) and the server was restarted from there; data intact. Local branch `spike/blank-page-vetting` keeps the vetting doc and upstream drafts. The sessions' raw reports and screenshots are in the orchestrator's side-session notes folder (~20 MB); copy what matters into the repo at the phase 3 retro.
