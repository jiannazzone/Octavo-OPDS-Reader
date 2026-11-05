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
| `opds-source.md` (+ `opds-source/`) | #8 | OPDS 1.2 and 2.0 as a library: why our own parsers, chips, start chip and Home rules, format order, sign-in and the origin rule, Kavita's key in URLs, the four local servers |
| `network-trust.md` (+ `network-trust/`) | #9 | Plain http only for home and VPN addresses, "Trust this server" and pinning, credentials in the Keychain: threat model, measured iOS 27.1 ATS behaviour (incl. an ATS bypass), decisions, adversarial audit, review checklist; step 16's follow-up (names measured against real DNS and Bonjour, the launch Keychain sweep, fail-closed pins, secrets in catalog addresses); why the launch steps never ran until 2026-11-03, and what their first run does on an existing install |
| `sync-in-app.md` (+ `sync-in-app/`) | step 13 | Position sync in the app: `BookPlaces` (one rule for every place line, the cover's pull reused by the reader), "Synced …" and "Not synced yet", Don't sync, debug switches, simulator checks in every posture, follow-ups |
| `settings.md` (+ `settings/`) | step 14 | Settings: the list and its pages folded and unfolded, Sign out (ending the BookOrbit session too) and Remove server (what goes, what stays), Books on iPhone, Licences, simulator checks, follow-ups |
| `more-than-one-server.md` (+ `more-than-one-server/`) | decision 36 | Any number of servers: the list and how an install moves to it, each server's books kept apart, the title's popover, Search's sections. |
| `empty-lists.md` (+ `empty-lists/`) | #30 | Empty lists: how the screen is chosen and kept through a reload, the words by kind of list, Open Library with several servers, the newest books on the right page |
| `other-ways-in.md` (+ `other-ways-in/`) | step 15 | Import from Files and Open in Octavo, the bundled sample book, On iPhone, no server yet: the imported-books store, IDs from the bytes, setup's rule, file types, a grid trap on folds, simulator checks, the sample book's blank-page and fold checks |
| `reader-page.md` (+ `reader-page/`) | #17 | The real reader: the page edge to edge with the text kept out of the side column, margins and the hinge gutter, controls and taps, the per-page footer and the scrubber, sideways, the debug remote that replaced the spike's screens for the check tools |
| `formats-check.md` (+ `formats-check/`) | step 15 | MOBI, AZW3 and FB2 ship: the bridge's second script-blocking layer, the restore guard and FB2 links, refusing DRM and unsupported files by their bytes, reading an imported file's details through a hidden page, each layer measured alone in the app, positions and folds |
| `page-turns.md` (+ `page-turns/`) | 2026-11-03 | Page turns and opening a book (decisions 27, 28): snapshot and chapter-break measurements, turns drawn from snapshots over foliate, why swipes are recognised in UIKit, the position through turns and folds, the cover opening and closing, videos in every posture |
| `going-back.md` | 2026-11-04 | Going back and chapter skipping (decisions 33, 35): what a jump did to the saved place, fixed-layout books, what the system slider does with a neutral value and ticks, the zooming scrubber, trips across closing, and links in the book |
| `footnotes.md` (+ `footnotes/`) | 2026-11-05 | Footnotes where you are (decision 34): how real books mark notes, which links count, what reaches the card, how it's placed, the check with real taps in every posture, and a lost-swipe bug found on the way |
| `tour.md` (+ `tour/`) | step 17 | The tour for a new install (decisions 29 and 30): the steps, how a new install is told apart and why it's decided once, a replay's throwaway place, Skip in the column, the WebKit trap on a fold, simulator checks, what to try on a Duo |
| `layout-polish.md` (+ `layout-polish/`) | 2026-11-03 | The folded book sheet's compact resting state, the progress bar lined up with the text, Narrow's text drifting onto the hinge (WebKit's whole-point scrolling; fixed), the Night line (not reproduced, dropped for now) |
| `reader-pictures.md` (+ `reader-pictures/`) | 2026-11-04 | Pictures fit their text column: why a box wider than the page cut them off, the fix in `bridge.js`, every sample book in every posture and margin, what's left alone |
| `fixed-layout.md` (+ `fixed-layout/`) | 2026-11-04 | Pre-paginated EPUBs (and CBZ) in the reader: what stopped them opening and folding, what BookOrbit's web reader stores and does, why Octavo opens by CFI and pushes a percentage inside the page, foliate patch 0003, the script layers measured alone, simulator checks |
| `reader-release.md` (+ `reader-release/`) | 2026-11-04 | A closed reader goes away: the frame wait that kept every closed book's model, page and web process alive, in the app and in tests, the fix, every way out measured before and after, why the place holds |
| `reader-background.md` | 2026-11-04 | Leaving the app doesn't move the place: iOS's snapshot layouts, why a fold made the wrong place stick, holding size and hinge changes until the app is back, measured with and without the fix |
| `ci.md` | #19 | CI on pull requests: the jobs, why GitHub's `xcode-27` runner, which pull requests skip tests, the build cache, timings |
| `xhtml-first-frame.md` | 2026-11-04 | Why a new WebKit process's first XHTML frame takes over a second (QuickLook's `dlopen`), book opens with and without it, warm-ups, why it doesn't matter on a real Duo (25 ms), rendering a book before the tap (tried, dropped), closed readers staying alive |

The sessions' raw run logs and screenshots weren't all committed. What's here is enough to re-run each check.
