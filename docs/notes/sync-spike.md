# Sync spike (task 2a): foliate-js ↔ BookOrbit position sync

Spike step 4, done 2026-10-31. Octavo (upstream foliate-js `6b11e17` in a SwiftUI `WebView`) against BookOrbit v3.6.0's web reader, both directions, following the position-match protocol in `docs/SPIKE.md`.

## Result

| Direction | Hit | Near | Miss | Failed |
|---|---|---|---|---|
| App → web (A→W) | **16** | 0 | 0 | 0 |
| Web → app (W→A) | **15** (2 of them straddles) | 0 | 0 | 0 |

- Five books, three positions each (early ≈ 12%, middle ≈ 50%, late ≈ 88–94%), both directions, plus one extra mid-chapter A→W row for P&P. 28 of the 31 source positions are mid-chapter; the other 3 start at a chapter heading.
- On every row the target page held the source's first visible words. In the 2 straddles, those words begin in the target page's last line and run onto its next page. The target page still contains the source's start point; see "Drift cases".
- **CFI shape doesn't change navigation:** pushing range CFIs instead of points gave 5/5 hits too (table below). Octavo pushes the point; see "Which CFI to push".
- The main risk is retired for reflowable EPUBs. BookOrbit's custom loader caused no drift on any of the five sample books.
- **Web → app → web loop** works end to end on Alice. Screenshots are in `sync-spike/`:
  1. `1-web-source.jpg`: the web reader at 41.7%, starting "“I speak severely to my boy”".
  2. `2-app-opened.png`: the app reopened the book from the server, and the page contains that verse.
  3. `3-app-moved.png`: the app paged forward and pushed `/94/1:122`.
  4. `4-web-target.jpg`: a reloaded web reader shows the page containing "no doubt that it had a very turn-up nose".

## How it was measured

- **App:** Debug build on simulator **Octavo Sync Duo** (`32DEFF1F-1885-4884-8DAF-2FC92AE08FC2`, iPhone Duo device type, iOS 27.1). It's a separate simulator because `iPhone Duo` was reserved by another session. Folded, outer display (466×678 pt); the reader area below the debug strip is about 466×470 pt. Pages hold about 1,100 characters.
- **Web:** BookOrbit's own reader in the built-in browser, mobile preset **375×812**, signed in as `octavo`, default reader settings. Pages hold about 1,300 characters. It ran on **`http://sync2a.localhost:3300`**, not `localhost` or `127.0.0.1`, because the browser's cookie jar is shared between sessions (see "Process notes").
- **Visible text** came from foliate's own visible range on each side (`view.lastLocation.range.toString()` in the browser; the bridge's new `visibleText()` in the app, written to `Documents/spike-state.json`). Screenshots spot-checked that this equals what's on screen. The source's first 8 words are searched in the target page's text after normalizing quotes and whitespace (`sync-spike/tools/check.py`, and the same check in the page). CFI strings were never compared.
- **Positions.** For W→A:
  1. Jump the web reader with its own `goToFraction` (the same call its "Jump to location" control makes; the control auto-hides and was hard to reach by clicks).
  2. Turn two pages with the keyboard (→) so the spot is mid-chapter.
  3. Close and reopen the book in the app, which pulls the server's position.

  For A→W:
  1. Turn two pages in the app (or `goto` a fraction first).
  2. Wait for the debounced push and confirm the server holds the app's CFI.
  3. Reload the web reader.
- **Driving the app:** the spike screens have a DEBUG-only command file (`Octavo/Spike/SpikeRemote.swift`), so host scripts can say `open`, `goto`, `next` and read the reader's state back. The scripts are in `sync-spike/tools/` (`app.sh`, `w2a.sh`, `a2w.sh`, `bo.sh`, `check.py`).
- The Mac was heavily loaded during the run (load average 36–67 from parallel sessions), so book opens took 10–30 s in the simulator. That's timing only; it didn't affect positions.

## Results: point CFIs (what Octavo pushes)

| Book | Position | Direction | Source first visible words (~8) | Verdict | Notes |
|---|---|---|---|---|---|
| Alice | early | W→A | them a railway station.) However, she soon made out that | hit | web 13.49% Ch II /32/1:517; app page starts 'And I declare it's too bad', probe at char 558 |
| Alice | early | A→W | sentence in her French lesson-book. The Mouse gave a | hit | app 14.56% pushed point /40/1:297; web page starts 'Perhaps it doesn't understand English', probe at char 296 |
| Alice | middle | W→A | question. “Why did they live at the bottom of a well?” | hit (straddle) | web 51.64% Ch VII /164/1:152; app page /146/1:62–/164/1:182 contains the point, ends 'repeated her question. “Why did they live' (5/8 words, rest on next page) |
| Alice | middle | A→W | with an M—” “Why with an M?” said Alice. “Why not?” | hit | app 52.55% pushed /192/1:174; web page starts 'Alice did not wish to offend the Dormouse' (/182/1:0), probe at char 711. (An earlier A→W attempt was voided: my own repro goto pushed over the position.) |
| Alice | late | W→A | bells, and the Queen’s shrill cries to the voice | hit | web 89.55% Ch XII /134/1:307; app page starts 'the neighbouring pool' (/132/1:113), probe at char 824 |
| Alice | late | A→W | You gave us three or more; They all returned | hit | app 86.50% pushed /84/23:0 (verse); web page starts '"Read them," said the King' (/76/1:0), probe at char 536 |
| Frankenstein | early | W→A | been imbued with a fervent longing to penetrate the | hit | web 12.99% Ch 2 /20/1:299; app page starts 'my father had taken of my volume' (/18/1:658), probe at char 448 |
| Frankenstein | early | A→W | banish disease from the human frame and render man | hit | app 13.29% pushed /24/1:782; web page starts 'to struggle with a child's blindness' (/24/1:419), probe at char 363 |
| Frankenstein | middle | W→A | was indignant; and it was judged that his religion | hit | web 50.61% Ch 14 /8/1:404; app page starts 'was a Turkish merchant' (/8/1:59), probe at char 345 |
| Frankenstein | middle | A→W | most ardent terms for his intended services towards her | hit | app 51.09% pushed /14/1:354; web page starts 'forward to the probability of the event' (/12/1:306), probe at char 434 |
| Frankenstein | late | W→A | mountain, and one, sinking under his fatigue, died, I | hit | web 88.79% Ch 24 /46/1:447; app page starts 'should soon have sunk beneath this misery' (/46/1:298), probe at char 149 |
| Frankenstein | late | A→W | astounded at the sight. I quickly destroyed part of | hit | app 89.33% pushed /52/1:291; web page starts 'terrific. I pressed on, but in vain' (/50/1:299), probe at char 690 |
| Moby-Dick | early | W→A | deliberated a moment whether, in case he invited me, | hit | web 12.31% Ch 10 /92/1:751 (book is one 1.2 MB spine item); app page starts 'said it was mine' (/92/1:388), probe at char 335 |
| Moby-Dick | early | A→W | CHAPTER 11. Nightgown. We had lain thus in bed, | hit | app 12.41% pushed element point /102[pgepubid00015] (page starts at the chapter heading); web page starts at the same heading, probe at char 0. Web reader stores the same spot as /102[pgepubid00015]/1:0 |
| Moby-Dick | middle | W→A | water, and may be seen by man in the act | hit | web 50.28% Ch 59 /106/1:612; app page starts 'Starbuck still gazing at the agitated waters' (/98/1:64), probe at char 999 (last line of the app page) |
| Moby-Dick | middle | A→W | for, though not so durable as hemp, it is | hit | app 50.44% Ch 60 pushed /122/1:135; web page starts 'CHAPTER 60. The Line.' (/116[pgepubid00064]/1:0), probe at char 961. (Two pages earlier the app sat on a blank end-of-chapter page, pushed /114 = empty element; web opened on Ch 59's last page, which contains it. Logged as a note, not a measurement.) |
| Moby-Dick | late | W→A | anchor here, though, so I can pass the rope; | hit | web 88.31% Ch 121 /224/3:576; app page starts 'or the water-bearer, Flask' (/224/3:260), probe at char 296 |
| Moby-Dick | late | A→W | swallow-tail, and drive down a beaver; so. Halloa! | hit | app 88.29% pushed /228/1:1156; web page starts 'if she is, she swings with an uncommon long cable' (/228/1:558), probe at char 555 |
| P&P | early | W→A | A note for Miss Bennet. CHAPTER VII. R. BENNET’S property | hit (straddle) | web 12.35% chapter VII opening; web point /444[pgepubid00062]/8/1:0 = the illustration caption inside the chapter `<h2>`. App page (illustration + caption + heading) contains the point; 7/8 words, the paragraph starts on the next app page |
| P&P | early | A→W | however bare of news the country in general might | hit | app 12.45% Ch VII pushed /450/1:536; web page starts 'She had a sister married to a Mr. Philips' (/448/1:0), probe at char 715 |
| P&P | middle | W→A | in his friend’s connections than from their want of | hit | web 50.52% Ch XXXIII /6/10!/4/96/3:126; app page starts 'an evil he might have inflicted' (/92/5:253), probe at char 905 |
| P&P | middle | A→W | CHAPTER XXXIV. | hit | app 50.51% page = chapter heading only, pushed element point /100[pgepubid00272]; web page starts 'CHAPTER XXXIV. HEN they were gone' (web stores /100[pgepubid00272]/9:0), probe at char 0 |
| P&P | middle (2) | A→W | She could not think of Darcy’s leaving Kent without | hit | extra mid-chapter row: app 50.75% Ch XXXIV pushed element point /104 (page starts at a block element); web page starts 'itself, and kindly disposed towards everyone' (/102/5:238), probe at char 612 |
| P&P | late | W→A | when Bingley was gone, Jane constantly sought the same | hit | web 88.41% Ch LV /6/14!/4/108/1:359; app page starts 'Wickham, Lydia, were all forgotten' (app point /102 = element), probe at char 1035 (last line) |
| P&P | late | A→W | “He made a little mistake, to be sure; but it | hit | app 88.51% pushed element point /120; web page starts 'when Bingley was gone' (/108/1:359), probe at char 1082 |
| Sherlock | early | W→A | Sherlock Holmes and I surveyed this curt announcement and | hit | web 12.61% II Red-Headed League /190/1:0; app page starts '"To an end?"' (app point /182 = element), probe at char 422 |
| Sherlock | early | A→W | “‘Oh, at his new offices. He did tell me | hit | app 12.97% pushed element point /208; web page starts "'Oh,' said he, 'his name was William Morris" (/204/1:0), probe at char 201 |
| Sherlock | middle | W→A | y thing,” said he. “Just see how it glints | hit | web 50.66% VII Blue Carbuncle /144/1:103 (web page starts mid-word: 'pret-\|ty' hyphen break); app page starts '"Ah, yes, I shall keep the stone' (app point /142 = element), probe at char 334 |
| Sherlock | middle | A→W | past six when I found myself in Baker Street | hit | app 50.96% pushed /162/1:62; web page starts '"In that case I shall continue my professional round' (/158/1:0), probe at char 421 |
| Sherlock | late | A→W | appeared to be a mere whim at first, developed into | hit | app 88.99% XII Copper Beeches pushed /36/1:115; web page starts 'and originality. As to my own little practice' (/20/1:359), probe at char 909 |
| Sherlock | late | W→A | moonlight night, and the lawn in front of the | hit | web 93.64% XII Copper Beeches /268/1:149; app page starts "between two planks. 'Is he not a beauty?'" (/262/1:55), probe at char 819. (First attempt at 88.67% voided: my script read the previous reader's state file under machine load.) |

## CFI shape A/B: range CFIs pushed

The same A→W check, with the app pushing foliate's full range CFI instead of the start point.

| Book | App position (range CFI pushed) | Source first visible words | Verdict | Web landed on |
|---|---|---|---|---|
| Alice | 31.59% Ch V epubcfi(/6/14!/4/2[pgepubid00007],/30,/46/1:62) | “Why?” said the Caterpillar. Here was another puzzling question; | hit | page /20/1:0, probe at char 679 |
| Frankenstein | 70.69% Ch 20 epubcfi(/6/54!/4/2[pgepubid00026],/12/1:117,/18/1:61) | trembling steps, I sought my own apartment. I was | hit | page /10/1:0, probe at char 518 |
| Moby-Dick | 30.24% Ch 36 epubcfi(/6/10!/4,/56/1:63,/66/1:41) | curious and not wholly unapprehensive faces, were eyeing him, | hit | page /46/1:0, probe at char 687 |
| P&P | 70.35% Ch XLVI epubcfi(/6/12!/4,/78/7:574,/80/1:183) | wonder. I am truly glad, dearest Lizzy, that you | hit | page /78/3:886, probe at char 1463 |
| Sherlock | 30.38% IV Boscombe Valley epubcfi(/6/12!/4/2[pgepubid00008],/322/1:59,/330/1:57) | about young McCarthy’s narrative which struck us both instantly, | hit | page /316/1:142, probe at char 378 |

## Which CFI to push: the point

**Push the start point of the visible range** (`CFI.collapse(range)`, computed in `bridge.js` with foliate's own parser). Both shapes navigate identically: foliate's `goTo` scrolls to the first rect of the range, which is its start. These are the reasons for the point:

- It's what BookOrbit's web reader stores. For pages that start inside text, our point string equals what the web reader would write for the same page start, so "has the position changed?" checks can compare strings.
- BookOrbit switched its web reader to points on purpose ("preserve exact positions when syncing with koreader"). Its server converts CFIs to KOReader and Kobo positions, and a point names one spot instead of a span. Conversion with either shape wasn't tested here.
- A point says where reading resumes, which is the thing being synced.

One remaining string difference: when a page starts at an element (a chapter heading, a block), our collapse gives the element step (`/102[pgepubid00015]`). BookOrbit's reader walks into the first text node (`/102[pgepubid00015]/1:0`). Both open the same page; 5 of the A→W rows pushed element points and all hit. Copying that walk in the bridge (our own code, from the described behavior) would make strings match there too. It isn't needed for navigation.

The spike screens keep a Point/Range picker, and `ReaderModel(cfiShape:)` takes either.

## Sync design (what was built)

- **`ProgressSync`** (OctavoKit): `pull() -> SyncedPosition?` and `push(ReadingPosition)`, one instance per book. `BookOrbitProgressSync` wraps `BookOrbitClient.progress(fileID:)` and `saveProgress(_:fileID:)`. The protocol came out naturally because `ReaderModel` needs some backend it can be handed.
- **On open:** `ReaderModel` pulls before opening (5 s timeout), then `OpeningPosition.choose(local:remote:)` decides where to open:
  1. **The server has a CFI and the device has nothing unpushed → open at the server's position.** Every move is pushed, so the server is at least as new as the device, and newer if another reader moved since.
  2. **Both moved** (the device has an unpushed position, e.g. read offline, and the server has a CFI) → **the later timestamp wins** (local `modifiedAt` against the server's `textUpdatedAt`). The server wins ties and undated positions. This is the only case that compares two clocks.
  3. **The server has no CFI** (never opened, or a percentage-only writer such as kosync) → the local position, else the server's fraction, else the start.
  4. **The pull failed or timed out** → local.

  The local store (`ReadingPositionStore`) now keeps `{position, modifiedAt, needsPush}` and reads old bare-position files as already pushed.
- **No push on open.** The page we land on starts at or before the server's point, so pushing it back would creep the position backwards by up to a page on every open. Pushing starts at the first relocation whose CFI differs from the one we opened at. (Opening BookOrbit's web reader didn't write the position back either.)
- **On relocate:** save locally (`needsPush = true`), then `DebouncedProgressPusher` pushes the last position once the reader has been still for **2 s**. The 3–4 relocate events per page turn become one push. Pushes run in order, one at a time. A failed push keeps its position for the next attempt unless a newer one replaces it. Closing the reader flushes. A successful push clears `needsPush` only if that position is still the saved one.
- **Blank pages aren't saved or pushed.** When the paginator falls back to `<body>`, the CFI only names the section. `bridge.js` flags those relocations (`blankPage`).
- **Tests:**
  - OctavoKit: `OpeningPositionTests` (every branch of the rule), `DebouncedProgressPusherTests` (bursts, quiet period, flush, retry, de-dup, with a manual clock), `BookOrbitProgressSyncTests` (CFI verbatim, percentage 0–100 ↔ fraction 0–1, never-opened → nil).
  - App: relocation shape mapping, blank-page flag, store migration, and `markPushed` racing a newer save.

## Drift cases and their causes

None produced a near or miss. These are the edge behaviors seen:

1. **Straddles (2 W→A rows).** The source page starts mid-paragraph, near where the target layout breaks its page. The target correctly opens the page containing the point, and the source's first words are its last line. A reader sees them at the bottom and turns once. Cause: different page sizes, nothing in CFI handling. Counted as hit. Reclassify as near if you want the strict reading of "contains the ~8 words".
2. **Blank end-of-chapter page not caught (Moby-Dick, ch. 59).** WebKit leaves an empty page at the end of some chapters, as the vetting session found for Gutenberg books. Here the page held a visible empty element, so foliate didn't fall back to `<body>`, `blankPage` stayed false, and the app pushed `/6/14!/4/114`. The web reader opened on chapter 59's last page, which contains that element, so the position held. A stricter blank test (no visible text) would skip these too, but the same test would skip image-only pages. Logged as a note, not a measurement.
3. **Pride and Prejudice front-matter blank page.** `goto 1.35%` landed on the known blank page (`epubcfi(/6/4!/4)`, flagged, not saved, not pushed). Four page turns then went forward through the preface with **no loop**. This run has the debug strip at a fixed height. That supports the vetting session's finding that the 1a loop needed a WebView resize (the strip growing). No measured position fell on a blank page.
4. **Element-start points:** see "Which CFI to push". Same page, different string.

## BookOrbit API notes (new since 1b)

- **The v3.6.0 web reader uses a different endpoint.** It uses `GET /api/v1/reading-progress?fileId=` and a batch `PUT /api/v1/reading-progress`, which also carries `kobo` and `koreader` fields. Octavo (via `BookOrbitClient`) uses `GET/POST books/files/{id}/progress`. Both read and write the same row: each side saw the other's writes immediately, with `textUpdatedAt` updated. Our POST doesn't send the Kobo location fields the web reader sends. That could matter for BookOrbit's Kobo sync and wasn't tested.
- Progress is per user, so a shared browser cookie silently writes to whoever is signed in (see "Process notes").
- **`BookOrbitClient` changes: none.** New: `BookOrbitProgressSync` (adapter) plus the generic `Sync/` types.

## Engine comparison (for 1c)

- Same engine on both sides means the only differences are page boundaries. Every position landed on the page containing the other side's point, in both directions, for points and ranges.
- For a like-for-like 1c table, match these conditions:
  - web viewport 375×812 (mobile preset), default reader settings;
  - fractions 0.12 / 0.5 / 0.88 plus two page turns;
  - an 8-word probe, scored with the straddle rule above;
  - a cookie host of 1c's own.
- Octavo needs no CFI translation layer: foliate's CFIs are BookOrbit's. Any Readium path has to convert both ways.

## Process notes

- **Shared browser cookies.** The built-in browser profile is shared across sessions. 1c signed in at `127.0.0.1:3300` as `octavo-readium` after I had signed in there as `octavo`. My first Alice W→A run at 19:30:51Z therefore wrote **octavo-readium's** Alice position (13.49%). I told 1c and moved to `sync2a.localhost:3300`. All results above come from that host and the `octavo` user, checked by confirming the web reader resumed at octavo's server position.
- **Two runs voided**, both noted in the table. In one, my own reproduction `goto` pushed over the position under test. In the other, the script read the previous reader's state file under load; `w2a.sh` now waits for the new reader's "pulled" state.
- Plain-http access uses `NSAllowsLocalNetworking` (`Config/Octavo-Info.plist`, merged through `INFOPLIST_FILE`). That covers `localhost` and `.local` only. Remote plain-http servers would need more ATS exceptions: owner decision, unchanged from 1b.

## Owner decisions surfaced

- Whether to copy BookOrbit's element → first-text walk so element-start CFI strings match exactly (cosmetic).
- Whether to switch to BookOrbit's `PUT reading-progress` and send the Kobo location fields, for Kobo-sync fidelity. Untested either way.
- Blank-page handling: skip only `<body>` fallbacks (current), or also text-free pages (would also skip image-only pages). The foliate patch from the vetting session fixes the root cause.

