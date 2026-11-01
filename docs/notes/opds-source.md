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

## Sign-in and secrets

Decided by Claude (technical, no UI effect), after #9's audit of the OPDS
side; Adam is the design owner and leaves these calls to us.

- `checkAccess()` loads the root: `.open(title:)`, or `.signInRequired`
  with the Authentication Document's title and field labels (Komga sends it
  with the 401; a `Link: rel="http://opds-spec.org/auth/document"` header is
  followed too, only on the catalog's own origin) and the **scheme** to
  record with the server (`OPDSAuthScheme`). The 401's `WWW-Authenticate`
  decides the scheme when there is one, read by scheme name (not
  `Bearer realm="basic"`), and Digest wins over Basic when both are
  offered; no challenge means Basic; only unsupported methods (OAuth,
  Bearer) mean `scheme: nil`. A server already recorded as Digest stays
  Digest whatever a later 401 says. This is what #12's form calls.
- **The scheme is pinned.** #12 stores it with the server and passes it as
  `OPDSSource(authScheme:)`. Only `.basic` sends the password up front, and
  only to the catalog's own origin (scheme, host, port), never to a cover or
  file on another host. `.digest` or `nil`: nothing up front; #9's transport
  answers the server's own challenge. So a server, or someone answering at
  its home-network address, can't ask a Digest server's client for Basic and
  get the password in clear. The transport must also refuse a Basic
  challenge for a Digest server; that's #9's side (told them).
- The password is read from the store once, not per request (the Keychain
  would be hit per cover), and read again after any 401.
- **Kavita's API key never leaves the source.** Kavita's address is
  `…/api/opds/<key>` and every link it sends repeats the key.
  `OPDSURLSecret.detect(in:)` finds it in the pasted address (#12 keeps it in
  the Keychain, next to the password); `OPDSSource(secret:)` writes `{key}`
  in its place in every link, book ID, file ID and cover value it hands out,
  and `resolve` puts it back only for a URL on the catalog's own origin. A
  link to another host keeps `{key}` and is refused. Checked on the
  simulator: after opening a Kavita book, the key appears nowhere in the
  app's data; `RecentBooks.json` holds `{key}`.
- **Networking goes through #9's types**, mirrored in
  `OPDS/NetworkStandIns.swift` until #9 merges (whichever merges second
  deletes that file and keeps #9's). `transport` is required, with no
  `URLSession` shortcut in OctavoKit: in the app it's #9's
  `ServerTransport` for that server, one per source. Tests use a test-only
  `SessionTransport`, and the debug rows a DEBUG-only
  `DebugSessionTransport`, both to be swapped for `ServerTransport` (tests:
  with the stub protocol in `configuration.protocolClasses` and
  `HomeNetworkPolicy.testing`). The transport checks every address,
  pins certificates, refuses https → http and `user:pass@` URLs, and strips
  `Authorization` on redirects that change origin, so the OPDS code doesn't.
  Its `NetworkTrustError`s pass through like `URLError`; a `URLError` loses
  its failing URL on the way out, since that URL has the real key in it.
- Filenames from URLs are dropped when they hold a decoded `/` or start
  with a dot.

### Adversarial audit (2026-11-01)

An independent reviewer attacked this code. What held: the key is never
restored for another origin (`//host`, userinfo tricks, `\@`, case, ports,
IPv6), a literal `{key}` in a feed is a template, not a link, the Basic
password never goes to another origin, the XML parser refuses
billion-laughs and external entities, and JSON nesting is bounded. Fixed
here: scheme parsing by name, Digest not talked down, failing URLs
stripped from errors, the key redacted in entry IDs, proxy-prefixed Kavita
addresses, ASCII-only encoding in redaction, unsafe filenames, a sign-in
document on another host.

**Still open, outside #8:**
- **High, #9's transport:** `ServerTransport` answers a Basic challenge
  even for a server recorded as Digest, so someone answering a home-http
  server's address can still get the password in clear. Fix: give the
  transport the recorded scheme and answer only that one (asked of #9).
- **#9's transport:** no limit on response size; an endless body from a
  hostile catalog can make iOS kill the app, on every launch if it's on
  Home. A cap belongs in the transport.
- **#12:** save `redact(catalogURL)`, never the live address; keep the
  Kavita key in the Keychain; record `checkAccess`'s scheme instead of
  assuming Basic. The DEBUG connect code (`DebugSessionTransport`, the
  bare-session Kavita login, hard-coded `.basic`) must not be copied into
  release code.
- The OpenSearch description and its template may sit on another host;
  search queries then go there. Left as is: some catalogs host search
  separately.

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
