# Curl (decision 27, 2026-11-07)

Pages curl as in Apple Books, by a tap or under a finger, with UIKit's own page curl: a `UIPageViewController` with `.pageCurl`. Adam chose it on 2026-11-07 after a prototype (branch `claude/curl-prototype-5539bb`, note `docs/notes/curl-prototype.md` there, with videos and measurements). Checked on 'Octavo Curl Duo' (823D3E1C-9187-4C3B-8E24-D4A08AA3D7CD, iPhone Duo, iOS 27.1 simulator) and on Adam's iPhone Duo (00008160-001C21D136A0000A).

## What Adam decided

- **UIKit's curl, shine and all.** Its lighting puts a highlight on the inside of the curl, a little glossy for paper; UIKit has no setting for it, and drawing our own curl (a Metal page mesh) would be 2–3 weeks more.
- **Automatic curls** folded, open and half open; with Reduce Motion it still fades. **Curl** is its own choice in Page Turn (Automatic, Slide, Flip, Curl, Fade, None); picked by hand it keeps curling with Reduce Motion.
- **The tour's Turn the page hint keeps its lift** (a flip open, a slide folded): UIKit can't play part of a curl.

## How it works

`ReaderCurl.swift`, `ReaderModel+Curl.swift`.

- While pages curl, one `UIPageViewController` waits over the web view with clear pages, so the live page shows through. One page curls about its left edge (`spineLocation .min`); a spread over its spine (`.mid`, double sided), with the next page on the back of the one that turns. It's remade when the spine moves (one page or a spread). Its pages are made once and reused.
- A turn pictures the page as it is (the snapshot views the other turns use) on the clear pages, and foliate turns at once underneath (`bridge.js` `turn`). The new page is pictured where it's on the back of the turning page or comes over it; where the curl uncovers it, the page stays clear over the web view, as under a flip. A picture that comes late (a chapter loading) fades in on the moving page.
- **A tap's turn** waits up to 100 ms for the new page, then plays the whole curl (`setViewControllers(_:direction:animated:)`, about 0.43 s, UIKit's own). A tap during a curl waits for it to land (up to three queue): UIKit's curl can't end early.
- **A finger's turn** is UIKit's own pan, moved to the web view's superview (where `ReaderSwipeRecognizer` sits for the other turns; it's off while pages curl) behind a delegate (`ReaderCurlPanDelegate`) that lets it recognise beside WebKit. UIKit says no to recognising with any of WebKit's recognizers, which already hold the touch, and with that the pan never begins. The delegate also keeps it from beginning over a selection or after a press, as the other swipes.
  - UIKit asks the data source for the next page as a finger lands, so asking commits nothing. The turn starts with the curl (`willTransitionTo`): the page is pictured and foliate turns, held. Landing keeps the turn; falling back turns foliate back, and nothing is saved or synced.

## The book's ends, and a crash on the Duo

UIKit's pan asks for the next page only once it has begun, and on a spread it crashes if it gets none: `'The number of view controllers provided (0) doesn't match the number required (2) for the requested transition'`. On Adam's Duo that was a book's first page, unfolded, the left page dragged right. The simulator never began the pan there.

- The bridge's relocations say whether there's a page each way (`turnsLeft`, `turnsRight`, from foliate's `atStart` and `atEnd`; on fixed layout, whether the book's first or last page is shown).
- The pan begins only if there's a page the way the finger moves and, on a spread, on the side it touches (`ReaderCurlPanDelegate.sides`).
- Once the pan has begun, UIKit is always given pages; if there's nothing to turn to (a finger turning back past where it started), `willTransitionTo` cancels the pan, just after UIKit's own handler returns, and the page falls back.
- Callbacks from a controller since replaced (a fold) are ignored. A curl whose end UIKit hasn't reported in 2 s counts as over, and the next touch or tap puts the waiting pages back.
- Fade didn't crash on the Duo; the fix was checked there.

### Tracing on a device

`curlTrace` (`Octavo/Debug/CurlTrace.swift`) prints each step of a curl in DEBUG when Octavo is launched with `OCTAVO_CURL_TRACE` set, flushed line by line so a crash keeps the last ones. To read it from a Duo:

```bash
xcrun devicectl device process launch --device <UDID> --console --terminate-existing -e '{"OCTAVO_CURL_TRACE": "1"}' com.ianazzone.ereader
```

An uncaught exception's reason reaches the same console; the crash report (`devicectl device info files --domain-type systemCrashLogs`) leaves it out.

## Checked

- Simulator: taps forward and back, folded, flat and half open; a finger forward, and let go early; a chapter break; rapid taps (three keys 120 ms apart: three curls, one after another); unfolding and closing mid-curl (nothing left curling or held; the closed reader goes away); the book's first page.
- Adam's Duo: the curl by tap and finger, folded, flat and half open; the book's first and last page, and a drag reversing there; rapid taps; folding mid-curl; a chapter break; the place after curls that fell back; the first-page crash and its fix.
- **A tap's curl back, folded** (Adam, on the Duo): the back of the curling page came up blank. UIKit copies the back of a page that curls on one page as the curl starts, and going back that page is the new one, whose picture had just come and was fading in. The pages coming in are drawn before a tap's curl starts, and a new page fades in only if it comes mid-curl.
- Tests: `ReaderPageTurnTests` (Automatic curls, Curl kept with Reduce Motion, where UIKit takes the finger, a curl's pictures, which ways a relocation turns, which sides a finger asks for), `TourFlowTests` (the hint).

## Frame rate

Measured 2026-11-07 on Adam's iPhone Duo, a 45-second Instruments recording (Animation Hitches) of a Debug build while Adam turned pages by tap and by finger, folded and unfolded.

- **The curl runs at 60 Hz, not 120.** Every curl, a tap's (0.4–0.5 s) or a finger's (0.8–1.4 s), had 16.7 ms between swaps; one stretch of 15 s ran at 48 Hz (20.8 ms). Only the book opening reached 120 Hz, on the cover motion's own link. UIKit animates the curl, so the turn's 120 Hz `UIUpdateLink` (`page-turns.md`, Frame rate) can't drive it.
- **Hitches:** about one frame of 16.7 ms at a curl's start, and one 20.8 ms render with 33 offscreen passes.
- The one lever left: a `UIUpdateLink` asking for 120 Hz while a page curls. Beside a SwiftUI animation it lifted about a third of slides to 120 (`page-turns.md`); not tried on the curl.
- **Recording:** attaching to a running Octavo failed (`Cannot find process`), and `--all-processes` kept about a second of display data, so xctrace launched it: `xcrun xctrace record --no-prompt --template 'Animation Hitches' --device <UDID> --time-limit 45s --output <trace> --launch -- com.ianazzone.ereader`. Ending the recording ends Octavo. It left a 2.8 GB `instruments*.ktrace` in `$TMPDIR`; delete it after exporting.
