import Foundation

/// A local book file the reader can open.
nonisolated struct ReaderBook: Identifiable, Hashable, Sendable {
    /// Stable key for the saved position. For now the file name; a library
    /// source will supply its own ID later.
    let id: String
    let fileURL: URL

    init(fileURL: URL, id: String? = nil) {
        self.fileURL = fileURL
        self.id = id ?? fileURL.lastPathComponent
    }

    var fileName: String { fileURL.lastPathComponent }

    /// Formats foliate-js opens (PDF goes to PDFKit, not here).
    static let supportedExtensions: Set<String> = ["epub", "mobi", "azw", "azw3", "fb2", "fbz", "cbz"]
}
