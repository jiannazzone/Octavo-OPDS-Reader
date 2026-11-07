# Footnotes where you are (decision 34)

Decision 34 in `docs/design/direction.md`. Written 2026-11-05 on 'Octavo Footnotes Duo 2' (CE2E0CD3-76DF-45EC-A4B8-EDF9FD63DAC6, iPhone Duo, iOS 27.1 simulator), against the local BookOrbit v3.6.0. `ReaderNote.swift`, `ReaderNoteCard.swift`, `ReaderModel+Notes.swift`, and the "Footnotes" section of `bridge.js`. Tests: `OctavoTests/ReaderNoteTests.swift`. Pictures: `footnotes/`.

## How two real books mark their notes

No test book had a note, so Adam OK'd two public-domain ones, chosen to be the two kinds there are. They're on the local BookOrbit only (`libraries/1/upload`), not in the repo or `SampleBooks/`.

| Book | Source | Marks | Notes |
|---|---|---|---|
| *The Count of Monte Cristo*, file 11 | [Standard Ebooks](https://standardebooks.org/ebooks/alexandre-dumas/the-count-of-monte-cristo/chapman-and-hall) | 33, `epub:type="noteref" role="doc-noteref"` | `li epub:type="endnote footnote"` in `endnotes.xhtml`, with a `↩︎` marked as a backlink |
| *The Interesting Narrative of Olaudah Equiano*, file 12 | [Project Gutenberg 15399](https://www.gutenberg.org/ebooks/15399) | 26, unmarked: `a.fnanchor`, text `[A]` | `div.footnote` at the end of the chapter's file. It starts with a `[A]` link back, so the way back looks just like a mark |

## Which links are notes

The bridge decides (`markKind`, then `noteElement`), so Swift hears `note` or `link`.

- **Marked:** `noteref` or `doc-noteref`, whatever it looks like, if its target can be found. FB2's note links come out of foliate marked too.
- **Unmarked, all of these:**
  - It looks like a mark: `12`, `12.`, `*`, `†`, `²`, `[A]`, `(iv)`, or any text of 8 characters or fewer that's raised (`sup`, or `vertical-align: super`).
  - There's text before it in its block, which rules out a note's own way back and a row of chapter numbers.
  - It isn't in a `nav`, a contents or an index, and doesn't go out of the book.
  - Its target starts a block that isn't a heading or a page break, and holds no heading.
- **Everything else is a jump,** and so is a note with a picture, a table or anything else only the page can draw, or one of over 20,000 characters or 200 paragraphs, which is a wrong guess or a book asking too much. Reading a note stops as soon as it's past those.
- **A wrong guess costs one tap,** as the card has Go to Note.
- **Near misses:** with nothing covering the page, a tap within 16 pt across or 12 pt up and down of a mark's box counts, if the note opens. It's otherwise an ordinary tap. So near a mark a tap can't turn the page, as decided.

`window.octavo.noteLinks()` lists every link in a book and what a tap on it does, for tuning this on another book.

| Books | Open a card | Jump |
|---|---|---|
| Monte Cristo | 33 of 33 marks | 50 |
| Equiano | 26 of 26 marks | 44, the notes' own `[A]` links among them |
| The five samples, and The Time Machine's four files on the server | 0 | 17, 33, 143, 171, 18 and 5, 42, 5, 5 |

## What the card gets

Only words, and which are italic, bold, raised, lowered or code, as JSON (`ReaderNote`, `noteBlocks`). Swift puts them in an `AttributedString` built from plain strings, not Markdown or HTML, so nothing of the book's runs in the card. Every script-blocking layer is untouched: a section read for its note is only parsed, like `describePlace`'s, and never goes in a frame. No foliate patch was needed.

- **A note's box:** the element marked as a note, or for an unmarked note its block, widened to a `li`, an `aside`, a `dd` or a `div` or `section` with a note-like class if that holds no other note (no other `id`, no heading). So Gutenberg's several paragraphs come whole.
- **Left out:** a marked backlink, a link to the mark, a link that's only an arrow, a short link to a box around the mark, and a link that starts the note and looks like a mark (`[A]`, `3.`). A number that's plain text stays, and so do a longer link's words. A picture in any but the first two means a jump, as the card can't draw it.
- **A note of several plain paragraphs with no box around them** shows only its first. Neither book has one. Go to Note shows the rest.
- **Font and size** are read off the mark's block with `getComputedStyle`, so they're what the page shows, the book's or Text and Theme's. A family iOS doesn't have (a book's embedded font) falls to the next one named, and then to Times New Roman, WebKit's own default (`ReaderNoteTypeface`). The two bundled fonts come out as themselves (next section).
- **Line spacing:** `line-height: normal` says nothing, and WebKit's normal for this book is 20 pt on 16 pt text where SwiftUI's is about 18.4. The bridge measures the lines' distance apart on the page (`linePitch`), leaving out a raised mark's smaller box (any box shorter than the block's own text's, since the bundled fonts' marks are taller than the font size), and the card adds the difference.
- **Not carried over:** justification and hyphenation, which SwiftUI's `Text` doesn't do, and small caps or anything else a book sets with its own classes.

## The bundled fonts on the card

Atkinson Hyperlegible and OpenDyslexic (decision 16, #83) reach the page through `@font-face`, which SwiftUI can't see, so at first the card drew them as Helvetica, the page's `sans-serif`. Now the first card registers the same WOFF2 files in `ReaderWeb/fonts/` with Core Text, for this run of the app only (`ReaderFont.cardFamilies`, `CTFontManagerRegisterFontsForURL`, scope `.process`). Nothing is copied or converted, so the app carries the 565 KB once. Measured on the iOS 27.1 simulator (2026-11-07, 'Octavo Notes Duo', 3F52E3E5-79C8-421A-8236-7FA7C79853FC):

- **Core Text reads WOFF2 as it is.** Atkinson's variable files register with their named instances (ExtraLight to ExtraBold, each italic too), and OpenDyslexic's four files as one family.
- **Registering all six files took about 40 ms,** once. After that the card's family list costs what it did.
- **One list feeds both:** `ReaderFont.bundledFaces` makes the page's `@font-face` rules and is what the card registers, and `bundledFamily` is the family the files name, which a test reads from the files themselves. `ReaderNoteTypeface` maps the page's `octavo-…` family to `.bundled`, and if registering failed it falls back as before.
- **Faces, as on the page:** bold is Atkinson's 700 instance (the page's `font-weight: bold`) or OpenDyslexic's bold file; italic is each one's italic file. The traits go in the font descriptor's attributes: `withSymbolicTraits` returns nothing for OpenDyslexic, whose faces carry another trait, so its italic and bold came out regular.
- **No ligatures in OpenDyslexic,** as on the page: the descriptor sets `liga` off, so "fi ffi office" is 13 glyphs where the font's own ligatures make 8.
- **Size and line spacing** come from the page, as for the iOS fonts. Measuring the lines needed a fix: `linePitch` left out a raised mark's box by being shorter than the font size, but these fonts' boxes are tall (OpenDyslexic's 30 pt for 16 pt text, Atkinson's 22), so Standard Ebooks' 0.75 em mark counted as a line and its raised top won. It reported 26.67 pt where the lines were 30 apart, and 17.67 for 22. It now keeps only boxes as tall as the block's own text's (its first text of its own; with none, the font size, as before). The card's lines measured 30 pt apart in OpenDyslexic, as on the page (`aRaisedMarkIsntALineInATallFont`). The iOS fonts' mark boxes were already under the font size, so nothing changes for them.

Checked with both fonts on Monte Cristo's notes 27 (italics) and 11 ("finished", "off"), folded and unfolded. The card was opened by the mark's own click in the page (the remote's `js`), as `idb`'s taps only reach the outer display. Tests: `ReaderNoteTypefaceTests`.

## Why native text and not a second web view

A second `WebView` would keep every style, but it brings a web process, an async height, a blob-URL problem for pictures, and a view SwiftUI might rebuild on a fold, which WebKit traps on (`reader-page.md`, section 6). A native card opens at once, measures itself and scrolls natively, and text can't run scripts.

## Where it goes

`ReaderNotePlacement`, `ReaderNotePlacementTests`. `ReaderNoteLayout` asks the card how tall the note wants it and places it, so there's no second layout pass.

- **Open, flat or half open:** on the other page from the mark, the `ReaderLayout.barSpans` stretch for that page, 12 pt from the fold and the safe area. The text's first line is level with the mark, so the card's top is 58 pt above it, the buttons' row. It moves up to stay above the footer and down to stay on the page.
- **Folded, or sideways:** along the bottom, unless that hides the mark and the top doesn't. Too long to miss it, it's on the side away from the mark.
- **The bottom limit** is 4 pt above the footer's line, so the numbers stay.
- **A long note** grows to the whole of that, then scrolls under the buttons.

## Closing, and your place

| What | Result |
|---|---|
| ✕, or a tap anywhere else, or a key or trackpad | Closes. No turn (`coversPage`, the panels' tap mode) |
| A tap on the card | Nothing |
| A tap on another link or mark | Only closes |
| The same mark reported again within 0.5 s | Nothing: it's the same tap |
| A swipe on the page or the card | Closes and turns |
| Page Turn None, a swipe | foliate turns; that turn's relocation closes it |
| Any other relocation | Nothing |
| Go to Note | A jump (`ReaderModel.jump`), with "Back to page N" |
| A fold, or any new layout | Closes, as its mark has moved |
| Half open and flat | Stays, as the layout's the same |
| The controls up, then a mark | The controls go and the note opens |
| A panel opening, or the bar | The note closes |

**Only a turn closes it, not a relocation (Adam, on his Duo).** It first closed on any relocation with a new CFI. On his Duo, going to a note and back, the same mark's card closed as it opened for a little while. A section just laid out again can report its page late (on the simulator a card failed to appear once after a jump, with 12 relocations where 7 is usual), though Back itself couldn't be made to do it there: its relocations all came at once. With this it's gone on his Duo. In a DEBUG build `spike-events.jsonl` logs why each card closes.

The way back and BookOrbit's capsule go while a note is open, as they do for a panel: the card overlapped the way back by 8 pt.

## Checked

Real taps and swipes on the simulator, Page Turn Automatic unless it says otherwise.

| Posture | Book, theme | What | Result |
|---|---|---|---|
| Folded | Monte Cristo, Original | Tap, a near miss 11 pt right and 4 pt down, a tap elsewhere, ✕, a tap on the card, a swipe on the page, a swipe on the card | All as above |
| Folded | Monte Cristo | Go to Note, then Back | Landed on note 6 with "Back to page 613". Back returned to the same CFI |
| Folded | Monte Cristo | A low mark, verse in the note | At the top, the quote indented |
| Folded | Equiano | A note's own `[G]` | A jump, not a card |
| Folded | Equiano, Night, 200% | The longest note | The page's height, scrolled, the buttons stayed |
| Half open | Monte Cristo, Sepia, Georgia, 120% | Tap, a tap elsewhere, ✕, a swipe, Go to Note, Back | All as above |
| Flat | Monte Cristo | Tap, a tap on the right side, a swipe on the card | All as above |
| Flat | Equiano, Original | The longest note, on the other page | Text level with the mark |
| Flat | Equiano | Page Turn None, a swipe | Closed and turned |
| Flat | Equiano | Unfolding with a note open | Closed; the place held |

**Your place:** on BookOrbit, the place's timestamp didn't change while a note was open for 3 s, or through Go to Note, 3.5 s away, and Back (Monte Cristo at 30.57% folded, 30.58% half open). A swipe's turn saved and sent as usual.

**Not run:** VoiceOver, a right-to-left or fixed-layout book, a MOBI, AZW3 or FB2 with notes, a note with a picture or table, a real device (no finger has tried the near-miss distances), and a modern book's notes: raised numbers and empty anchors have only been through `ReaderNotesBridgeTests`' own book.

## A lost swipe, found on the way

`ReaderSwipeRecognizer` tested direction with `pan.translation`, which can still read (0, 0) when it's asked, 10 pt on, as its own comment says about where a pan starts. A zero isn't sideways, so the pan failed and the page didn't turn. It went either way from one swipe to the next, with or without a note, driven by the same scripted swipe. It now measures from where the finger landed. A real finger moves more slowly than the 0.25 s swipe that showed it, so how often it hit on a Duo isn't known.

**A SwiftUI `DragGesture` on the card stops the page's swipes.** With one anywhere in the card, the page's pan was never asked. The card's own swipe is a `UIPanGestureRecognizer` (`UIGestureRecognizerRepresentable`), which doesn't.

**Seen and not chased:** four scripted swipes soon after launching were read late, 0.7–1.4 s after the touch, and refused as presses. Two were on a page with a note open and two weren't, and with 12 s more wait after opening the next ones were on time. An Android emulator was using about 570% CPU on the Mac at the time, so this may be nothing but load. It hasn't been seen with a finger, and nothing was changed for it.

## Tools

`docs/notes/page-turns/tools/remote.sh` sends commands, including the new `noteState`. `docs/notes/sync-spike/tools/bo.sh progress 11` reads the server's place.
