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

/// A page of a paged list. `page` is 0-based.
public struct BookOrbitPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public var items: [Item]
    public var total: Int?
    public var page: Int?
    public var size: Int?
}

extension BookOrbitPage: Equatable where Item: Equatable {}
extension BookOrbitPage: Hashable where Item: Hashable {}

/// A book, from a list (`collections/{id}/books`) or from `books/{id}`.
/// The detail response fills more of the optional fields.
public struct BookOrbitBook: Decodable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var libraryID: Int?
    public var title: String
    public var subtitle: String?
    public var authors: [String]
    public var files: [BookOrbitFile]
    public var seriesName: String?
    public var seriesIndex: Double?
    public var language: String?
    public var publisher: String?
    public var description: String?
    public var hasCover: Bool?
    public var coverVersion: String?
    /// Progress through the book, 0...1. Lists only; BookOrbit sends 0–100.
    public var readingFraction: Double?

    /// The file BookOrbit marks primary, else the first one.
    public var primaryFile: BookOrbitFile? {
        files.first { $0.role == "primary" } ?? files.first
    }

    private enum CodingKeys: String, CodingKey {
        case id, libraryId, title, subtitle, authors, files, seriesName, seriesIndex
        case language, publisher, description, hasCover, coverVersion, readingProgress
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        libraryID = c.lenient(Int.self, .libraryId)
        subtitle = c.lenient(String.self, .subtitle)
        // Lists send author names; the detail sends {id, name, sortName}.
        authors = c.lenient([AuthorName].self, .authors)?.map(\.name) ?? []
        files = c.lenient([BookOrbitFile].self, .files) ?? []
        seriesName = c.lenient(String.self, .seriesName)
        seriesIndex = c.lenient(Double.self, .seriesIndex)
        language = c.lenient(String.self, .language)
        publisher = c.lenient(String.self, .publisher)
        description = c.lenient(String.self, .description)
        hasCover = c.lenient(Bool.self, .hasCover)
        coverVersion = c.lenient(String.self, .coverVersion)
        readingFraction = c.lenient(Double.self, .readingProgress).map(BookOrbitProgress.fraction(fromPercentage:))
    }
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

private struct AuthorName: Decodable {
    var name: String

    private enum CodingKeys: String, CodingKey { case name }

    init(from decoder: any Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.name = name
        } else {
            name = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .name)
        }
    }
}

extension KeyedDecodingContainer {
    /// The value, or `nil` if it's missing, null or of an unexpected type.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
