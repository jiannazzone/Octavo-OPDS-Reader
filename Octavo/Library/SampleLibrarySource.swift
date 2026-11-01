#if DEBUG
import Foundation
import OctavoKit

/// Made-up library data with no server: the public-domain books from the
/// Figma frames, a collection, a smart scope, a series and their authors.
/// For screenshots (`-sampleLibrary 1`), previews and tests. Covers fail, so
/// books show their stand-in covers.
nonisolated struct SampleLibrarySource: LibrarySource {
    static let id = LibrarySourceID(rawValue: "sample")

    /// Home's empty state (frame 25): nothing in progress.
    var nothingInProgress = false

    static let books: [LibraryBook] = {
        func book(_ id: String, _ title: String, _ author: String, series: (String, Double)? = nil, progress: Double? = nil, hoursAgo: Double? = nil) -> LibraryBook {
            LibraryBook(
                id: LibraryBookID(rawValue: id), title: title, authors: [author],
                series: series.map { LibrarySeriesPosition(name: $0.0, position: $0.1, link: LibraryLink(rawValue: "series/sherlock")) },
                cover: LibraryCover(rawValue: id),
                files: [LibraryFile(id: LibraryFileID(rawValue: id), format: "epub", isPrimary: true)],
                progress: progress,
                lastReadAt: hoursAgo.map { Date(timeIntervalSinceNow: -$0 * 3600) }
            )
        }
        return [
            book("moby-dick", "Moby-Dick", "Herman Melville", progress: 0.3, hoursAgo: 2),
            book("frankenstein", "Frankenstein", "Mary Wollstonecraft Shelley", progress: 0.71, hoursAgo: 26),
            book("pride-and-prejudice", "Pride and Prejudice", "Jane Austen"),
            book("alice", "Alice’s Adventures in Wonderland", "Lewis Carroll"),
            book("adventures", "The Adventures of Sherlock Holmes", "Arthur Conan Doyle", series: ("Sherlock Holmes", 1)),
            book("memoirs", "The Memoirs of Sherlock Holmes", "Arthur Conan Doyle", series: ("Sherlock Holmes", 2)),
            book("return", "The Return of Sherlock Holmes", "Arthur Conan Doyle", series: ("Sherlock Holmes", 3)),
        ]
    }()

    private static func books(_ ids: String...) -> [LibraryBook] {
        ids.compactMap { id in books.first { $0.id.rawValue == id } }
    }

    private static func link(_ rawValue: String) -> LibraryLink {
        LibraryLink(rawValue: rawValue)
    }

    private static let authors: [(sortName: String, name: String)] = [
        ("Austen, Jane", "Jane Austen"),
        ("Carroll, Lewis", "Lewis Carroll"),
        ("Doyle, Arthur Conan", "Arthur Conan Doyle"),
        ("Melville, Herman", "Herman Melville"),
        ("Shelley, Mary Wollstonecraft", "Mary Wollstonecraft Shelley"),
    ]

    func root() async throws -> LibraryRoot {
        LibraryRoot(
            title: "Sample",
            chips: [
                LibraryEntry(kind: .feed, title: "All", link: Self.link("all")),
                LibraryEntry(kind: .feed, title: "Collections", link: Self.link("collections")),
                LibraryEntry(kind: .feed, title: "Series", link: Self.link("series")),
                LibraryEntry(kind: .feed, title: "Authors", link: Self.link("authors")),
            ],
            search: .booksSeriesAndAuthors,
            recentlyAdded: Self.link("recent"),
            continueReading: Self.link("reading")
        )
    }

    func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        let feed: LibraryFeed
        switch link.rawValue {
        case "all":
            feed = LibraryFeed(title: "All", books: Self.books.sorted { $0.title < $1.title })
        case "recent":
            feed = LibraryFeed(books: Self.books("pride-and-prejudice", "alice", "adventures", "memoirs", "return"))
        case "reading":
            feed = LibraryFeed(books: nothingInProgress ? [] : Self.books("moby-dick", "frankenstein"))
        case "collections":
            feed = LibraryFeed(title: "Collections", entries: [
                LibraryEntry(kind: .collection, title: "Classics", count: 5, link: Self.link("collections/classics")),
                LibraryEntry(kind: .smartCollection, title: "To read next", count: 2, link: Self.link("collections/next")),
            ])
        case "collections/classics":
            feed = LibraryFeed(books: Self.books("moby-dick", "frankenstein", "pride-and-prejudice", "alice", "adventures"))
        case "collections/next":
            feed = LibraryFeed(books: Self.books("memoirs", "return"))
        case "series":
            feed = LibraryFeed(title: "Series", entries: [
                LibraryEntry(kind: .series, title: "Sherlock Holmes", subtitle: "Arthur Conan Doyle", count: 3,
                             previewCovers: Self.books("adventures", "memoirs", "return").compactMap(\.cover),
                             link: Self.link("series/sherlock")),
            ])
        case "series/sherlock":
            feed = LibraryFeed(books: Self.books("adventures", "memoirs", "return"))
        case "authors":
            feed = LibraryFeed(title: "Authors", entries: Self.authors.map { author in
                LibraryEntry(kind: .author, title: author.name, count: Self.books.filter { $0.authors == [author.name] }.count,
                             sortName: author.sortName, link: Self.link("authors/\(author.name)"))
            })
        case let path where path.hasPrefix("authors/"):
            let name = String(path.dropFirst("authors/".count))
            feed = LibraryFeed(books: Self.books.filter { $0.authors == [name] })
        default:
            throw LibraryError.invalidLink
        }
        var counted = feed
        counted.total = feed.entries.count + feed.books.count
        return counted
    }

    func search(_ query: String) async throws -> LibrarySearchResults {
        let books = Self.books.filter { $0.title.localizedStandardContains(query) }
        return LibrarySearchResults(query: query, books: LibraryFeed(books: books, total: books.count))
    }

    func details(for book: LibraryBook) async throws -> LibraryBookDetails {
        LibraryBookDetails(book: book)
    }

    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data {
        throw LibraryError.notFound
    }

    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw LibraryError.notFound
    }
}
#endif
