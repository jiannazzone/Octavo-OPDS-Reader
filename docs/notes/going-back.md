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

Measured before #56 with a 12-page pre-paginated EPUB made locally. #56 fixed what stopped these books opening and folding (`fixed-layout.md`), so what's left for going back is short:

- **Going back has to use the CFI.** By the saved CFI it landed on the same page, folded and unfolded. By fraction it landed one page late every time, as a relocation reports the section's end. `restore` now tries the CFI first too.
- **"Back on your page" can use `onPage`** in every book: since #56 it goes by the page's section there.
- **Check once built:** a jump inside the same spread posted no relocation before #56, so a trip shouldn't start from one.

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

### Chapter buttons

`ReaderChapterSkip` (`ReaderChapterSkipTests`), `ReaderModel.skipChapter`. Video: `going-back/videos/chapter-buttons-folded.mp4`.

- **Places to try, not sums.** An entry's fraction can be a page or two out until its section is laid out, so working out "am I on this chapter's first page?" from it would go wrong. ⏮ goes to this chapter's start, and if the page didn't move, to the one before, up to three tries. ⏭ likewise, which also steps past a chapter or a "Part Two" starting on the spread already showing.
- **Waiting for the page:** half open a move can report late and more than once, and an early look read as "didn't move", sending ⏮ a chapter too far. It now waits for the relocations to go quiet, up to 0.5 s.
- **Checked** on Moby-Dick with real taps, folded and half open: partway through a chapter, ⏮ to its heading, ⏮ to the one before, ⏭ forward again. Not run on a book with nested contents, as Adam's three books are no longer in scratch, or on a fixed-layout book.

### Hold still to zoom

Built in `ReaderScrubber.swift` (the slider) and `ReaderScrubberLine.swift` (the sums, `ReaderScrubberLineTests`). Checked on 'Octavo Navigation Duo' with real drags, folded, flat and half open, light and Night (`going-back/videos/scrubber-half-open.mp4`). A test build went on Adam's Duo; the ticks can only be felt there.

- **It's the system's `UISlider`, moving freely, with its range narrowed.** After a 0.35 s pause, `minimumValue` and `maximumValue` animate over 0.22 s to a window around the knob, so the knob stays under the finger. Tracking carries on through the change. SwiftUI's `Slider` isn't used because the dots need `thumbRect` to line up.
- **The slider eases toward the finger,** and keeps sending `valueChanged` for a moment after it lifts. Those came after the release and left a stale value that the next press went to, so `changed` ignores everything once tracking ends.
- **Letting go on a bar** goes by the contents entry's href, which lands on the heading: Moby-Dick's Chapter 60 from a catch at 50.2%. `goToFraction` of the bar's own fraction can land a page or two on, as a fraction is only placed by characters until its section has been laid out.
- **Measured on Moby-Dick:** folded the window is about 33 pages, so 60 pt of finger moved about 7 pages. Unfolded it's about 75. Pages stepped one at a time (231 to 237, the chapter's name changing on the way), a catch held over about 3 pt either side, and letting go landed on the page: 49.7% to page 493 (the first run), then 59.3% to Chapter 75.
- **Quick moves:** speed has to be read over about 120 ms and at least 12 pt, as touches arrive in bunches and a single pair read as a quick move. Zooming out while the finger is down is at once, so the knob follows the finger.
- **To check when building:**
  - VoiceOver, which should keep the slider's own adjustments.
  - Catching only within the zoom: a bar closer than 6 pt to another shouldn't happen at 8 pt per page, but two chapters can start on one page.

## Notes in real books (decision 34)

- **No test book has one:** no `noteref` or `doc-noteref`, and no superscript or numbered note link in the five samples, the bundled book, or Adam's three modern novels. Green City Wars' chapter headings do link back to its contents.
- **Links today:** `detectTaps` leaves a tap on `a[href]` alone, foliate's `link` event goes to `onLink`, and foliate then calls `goTo`. That's where a note would be caught.
- **foliate's `footnotes.js` isn't vendored** (`PINNED.md`). Reading a note from a parsed section, as `describePlace` does, runs no script.
- **There's no standard:** other readers were reported to guess, or to show only a note's first paragraph.

## The way back

Built so far: your place holds, "Back to page N", ✕, reading on, trips across closing and the fill (`ReaderTrip`, `ReaderModel+Trip`, `ReaderTripTests`). Videos: `going-back/videos/way-back-folded.mp4` (about twice real speed) and `trip-closing.mp4` (with the waits cut). Still to come: links in the book.

Measured on 'Octavo Navigation Duo' with real taps and drags, Moby-Dick (file 3) on the local BookOrbit, the server at 47.8%:

| What | Saved on the iPhone | On BookOrbit |
|---|---|---|
| Scrub to 78% | Still Chapter 55, 47.7% | Still 47.8% after 3.5 s |
| One turn, then Back | Back on the same page | Untouched, same timestamp |
| ⏭ to Chapter 56, then ✕ | Chapter 56, 48.3% | 48.3% |
| ⏭ to Chapter 57, then 4 turns | Still Chapter 56 | Still 48.3% |
| The 5th turn | Chapter 58, 49.3%, the button gone | 49.3% |

- **Jumps go through `jump`, not `goTo`,** so the debug remote's `goto`, which the check tools rely on to save and push, still does.
- **A jump starts with `beginJump` and ends with `endJump`,** which waits for the relocations to go quiet and asks `onPage` whether your place is showing. If it is, there's no trip, so a tiny scrub shows nothing.
- **Which way a turn went** comes from the shown fraction before and after, so it doesn't depend on a book's direction (no right-to-left book has been run).

### Across closing

A trip is saved per book beside the positions (`ReadingPositionStore`, `Trips/`), only on the iPhone. Your place stays as it was, so `BookPlaces` and the opening rule still hold. Opening, a trip whose place matches where the rule opens the book reopens on the trip's page; otherwise it's dropped.

| What | The book's screen | Opens at | On BookOrbit |
|---|---|---|---|
| Scrub to 76%, fold | "48% · Opens at 76%", fill from 48% to 76% | | Still 47.8% |
| Unfold, or quit and open | | That page, with "Back to page 463" | Still 47.8% |
| Back from there | | The same page as before, the trip's file gone | Still 47.8% |
| Another reader moves the server to 83.2% | "83%", no "Opens at" | 83.2%, no button, the trip's file gone | 83.2% |

### The fill

`UISlider.TrackConfiguration(allowsTickValuesOnly: false, neutralValue:, ticks: [])`, on 'Octavo Navigation Duo' with real drags, flat, folded and half open. With no ticks the knob stays free.

- **It can't go back to nil.** After `trackConfiguration = nil` the line stayed empty and the next drag didn't take. It's now always set, with a neutral of 0 when there's no trip, which looks like the plain slider.
- **The fill only redraws for a value that moves it.** Landing brings none, as the knob is already there, so the old fill stayed up. A nudge of the smallest step did nothing. `ReaderView` gives the slider a new `.id` when your place changes, and a slider made with the setting draws it right.
- **Zoomed in, the fill's start stays where it was.** It keeps the point on the screen that your place had on the whole line, whether or not your place is in the zoomed window, and it's right again after letting go. Setting the neutral with the range was worse: it left a short, wrong fill after zooming out.

## How the rest would be built

A plan, for when Adam says to build it.

- **Links:** `bridge.js` tells Swift when a link in the book jumps, so it starts a trip.
- **Files shared with other work:** `bridge.js` also changes in the fixed-layout session.
- **Keep every script-blocking layer.** No foliate patch should be needed: foliate's own `history` isn't used, as a trip has to outlive the page.

## Tools

`docs/notes/page-turns/tools/remote.sh` sends the commands, and `docs/notes/sync-spike/tools/bo.sh` reads and moves the server's place. Moby-Dick's place on the server was put back to 47.8% after each run.
