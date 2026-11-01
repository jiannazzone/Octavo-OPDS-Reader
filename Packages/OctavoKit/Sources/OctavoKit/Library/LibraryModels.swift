import Foundation

// What a `LibrarySource` hands the app. Identifiers are opaque strings: the
// app stores them and passes them back, and only the source that made one
// reads it (a BookOrbit route, an OPDS URL).

/// Where a list lives: a chip, a collection, an author, the next page.
public struct LibraryLink: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct LibraryBookID: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct LibraryFileID: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A cover image the source can fetch.
public struct LibraryCover: Hashable, Codable, Sendable {
    /// Opaque, read by the source that made it.
    public var rawValue: String
    /// Changes when the image does. `nil` if the source can't tell.
    public var version: String?

    public init(rawValue: String, version: String? = nil) {
        self.rawValue = rawValue
        self.version = version
    }

    /// Stable while the image is unchanged; key an image cache on it.
    public var cacheKey: String {
        version.map { "\(rawValue)@\($0)" } ?? rawValue
    }
}

public enum LibraryCoverSize: Sendable {
    /// For grids and rows (BookOrbit: about 386×600).
    case thumbnail
    /// The original, for the full-screen cover.
    case full
}

/// The top of a library: the Library tab's chips and what search can do.
public struct LibraryRoot: Hashable, Codable, Sendable {
    public var title: String?
    /// BookOrbit: All, Collections, Series, Authors. OPDS: the root feed's
    /// own entries.
    public var chips: [LibraryEntry]
    public var search: LibrarySearchSupport
    /// Newest books first, for Home. `nil` if the source has no such list.
    public var recentlyAdded: LibraryLink?

    public init(title: String? = nil, chips: [LibraryEntry], search: LibrarySearchSupport, recentlyAdded: LibraryLink? = nil) {
        self.title = title
        self.chips = chips
        self.search = search
        self.recentlyAdded = recentlyAdded
    }
}

public enum LibrarySearchSupport: String, Hashable, Codable, Sendable {
    /// The server can't search; search only the books on the device.
    case unavailable
    /// Books only (OPDS OpenSearch).
    case books
    /// Books, plus matching series and authors (BookOrbit).
    case booksSeriesAndAuthors
}

/// One page of a list. A list can hold entries (shown as a list), books
/// (shown as a grid), or both.
public struct LibraryFeed: Hashable, Codable, Sendable {
    public var title: String?
    public var entries: [LibraryEntry]
    public var books: [LibraryBook]
    /// Items across all pages, if the source knows.
    public var total: Int?
    /// The next page; `nil` on the last one.
    public var next: LibraryLink?

    public init(title: String? = nil, entries: [LibraryEntry] = [], books: [LibraryBook] = [], total: Int? = nil, next: LibraryLink? = nil) {
        self.title = title
        self.entries = entries
        self.books = books
        self.total = total
        self.next = next
    }
}

/// An item that leads to another list: a chip, a collection, a series, an
/// author, an OPDS navigation entry.
public struct LibraryEntry: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case collection
        /// A saved filter, such as a BookOrbit smart scope.
        case smartCollection
        case series
        case author
        /// Anything else: a chip, an OPDS navigation entry.
        case feed
    }

    public var kind: Kind
    public var title: String
    /// Series: its authors. OPDS: the entry's summary.
    public var subtitle: String?
    /// How many books it leads to, if known.
    public var count: Int?
    /// For A–Z sections, e.g. "Austen, Jane". `nil`: use `title`.
    public var sortName: String?
    /// Up to three covers to show on the row. Empty when the source doesn't
    /// list them (BookOrbit collections): load the entry's first page instead.
    public var previewCovers: [LibraryCover]
    public var link: LibraryLink

    public var id: LibraryLink { link }

    public init(
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        count: Int? = nil,
        sortName: String? = nil,
        previewCovers: [LibraryCover] = [],
        link: LibraryLink
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.sortName = sortName
        self.previewCovers = previewCovers
        self.link = link
    }
}

/// A book as lists show it.
public struct LibraryBook: Hashable, Codable, Sendable, Identifiable {
    public var id: LibraryBookID
    /// Empty if the server has none; show a placeholder.
    public var title: String
    public var authors: [String]
    public var series: LibrarySeriesPosition?
    public var cover: LibraryCover?
    public var files: [LibraryFile]
    /// The server's progress through the book, 0...1, for lists. `nil` if it
    /// doesn't track one. The reader's own position comes from `ProgressSync`.
    public var progress: Double?

    public init(
        id: LibraryBookID,
        title: String,
        authors: [String] = [],
        series: LibrarySeriesPosition? = nil,
        cover: LibraryCover? = nil,
        files: [LibraryFile] = [],
        progress: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.series = series
        self.cover = cover
        self.files = files
        self.progress = progress
    }

    /// The file the server marks primary, else the first one.
    public var primaryFile: LibraryFile? {
        files.first(where: \.isPrimary) ?? files.first
    }
}

/// Where a book sits in a series.
public struct LibrarySeriesPosition: Hashable, Codable, Sendable {
    public var name: String
    /// The book's number (1, 2, 2.5). `nil` if unnumbered.
    public var position: Double?
    /// The series' books in reading order, if the source has that list.
    public var link: LibraryLink?

    public init(name: String, position: Double? = nil, link: LibraryLink? = nil) {
        self.name = name
        self.position = position
        self.link = link
    }
}

/// A downloadable file of a book.
public struct LibraryFile: Hashable, Codable, Sendable, Identifiable {
    public var id: LibraryFileID
    /// Lowercase format name: `"epub"`, `"pdf"`, `"cbz"`, …
    public var format: String?
    public var sizeBytes: Int?
    public var filename: String?
    public var isPrimary: Bool

    public init(id: LibraryFileID, format: String? = nil, sizeBytes: Int? = nil, filename: String? = nil, isPrimary: Bool = false) {
        self.id = id
        self.format = format
        self.sizeBytes = sizeBytes
        self.filename = filename
        self.isPrimary = isPrimary
    }
}

/// Everything the details sheet shows (decision 20).
public struct LibraryBookDetails: Hashable, Codable, Sendable {
    /// The book, with its files' filenames filled in where the source has them.
    public var book: LibraryBook
    public var subtitle: String?
    /// May contain HTML.
    public var description: String?
    public var publisher: String?
    public var language: String?
    /// As the server sends it: `"1998-06-01"` or `"1998"`.
    public var published: String?
    public var addedAt: Date?
    /// Each leads to the author's books when the source has that list.
    public var authors: [LibraryEntry]
    /// Every series the book is in; the first is `book.series`.
    public var series: [LibrarySeriesPosition]
    public var collections: [LibraryEntry]

    public init(
        book: LibraryBook,
        subtitle: String? = nil,
        description: String? = nil,
        publisher: String? = nil,
        language: String? = nil,
        published: String? = nil,
        addedAt: Date? = nil,
        authors: [LibraryEntry] = [],
        series: [LibrarySeriesPosition] = [],
        collections: [LibraryEntry] = []
    ) {
        self.book = book
        self.subtitle = subtitle
        self.description = description
        self.publisher = publisher
        self.language = language
        self.published = published
        self.addedAt = addedAt
        self.authors = authors
        self.series = series
        self.collections = collections
    }
}

public struct LibrarySearchResults: Hashable, Codable, Sendable {
    public var query: String
    /// The first page of matching books; `books.next` pages on.
    public var books: LibraryFeed
    /// Empty unless the source supports `.booksSeriesAndAuthors`.
    public var series: [LibraryEntry]
    public var authors: [LibraryEntry]

    public init(query: String, books: LibraryFeed = LibraryFeed(), series: [LibraryEntry] = [], authors: [LibraryEntry] = []) {
        self.query = query
        self.books = books
        self.series = series
        self.authors = authors
    }
}

/// What a `LibrarySource` throws, whatever the server. Network failures stay
/// `URLError` (the server can't be reached).
public enum LibraryError: Error, Equatable, Sendable {
    /// No session, or the server ended it. Sign in again.
    case signedOut
    /// The book, file or list doesn't exist (any more).
    case notFound
    /// The link wasn't made by this source.
    case invalidLink
    /// Any other non-2xx answer.
    case server(status: Int, message: String?)
    /// The server's answer couldn't be read.
    case invalidResponse
}
