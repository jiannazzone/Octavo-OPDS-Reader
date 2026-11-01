import Foundation

// Response models for the BookOrbit REST API (`/api/v1`), checked against
// BookOrbit v3.6.0. Only `id` and the display name are required; everything
// else is optional so a server that drops or renames a field still decodes.
// Unknown fields are ignored.

public struct BookOrbitUser: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var username: String
    public var name: String?
    public var email: String?
    public var isSuperuser: Bool?
    public var permissions: [String]?
}

public struct BookOrbitLibrary: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// `"books"` or `"podcasts"`.
    public var type: String?
    public var icon: String?
    public var bookCount: Int?
}

public struct BookOrbitCollection: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// `"books"` or `"podcasts"`.
    public var mediaType: String?
    public var icon: String?
    public var description: String?
    public var bookCount: Int?
    public var isPublic: Bool?
    public var isOwner: Bool?
}

/// A saved filter over the user's books (BookOrbit's "smart scope"), listed
/// with collections.
public struct BookOrbitSmartScope: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// `"books"` or `"podcasts"`.
    public var mediaType: String?
    public var icon: String?
    public var bookCount: Int?
    public var isPublic: Bool?
    public var isOwner: Bool?
}

/// A series from `GET series` or a search.
public struct BookOrbitSeries: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var bookCount: Int?
    public var authors: [String]
    /// Books whose covers stand for the series, in order.
    public var coverBookIDs: [Int]

    private enum CodingKeys: String, CodingKey { case id, name, bookCount, authors, coverBookIds }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        bookCount = c.lenient(Int.self, .bookCount)
        authors = c.lenient([String].self, .authors) ?? []
        coverBookIDs = c.lenient([Int].self, .coverBookIds) ?? []
    }
}

/// An author from `GET authors` or a search.
public struct BookOrbitAuthor: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// "Austen, Jane".
    public var sortName: String?
    public var bookCount: Int?
    /// One of their books with a cover, newest first.
    public var coverBookID: Int?

    private enum CodingKeys: String, CodingKey { case id, name, sortName, bookCount, coverBookId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sortName = c.lenient(String.self, .sortName)
        bookCount = c.lenient(Int.self, .bookCount)
        coverBookID = c.lenient(Int.self, .coverBookId)
    }
}

/// `GET search`: up to `limit` matches per section, with each section's total.
public struct BookOrbitSearchResults: Decodable, Hashable, Sendable {
    public var books: [BookOrbitBook]
    public var series: [BookOrbitSeries]
    public var authors: [BookOrbitAuthor]
    public var bookTotal: Int?
    public var seriesTotal: Int?
    public var authorTotal: Int?

    private enum CodingKeys: String, CodingKey { case books, series, authors }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let books = c.lenient(Section<BookOrbitBook>.self, .books)
        let series = c.lenient(Section<BookOrbitSeries>.self, .series)
        let authors = c.lenient(Section<BookOrbitAuthor>.self, .authors)
        self.books = books?.items ?? []
        self.series = series?.items ?? []
        self.authors = authors?.items ?? []
        bookTotal = books?.total
        seriesTotal = series?.total
        authorTotal = authors?.total
    }

    /// `{items: [{item, matchedField, matchedText}], total}`.
    private struct Section<Item: Decodable>: Decodable {
        var items: [Item]
        var total: Int?

        private enum CodingKeys: String, CodingKey { case items, total }
        private struct Hit: Decodable { var item: Item }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            items = (c.lenient(LossyArray<Hit>.self, .items)?.elements ?? []).map(\.item)
            total = c.lenient(Int.self, .total)
        }
    }
}

/// A page of a paged list. `page` is 0-based. Items that don't decode are
/// dropped rather than failing the page.
public struct BookOrbitPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public var items: [Item]
    public var total: Int?
    public var page: Int?
    public var size: Int?

    public init(items: [Item], total: Int? = nil, page: Int? = nil, size: Int? = nil) {
        self.items = items
        self.total = total
        self.page = page
        self.size = size
    }

    private enum CodingKeys: String, CodingKey { case items, total, page, size }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode(LossyArray<Item>.self, forKey: .items).elements
        total = c.lenient(Int.self, .total)
        page = c.lenient(Int.self, .page)
        size = c.lenient(Int.self, .size)
    }
}

/// A sort key for `POST books/query`.
public struct BookOrbitBookSort: Encodable, Hashable, Sendable {
    /// `"title"`, `"addedAt"`, `"relevance"`, `"seriesIndex"`, …
    public var field: String
    public var descending: Bool

    public init(_ field: String, descending: Bool = false) {
        self.field = field
        self.descending = descending
    }

    public static let title = BookOrbitBookSort("title")
    public static let newest = BookOrbitBookSort("addedAt", descending: true)
    public static let relevance = BookOrbitBookSort("relevance", descending: true)

    private enum CodingKeys: String, CodingKey { case field, dir }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(field, forKey: .field)
        try c.encode(descending ? "desc" : "asc", forKey: .dir)
    }
}

extension BookOrbitPage: Equatable where Item: Equatable {}
extension BookOrbitPage: Hashable where Item: Hashable {}

/// A book, from a list (`books/query`, `collections/{id}/books`, …) or from
/// `books/{id}`. The detail response fills more of the optional fields.
public struct BookOrbitBook: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var libraryID: Int?
    /// Empty if the server has none (lists can send `null`).
    public var title: String
    public var subtitle: String?
    public var authors: [String]
    /// Detail only: the authors with their ids, same order as `authors`.
    public var authorRefs: [BookOrbitAuthorRef]
    public var files: [BookOrbitFile]
    public var seriesID: Int?
    public var seriesName: String?
    /// BookOrbit 3.6 sends a string (`"2.5"`); older servers a number.
    public var seriesIndex: Double?
    /// Every series the book is in, in BookOrbit's display order.
    public var seriesMemberships: [BookOrbitSeriesMembership]
    /// Detail only.
    public var collections: [BookOrbitCollectionRef]
    public var language: String?
    public var publisher: String?
    public var publishedDate: String?
    public var publishedYear: Int?
    public var description: String?
    public var addedAt: Date?
    public var hasCover: Bool?
    public var coverVersion: String?
    /// Progress through the book, 0...1. Lists only; BookOrbit sends 0–100.
    public var readingFraction: Double?

    /// The file BookOrbit marks primary, else the first one.
    public var primaryFile: BookOrbitFile? {
        files.first { $0.role == "primary" } ?? files.first
    }

    private enum CodingKeys: String, CodingKey {
        case id, libraryId, title, subtitle, authors, files, seriesId, seriesName, seriesIndex, seriesMemberships
        case collections, language, publisher, publishedDate, publishedYear, description, addedAt
        case hasCover, coverVersion, readingProgress
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = c.lenient(String.self, .title) ?? ""
        libraryID = c.lenient(Int.self, .libraryId)
        subtitle = c.lenient(String.self, .subtitle)
        // Lists send author names; the detail sends {id, name, sortName}.
        authorRefs = c.lenient(LossyArray<BookOrbitAuthorRef>.self, .authors)?.elements ?? []
        authors = authorRefs.map(\.name)
        files = c.lenient(LossyArray<BookOrbitFile>.self, .files)?.elements ?? []
        seriesID = c.lenient(Int.self, .seriesId)
        seriesName = c.lenient(String.self, .seriesName)
        seriesIndex = c.seriesIndex(.seriesIndex)
        seriesMemberships = c.lenient(LossyArray<BookOrbitSeriesMembership>.self, .seriesMemberships)?.elements ?? []
        collections = c.lenient(LossyArray<BookOrbitCollectionRef>.self, .collections)?.elements ?? []
        language = c.lenient(String.self, .language)
        publisher = c.lenient(String.self, .publisher)
        publishedDate = c.lenient(String.self, .publishedDate)
        publishedYear = c.lenient(Int.self, .publishedYear)
        description = c.lenient(String.self, .description)
        addedAt = c.lenient(Date.self, .addedAt)
        hasCover = c.lenient(Bool.self, .hasCover)
        coverVersion = c.lenient(String.self, .coverVersion)
        readingFraction = c.lenient(Double.self, .readingProgress).map(BookOrbitProgress.fraction(fromPercentage:))
    }
}

/// A book's author: a bare name in lists, `{id, name, sortName}` in the detail.
public struct BookOrbitAuthorRef: Decodable, Hashable, Sendable {
    public var id: Int?
    public var name: String
    public var sortName: String?

    private enum CodingKeys: String, CodingKey { case id, name, sortName }

    public init(from decoder: any Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.name = name
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = c.lenient(Int.self, .id)
        sortName = c.lenient(String.self, .sortName)
    }
}

public struct BookOrbitSeriesMembership: Decodable, Hashable, Sendable {
    public var seriesID: Int
    public var seriesName: String
    public var seriesIndex: Double?

    private enum CodingKeys: String, CodingKey { case seriesId, seriesName, seriesIndex }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = try c.decode(Int.self, forKey: .seriesId)
        seriesName = try c.decode(String.self, forKey: .seriesName)
        seriesIndex = c.seriesIndex(.seriesIndex)
    }
}

/// A collection a book is in (`books/{id}` → `collections`).
public struct BookOrbitCollectionRef: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
}

public struct BookOrbitFile: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    /// Lowercase format name: `"epub"`, `"pdf"`, `"cbz"`, …
    public var format: String?
    /// `"primary"` for the file BookOrbit opens by default.
    public var role: String?
    public var sizeBytes: Int?
    /// Detail only.
    public var filename: String?
}

/// A reading position as stored by BookOrbit, per file.
public struct BookOrbitProgress: Hashable, Sendable {
    public var position: ReadingPosition
    /// When the text position last moved, on the server's clock. `nil` on
    /// servers that don't report it.
    public var updatedAt: Date?

    public init(position: ReadingPosition, updatedAt: Date? = nil) {
        self.position = position
        self.updatedAt = updatedAt
    }

    /// BookOrbit's `percentage` is 0–100; `ReadingPosition.fraction` is 0...1.
    static func fraction(fromPercentage percentage: Double) -> Double {
        clamp(percentage / 100)
    }

    static func percentage(fromFraction fraction: Double) -> Double {
        clamp(fraction) * 100
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

// MARK: - Wire types

struct LoginResponse: Decodable {
    var accessToken: String
    var accessTokenExpiresAt: Date?
    var refreshToken: String?
    var refreshTokenExpiresAt: Date?
    var sessionId: Int?
    var user: BookOrbitUser?
}

/// `GET books/files/{fileId}/progress`. A file that was never opened comes
/// back with `percentage: 0` and every position field null.
struct ProgressResponse: Decodable {
    var cfi: String?
    var percentage: Double?
    var pageNumber: Int?
    var textUpdatedAt: Date?

    var progress: BookOrbitProgress? {
        let percentage = percentage ?? 0
        if cfi == nil, pageNumber == nil, percentage == 0 { return nil }
        let position = ReadingPosition(
            cfi: cfi,
            fraction: BookOrbitProgress.fraction(fromPercentage: percentage),
            pageNumber: pageNumber
        )
        return BookOrbitProgress(position: position, updatedAt: textUpdatedAt)
    }
}

/// `POST books/files/{fileId}/progress`. A text write replaces the stored
/// position outright, so a missing `cfi` clears the server's CFI.
struct SaveProgressRequest: Encodable {
    var cfi: String?
    var percentage: Double
    var pageNumber: Int?

    init(_ position: ReadingPosition) {
        cfi = position.cfi
        percentage = BookOrbitProgress.percentage(fromFraction: position.fraction)
        pageNumber = position.pageNumber
    }
}

/// BookOrbit's error body: `{statusCode, message, errorCode?}`, where
/// `message` is a string or a list of validation messages.
struct ErrorResponse: Decodable {
    var message: String?
    var errorCode: String?

    private enum CodingKeys: String, CodingKey { case message, errorCode }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = c.lenient(String.self, .message)
            ?? c.lenient([String].self, .message)?.joined(separator: "; ")
        errorCode = c.lenient(String.self, .errorCode)
    }
}

/// An array that drops the elements that don't decode.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !c.isAtEnd {
            if let element = try? c.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode doesn't advance the container; this does.
                _ = try c.decode(Skipped.self)
            }
        }
        self.elements = elements
    }

    /// Decodes from any value, reading nothing.
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

extension KeyedDecodingContainer {
    /// The value, or `nil` if it's missing, null or of an unexpected type.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// A series index sent as a number or as a numeric string.
    func seriesIndex(_ key: Key) -> Double? {
        let value = lenient(Double.self, key) ?? lenient(String.self, key).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return value?.isFinite == true ? value : nil
    }
}
