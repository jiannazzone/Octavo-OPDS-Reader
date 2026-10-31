# Octavo – OPDS Reader

I'm using Claude as part of the development process. Just stating that upfront.

A free, open-source e-reader for iPhone and iPad, built first for **iPhone Duo**.

Octavo reads books from your own library servers. It works with any OPDS catalog (Calibre, COPS, Calibre-Web, Kavita, Komga and others), and it has a full native integration with [BookOrbit](https://github.com/bookorbit/bookorbit).

> **Status:** early planning and prototyping. Nothing usable yet.

## Goals

- **Free and open source.** No subscriptions, no accounts, no tracking.
- **Your library, your server.** Browse, search and download from OPDS 1.2 and OPDS 2.0 catalogs.
- **First-class BookOrbit support.** Collections, smart scopes, series and authors. Two-way sync of reading position, highlights, bookmarks, reading sessions and read status.
- **Built for iPhone Duo.** Two-page spreads across the fold, a "book" posture when half-folded, and seamless fold/unfold continuity.
- **Formats:** EPUB, PDF, CBZ/CBR, plus MOBI/AZW3/FB2 where the engine supports them.

## Planned features

| Area | Planned |
|---|---|
| Sources | Generic OPDS 1.2 / 2.0 (OpenSearch, Basic auth, OPDS Authentication, Page Streaming), BookOrbit native API |
| Progress sync | BookOrbit, KOReader sync (kosync), iCloud |
| Reading | Paginated and scrolled modes, themes, fonts, highlights, bookmarks, search, TOC |
| iPhone Duo | Hinge-aware layouts, two-page spreads, half-folded book mode |

## Building

Requires Xcode 27.1+ and the iOS 27.1 SDK (for the iPhone Duo APIs). Open `Octavo.xcodeproj` and run the `Octavo` scheme. There are no package dependencies to install.

For test books, `Scripts/fetch-sample-books.sh` downloads a few public-domain EPUBs from Project Gutenberg into `SampleBooks/`.

## License

Octavo is licensed under the [Mozilla Public License 2.0](LICENSE).

Third-party components keep their own licenses. See `THIRD-PARTY-NOTICES.md` once it exists.
