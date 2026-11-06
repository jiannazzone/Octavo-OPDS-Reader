# Accessibility: the App Store's labels (#73)

What Apple asks for, the common tasks that have to work, and what's been checked on what. Started 2026-11-05 on 'Octavo Accessibility Duo' (FC72C74F-084F-4FEC-985D-758B080D588A, iPhone Duo, iOS 27.1 simulator). Each slice of #73 fills in its own column.

## Summary

- **Nothing is claimed yet.** Claiming happens in App Store Connect, on the owner's say, once a label's column is full for that device.
- **Dark Interface (#77) and Reduced Motion (#80):** checked across the common tasks below, except what's listed under Not checked: on the simulator, then by Adam on his Duo (2026-11-05, at 1e6a5cf).
- **Labels are per device.** The app builds for iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`), so iPad needs its own pass or its own "no".
- **Captions and Audio Descriptions stay unclaimed.** The app has no video or audio, and Apple's pages offer no "not applicable".

## What Apple asks

From Apple's App Store Connect pages on the labels, read 2026-11-05:

- A label needs people to be able to complete **all** common tasks with that feature: the primary functions, first launch ("complete or skip"), login and settings. Purchase only if it's offered.
- **Third-party content:** an app needn't make all of it accessible, but gives its creators a reasonable way. WebKit's HTML, CSS and ARIA support is the named way for web views. Book colours and covers fall under this for Dark Interface.
- **Dark Interface:** dark by default, or a setting or the system's Dark Mode that keeps it dark. Temporary flashes count.
- **Reduced Motion:** spinning, scaling, depth and multi-axis motion change or go away when the setting is on. Meaningful motion stays as a dissolve or fade. An in-app setting with finer control may stand in.
- **Larger Text:** 200%, or the system's maximum. An in-app control counts, with Apple Books as the example.
- **Sufficient Contrast:** 4.5:1 for most text and commonly 3:1 for non-text, by default, or check that Increase Contrast does enough.
- **Differentiate Without Color:** common tasks don't rely on color alone. Grayscale is the suggested test.

## Common tasks

✓ means checked on the simulator with that feature on, folded and unfolded unless it says otherwise. A blank is not yet checked. VoiceOver and Voice Control need a person on a real Duo, so a ✓ there means Adam ran it.

| Task | Dark | Motion | Color | Contrast | Larger Text | VoiceOver | Voice Control |
|---|---|---|---|---|---|---|---|
| **First launch:** the tour, or Skip | ✓ unfolded | ✓ unfolded | | | | | |
| **Sign in:** BookOrbit, a wrong password | ✓ unfolded | ✓ unfolded | | | | | |
| **Sign in:** an OPDS catalog (COPS, no password), Trust this server | ✓ unfolded | ✓ unfolded | | | | | |
| **Find a book:** Home, Library, Search's first screen | ✓ | ✓ | | | | | |
| **A book's screen:** details | ✓ | ✓ | | | | | |
| **A book's screen:** download, the remove prompt | ✓ unfolded | ✓ unfolded | | | | | |
| **Read:** open, fold, unfold, close | ✓ | ✓ | | | | | |
| **Read:** turn a page | ✓ Duo | ✓ Duo | | | | | |
| **In the book:** controls, Contents, Text and Theme, bookmark | ✓ | ✓ | | | | | |
| **In the book:** search, a result | ✓ unfolded | ✓ unfolded | | | | | |
| **Read:** half open | ✓ Duo | ✓ Duo | | | | | |
| **In the book:** footnotes, going back | | | | | | | |
| **Other ways in:** Import from Files, Open in Octavo | | | | | | | |
| **Settings:** the list | ✓ | ✓ | | | | | |
| **Settings:** a server's page, Books on iPhone | ✓ unfolded | ✓ unfolded | | | | | |

"✓ Duo" means only on Adam's Duo. He ran these with Dark Mode and Reduce Motion on, and all passed: a book's screen and Back, a swipe back, a Settings page, opening a book, turning pages, the panels, a bookmark and a search result unfolded; folding while reading, half open and folding on Home; the book sheet, opening a book, turning pages and the panels folded; Show the tour and Skip.

## Reduced Motion

What each motion does with the setting on:

| Motion | With Reduce Motion | Where |
|---|---|---|
| A pushed screen, Back | Fades, 0.2 s | `ScreenStack` |
| Screens re-laying out on a fold | At once | `ScreenStack` |
| A swipe back | Follows the finger, then fades when let go | `ScreenStack` |
| Page turn, Automatic | Fades, 0.3 s | `ReaderPageTurn` |
| Page turn, picked by hand | Stays. It's the reader's own choice (Adam, `docs/design/direction.md`), which Apple's finer in-app setting allows | `ReaderPageTurn` |
| Opening and closing a book | Fades, 0.3 s | `ReaderCoverMotion` |
| Reader panels, note card | Fade | `ReaderTextPanel`, `ReaderNoteCard` |
| Bookmark ribbon, search bar, server place bar | Fade | `ReaderView` |
| Scrubber's zoom, the tour's page lift | Off | `ReaderScrubber`, `ReaderPageTurn.hintMotion` |
| The book sheet, folded | Grows without the bounce, 0.2 s, as the system's sheets do | `BookSheet` |
| The download check | Fades | `DownloadBadge` |
| The download ring's progress | Stays, since it's the progress | `DownloadBadge` |

Seen frame by frame in recordings with the setting on: pushes, Back and Settings cross-fading unfolded (`accessibility/reduce-motion-pushes.jpg`), and a book opening folded (`accessibility/reduce-motion-opening.jpg`). Adam watched the rest on his Duo, except the download check, which is from the code.

## Dark Interface

Match Dark Mode is on by default, which gives Night, and every other screen follows the system. Nothing in the app forces a light surface. The one hard-coded white, a fold snapshot's fallback fill, now takes the page's paper (`ReaderFoldCover`).

Measured from `simctl io recordVideo` by each frame's average brightness (ffmpeg's `signalstats` YAVG, 0–255), with the simulator in Dark Mode and on a new install. Covers are book content, which Apple excludes.

| Recording | Frames | Peak | What the peak is |
|---|---|---|---|
| Unfolded: first launch to reading, Settings | 1777 | 72.6 | Moby Dick's grey cover |
| Folded: book's screen, opening, closing | 435 | 124.9 | The same cover, filling the screen |
| Unfolded in the reader, folding and unfolding in Night | 303 | 41.6 | Night's own page, full of text |

A recording of an inactive display isn't what anyone sees: display 1 holds an old frame while the Duo is open. The OPDS form, the trust prompt, the remove prompt and Settings folded were checked from screenshots, not recordings. The screens are in `accessibility/dark-unfolded.jpg`, `dark-folded.jpg` and `dark-servers.jpg`.

## How to check

```bash
# On your own named simulator. Relaunch the app after changing Reduce Motion.
xcrun simctl ui <udid> appearance dark
xcrun simctl spawn <udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool true
xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large
xcrun simctl ui <udid> increase_contrast enabled
# One recording at a time: display 3 unfolded, display 1 folded
xcrun simctl io <udid> recordVideo --display=3 --force flow.mov
ffmpeg -i flow.mov -vf "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=yavg.txt" -f null -
```

`tools/probe.sh` runs a UI test in its own project, headless, that reads the running app's accessibility tree and runs Apple's audit:

```bash
docs/notes/accessibility/tools/probe.sh start <udid>
docs/notes/accessibility/tools/probe.sh tap Library
docs/notes/accessibility/tools/probe.sh audit
docs/notes/accessibility/tools/probe.sh stop
```

Where it misleads:

- **The tree and the audit include what the code hides** with `accessibilityHidden`, so they can't show what VoiceOver skips, and the audit's counts are rough.
- **The audit's contrast part returns nothing unfolded.** Run it folded.
- **A tap can wait a minute.** After a fold, XCUITest often logs "App animations complete notification not received" and goes on after 60 s. The app sits at about 0% CPU meanwhile.
- **VoiceOver starts on the simulator, but scripted gestures don't move its cursor.** It needs a person on a device.

## Not checked

- A plain iPhone or an iPad.
- The blank rows above: footnotes, going back, Import from Files, Open in Octavo.
- With Reduce Transparency on, or Bold Text.
- CBZ and fixed-layout books.
- The tour's later cards. Apple's first-launch test is complete or skip, and Skip was checked.
- The Search tab's results, and an OPDS catalog that asks for a password.
