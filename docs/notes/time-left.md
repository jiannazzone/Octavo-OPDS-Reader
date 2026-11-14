# Reading time left (#124)

Built 2026-11-14 from Adam's design of 2026-11-09. The footer's numbers show time left in the chapter (the default), time left in the book, the page ("291 of 974") or the percentage ("30%"). A tap goes to the next, and the choice holds for every book (`ReaderFooterReadout`, `reader.footerReadout`). Book mode's bar under the right page is unchanged (`ReaderBarReadout`).

## Characters, not pages

A page holds a different amount of text folded, unfolded, half open and at each text size, so speed is measured in characters:

- **Each page:** `bridge.js` sends `characters` with every `relocate`: the visible range's text (both pages of a spread), with each run of white space counted once (`countCharacters`). It's `null` on fixed layout, which never shows time left.
- **Each section:** the contents pass (`refineContents`) counts the sections it reads, then `sectionCharacters` reads the rest (a pause between sections), and the bridge sends `textMap`: each section's characters and foliate's section fractions. A non-linear or empty section counts none, as it takes no share of foliate's fractions. Nothing is sent for a book closed in the meantime.
- **Turning a place into characters** (`BookTextMap`, OctavoKit): foliate's fractions count bytes, markup and all, so a section's share of the book isn't its share of the words. Within a section, a place goes straight across (`characters(before:)`). A section that couldn't be read leaves everything after it unknown, so no time shows rather than a wrong one.
- **Time left** (`ReaderTimeLeft`) runs from the start of the page on screen, so the page you haven't read yet counts. In the chapter it ends at the next contents entry, the same chapter the bar names. Divided by the book's speed, it's rounded by `ReadingTimeLeft`: to the minute under an hour, to ten minutes under ten hours, then to the hour. "Under 1 min" below a minute.

Measuring in foliate's locations would have needed no pass over the book, but locations count bytes. Speeds would drift between books with heavy markup and books with light markup, and between chapters.

## What counts as reading

`ReaderPaceClock` times the page on screen. A page turn forward by one page hands back the page left, as a `ReadingSpan` (start, end, characters). Anything else starts the clock again without counting: a jump of any kind (decision 33), Back, a fold's re-layout, opening, a turn back, leaving the app (`ReaderModel.isInBackground`) and closing. So does a panel, the progress bar or a note card coming up or going (`ReaderModel.coversPage`): the time they're up isn't reading the page.

`ReadingPace` (OctavoKit) judges each span by `ReadingPaceRules`. **These are starting values, to be set on a real Duo:**

| Rule | Value |
|---|---|
| Leafing | under 3 s, or under ¼ of the time the speed gives the page |
| A break | over 2 min, unless the speed gives the page more than ⅓ of that (a dense unfolded spread), then over 3× its time |
| Too little text to tell | under 200 characters (a title page, a picture) |
| Before a pace | pages are judged by 1,500 characters a minute (brisk, so a fast reader isn't taken for leafing) |
| A pace | 10 counted pages overall. Until then the time readouts are left out of the cycle and a time choice shows the page. |
| A new book | starts as 20 pages at the overall speed, then moves to its own |
| Memory | about the last 200 pages; older ones fade |

Speeds live in `Application Support/ReadingPace.json` (`ReadingPaceStore.shared`), overall and per book by the book's storage key, never synced. The file is written when the reader closes and when the app leaves, not on every page. A reader model made without a store (the tests) keeps its pace in memory. Remove server forgets that server's books, and a removed server coming back takes them back, as with places.

## For BookOrbit reading sessions later (#121)

Every counted page is a `ReadingSpan` with its start and end times. A session can be built by joining spans with no break between them; that's not done or sent yet.

## The footer

- **Numbers** are a button over the footer line (`ReaderFooterLines`, `onTapNumbers` on the page's own footer only; the turns' pictures draw the same readout from the `readerFooterNumbers` environment). The touch area is 44 pt tall and at least 120 pt wide, reaching left from the numbers' right end, so "30%" is as easy to hit as "3 h 40 min left in book" (Adam, 2026-11-14). The rest of the bottom margin still turns pages and shows the controls, as on Kindle. A strip that ignores every tap was considered and left: taps there would do nothing. If misses persist on the Duo, the next step is the whole right half of the footer line.
- **Changing readout** swaps the text with no animation, so Reduce Motion has nothing to change.
- **VoiceOver** gets one button, "Reading Progress", with the readout in words as its value ("2 minutes left in chapter", "Pages 106–108 of 974") and the hint "Shows the next readout." Checked with `accessibility/tools/probe.sh` on the simulator: four activations go through all four readouts.

## Checked (simulator, Duo Time Left)

- A new install's first book shows "1 of 974" until there's a pace.
- 11 turns 15 s apart in Moby-Dick all counted (12,467 characters in 171 s), so tap turns arrive as `page` relocations.
- Folded and unfolded, "2 min left in chapter" under the page and under the right page.
- A tap ~75 pt left of "10%" goes to the next readout without turning the page.

Not checked: Curl and swipe turns by a finger, folding mid-page on a real Duo, and the thresholds against real reading.
