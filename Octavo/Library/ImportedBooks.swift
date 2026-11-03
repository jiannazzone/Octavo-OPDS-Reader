import CryptoKit
import Foundation
import OctavoKit

/// The books imported from Files, and the bundled sample book once it has
/// been read: each one's file, details and cover in
/// `Application Support/Imported/` (`docs/design/direction.md`, Other ways
/// in). Unlike downloads, this folder is in the iPhone's backup, since no
/// server has these books.
///
/// - `Books.json`: every book's details, newest first.
/// - `<storageKey>.<format>`: its file, named as `StoredBookFiles` names a
///   download, so the reader keys its place, bookmarks and finished mark
///   the same way.
/// - `<storageKey>.cover`: its cover image, if it has one.
///
/// Files on their way in wait in a folder under `tmp/`, out of the backup.
nonisolated struct ImportedBooks: Sendable {
    let directory: URL

    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "Imported", directoryHint: .isDirectory)

    /// Newest first. Empty if the list can't be read, for showing; changes
    /// go through `load()`, which refuses to write over it.
    func all() -> [LibraryBookDetails] {
        (try? load()) ?? []
    }

    /// The list, `[]` only when there's none yet. A list that's there but
    /// can't be read throws, so a write can't replace every book with one.
    private func load() throws -> [LibraryBookDetails] {
        guard FileManager.default.fileExists(atPath: catalogURL.path) else { return [] }
        return try JSONDecoder().decode([LibraryBookDetails].self, from: Data(contentsOf: catalogURL))
    }

    func details(for id: LibraryBookID) -> LibraryBookDetails? {
        all().first { $0.book.id == id }
    }

    /// Where `file` lives once imported, whether or not it's there.
    func url(for file: LibraryFile) -> URL? {
        guard let ext = file.readableExtension else { return nil }
        return directory.appending(path: "\(file.storageKey).\(ext)", directoryHint: .notDirectory)
    }

    func localFile(for file: LibraryFile) -> URL? {
        guard let url = url(for: file), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func coverURL(for id: LibraryBookID) -> URL {
        let key = LibraryFile(id: LibraryFileID(rawValue: id.rawValue)).storageKey
        return directory.appending(path: "\(key).cover", directoryHint: .notDirectory)
    }

    /// Keeps `details`' book with the file at `file` (moved in) and its
    /// cover, first in the list. A book already here just moves first.
    func add(_ details: LibraryBookDetails, file: URL, cover: Data?) throws {
        guard let bookFile = details.book.primaryFile, let destination = url(for: bookFile) else {
            throw BookFilesError.unreadableFormat
        }
        try makeDirectory()
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: file, to: destination)
        if let cover {
            try cover.write(to: coverURL(for: details.book.id), options: .atomic)
        }
        try write([details] + load().filter { $0.book.id != details.book.id })
    }

    /// Puts a book already here first again (imported once more).
    func moveFirst(_ id: LibraryBookID) throws {
        let books = try load()
        guard let book = books.first(where: { $0.book.id == id }) else { return }
        try write([book] + books.filter { $0.book.id != id })
    }

    /// Deletes the book's file, cover and record. Its place and bookmarks
    /// are the reader's, and stay: the same file imported again has the
    /// same ID, and opens where it was.
    func remove(_ id: LibraryBookID) throws {
        let books = try load()
        guard let book = books.first(where: { $0.book.id == id }) else { return }
        let manager = FileManager.default
        if let file = book.book.primaryFile, let url = localFile(for: file) {
            try manager.removeItem(at: url)
        }
        try? manager.removeItem(at: coverURL(for: id))
        try write(books.filter { $0.book.id != id })
    }

    /// A folder for files on their way in, in `tmp/`, so a copy cut short
    /// never reaches the backup. One per store.
    func incomingDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: incomingURL, withIntermediateDirectories: true)
        return incomingURL
    }

    /// At launch: whatever an import cut short left behind.
    func clearIncoming() {
        try? FileManager.default.removeItem(at: incomingURL)
    }

    private var incomingURL: URL {
        let digest = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
        let name = "ImportIncoming-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return URL.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    private var catalogURL: URL {
        directory.appending(path: "Books.json", directoryHint: .notDirectory)
    }

    private func write(_ books: [LibraryBookDetails]) throws {
        try makeDirectory()
        try JSONEncoder().encode(books).write(to: catalogURL, options: .atomic)
    }

    private func makeDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

nonisolated extension LibraryBookID {
    /// The sample book's (`SampleBook`).
    static let sample = LibraryBookID(rawValue: "sample-pride-and-prejudice")

    /// An imported book's, from its bytes: the same file imported twice is
    /// one book, and keeps its place.
    static func imported(sha256 digest: SHA256.Digest) -> LibraryBookID {
        LibraryBookID(rawValue: "import-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined())
    }
}

nonisolated extension SourcedBook {
    /// The bundled sample book, which isn't something you added.
    var isSample: Bool { source == .files && book.id == .sample }
}

/// The books in `ImportedBooks` as a library, so their screens, covers and
/// the reader work as they do for a server's. Nothing syncs: places,
/// bookmarks and finished marks stay on the iPhone.
nonisolated struct ImportedBooksSource: LibrarySource {
    let store: ImportedBooks

    /// The details' From row.
    static let title = "Files"

    func root() async throws -> LibraryRoot {
        LibraryRoot(title: Self.title, chips: [], search: .books)
    }

    func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        let books = store.all().map(\.book)
        return LibraryFeed(books: books, total: books.count)
    }

    func search(_ query: String) async throws -> LibrarySearchResults {
        let books = store.all().map(\.book).filter { SearchModel.matches($0, query) }
        return LibrarySearchResults(query: query, books: LibraryFeed(books: books, total: books.count))
    }

    func details(for book: LibraryBook) async throws -> LibraryBookDetails {
        guard let details = store.details(for: book.id) else { throw LibraryError.notFound }
        return details
    }

    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data {
        try Data(contentsOf: store.coverURL(for: LibraryBookID(rawValue: cover.rawValue)))
    }

    /// The file is already here; a copy, if anything asks for one.
    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let url = store.localFile(for: file) else { throw LibraryError.notFound }
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.copyItem(at: url, to: destination)
        progress(1)
        return destination
    }
}
