# OPDS as a source (#8)

`OPDSSource` (OctavoKit `OPDS/`) makes any OPDS 1.2 (Atom) or 2.0 (JSON)
catalog a `LibrarySource`. Tested against Calibre-Web, COPS, Komga (both
versions) and Kavita, run locally from `dev/opds/`. Screenshots in
`opds-source/`.

## Decisions (Adam, 2026-11-01)

1. **Our own parsers,** not Readium's `ReadiumOPDS`: `XMLParser` for Atom,
   `Codable` for JSON. Readium 3.11.1's OPDS module needs `ReadiumShared`
   (about 20,500 lines plus SwiftSoup, Fuzi, ZIPFoundation and Zip/minizip
   under zlib), which imports UIKit unguarded and is iOS-only, so OctavoKit's
   macOS `swift test` would break. Its fetch helpers use `URLSession.shared`
   (bypassing #9's session), it doesn't read Authentication Documents, and
   its models are non-Sendable classes. It would have saved only the raw parse.
2. **Format preference:** EPUB, then AZW3, MOBI, FB2, FBZ, then the rest in
   the server's order. The first file is marked primary, so Open downloads
   the first one the reader opens.
3. **Chips:** every root entry, in the server's order; the bar scrolls. A
   root with no entries gets one chip named after the feed. A root that lists
   books as well gets that chip too.
4. **Home's "New on …":** the `sort/new` link, else a root entry that is
   clearly the newest books (by id, path, then title). Only COPS sends
   `sort/new`.
5. **Start chip:** the Library opens on the whole-library chip (Calibre-Web
   Alphabetical Books, COPS All books, Komga All series, Kavita All
   Libraries) rather than an empty Keep Reading or On Deck; Home covers
   what you're reading. The chips keep the server's order, and the bar
   scrolls to the selected chip. `LibraryRoot.startChip` carries it.

## How it maps

| OPDS | Library |
|---|---|
| Navigation entry (Atom entry with a catalog link and no acquisition link; OPDS 2 `navigation`) | `LibraryEntry` `.feed`; subtitle from authors, else the summary as plain text; count from `thr:count` / `numberOfItems` |
| Entry with an acquisition link, or with cover art and no catalog link | `LibraryBook` |
| OPDS 2 group with its own `self` list | one entry that opens it, with up to three preview covers |
| OPDS 2 group without one | its items, inline |
| `rel="next"` | `LibraryFeed.next` |
| `opensearch:totalResults` / `numberOfItems` | `total`; a single-page feed counts its items |
| `rel="search"` | `.books`; the template in the root wins over fetching the OpenSearch description; RFC 6570 `{?query}` too |

- **IDs are absolute URLs.** Links, file IDs and the cover's two URLs (JSON in
  `LibraryCover.rawValue`) are what the catalog linked, resolved against the
  response's URL. `feed` refuses anything that isn't absolute http(s)
  (`invalidLink`). A book's ID is its entry `id`.
- **Files:** only `acquisition` and `acquisition/open-access`; purchases,
  loans, samples and indirect acquisitions (DRM licences, web pages) are left
  out. A link's title or extension wins over its type when it names a known
  format: Calibre-Web sends AZW3 and MOBI as the same
  `application/x-mobipocket-ebook` and plain FB2 as `application/fb2+zip`.
- **Details:** OPDS has no detail request, so the source keeps every book it
  listed (bounded at 5,000) and builds details from that entry, following a
  `rel="alternate"` full-entry link when there is one. A book it hasn't
  listed this launch (one remembered by Continue reading) gets only what the
  `LibraryBook` carries. Authors link to their books when the catalog does
  (COPS `<uri>` on the catalog's own origin, OPDS 2 links), else to a search
  for their name.
- **Kavita quirks:** its read-state glyph ("⭘ ", "◔ ", "⬤ ") is stripped from
  titles, and "Alice - Alice" becomes "Alice". Its Recently Added lists
  series, so Home's row stays empty there.

## Sign-in

- `checkAccess()` loads the root: `.open(title:)`, or `.signInRequired`
  with the Authentication Document's title and field labels (Komga sends it
  with the 401; a `Link: rel="http://opds-spec.org/auth/document"` header is
  followed too), or a plain request when there's only `WWW-Authenticate:
  Basic` (Calibre-Web). A document that offers no Basic method says
  `supportsBasic: false`. This is what #12's form calls.
- The Basic header goes **only to the catalog's origin** (scheme, host, port),
  never to a cover or file on another host, and is dropped if a redirect
  leaves the origin (including https → http). A 401 is `signedOut`.
- `OPDSCredentialStore` (`load`/`save`, like `BookOrbitTokenStore`) with
  `InMemoryOPDSCredentialStore` for now. **#9** supplies the Keychain store
  and the trust-aware `URLSession` (both injected through `OPDSSource.init`);
  whichever of #8 and #9 merges second wires them.

### For the security review (#9)

- Whether Basic may go over plain http is the session's call (decision 25);
  `OPDSSource` sends it on whatever the session lets through.
- **Kavita's API key is in every URL** (`/api/opds/{key}/…`, covers'
  `apiKey=`). Those URLs become `LibraryLink`s, file IDs and cover values, and
  `RecentBooks` writes `SourcedBook`s to Application Support, so the key ends
  up on disk in plain JSON. Options: keep it (it's what Kavita hands out),
  or have the source store links without the key and add it back per request.
- The redirect guard isn't covered by the stub tests (the stub protocol
  doesn't redirect).

## Pitfalls

- macOS `cp -n` exits 1 when the target exists; `seed.sh` checks first.
- Calibre-Web's `cps.py -s user:pass` checks its default password policy
  (needs a special character) before reading the database's settings; the
  seed writes the hash with Calibre-Web's own werkzeug instead.
- Adam's calibre has third-party plugins that run on `calibredb add`; the
  seed gives calibredb a throwaway `CALIBRE_CONFIG_DIRECTORY`.
- Kavita 0.9.1's `Library/create` rejects a missing `fileGroupTypes`,
  `excludePatterns` or a `metadataProvider` other than 2.
- Kavita's root `self` link drops the API key (`/api/opds/`); never resolve
  against `self`, only the response URL.
- Komga's `<content>` is empty and its series are named after folders, so the
  seed names folders after the titles.
- Home shows "Nothing in progress" and hides the new-books row until a book
  is in Continue reading (#13, frame 25). Open one book to see the row.

## Tests

- OctavoKit 129/129 (`swift test`), 31 of them OPDS with fixtures written for
  Octavo (`OPDSFixtures.swift`): Atom and JSON parsing, formats and order,
  templates, chips and hints, groups, covers, details, search, origin-only
  sign-in, the access check, refused links.
- Live: `OCTAVO_OPDS_LIVE=1 swift test --filter OPDSLiveTests`, 11 cases
  over the five catalogs (`dev/opds/README.md`). Read-only.
- App on 'Octavo OPDS Duo': Library on all five catalogs; Calibre-Web
  covers and an EPUB download with Basic sign-in, opened in the reader; Home
  with Continue reading and New on Calibre-Web, folded and unfolded.
