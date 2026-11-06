# Accessibility: the App Store's labels (#73)

What Apple asks for, the common tasks that have to work, and what's been checked on what. Started 2026-11-05 on 'Octavo Accessibility Duo' (FC72C74F-084F-4FEC-985D-758B080D588A, iPhone Duo, iOS 27.1 simulator). Each slice of #73 fills in its own column.

## Summary

- **Nothing is claimed yet.** Claiming happens in App Store Connect, on the owner's say, once a label's column is full for that device.
- **Dark Interface (#77) and Reduced Motion (#80):** checked across the common tasks below, except what's listed under Not checked: on the simulator, then by Adam on his Duo (2026-11-05, at 1e6a5cf).
- **Sufficient Contrast (#79):** met only with Increase Contrast on, which Apple allows. By default `.secondary` text is about 3.4:1 in light. The rows below say what's been measured.
- **Differentiate Without Color (#78):** nothing checked relies on color alone, judged from grey versions of the screenshots.
- **Larger Text (#76):** the app's own words wrap or stack at the accessibility text sizes, and book text stays on its own A− A+ control, up to 200%. The rows below say what's been seen, and nothing has run on a real Duo.
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
| **First launch:** the tour, or Skip | ✓ unfolded | ✓ unfolded | ✓ unfolded | ✓ unfolded, light, first card | ✓ unfolded | | |
| **Sign in:** BookOrbit, a wrong password | ✓ unfolded | ✓ unfolded | | | The fields, folded | | |
| **Sign in:** an OPDS catalog (COPS, no password), Trust this server | ✓ unfolded | ✓ unfolded | | | | | |
| **Sign in:** an OPDS catalog with a password, a wrong password | ✓ folded | ✓ folded | ✓ folded | ✓ unfolded | | | |
| **Find a book:** Home, Library, Search's first screen | ✓ | ✓ | ✓ folded | ✓ folded | ✓ | | |
| **Find a book:** the Search tab's results | ✓ folded | ✓ folded | ✓ folded | | ✓ folded | | |
| **A book's screen:** details | ✓ | ✓ | ✓ folded | ✓ folded | ✓ | | |
| **A book's screen:** download, the remove prompt | ✓ | ✓ | ✓ folded | Open only | Open only | | |
| **Read:** open, fold, unfold, close | ✓ | ✓ | ✓ folded | ✓ folded | Open, close | | |
| **Read:** turn a page | ✓ Duo | ✓ Duo | | | ✓ unfolded | | |
| **In the book:** controls, Contents, Text and Theme, bookmark | ✓ | ✓ | ✓ folded | ✓ | ✓ | | |
| **In the book:** search, a result | ✓ | ✓ | ✓ folded | The field only | ✓ folded | | |
| **Read:** half open | ✓ Duo | ✓ Duo | | | | | |
| **In the book:** footnotes, going back | ✓ | ✓ | ✓ folded | | Going back, folded | | |
| **Other ways in:** Import from Files, Open in Octavo | ✓ folded | ✓ folded | ✓ folded | | | | |
| **Settings:** the list | ✓ | ✓ | ✓ folded | ✓ folded | ✓ | | |
| **Settings:** a server's page, Books on iPhone | ✓ | ✓ | ✓ folded | A server's page, unfolded | A server's page, unfolded | | |

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

Seen frame by frame in recordings with the setting on: pushes, Back and Settings cross-fading unfolded (`accessibility/reduce-motion-pushes.jpg`), and a book opening folded (`accessibility/reduce-motion-opening.jpg`). Adam watched the rest on his Duo, except the download check, which is from the code. Footnotes, going back, Import from Files, Open in Octavo and the rows marked folded were walked with the setting on, and their motion is from the code, not watched.

## Dark Interface

Match Dark Mode is on by default, which gives Night, and every other screen follows the system. Nothing in the app forces a light surface. The one hard-coded white, a fold snapshot's fallback fill, now takes the page's paper (`ReaderFoldCover`).

Measured from `simctl io recordVideo` by each frame's average brightness (ffmpeg's `signalstats` YAVG, 0–255), with the simulator in Dark Mode and on a new install. Covers are book content, which Apple excludes.

| Recording | Frames | Peak | What the peak is |
|---|---|---|---|
| Unfolded: first launch to reading, Settings | 1777 | 72.6 | Moby Dick's grey cover |
| Folded: book's screen, opening, closing | 435 | 124.9 | The same cover, filling the screen |
| Unfolded in the reader, folding and unfolding in Night | 303 | 41.6 | Night's own page, full of text |

A recording of an inactive display isn't what anyone sees: display 1 holds an old frame while the Duo is open. The OPDS form, the trust prompt, the remove prompt and Settings folded were checked from screenshots, not recordings. The screens are in `accessibility/dark-unfolded.jpg`, `dark-folded.jpg` and `dark-servers.jpg`.

## Sufficient Contrast

Apple asks for 4.5:1 for most text and commonly 3:1 for non-text, by default or with Increase Contrast. Read from screenshots with `tools/contrast.py`, on the simulator, folded unless it says otherwise:

| What | Default | Increase Contrast | With Reduce Transparency too |
|---|---|---|---|
| `.secondary` on a plain screen, light | 3.4 | 6.0 | 6.0 |
| `.secondary` on a plain screen, dark | clean in the audit | 7.1 to 8.5 | 7.1 to 8.5 |
| The reader's footer, by theme | | Sepia 5.3, Original 6.0, Night 8.0 | |
| Words on glass (Text and Theme, Contents, the bar, the book sheet) | 2.9 to 3.8, light | Was 4.3 to 4.9. Now 13.6 to 21 | Was 4.3 to 4.8. Now 15 to 21 |
| The current Contents row, tint on its band | | 8.0 light, 6.4 dark | 8.2 light, 6.9 dark |
| Open in Dark Mode, filled | Was 1.7. Now 12.2 | Was 1.7 | Was 1.7 |
| Open in Light Mode, filled | 9.1 | 10.8 | |
| An error's words | | 4.6 light, 7.2 dark, unfolded | |
| Chevrons, `.tertiary` (non-text) | | 3.1 to 5.0 | 3.1 to 5.0 |

Two fixes, in `Octavo/Shell/ContrastStyles.swift`:

- **`.secondaryOnGlass`:** `.primary` with Increase Contrast on, otherwise `.secondary`. With the setting off, the three screens compared have identical pixels. Pictures: `accessibility/increase-contrast-glass.jpg`.
- **`.onAccent`:** the words on a filled button, black in Dark Mode and white in light, because the system's white on the dark-mode accent (decision 31) is 1.7:1 and Increase Contrast doesn't change it. A disabled button still looks disabled, seen with Open forced off. Pictures: `accessibility/dark-filled-buttons.jpg`.

**The system's placeholders are left alone:** the Search tab's is 3.9 in light and 4.9 in dark with Increase Contrast. Apple's audit doesn't flag it.

Bold Text was walked folded and nothing broke; rows wrap. Reduce Transparency makes the glass opaque (`EnhancedBackgroundContrastEnabled`).

## Differentiate Without Color

Grey versions of the same screenshots, folded, light and dark, plus the first tour card unfolded. Each state has something besides color:

| State | Besides color |
|---|---|
| The selected tab | A pill behind it |
| The selected theme | A thicker ring |
| The current Contents row | A band |
| A search match in the results | Bold |
| A search match on the page | A box |
| A bookmark | Filled symbol, and the ribbon |
| A downloaded book | A check |
| Progress | The bar's length, and a percentage |
| Switches | The thumb's position |
| An error | A symbol and words |
| An open panel's button | The panel itself |
| The button the tour asks for | The card names it |

## Larger Text

Apple asks for 200%, or the system's maximum, without overlapping or severe truncation. Dynamic Type passes 200% at AX3 (`accessibility-extra-large`) and reaches over 300% at AX5. The screens were read at both, folded and unfolded as the table says. Everything here applies only at the accessibility text sizes, in `Octavo/Shell/LargerText.swift`. Pictures at AX3: `accessibility/larger-text-before-after.jpg`.

| What | At the accessibility text sizes |
|---|---|
| Titles, authors, list rows | Wrap instead of cutting off (`.lineLimit(untilLargerText:)`) |
| The book sheet | The title wraps, and Open sits under it at full width. Pulled up, the details scroll and the title stays whole |
| A book's screen | Mark finished over Open, the place over when it synced (`LargerTextStack`) |
| Text and Theme | Themes are rows with the name beside the swatch, because a name under a quarter of the panel broke mid-word. Customize's labels sit over their values, because a menu wider than the panel pushed everything off its edges |
| Contents | The chapter's name in full, the page number under it |
| The progress bar | The chapter's name wraps |
| The footer | Stops growing at AX2, about 218%. Folded, it leaves out the chapter, which was a letter or two |
| The way back, the server's place | Stop growing at AX2, 200%, on one line, and shrink a little if a long line needs it. Beyond that the way back's ✕, its only way to stay, went off the screen, and the server's capsule covered the page. The capsule leaves out the chapter, and the way back's page numbers go |
| The tour's cards | The words scroll inside the card, so its title stays on it and its buttons stay in reach |
| Search and Setup's fields | Grow with their text |

**Book text keeps its own control:** A− A+ goes from 80% to 200%, and the system's size doesn't change it. Apple names Apple Books as the example of this. Footnote cards follow it too.

**Left alone:**

- The side column's buttons and the tour's Skip stay about the same size, as Apple says a tab bar may. They don't offer the Large Content Viewer yet.
- The Contents and Bookmarks switch and the margins switch are the system's segmented controls, which don't grow.
- At AX5, "Languages" in the Library breaks as "Lan-guages", and an address such as localhost:3320 breaks where it must.

## How to check

```bash
# On your own named simulator. Relaunch the app after changing Reduce Motion.
xcrun simctl ui <udid> appearance dark
xcrun simctl spawn <udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool true
xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large
xcrun simctl ui <udid> increase_contrast enabled
xcrun simctl spawn <udid> defaults write com.apple.Accessibility EnhancedBackgroundContrastEnabled -bool true
xcrun simctl spawn <udid> defaults write com.apple.Accessibility EnhancedTextLegibilityEnabled -bool true
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
- **On glass it fails text that's fine,** down to 20:1 black on white. Read those from the pixels with `tools/contrast.py`, and take the screenshot first, because the audit can move a list.
- **A tap can wait a minute.** After a fold, XCUITest often logs "App animations complete notification not received" and goes on after 60 s. The app sits at about 0% CPU meanwhile.
- **VoiceOver starts on the simulator, but scripted gestures don't move its cursor.** It needs a person on a device.

## Not checked

- A plain iPhone or an iPad.
- CBZ and fixed-layout books.
- The tour's later cards, apart from Larger Text. Apple's first-launch test is complete or skip, and Skip was checked.
- Contrast, measured: the note card, the way back, the Search tab's results, search results in a book, the remove prompt, Books on iPhone, Import from Files, and BookOrbit's sign-in.
- **Not seen running since `.onAccent`:** the trust prompt's button and an empty screen's button. They take the same style as Open, Sign in and the server place's Go, which were seen.
- Color: BookOrbit's sign-in, the trust prompt, the connection banner, half open.
- Unfolded: Reduce Transparency, Bold Text, grey versions of most screens.
- Larger Text: half open, folding with a book open, the trust prompt, footnote cards, Import from Files, Books on iPhone, an empty screen, the connection banner, Dark Mode at these sizes.
- Nothing from Color and Contrast or Larger Text has run on a real Duo.
