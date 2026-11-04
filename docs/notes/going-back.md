# Going back after a jump (decision 33)

Decision 33 in `docs/design/direction.md`. Written 2026-11-04 on 'Octavo Navigation Duo' (F7C03777-468D-4B9C-9E47-AAD7FF706A88, iPhone Duo, iOS 27.1 simulator), against the local BookOrbit v3.6.0. These are the measurements behind the design. Nothing is built yet.

## What a jump does today

Moby-Dick (file 3), with the place on the server at 47.8%, driven with the debug remote's `goto`. That makes the same `ReaderModel.goTo(fraction:)` call as the scrubber.

| What | Saved on the iPhone | On BookOrbit |
|---|---|---|
| Scrub to 80% | At once, `needsPush` true | Still 47.8% at 1.5 s, 80.1% by 3 s |
| Jump by CFI to Chapter 8 (as Contents does) | At once | 9.8% by 3.5 s |
| Close and reopen | Opens at 9.8%, from the server | |

Every jump goes through `moved(to:)`, which saves and hands the place to the pusher. A link in the book does too: foliate's `link` event calls `view.goTo`, and Swift only sees a relocation.

- **Count turns, not relocations.** A scrub posted 5 relocations and a CFI jump 4.
- **The controls can't hold the button.** They hide on the next tap, and after a choice in Contents or Search (`backToReading`).

## Fixed-layout books

Measured with a 12-page pre-paginated EPUB made locally. Their own fix is a separate session (`make-fixed-layout-epubs`).

- **They don't open today.** "Couldn't Open": `renderer.setStyles` doesn't exist on the fixed-layout renderer (`bridge.js`, since 522014f). With `setStyles?.(...)` as a temporary change, they open.
- **A fold then breaks.** `applyLayout` calls `renderer.render()`, which doesn't exist there, so the fold's hold never ends.
- **Going back has to use the CFI.** By the saved CFI it landed on the same page, folded and unfolded. By fraction it landed one page late every time: a relocation reports the section's end (`fraction: 0, size: 1`), and `goToFraction` of that is the next section. `restore` goes by fraction first, so each open creeps forward a page.
- **`onPage` is always false there**, as the section-level CFI collapses to a point. "Back on your page" needs `CFI.compare` of the two points. A jump inside the same spread posts no relocation.

## The line

Tried in `ReaderProgressBar` as a temporary change, reverted, on real pages at 90% and 3%, folded and flat.

- **`Slider(value:in:neutralValue:)` does it natively** (iOS 26): the fill runs from the neutral value to the knob, in either direction, on the glass. The book's screen can use the same slider without its knob, as the book-mode readout already does.
- **A tick doesn't work on the scrubber.** `SliderTick` locks the knob onto its ticks: at page 876 the knob sat on the tick at 47.8%. So there's no native mark for your place.
- Not yet seen: whether the knob slides home along the line when Back is tapped.

## Chapters on the scrubber (decision 35)

Temporary changes, all reverted, driven with real drags (`touch_path`) on 'Octavo Navigation Duo', folded.

- **iOS's own detents are hard.** `UISlider.TrackConfiguration` draws dots under the track, but even with `allowsTickValuesOnly: false` every value the slider reported was a tick: 8 of 8 on Moby-Dick (35 ticks) and 4 of 4 on Standard Ebooks' Pride and Prejudice. SwiftUI's `Slider` has no such setting. With ticks, a page inside a chapter can't be reached.
- **A soft catch on the plain slider works.** The knob stays with the finger: setting `value` during tracking doesn't make it lag, and the raw value kept moving 0.0034 per point. Letting go in a catch landed on that chapter's start.
- **But it takes most of the track.** With 3 pt either side and dots at least 6 pt apart, Moby-Dick was caught for 37 samples of 44. The folded track travels 259 pt, so 38 chapters are 6.8 pt apart (88% caught), 69 are thinned to 7.5 pt (80%) and 12 are 21.6 pt (28%). 1 pt either side frees it, but that's about what a finger can hold.
- **1 pt of scrubber is about 4 of Moby-Dick's 974 pages** folded (259 pt of travel), and 1.6 flat (604 pt).
- **The chapter's name between two 44 pt buttons** has 208 pt folded and 189 pt half open. Share of Contents entries that fit folded: Dungeon Anarchist's Cookbook 97%, Trust 98%, Green City Wars 94%, Standard Ebooks' Pride and Prejudice 100%, Moby-Dick 73%, Gutenberg's Pride and Prejudice 57%. Beside the scrubber, with its 296 pt: 97%, 100%, 100%, 100%, 91%, 87%.
- **Contents sizes:** Green City Wars 38 entries (two levels), The Dungeon Anarchist's Cookbook 47, Standard Ebooks' Pride and Prejudice 65, Trust 69 (three levels), Moby-Dick 145.

### Hold still to zoom

A test build, on 'Octavo Navigation Duo' with real drags and on Adam's Duo, not yet the real thing.

- **It's the system's `UISlider`, moving freely, with its range narrowed.** After a 0.35 s pause, `minimumValue` and `maximumValue` animate over 0.22 s to a window around the knob, so the knob stays under the finger. Tracking carries on through the change. SwiftUI's `Slider` isn't used because the dots need `thumbRect` to line up.
- **Measured on Moby-Dick:** folded the window is about 33 pages, so 60 pt of finger moved about 7 pages. Unfolded it's about 75. Pages stepped one at a time (231 to 237, the chapter's name changing on the way), a catch held over about 3 pt either side, and letting go landed on the page: 49.7% to page 493 (the first run), then 59.3% to Chapter 75.
- **Quick moves:** speed has to be read over about 120 ms and at least 12 pt, as touches arrive in bunches and a single pair read as a quick move. Zooming out while the finger is down is at once, so the knob follows the finger.
- **To check when building:**
  - That `TrackConfiguration(neutralValue:)` with no ticks leaves the knob free, for the trip's fill (decision 33), and how the fill behaves when your place is outside the zoomed window.
  - Half open, which hasn't been run.
  - VoiceOver, which should keep the slider's own adjustments.
  - Catching only within the zoom: a bar closer than 6 pt to another shouldn't happen at 8 pt per page, but two chapters can start on one page.

## Notes in real books (decision 34)

- **No test book has one:** no `noteref` or `doc-noteref`, and no superscript or numbered note link in the five samples, the bundled book, or Adam's three modern novels. Green City Wars' chapter headings do link back to its contents.
- **Links today:** `detectTaps` leaves a tap on `a[href]` alone, foliate's `link` event goes to `onLink`, and foliate then calls `goTo`. That's where a note would be caught.
- **foliate's `footnotes.js` isn't vendored** (`PINNED.md`). Reading a note from a parsed section, as `describePlace` does, runs no script.
- **There's no standard:** other readers were reported to guess, or to show only a note's first paragraph.

## How it would be built

A plan, for when Adam says to build it.

- **A trip per book:** your place, the page you're on, and the turns forward since landing, saved beside the positions and only on the iPhone. `ReadingPositionStore` keeps your place, unchanged, so `BookPlaces` and the opening rule still hold, and a killed app loses nothing.
- **`ReaderModel`:** Swift's own jumps start a trip, and `bridge.js` tells Swift when a link does. While away, `moved(to:)` updates the trip and doesn't save or push. Back goes by CFI and pushes nothing, like `goToServerPlace`. ✕ and the fifth turn save and push the page.
- **Opening:** a trip whose place still matches where the rule opens the book reopens on the trip's page. Otherwise it's dropped.
- **BookOrbit's capsule while away:** `keepThisPlace` sends your place, not the visible page, and `offeredOn` stops leaving the capsule on a trip's turns.
- **Files shared with other work:** `bridge.js` also changes in the fixed-layout session. `BookSheet.swift` isn't touched by the covers pull request (#54).
- **Keep every script-blocking layer.** No foliate patch should be needed: foliate's own `history` isn't used, as a trip has to outlive the page.

## Tools

`docs/notes/page-turns/tools/remote.sh` sends the commands, and `docs/notes/sync-spike/tools/bo.sh` reads and moves the server's place. Moby-Dick's place on the server was put back to 47.8% after each run.
