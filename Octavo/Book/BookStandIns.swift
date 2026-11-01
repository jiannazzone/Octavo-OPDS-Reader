import Foundation
import OctavoKit

// Stand-ins until #13 brings the Library and the current source: the shell's
// placeholder books as library books, and a source that serves their
// details. Delete when `ShellRoute.cover` carries a `LibraryBook`.

extension PlaceholderBook {
    /// The book as a library lists it. The IDs are the seeded local
    /// BookOrbit's (`dev/bookorbit/README.md`), so with `-shellSource
    /// bookorbit` the same covers open the real books.
    nonisolated var libraryBook: LibraryBook {
        let ids = ["alice": "1", "frankenstein": "2", "moby-dick": "3", "pride-and-prejudice": "4", "sherlock": "5"]
        return LibraryBook(id: LibraryBookID(rawValue: ids[id] ?? id), title: title, authors: [author], progress: progress)
    }
}

/// Details for the placeholder books, with no covers and no downloads
/// (Open reports "Couldn't download"). For previews and the shell's
/// stand-in screens.
nonisolated struct SampleLibrarySource: LibrarySource {
    func root() async throws -> LibraryRoot {
        LibraryRoot(title: "Sample library", chips: [], search: .unavailable)
    }

    func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        LibraryFeed()
    }

    func search(_ query: String) async throws -> LibrarySearchResults {
        LibrarySearchResults(query: query)
    }

    func details(for book: LibraryBook) async throws -> LibraryBookDetails {
        var full = book
        full.files = [LibraryFile(id: LibraryFileID(rawValue: book.id.rawValue), format: "epub", sizeBytes: 1_234_567, isPrimary: true)]
        return LibraryBookDetails(
            book: full,
            description: "<p>A stand-in description for <i>\(book.title)</i>, long enough to need More: the Library and its server arrive with #13, and with them each book’s own description, its series, its collections and the day it was added.</p>",
            addedAt: Date(timeIntervalSince1970: 1_793_404_800),
            authors: book.authors.map { LibraryEntry(kind: .author, title: $0, link: LibraryLink(rawValue: "author/\($0)")) },
            collections: [LibraryEntry(kind: .collection, title: "Classics", link: LibraryLink(rawValue: "collection/classics"))]
        )
    }

    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data {
        throw LibraryError.notFound
    }

    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw URLError(.cannotConnectToHost)
    }
}
