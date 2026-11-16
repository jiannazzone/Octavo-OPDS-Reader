# Highlights and notes (#125)

Designed with Adam on 2026-11-09 and revised on 2026-11-15 (the issue holds the design). Built 2026-11-15 and 16 on 'Octavo Highlights Duo' (8D44836F-5809-4D2B-AEDC-ED65F0B4A29F, iPhone Duo, iOS 27.1 simulator), against the local BookOrbit v3.6.0 with *Pride and Prejudice* (book 4, file 4). Code: OctavoKit `Sync/HighlightSync.swift`, `HighlightPalette.swift`, `HighlightExport.swift` and `BookOrbit/BookOrbitHighlightSync.swift`; the app's `ReaderHighlights.swift`, `HighlightsWaiting.swift`, `ReaderModel+Highlights.swift`, `ReaderHighlightBar.swift`, `ReaderHighlightCard.swift`, `HighlightsExport.swift` and the "Highlights" parts of `bridge.js` and `ReaderContentsPanel.swift`. Tests: `HighlightReconciliationTests`, `BookOrbitHighlightSyncTests`, `HighlightPaletteTests`, `ReaderCFITests`, `HighlightExportTests`, and the app's `ReaderHighlightsTests.swift`. Pictures: `highlights/`.

## What it does

- **Making one:** selecting text puts a bar at the page's foot, in the footer's place (`ReaderChromeLayout.FooterBar.highlight`), under the selection's page on a spread. It holds BookOrbit's ten colours in a row that scrolls (five and a half at rest, from yellow: `HighlightColorRow`) and Note. The system's edit menu stays as it is. A colour highlights the words; the bar then stays with the colour ringed and trash beside it, until a tap on the page (which doesn't turn it) or a turn. Note highlights in yellow, then opens the note's sheet. (`bar-selecting.png`, `bar-after-green.png`, `bar-spread.png`)
- **A highlight tapped** opens its card where a footnote's card goes (`ReaderCardLayout`, shared with it): the facing page of a spread, level with it, or clear of it on one page. Share (the quote with the title and author), Copy, Delete, ✕, the colours, and the note with Edit Note or Add Note. The card and a footnote's never show together. (`card-folded.png`, `card-spread.png`)
- **The note** is written in a system sheet: the quote in its colour, then the note, with Cancel (the highlight stays) and Done. An empty note clears it. (`note-sheet.png`)
- **The Highlights tab** in the Contents panel: "Chapter · Page N", the words with their colour beside them (three lines), the note in grey, in the book's order. A tap is a jump (decision 33) to where the highlight starts; a swipe deletes. BookOrbit's highlights that this file doesn't have are listed last under "Not Found in This File", with nowhere to go. Share All Highlights exports Markdown. (`highlights-tab.png`)
- **Fixed-layout books** are left out: foliate's fixed-layout renderer has nothing to draw on. No bar, no tab, and their BookOrbit highlights stay on the server untouched.

## Why our own bar, not the edit menu

The first spike put Highlight and Note first in the system's selection menu. SwiftUI's `webViewContextMenu` isn't on iOS, SwiftUI replaces both the application (`SwiftUIApplication`, so `NSPrincipalClass` is ignored) and the app delegate, so `buildMenu(with:)` there is never called. WebKit does ask the web view itself (`WebKit.WebPageWebView`), which only a runtime subclass of it reaches. Adam chose a bar of our own over that (2026-11-15), and the subclass was taken out.

## Drawing

- foliate's overlayer draws them, as it draws Search's match. The bridge keeps them by CFI with their colour, takes them with `open` (the first page draws them) and then the whole list on every change (`setHighlights`), drawing what's new or recoloured and removing what's gone. Each range's section is resolved once per book.
- Search's match shares foliate's keys. Clearing a match on a highlighted range draws the highlight again.
- Colours go through `HighlightPalette.drawable`: one of the ten by name or hex, any other hex as it is, anything else yellow. The bridge checks again, so only `#` and 6 or 8 hex digits reach the overlay's markup. A colour another app stored is never written back unless it's changed here, and a colour outside the ten rings no dot.
- **Taps:** foliate's own `show-annotation` listens for `click`, which iOS doesn't send to a document for text that isn't a link. The bridge's own tap test asks the overlayer (`hitTest`) before notes and page turns, and sends Swift the CFI and the highlight's box, never its words.
- While the bar or a card is up, a tap only dismisses (`tapMode`), as with a footnote's card.

## Sync with BookOrbit

Shapes in `bookorbit-api.md` ("Highlights"). Always for the file read (`readerFileId`): without it, ranges would be for whichever file each was made on.

- **Merging** (`HighlightReconciliation`): the server's range, words and chapter always win. For colour and note, changes made here win unless the server changed since it was last seen and later than they were made; ties go to the server, as in the opening rule. One the server no longer has was deleted elsewhere and goes, edits and all. A lost add is matched by its CFI and words, as BookOrbit returns a posted CFI byte for byte.
- **Sending:** an add, then PATCHes of only what changed (`HighlightEdit`; a `null` note clears it), then a removal, each answered before the next. A PATCH that gets 404 means it was deleted elsewhere.
- **When:** when the book opens and when the app or the connection comes back. A refresh that sees a send answered while its list was on its way fetches again, so a highlight made meanwhile isn't dropped. With the book closed, `HighlightsWaiting` retries what it left unsent, with places (`retryUnsentPlaces`). A book's highlights are one shared `ReaderHighlights` at a time, so a retry and a reader opening the same book don't save over each other.
- **Storage:** per book under its server (`HighlightStore`, a `PerBookStore` like bookmarks'), so they go with Remove server, come back with a returning server, move with an install's first move to several servers, and stay apart while a tour replays.
- Books from Files or an OPDS catalog keep their highlights on the iPhone. KOReader sync carries places only.

## The export

`HighlightExport` writes the title and author, then each chapter's quotes in order with their notes under them, and the not-found ones last. Every line of a quote is quoted (`> `), and the characters that make emphasis, links, code or HTML are escaped, as are those that start a heading, list or table at a line's start. Ordinary punctuation stays, since the same text is also shared as plain text. A highlight with no chapter after a chapter's starts after a rule. The file is "<Title> – Highlights.md", cleaned of `/ \ : ? % * | " < >`, written to its own folder under the temporary directory, which the next export clears.

## Safety

Quotes and notes are plain text everywhere (`Text(verbatim:)`), never logged, and never reach the page as HTML. The bridge's rules are unchanged (CLAUDE.md, "Book scripts never run"). Messages from the bridge carry a highlight's CFI and box, not its words.

## Accessibility

- **VoiceOver:** the page item (`ReaderVoiceOverPage`) has an action per highlight starting on the page, "Highlight: “its first words…”", which opens its card. The bridge finds them by where their first line is on screen (`highlightBoxes`), a quarter of a second after the page settles: a jump reports its place before its page is laid out. A row in the tab has Add Note or Edit Note and Share beside the swipe's Delete. The colours are named ("Yellow", "Green"…). Checked headless by `highlights/tools/voiceover_check.py` (below).
- **Making one with VoiceOver:** the page item's words are text VoiceOver can select in (`accessibilityTextInputResponder`, a hidden, non-editable `UITextView` holding the same words). The Text Selection rotor picks words, lines or sentences there; the bridge kept where each character of the page's words came from in the book (`pageWordsOf`'s `points`), so `selectPageWords` selects the same words in the book, its `selection` message brings up the bar, and the bar's colours and Note are in VoiceOver's reach. Unselecting in the item unselects the book; a highlight or a tap that takes the selection lets the item's go too. Words from a page since turned select nothing (the bridge compares the words it last sent). Fixed-layout books get no text to select. Page turns and the double tap are the item's own, as before.
  - **The system makes the item a text field.** Any element with a text input responder gets UIKit's private text-entry and text-operations traits (`0x40000`, `0x2000000000`, measured on 2026-11-16 with a non-editable responder, an unselectable one and none), so VoiceOver may now say "text field" on the page. They're left as the system sets them, not stripped by their private values.
  - **Only a person on a device can still confirm** that VoiceOver offers the Text Selection rotor on the item without editing it, how the page is announced, that three-finger turns and Read All's turn to the next page still reach the item, and where VoiceOver's own selection outline is drawn (the hidden text is laid out over the page in the body font, not the book's). If turns or Read All broke, the fallback is a "Highlight…" action on the page item listing the page's sentences, for Adam to choose.
- **Reduce Motion:** the card and the bar fade rather than move.
- **Larger text:** the bar stops growing at the second accessibility size, as BookOrbit's capsule does. Rows wrap with `lineLimit(untilLargerText:)`.

## The VoiceOver check

`docs/notes/highlights/tools/voiceover_check.py <udid>` scripts a VoiceOver user's highlight tasks through the debug remote, headless, and stops at the first that fails, printing what VoiceOver could reach. It checks the page item is text to select in and still turns pages, selects the range's words in the item's text input as the Text Selection rotor would (`voiceOverSelect`, through `accessibilityTextInputResponder`), sees the same words selected in the book and the bar's colours in reach, unselects and sees the book's selection go, selects again and double-taps Green, and checks the highlight is the range's own CFI. Then it turns away and back with three-finger scrolls (the next page's words replace the item's), selects and unselects once more, finds "Highlight: “This…”" in the page's Actions rotor and runs it, reads the card (Share, Copy, Delete, Close, the colours with its own selected, Add Note) with the page hidden behind it, opens the note's sheet and cancels it, opens Contents and the Highlights tab with double taps and reads the row's actions, then deletes the highlight from its card. It clears the range first (`unhighlight` by CFI and by its words), so a failed run doesn't leave it stuck. 48 steps, all passing on 2026-11-16 on 'Octavo VO Select Duo', folded and unfolded. It needs the local BookOrbit and *Pride and Prejudice* (file 4) by default; `--file`, `--cfi` and `--words` (the range's words, as the item has them) point it elsewhere. `ReaderVoiceOverBridgeTests` checks the mapping itself: across markup, a run of spaces, a paragraph's end and a line break, and stale words.

## Checked on the simulator

Folded and unfolded: making a highlight from the bar, recolouring it, a highlight made in Octavo reaching BookOrbit and one added or recoloured there arriving on return, drawing across lines and after reopening, the card and its placement, writing a note and seeing it on BookOrbit, the tab's order and a jump from chapter 33. Not seen on screen: Share and Copy (scripted taps don't drive the share sheet), swipe to delete, "Not Found in This File" (no local book has two EPUB files), the empty tab, and anything with VoiceOver speaking.
