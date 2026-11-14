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

    struct ID: Hashable, Codable, Sendable {
        var source: LibrarySourceID
        var book: LibraryBookID
    }

    var id: ID { ID(source: source, book: book.id) }

    /// This book with the mark in `marks`, if there's one for it.
    func withMarks(from marks: [ID: ReadMark]) -> SourcedBook {
        guard let mark = marks[id] else { return self }
        var marked = self
        marked.book.isFinished = mark.finished
        marked.book.readStatus = mark.status
        return marked
    }
}

/// A server's word on a book: finished, and its read status where the server
/// keeps one (BookOrbit's, #120).
nonisolated struct ReadMark: Hashable, Sendable {
    var finished: Bool
    var status: LibraryReadStatus?

    init(finished: Bool, status: LibraryReadStatus? = nil) {
        self.finished = finished
        self.status = status
    }

    /// The status, which says whether it's finished.
    init(_ status: LibraryReadStatus) {
        self.init(finished: status == .read, status: status)
    }
}

extension LibraryBook {
    /// What the server says, if it keeps a finished mark.
    nonisolated var readMark: ReadMark? {
        isFinished.map { ReadMark(finished: $0, status: readStatus) }
    }
}
