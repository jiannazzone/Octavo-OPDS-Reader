import CryptoKit
import Foundation
import OctavoKit

/// Where a book's file lives on the iPhone once it has downloaded. A
/// download stays until it's removed (`docs/design/direction.md`, Getting
/// books onto the iPhone).
nonisolated protocol BookFiles: Sendable {
    /// `library`'s file on the iPhone, or `nil` if it hasn't downloaded.
    func localFile(for file: LibraryFile, in library: LibrarySourceID) -> URL?

    /// Downloads `file` from `source`, replacing any earlier copy.
    /// Cancelling the calling task cancels the download.
    func download(
        _ file: LibraryFile, in library: LibrarySourceID, from source: any LibrarySource, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    /// Deletes the downloaded copy, if there is one.
    func remove(_ file: LibraryFile, in library: LibrarySourceID) throws

    /// Deletes every downloaded book but `keeping`'s storage keys (Storage's
    /// Remove all downloads keeps none).
    func removeAll(keeping keys: Set<String>) throws

    /// Deletes every download of `library`'s, whichever book it was for.
    func removeAll(of library: LibrarySourceID)

    /// Gives `library`'s downloads to `other` (`RemovedServer`).
    func moveAll(of library: LibrarySourceID, to other: LibrarySourceID)
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
    /// looks like (an OPDS ID is a URL).
    var storageKey: String {
        let digest = SHA256.hash(data: Data(id.rawValue.utf8))
        return "book-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The name of `library`'s copy of the file, its place and its bookmarks:
    /// BookOrbit numbers its files from 1 on every server, so another server's
    /// file 17 is another book. Starts with the server's own ID, which is
    /// ours and safe in a path, so all of a server's can be found by it.
    /// Imported books belong to no server and keep the plain name.
    func storageKey(in library: LibrarySourceID) -> String {
        library == .files ? storageKey : "\(StoredBookKeys.prefix(of: library))\(storageKey)"
    }
}

nonisolated extension SourcedBook {
    /// `LibraryFile.storageKey(in:)` for the file the reader opens.
    var storageKey: String? {
        book.readableFile?.storageKey(in: source)
    }
}

/// How keys start with their server (`LibraryFile.storageKey(in:)`), for the
/// stores that keep per-book files in one folder.
nonisolated enum StoredBookKeys {
    static func prefix(of library: LibrarySourceID) -> String {
        "\(library.rawValue)."
    }

    /// Deletes every file of `library`'s directly in `directory`.
    static func removeFiles(of library: LibrarySourceID, in directory: URL) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix(of: library)) {
            try? manager.removeItem(at: directory.appending(path: name, directoryHint: .notDirectory))
        }
    }

    /// Gives `library`'s files in `directory` to `other`: the same server
    /// added again finds what it left (`RemovedServer`). A file `other`
    /// already has stays as it is.
    static func moveFiles(of library: LibrarySourceID, to other: LibrarySourceID, in directory: URL) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix(of: library)) {
            let moved = prefix(of: other) + name.dropFirst(prefix(of: library).count)
            let target = directory.appending(path: moved, directoryHint: .notDirectory)
            guard !manager.fileExists(atPath: target.path) else { continue }
            try? manager.moveItem(at: directory.appending(path: name, directoryHint: .notDirectory), to: target)
        }
    }
}

/// Downloads into `Application Support/Books/`, one file per book file:
/// iOS doesn't clear it when space runs low, and it stays out of the
/// iPhone's backup, since the server has every book.
///
/// Books imported from Files (and the sample book) are on the iPhone too,
/// in `ImportedBooks`' folder: they open from there, but only
/// `ImportedBooks` removes them, never Remove download or Remove all
/// downloads.
nonisolated struct StoredBookFiles: BookFiles {
    let directory: URL
    let imported: ImportedBooks

    init(
        directory: URL = URL.applicationSupportDirectory.appending(path: "Books", directoryHint: .isDirectory),
        imported: ImportedBooks = ImportedBooks()
    ) {
        self.directory = directory
        self.imported = imported
    }

    func url(for file: LibraryFile, in library: LibrarySourceID) -> URL? {
        guard let ext = file.readableExtension else { return nil }
        return directory.appending(path: "\(file.storageKey(in: library)).\(ext)", directoryHint: .notDirectory)
    }

    func localFile(for file: LibraryFile, in library: LibrarySourceID) -> URL? {
        library == .files ? imported.localFile(for: file) : downloadedFile(for: file, in: library)
    }

    private func downloadedFile(for file: LibraryFile, in library: LibrarySourceID) -> URL? {
        guard library != .files, let url = url(for: file, in: library), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func download(
        _ file: LibraryFile, in library: LibrarySourceID, from source: any LibrarySource, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let destination = url(for: file, in: library) else { throw BookFilesError.unreadableFormat }
        try makeDirectory()
        return try await source.download(file, to: destination, progress: progress)
    }

    func remove(_ file: LibraryFile, in library: LibrarySourceID) throws {
        guard let url = downloadedFile(for: file, in: library) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func removeAll(keeping keys: Set<String>) throws {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !keys.contains((name as NSString).deletingPathExtension) {
            try manager.removeItem(at: directory.appending(path: name))
        }
    }

    func removeAll(of library: LibrarySourceID) {
        StoredBookKeys.removeFiles(of: library, in: directory)
    }

    func moveAll(of library: LibrarySourceID, to other: LibrarySourceID) {
        StoredBookKeys.moveFiles(of: library, to: other, in: directory)
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
