import CryptoKit
import Foundation
import OctavoKit

/// Where a book's file lives on the iPhone once it has downloaded. A
/// download stays until it's removed (`docs/design/direction.md`, Getting
/// books onto the iPhone).
nonisolated protocol BookFiles: Sendable {
    /// The file on the iPhone, or `nil` if it hasn't downloaded.
    func localFile(for file: LibraryFile) -> URL?

    /// Downloads `file` from `source`, replacing any earlier copy.
    /// Cancelling the calling task cancels the download.
    func download(_ file: LibraryFile, from source: any LibrarySource, progress: @escaping @Sendable (Double) -> Void) async throws -> URL

    /// Deletes the downloaded copy, if there is one.
    func remove(_ file: LibraryFile) throws

    /// Deletes every downloaded book (Storage's Remove all downloads).
    func removeAll() throws
}

nonisolated extension LibraryBook {
    /// The file the reader opens: the server's primary file if the reader
    /// reads its format, else the first file it reads. `nil` if it reads
    /// none of them, or the book lists no files.
    var readableFile: LibraryFile? {
        let readable = files.filter { $0.readableExtension != nil }
        return readable.first(where: \.isPrimary) ?? readable.first
    }
}

nonisolated extension LibraryFile {
    /// The file's extension on disk, from the server's format. Only formats
    /// the reader opens reach a path.
    var readableExtension: String? {
        guard let format = format?.lowercased(), ReaderBook.supportedExtensions.contains(format) else { return nil }
        return format
    }

    /// A stable name for the file, safe in a path whatever the source's ID
    /// looks like (an OPDS ID is a URL). Also the reader's key for the
    /// saved position.
    var storageKey: String {
        let digest = SHA256.hash(data: Data(id.rawValue.utf8))
        return "book-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// Downloads into `Application Support/Books/`, one file per book file:
/// iOS doesn't clear it when space runs low, and it stays out of the
/// iPhone's backup, since the server has every book.
///
/// Keyed by the file's ID alone: v1 has one server (decision 1). A second
/// server needs the server in the key.
nonisolated struct StoredBookFiles: BookFiles {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Books", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func url(for file: LibraryFile) -> URL? {
        guard let ext = file.readableExtension else { return nil }
        return directory.appending(path: "\(file.storageKey).\(ext)", directoryHint: .notDirectory)
    }

    func localFile(for file: LibraryFile) -> URL? {
        guard let url = url(for: file), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func download(_ file: LibraryFile, from source: any LibrarySource, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let destination = url(for: file) else { throw BookFilesError.unreadableFormat }
        try makeDirectory()
        return try await source.download(file, to: destination, progress: progress)
    }

    func remove(_ file: LibraryFile) throws {
        guard let url = localFile(for: file) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func removeAll() throws {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names {
            try manager.removeItem(at: directory.appending(path: name))
        }
    }

    /// The app's store, with any books from before it moved in.
    static func moved() -> StoredBookFiles {
        let files = StoredBookFiles()
        files.moveBooks()
        return files
    }

    /// Moves books downloaded before this store existed (#14 kept them in
    /// `Caches/Books/`, which iOS may clear) into it. Leaves a book that's
    /// already here alone.
    func moveBooks(from old: URL = URL.cachesDirectory.appending(path: "Books", directoryHint: .isDirectory)) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: old.path), !names.isEmpty, (try? makeDirectory()) != nil else { return }
        for name in names where !manager.fileExists(atPath: directory.appending(path: name).path) {
            try? manager.moveItem(at: old.appending(path: name), to: directory.appending(path: name))
        }
        try? manager.removeItem(at: old)
    }

    private func makeDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }
}

nonisolated enum BookFilesError: Error, Equatable {
    /// The book has no file in a format the reader opens.
    case unreadableFormat
}
