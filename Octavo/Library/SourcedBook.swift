import Foundation
import OctavoKit

/// Which library something came from: the connected server, or the books
/// imported from Files. Opaque, like the IDs a `LibrarySource` hands out.
///
/// A server's ID is a UUID made when it's added, so records it leaves behind
/// (recent books, later downloads) never point at the books of a server that
/// replaced it.
nonisolated struct LibrarySourceID: RawRepresentable, Hashable, Codable, Sendable {
    var rawValue: String

    /// Books imported from Files.
    static let files = LibrarySourceID(rawValue: "files")
}

/// A book and the library it came from: what a cover page, the reader and
/// the iPhone's own records carry. Only that library can fetch its cover or
/// file (`LibraryModel.source(for:)`).
nonisolated struct SourcedBook: Hashable, Codable, Sendable, Identifiable {
    var source: LibrarySourceID
    var book: LibraryBook

    struct ID: Hashable, Sendable {
        var source: LibrarySourceID
        var book: LibraryBookID
    }

    var id: ID { ID(source: source, book: book.id) }
}
