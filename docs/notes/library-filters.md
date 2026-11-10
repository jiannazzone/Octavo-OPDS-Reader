# Library filters: scoping (#131 step 2)

Scoped on 2026-11-09, before anything is built. Step 1, the Unread shelf, is in #132. This note gathers what each kind of library can do on the server, what's measured, and what's left for Adam to decide.

## Decided so far (Adam, 2026-11-09)

- **One button** in the side column, under Back, opens a system menu. **Sort by:** Title (the default), Author, Recently added. **Show:** All books, Unread, Reading, Finished. (Later split into two buttons; see the questions at the end.)
- **While Show isn't All books**, the title says what's shown ("Unread", "65 books") and the button is filled. A sort alone doesn't fill it.
- **The Unread shelf's heading** opens All with Unread picked.
- **Remembered:** the sort, per server, on the iPhone. Show starts where the heading points every time.
- **Left out for now:** genre, author and format filters.

Adam then asked for sorting on the other lists too (collections, series, authors), for OPDS catalogs and for books on the iPhone, and whether sort and filter should be split into two buttons. That's what the rest of this note scopes.

## What each library can do

Measured against the local servers (`dev/bookorbit/`, `dev/opds/`). Timing used throwaway copies with **2,000 books**: a calibre library made with `calibredb` and served by separate COPS and Calibre-Web containers, and 2,000 tiny EPUBs in 200 folders for Komga. All times are on this Mac with no Wi-Fi in the way, so they show the server's own speed.

| | Sorts on the server | Read status on the server | Paging | Every book | 2,000 books |
|---|---|---|---|---|---|
| **BookOrbit** | Yes, any list | Yes, any list (`filter`) | 200 a page, jump to any page, totals | `books/query`, 10 requests | not timed (75 books here; a page of 200 took about 25 ms) |
| **COPS 4.6.1** | Yes, `?sort=` on any book feed | No (no users) | 48 a page, `?n=` jumps, totals | All books split by first letter | 51 requests, 1.9 s |
| **Calibre-Web 0.6.27** | No, only fixed feeds | Its own "Read Books" and "Unread Books" feeds | 60 a page (an admin setting), `?offset=` jumps, no totals | `/opds/new` | 34 requests, 5.2 s, no faster in parallel |
| **Komga 1.29.2** | No, one fixed order per feed | Not in the feed for EPUBs | 20 a page, `size=` up to 2,000, `page=` jumps, totals in OPDS 2 only | `books/latest?size=2000` | **1 request, 0.38 s, 1.3 MB** |
| **Kavita 0.9.1** | No | A glyph on book titles (⭘ ◔ ◑ ◕ ⬤), per user, can be turned off | 20 a page fixed, `pageNumber=` jumps, totals | Only under each series | 1 request per series (not timed at scale; 3–13 ms a request) |
| **On iPhone** | All on the iPhone | Octavo's own record | None | Already there | Instant |

### BookOrbit

- **All, collections and smart scopes** take the same body: `POST books/query`, `collections/{id}/books/query` and `smart-scopes/{id}/books/query`, each `{filter?, sort, pagination}`.
- **Sorts measured live:** `title`, `author` (by sort name), `addedAt`, `lastReadAt`, `publishedDate`, `series`, `seriesIndex`, `readProgress` and `random`. `collectionOrder` works only inside a collection and is a 400 elsewhere. An unknown field is a 400.
- **Series** sort only through their own list: `GET series/{id}/books?sort=` takes `seriesIndex`, `title` or `addedAt`. **Authors** likewise: `GET authors/{id}/books?sort=` takes `title`, `publishedYear` or `addedAt`. Neither filters. `books/query` with a `series` or `author` rule does filter, but by **name**, not id (an id matches nothing), and an author's name matches any part of a name ("Dumas" finds Alexandre Dumas). So a series' or an author's books filter on the iPhone, from every page of their own list (measured 2026-11-10; `bookorbit-api.md`, "Filtering").
- Read status is BookOrbit's own, which every reader writes (`bookorbit-api.md`, "Filtering").

### COPS

- `?sort=title|author|pubdate|rating|timestamp`, with ` desc` after it, works on every book feed. Sort facets (`opds:facetGroup="Sort"`) appear only on feeds with more than one page. An unknown sort is a 404.
- Filter facets (Authors, Tags, Languages, Ratings) appear on per-item feeds. There's no read state, because COPS has no users.
- Page size and a flat "All books" list can be set with cookies (`max_item_per_page`, `titles_split_first_letter`), but they're undocumented and don't change the reported `itemsPerPage`. Don't rely on them.

### Calibre-Web

- No facets, and no sort parameter. Sorts are fixed root feeds: by letter, newest, top rated, most downloaded, random.
- `?offset=N` jumps to any position, and pages are 60 long. There are no totals, so the end is the first short page.
- "Unread Books" means *not finished*, so books in progress count too. It's per user, unless the admin points it at a calibre column, which is shared.
- **The date added isn't in the entries**, only the order of `/opds/new`. `updated` is the last-modified date.
- Fetching pages several at a time didn't help (5.1 s for one at a time, 5.0 s for six), because the server's own work is the limit.

### Komga

- OPDS 1.2 has no facets, and each feed has one fixed order. `?sort=` is ignored.
- **`next` and `previous` links drop `size=`**, so Octavo would have to build page addresses itself (`page=` starts at 0).
- Most feeds list series. Feeds that list books: Keep Reading, On Deck, Latest books, each series, each read list. Following the `next` links of "Latest books" gave only 394 books over 20 pages (not looked into), while `size=2000` returned all 2,000 in one request.
- Read state is per user, written by Komga's reader, Kobo and KOReader sync and its API. It isn't in OPDS 1.2 entries for EPUBs. In OPDS 2 it's one progression request per book.
- With Basic auth every request costs about 60 ms; a session cookie brings it to about 8 ms. Octavo keeps no cookies (`ServerTransport`, network trust), and with one large request it doesn't matter.

### Kavita

- No facets and no sort parameter. Pages are 20 long, fixed. `pageNumber` starts at 1.
- Books appear only inside a series (`series/{id}`, every book at once) and reading lists. Everything else lists series.
- The read-state glyph sits on book titles, never on series. Octavo already strips it. It's per user and counts Kavita's pages.
- **A GET on a PSE `/image` link saves progress by default.** Never fetch those links while listing.
- The "recently updated" feed always claims 30 results and a next page, and page 2 is empty.

### Every OPDS server

- No feed on any of the four answers a conditional GET: COPS, Calibre-Web and Kavita send no ETag, and Komga's changes on most feeds. A list can only be checked for changes by fetching it again.
- Dates in entries aren't the date added (Calibre-Web, Kavita and COPS put other dates in `updated`). **Recently added** can only be the server's own "new" feed (`OPDSCatalogHints.recentlyAdded`), not a sort on the iPhone.
- Author names come as "First Last". Sorting by author on the iPhone needs `AuthorIndex`'s last-name rule.

## How Octavo could do it

### Read status off BookOrbit

Octavo already keeps a place for every book it has opened (`BookPlaces`) and a Finished mark for books whose server doesn't keep one (`FinishedBooks`). So:

- **Unread:** no place and not finished.
- **Reading:** a place, not finished.
- **Finished:** marked finished.

This works the same on every OPDS server and on the iPhone, and needs no server support. Its limit: **it knows only what happened in Octavo** (and through KOReader sync, for a catalog with it switched on). A book read in Komga's own reader still shows as Unread. Calibre-Web's Unread feed and Kavita's glyphs could add the server's knowledge, but each works differently, so leave them for later.

### Sorting and filtering an OPDS list

Per list, not per server. When a sort the server can't do, or a status, is picked on an OPDS list:

1. **Fetch the whole list.** Generic OPDS: follow `next`. Known servers go faster:
   - Komga: `size=2000`, building page addresses itself.
   - Calibre-Web: `?offset=`.
   - COPS: `?sort=`, so no full fetch is needed for a sort.
2. **Show books as they arrive.** The count reads as loading until the last page is in.
3. **Stop at a cap**, say 2,000 books, and say so ("Showing the first 2,000"). From the timings, 2,000 books takes 0.4–5 s on this Mac, before Wi-Fi.
4. **Sort and filter on the iPhone**, with the local status above and `AuthorIndex` for authors.
5. **Keep it in memory** while the app runs. Pull to refresh fetches it again. A disk cache waits until real-device timings show it's needed. If one comes, it's keyed by the server's ID and the stored address (Kavita's and Stump's keys sit in the address), lives in Caches, goes with Remove server, and needs the network-trust review.

Lists of series or authors (Komga's and Kavita's usual feeds) hold no books, so they'd sort by name only, or get no button.

### Books on the iPhone

All local: title, author, the date it came in (`DownloadedBook.downloadedAt`), and the status above. `DownloadOrder` (Books on iPhone's sort menu) already sorts by title, author and date, and the shared menu can reuse it.

### Which menu where

| List | Sort by | Show |
|---|---|---|
| BookOrbit All, collection, smart scope | Title, Author, Recently added (plus collection order in a collection, scope order in a scope) | Server |
| BookOrbit series | Reading order, Title, Recently added | On the iPhone, from the series' own list |
| BookOrbit author | Title, Recently added | On the iPhone, from the author's own list |
| COPS book list | Server `?sort=` | Local, after a full fetch |
| Other OPDS book list | Server order, plus Title and Author after a full fetch | Local, after a full fetch |
| OPDS list of series or authors | Name only, or none | None |
| On iPhone | Title, Author, Recently added | Local |

That didn't settle **split or one menu** on its own: every list above has both sections or neither, except OPDS lists of series. Two buttons would cost room in the side column for nothing on most lists.

## Questions for Adam (all answered 2026-11-09)

1. ~~Show on OPDS and On iPhone from Octavo's own record?~~ **Yes** (Adam, 2026-11-09): "Unread" there means not started in Octavo.
2. ~~One menu, or two buttons?~~ **Two buttons** (Adam, 2026-11-09): Sort (Sort by: Title, Author, Recently added) and Filter (Show: All books, Unread, Reading, Finished), one under the other below Back. Only Filter fills while it hides books. A list that can't be filtered (OPDS series) shows Sort alone. Filters can grow later without pushing Sort down.
3. ~~The cap and loading~~ **Load first, cap at 2,000** (Adam, 2026-11-09): a list sorted or filtered on the iPhone shows "Loading books…" over "600 of 2,000" (or "600 books" without a total) until every page is in, then appears at once; past the cap the list ends with "Only the first 2,000 books were loaded." A list in the server's order still loads page by page.
4. ~~Sort on OPDS~~ **Decided** (Adam, 2026-11-09): BookOrbit and COPS sort on the server (Title, Author, Recently added). Calibre-Web, Komga, Kavita and other OPDS servers offer Default (the catalog's order), Title and Author, sorted on the iPhone after the list loads. No Published sort.
5. ~~Lists of series~~ **Books only** (Adam, 2026-11-09): lists of series, authors and collections get neither button.
6. ~~Order of work~~ **Three pull requests** (Adam, 2026-11-09): BookOrbit first (every book list, sorted and filtered on the server, plus the shared buttons, menus, remembered sort and empty lists), then On iPhone (local), then OPDS (loading whole lists).

## Not measured yet

- Real-device timings over Wi-Fi and over a VPN. Every request adds the network's delay: Komga's single request barely changes, while COPS's 51 and Kavita's one-per-series grow most.
- Kavita at scale, and Stump, which isn't among the local servers.
- Memory and parse time for 2,000 entries on the Duo.
