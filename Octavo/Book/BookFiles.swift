import CryptoKit
import Foundation
import OctavoKit

/// Where a book's file lives on the iPhone once it has downloaded
/// (decision 3: books download on first open).
///
/// #14 keeps files in Caches (`CachedBookFiles`): iOS may clear them when
/// space runs low, and the book downloads again on its next open. #10
/// replaces this with permanent storage, the On iPhone list and Remove
/// download.
nonisolated protocol BookFiles: Sendable {
    /// The file on the iPhone, or `nil` if it hasn't downloaded.
    func localFile(for file: LibraryFile) -> URL?

    /// Downloads `file` from `source`, replacing any earlier copy.
    /// Cancelling the calling task cancels the download.
    func download(_ file: LibraryFile, from source: any LibrarySource, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
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

/// Downloads into `Caches/Books/`, one file per book file.
///
/// Keyed by the file's ID alone: v1 has one server (decision 1). A second
/// server needs the server in the key (#10).
nonisolated struct CachedBookFiles: BookFiles {
    let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "Books", directoryHint: .isDirectory)) {
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await source.download(file, to: destination, progress: progress)
    }
}

nonisolated enum BookFilesError: Error, Equatable {
    /// The book has no file in a format the reader opens.
    case unreadableFormat
}
