# A closed reader goes away (2026-11-04)

Does closing a book release its `ReaderModel`, its `WebPage` and the page's WebKit content process? It didn't, in the real app or in tests. Now it does. Measured on 'Octavo Reader Release Duo' (F6860649-97DB-4A2F-881A-400BB68B8212, iPhone Duo, iOS 27.1 simulator), debug builds.

## Summary

- **The app leaked.** Opening and closing five books left four models, pages, web views and content processes alive 15 s later, and they would have stayed until the app quit. It happened on Back, and on most other ways out (table below).
- **Cause:** the web view leaves the window as the reader closes, and the page reports another size. The model answers with `setLayout`, and the bridge's `setLayout` waits for a frame. A page off the window draws no frames, so the call never ends, and the `Task` in `ReaderModel.call` waiting for it holds the model, which holds the page.
- **Fix:** `close()` ends the page's say (`phase == .closed`: no more messages, no more calls), and no bridge call waits more than a second for a frame (`nextFrame`).
- **Tests were held the same way.** A page that's never shown draws no frames. While `ReaderFixedLayoutTests` ran, this simulator's content processes climbed to 48 without the bridge's part of the fix, and peaked at 2 with it.
- **Tests:** `OctavoTests/ReaderCloseTests.swift`. All three fail with the fix's layers off.
- **Not measured:** a real device, or a Release build. `ReaderRemote` only exists in debug builds, but nothing in the cause does.

## 1. What holds the model

The timeline of one close, from temporary logging:

```
14:28:07.829  reader disappeared
14:28:07.959  viewport 1024.0x768.0
14:28:07.967  call start setLayout(layout)
14:28:08.045  viewport 466.0x678.0
14:28:08.045  call start setLayout(layout)
              (no call end, no deinit)
```

- As the web view leaves, the page reports 1024×768, then its old size. The bridge's `ResizeObserver` on the page's root sends these, and the model lays out for them (`.viewport` → `updateGeometry` → `relayout` → `call`).
- `setLayout` → `applyLayout` → `await nextFrame()` → `requestAnimationFrame`, which never fires. On screen it fires within 23 ms, measured in the same headless simulator with `visibilityState` `visible`.
- The `Task` around `callJavaScript` in `call` holds `self` and the page, so a call that never ends keeps the model, the page, the web view and the process.
- A close that didn't leak had no such message before its model went, 330 ms after the close. That's why one in five got away.

`leaks --traceTree=<model address> <pid>` (`liveReaders` gives the addresses) names one holder, a `Task stack`, but its path to a root is misleading: it runs through a stale slot in `WKURLSchemeHandlerAdapter.tasks`, as if the scheme handler held the model. Reading that task's stack in `lldb` (`memory read --format A`) shows what it is: frames of `closure #1 in ReaderModel.call`, with the 44-character literal `return await window.octavo.setLayout(layout)`. `swift-inspect` couldn't attach ("unable to get task for pid").

Only `bridge.js` waits on frames. foliate-js's own `requestAnimationFrame` calls are never awaited, apart from `animate`, which we don't use (the paginator isn't `animated`) and which checks `document.hidden`.

## 2. The fix

**`ReaderModel.close()`** sets `phase = .closed`, ends any fold under way and flushes pushes as before. `handle` drops every message once closed, and everything that talks to the page already checks `phase == .open`. `openBook` stops if the reader closed while it was asking the server, instead of opening the whole book in a page nobody can see. `ReaderView` starts `close()` with `Task.immediate`, so it's closed before the page's messages arrive.

**`nextFrame` in `bridge.js`** gives up after a second. That covers a call already under way as the reader closes (a turn, a jump, a re-layout, an open), which `close()` can't stop. On screen a frame comes long before that, so nothing changes there. A closed page's calls end within a few seconds.

**Both parts are needed.** Each alone, measured:

| Only | Readers | The place |
|---|---|---|
| `nextFrame` | All go, about 2 s after closing | **Moves.** A fold that closes a BookOrbit book: saved and server went from `/140/3:47` to `/130/3:105`, because the fold's `setLayout` now finishes and re-renders the closed page |
| `close()` | Closed mid-turn, 2 of 7 stay. Closed mid-re-layout, 3 of 6 stay | Not measured |

So the old hang was also why a close never moved the place: `applyLayout` shadows `render` while it waits, and it never stopped waiting.

**Rule from here:** anything in `bridge.js` that a Swift call awaits has to finish without frames.

**One trade-off:** a relocation that arrives after the close is dropped. A turn or a jump into a section still loading when Back is tapped isn't saved, and the book reopens on the page last seen.

## 3. Measured in the app

`tools/check.py`, on what's alive 15 s after the last close. Models, pages, web views and content processes were always the same number, so one column stands for all of them. The content processes are counted under this simulator's `launchd_sim`, so other sessions don't count.

| Way out | Readers opened | Alive before | Alive after |
|---|---|---|---|
| Closed while reading (`plain`) | 5 | 4 | 0 |
| Back (`back`) | 5 | 4 | 0 |
| Back, fixed-layout book (`fixed`) | 3 | 3 | 0 |
| Closed 0–2.5 s into opening (`while_opening`) | 7 | 3 | 0 |
| Closed 0–200 ms into a turn (`while_turning`) | 7 | 7 | 0 |
| Closed 0–600 ms into a jump (`while_jumping`) | 6 | 5 | 0 |
| Closed 0–600 ms into a re-layout (`while_laying_out`) | 6 | 6 | 0 |
| Folding closes the book (`folding`) | 4 | 1 | 0 |
| Back after the background (`away`) | 1 | 1 | 0 |
| BookOrbit, with its pull, push and cover motion (`synced`) | 3 | 3 | 0 |

After the fix nearly every reader had gone 1 s after its close. Two closed mid-open lasted past that, and were gone by the next row. Before the fix, closes up to 600 ms into opening didn't leak, and those from 1 s on did.

**Nothing else stops a reader** (`stays_open`): it still turns after opening folded, unfolding, half open, flat, landscape and back, and coming back from the background.

**The place holds** (`place_kept`): on Back, on a fold, and with a re-layout under way as it closes, the saved places are the same 5 s later, and for a BookOrbit book so is the server's. A re-layout just before closing does move the place, as it would with the book open: it's the reader's own.

## 4. In tests

`ReaderFixedLayoutTests`, content processes under this simulator every second:

| | Peak | At the end |
|---|---|---|
| With the fix | 2 | 1 |
| Without the `nextFrame` change | 48 | 48 |

So tests and the app were held the same way. The suite's own `requestAnimationFrame` stand-in (`window.requestAnimationFrame = f => setTimeout(f, 16)`) goes in after the book opens, too late for a call already waiting.

The suite's time didn't clearly change: 82.7 s with the fix against 82.1 s without, then 109.6 s against 94.0 s with the sampler running and other sessions loading the Mac. All 476 app tests pass. `goesAwayWithACallWaitingForAFrame` takes about 7 s: it opens a book and waits out the real limit.

## 5. Running it again

The debug build's `ReaderRemote` has `liveReaders`, `back` and `closeAfter` for this.

```bash
DOCS=$(xcrun simctl get_app_container <udid> com.ianazzone.ereader data)/Documents
cp SampleBooks/*.epub "$DOCS/"
python3 docs/notes/fixed-layout/tools/make-test-book.py "$DOCS/fixed.epub"
python3 docs/notes/reader-release/tools/check.py <udid> plain back fixed while_opening while_turning while_jumping while_laying_out folding away synced place_kept stays_open
```

`synced` and `place_kept` need the local BookOrbit (`dev/bookorbit/README.md`).
