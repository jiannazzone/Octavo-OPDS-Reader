import Foundation
import OctavoKit

/// The books this iPhone has downloaded, or started to, with their details,
/// so Search can find them without the server (decision 21). A file on disk
/// is only a name; this says whose book it is. Whether the file is still
/// there is the opener's to say. One small JSON file, written atomically.
nonisolated struct BooksOnIPhone: Sendable {
    let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "BooksOnIPhone.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
    }

    /// Newest first.
    func books() -> [SourcedBook] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SourcedBook].self, from: data)) ?? []
    }

    /// Puts `book` first, replacing an older record of it.
    func record(_ book: SourcedBook) throws {
        let books = [book] + books().filter { $0.id != book.id }
        try write(books)
    }

    /// Gives `library`'s records to `other` (`RemovedServer`).
    func moveAll(of library: LibrarySourceID, to other: LibrarySourceID) throws {
        let books = books()
        guard books.contains(where: { $0.source == library }) else { return }
        try write(books.map { $0.source == library ? SourcedBook(source: other, book: $0.book) : $0 })
    }

    func remove(_ book: SourcedBook.ID) throws {
        let kept = books().filter { $0.id != book }
        guard kept.count != books().count else { return }
        try write(kept)
    }

    /// The list as it stands, for `ServerStorageMigration`.
    func replace(_ books: [SourcedBook]) throws {
        guard !books.isEmpty || !self.books().isEmpty else { return }
        try write(books)
    }

    private func write(_ books: [SourcedBook]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(books).write(to: fileURL, options: .atomic)
    }
}
