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
- **A tick doesn't work on the scrubber.** `SliderTick` locks the knob onto its ticks: at page 876 the knob sat on the tick at 47.8%. UIKit's track configuration has `allowsTickValuesOnly`, defaulting to YES; SwiftUI's `Slider` doesn't take that setting. So there's no native mark for your place.
- Not yet seen: whether the knob slides home along the line when Back is tapped.

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
