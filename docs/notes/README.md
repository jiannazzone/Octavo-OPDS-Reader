# Engineering notes

Write-ups from the first spike (2026-10-31). The tracker with phases, results and decisions is `docs/SPIKE.md`; the decisions that stuck are in `CLAUDE.md`.

| Note | Spike | What it covers |
|---|---|---|
| `bookorbit-foliate.md` | 1a | How BookOrbit uses foliate-js, why we pin `6b11e17`, the CFI-compatibility analysis |
| `reader-spike.md` | 1a | Reader wiring: `WebView`, the `octavo://` scheme handler, the bridge, book-script blocking, getting books into the app |
| `bookorbit-api.md` | 1b, 2a | BookOrbit v3.6.0 API behaviour: native auth and token rotation, validation, progress format, library shapes, networking |
| `readium-spike.md` | 1c | Readium bake-off: 30/30 position matches, costs, why foliate-js was kept. Code on branch `spike/readium-eval` |
| `sync-spike.md` (+ `sync-spike/`) | 2a | Position sync with BookOrbit's web reader: 31/31, the disagreement rule, repro tools and screenshots |
| `foliate-blank-page-upstream.md` (+ `foliate-blank-page/`) | vetting | The foliate-js blank-page bug: cause, fix (patch 0001), draft upstream issue and PR (not sent), re-check harness |
| `duo-spreads.md` (+ `duo-spreads/`) | 2b | Duo layout: hinge APIs, one/two pages, gap at the hinge, position across folds, cover-display handoff, open UX questions |
| `duo-fold.md` (+ `duo-fold/`) | #5 | One re-layout per fold under a cross-fade, book mode (angles, taps, spine shadow), the cold-launch page-size fix, measuring tools and videos |

The sessions' raw run logs and screenshots weren't all committed. What's here is enough to re-run each check.
