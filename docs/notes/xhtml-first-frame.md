# The first XHTML frame in a new WebKit process

Measured 2026-11-04. Simulator: **Octavo XHTML Warmup Duo** (`A13E5833-6988-42FA-8D69-737D667ECF1F`, iPhone Duo, iOS 27.1), Debug build, unfolded, sample EPUBs, on a Mac busy with other work (load average 5–70), so trust the medians over single runs. Real device: Adam's iPhone Duo (`00008160-001C21D136A0000A`, iOS 27.2), Debug build. Found while shortening CI.

## Answer

- **Cause:** not XML. The first time a WebKit process sees a frame that isn't `text/html` or `text/plain`, WebKit asks QuickLook whether it can preview that type, which loads the QuickLook framework with `dlopen` on the main thread.
- **Do readers feel it?** No. On a real Duo the frame takes 25 ms the first time in a launch and 1–6 ms in every later process, against 1.2–2.1 s on the simulator. Loading it first makes no difference to a whole open there: 264 ms against 265.5 ms.
- **Recommendation:** do nothing to the reader. The tests keep their shared page, because CI runs on the simulator and pays the full cost there.

## Cause

Each row is a new page and process, timing blob frames from `iframe.src =` to `load` (three rounds):

| First frame's type | First frame | Same type again | XHTML after it |
|---|---|---|---|
| `text/html`, `text/plain` | 2–12 ms | 2–4 ms | **1,273–1,423 ms** |
| `application/xhtml+xml`, `application/xml`, `text/xml`, `image/svg+xml`, `application/json`, `text/css`, `text/javascript`, a made-up type | **1,221–2,090 ms** | 2–15 ms | 2–4 ms |

So any type but those two pays once per process, and after that nothing does. That also explains the earlier measurements: an empty body and `sandbox` make no difference, a reload stays in the same process, and `DOMParser` on the OPF is no frame.

Sampling the process through that frame shows it. 311 of the main thread's 319 working samples are here:

```
WebCore::SubresourceLoader::didReceiveResponse
  WebCore::PreviewConverter::supportsMIMEType
    WebCore::PreviewConverter::platformSupportedMIMETypes
      PAL::initQuickLookQLPreviewGetSupportedMIMETypes
        PAL::QuickLookLibrary → dlopen
          dyld4::JustInTimeLoader::loadDependents   (280 of the 311)
```

**The app pays it too.** A launch's first frame runs the same load on the app's own main thread, through `WebPageProxy::decidePolicyForResponseShared` (76 samples, about 0.9 s under the sampler). The app can't draw during that, but only once per launch.

## Book opens in the app, on the simulator

Time from `ReaderModel.init` to the bridge's `opened`, from the reader's own log lines. The cover rests this long plus 150 ms (decision 28); unfolding on a cover shows the spinner instead. Median, with the range in brackets. Later opens are three per launch, so their median is given as a span.

| | First open after launch | Later opens |
|---|---|---|
| As it is today (6 launches) | 5,646 ms (4,209–10,883) | 1,696–1,944 ms (1,566–2,585) |
| Hidden frame when the reader page loads (5) | 4,768 ms (4,519–5,133) | 1,646–1,720 ms (1,465–2,857) |
| Warmed page kept ready before the tap (5) | 545 ms (479–615) | 158–218 ms (117–268) |

- **With and without the cost:** every open gets a new process, so every open pays. Once the frame has loaded, opening the book takes 103–152 ms, against 1,316–1,374 ms today.
- **The first open** costs about 3.8 s more than later ones. The app's own load is about 0.9 s of that. For the rest WebContent's main thread is mostly idle, waiting on WebKit's other processes starting, which isn't broken down further. The warmed page covers it too.

## Warm-ups

Neither is needed, given the Duo's numbers. Neither was kept.

**Hidden frame when the reader page loads: no.** `dlopen` blocks the main thread that JavaScript also runs on, so the cost only moves ahead of the book. The totals above don't change.

**Warmed page before the tap: works, at a price.** The app keeps one reader page loaded and warmed, with no view, and the next book opens in it.

- **Memory:** one more web process, 18 MB idle on the simulator.
- **Readiness:** ready 6.1 s after launch and 1.6 s after a close (one run). A tap before that gets a new page, as today. Making it at launch moves the app's main-thread load to launch, unless QuickLook is loaded off the main thread first (not tried).
- **Scheme handler:** the handler has to learn its book late, so it needs a place that says which book the page has. It sits inside the network and script layers, so it needs a security review. The experiment serves `/dev/null` before a book is chosen; a real version should answer 404.
- **Book scripts:** the frame holds only our own empty XHTML, and the CSP, `sandbox`, `nosniff`, the load hook and the bridge's main-frame check don't change. The formats check's script tests weren't re-run against it, and would have to be.
- **Not handled:** a spare page whose process was killed.

**Not options:** serving sections as `text/html` avoids the check but parses them as HTML, which changes the tree and breaks CFIs (`bookorbit-foliate.md`). I know of no public setting that turns the check off.

## On a real Duo

A probe test, run on the Duo with `xcodebuild test`. Every page got its own process (31 pages, 31 process IDs; 39 of 39 in the open times), so each one really is a process's first frame.

| First frame in a process | Duo | Simulator |
|---|---|---|
| A launch's first page, XHTML | 25 ms (2 runs) | over 5 s (1 run; 3.8–4 s when CI's probe measured it) |
| Later pages, non-HTML types | 2–6 ms | 1,221–2,090 ms |
| Later pages, XHTML after `text/html` or `text/plain` | 1–2 ms | 1,273–1,423 ms |

Whole opens of a small test book in a new page, from `WebPage` to `octavo.open` returning (three launches):

| | Median | Range |
|---|---|---|
| A launch's first open | 375 ms | 344–452 |
| Later opens, as today (18) | 264 ms | 243–276 |
| Later opens, frame loaded first (18) | 265.5 ms | 245–285 |

- **Why the gap fits:** on the simulator 280 of the 311 samples are `dyld_sim` walking QuickLook's dependencies, reading each library's headers and comparing paths. On a device, system frameworks come from the shared cache with their loaders prebuilt.
- **Limits:** these pages have no window and the book is small, so this isn't the whole in-app open, with its drawing and cover motion. It measures this one cost directly. The Duo runs iOS 27.2 and the simulator 27.1, and a 27.2 simulator wasn't tried: Adam expects the simulator to be the difference, not the version.
- **Left on the Duo:** the run left two small JSON files in the app's `Documents` (`xhtml-probe.json`, `xhtml-probe-open.json`), which do nothing.

## What would speed up an open on a real Duo

Worked out from the Duo's small test book and the motion's lengths, not timed in the app on a Duo. Opening from a book's screen, a later open. The book is ready 264 ms plus `ReaderView`'s 150 ms wait after the tap. Unfolded the slide runs meanwhile, and the swing waits for both. Folded there's no slide.

| | Unfolded, done at | Folded, done at |
|---|---|---|
| Cover as it was (slide 0.35 s, swing 0.5 s) | 0.91 s | 0.66 s |
| Cover a third quicker (slide 0.23 s, swing 0.33 s), as now | 0.74 s | 0.58 s |
| Also rendered before the tap (tried, dropped) | about 0.56 s | about 0.2 s |

## Rendering before the tap: tried, and dropped

The idea: while a downloaded book's screen shows, open the book at your place in a page with no view, and hand that page to the reader on Open. A prototype worked, and Adam dropped it on 2026-11-04. The code was not kept.

Time on the simulator from Open to the cover being told to swing, on a large book 29% in, unfolded. Medians, with ranges:

| | First of a launch | Later opens |
|---|---|---|
| As it is today | 6,305 ms (1 run) | 2,524 ms (2,493–2,555) |
| Held page | 429 ms (396–487) | 362 ms (353–398) |

All 9 held opens used the held page without re-rendering, and landed on the same page and layout as a normal open. A run on a busier Mac took 7,046 and 3,048 ms today.

**Why it was dropped:**
- **Small gain on a real Duo:** an estimated 0.2 s unfolded and 0.2–0.3 s folded. The big numbers above are mostly the simulator being slow. The Duo was never timed with it.
- **No help when unfolding:** unfolding on a book's screen still opens a new page, because the held page was laid out folded.
- **Ongoing cost:** every downloaded book's screen you stop on starts a web process of about 38 MB.
- **Fragile:** it needs the four workarounds below, which depend on how WebKit treats a page with no view.

**What a page with no view does, for anyone who tries this again:**
- **Size:** it's 1024×768 whatever the reader will be, and `foliate-view` is `position: fixed`. The prototype gives the body the reader's size and a `transform`, which holds `foliate-view` to it.
- **Frames:** it draws none, so `octavo.open` stops at `settle`. Timing the wait out (as `nextFrame` does since #60) leaves foliate half laid out, and opens then took 1–12 s and moved around. The prototype runs `requestAnimationFrame` on a timer until the page has a view.
- **First reports from the view:** SwiftUI reports 0×0, then the size with no fold, then the real geometry. Each would re-render a page that's already open, so the prototype ignores them until they match.
- **`position: fixed` lags:** it still measures against 1024×768 for about 0.6 s after the page reports its new size, on the simulator. Letting go of the held size sooner has foliate lay out twice. The prototype waits until a hidden fixed element measures the real size.
- **Side effects:** saving the place, syncing and bookmarks have to wait for Open. Three held pages left the saved places unchanged.
- **Folds:** a page out of the view tree gives an unfold nothing to rebuild. All 13 steps of a fold check ran without a crash, with at most one page alive.

**Not checked on the final build:** the fold run and the saved-places check ran on an earlier build, and the films from that build weren't reviewed.

## Found along the way: closed readers stay alive

After 8 opens and closes in one launch, the app held 8 `ReaderModel`s and 8 `WebPage`s, and 8 WebContent processes were running, at about 31–37 MB each on the simulator (`heap`, `footprint`). Neither of the two I watched for 100 s exited. The unpatched baseline shows the same processes piling up; one exited on its own in six launches. `leaks --traceTree` shows a suspended Swift task capturing the `ReaderModel`, on a continuation; which task isn't known yet. It hasn't been checked in a Release build. This is separate from the frame cost, and hasn't been measured on a real Duo. #60 fixed it.
