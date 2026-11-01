# Engineering notes

Write-ups from the first spike (2026-10-31). The tracker with phases, results and decisions is `docs/SPIKE.md`; the decisions that stuck are in `CLAUDE.md`.

| Note | Spike | What it covers |
|---|---|---|
| `bookorbit-foliate.md` | 1a | How BookOrbit uses foliate-js, why we pin `6b11e17`, the CFI-compatibility analysis |
| `reader-spike.md` | 1a | Reader wiring: `WebView`, the `octavo://` scheme handler, the bridge, book-script blocking, getting books into the app |
| `bookorbit-api.md` | 1b, 2a, #7 | BookOrbit v3.6.0 API behaviour: native auth and token rotation, validation, progress format, library shapes, browsing endpoints and their parameters, networking |
| `readium-spike.md` | 1c | Readium bake-off: 30/30 position matches, costs, why foliate-js was kept. Code on branch `spike/readium-eval` |
| `sync-spike.md` (+ `sync-spike/`) | 2a | Position sync with BookOrbit's web reader: 31/31, the disagreement rule, repro tools and screenshots |
| `foliate-blank-page-upstream.md` (+ `foliate-blank-page/`) | vetting | The foliate-js blank-page bug: cause, fix (patch 0001), draft upstream issue and PR (not sent), re-check harness |
| `duo-spreads.md` (+ `duo-spreads/`) | 2b | Duo layout: hinge APIs, one/two pages, gap at the hinge, position across folds, cover-display handoff, open UX questions |
| `formats-spike.md` (+ `formats-spike/`) | #4 | MOBI, AZW3 and FB2 through foliate-js, the bridge and the CSP: go/no-go per format, script-blocking tests with a positive control, positions, folds, BookOrbit round trip, a prototype second blocking layer |
| `duo-tabbar.md` (+ `duo-tabbar/`) | #6 | SwiftUI `TabView` on the Duo: the tab bar in the side column, Search in one capsule, over a cover, next to column controls, how to split screens at the hinge, and presenting during an unfold |
| `duo-fold.md` (+ `duo-fold/`) | #5 | One re-layout per fold under a cross-fade, book mode (angles, taps, spine shadow), the cold-launch page-size fix, measuring tools and videos |
| `home-library.md` (+ `home-library/`) | #13 | Home and Library: app-wide library state, a book's source, Continue reading, list layouts, the pane-title offset, debug connections, a simulator cover-decoding trap |
| `network-trust.md` (+ `network-trust/`) | #9 | Plain http only for home and VPN addresses, "Trust this server" and pinning, credentials in the Keychain: threat model, measured iOS 27.1 ATS behaviour (incl. an ATS bypass), decisions, adversarial audit, review checklist |

The sessions' raw run logs and screenshots weren't all committed. What's here is enough to re-run each check.
