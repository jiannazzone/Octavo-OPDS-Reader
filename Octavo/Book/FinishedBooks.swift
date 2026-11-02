import Foundation

/// The finished marks this iPhone keeps, for books whose server doesn't keep
/// one (OPDS; BookOrbit keeps its own). One small JSON file, written
/// atomically.
nonisolated struct FinishedBooks: Sendable {
    let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "FinishedBooks.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
    }

    func contains(_ book: SourcedBook.ID) -> Bool {
        books().contains(book)
    }

    func set(_ finished: Bool, for book: SourcedBook.ID) throws {
        var books = books()
        guard books.contains(book) != finished else { return }
        if finished { books.insert(book) } else { books.remove(book) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(books).write(to: fileURL, options: .atomic)
    }

    private func books() -> Set<SourcedBook.ID> {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode(Set<SourcedBook.ID>.self, from: data)) ?? []
    }
}
