import Foundation
import OctavoKit
@testable import Octavo

/// A source for the cover page and opener tests: one book, details, and a
/// download that writes a small file, waits, or fails as asked.
nonisolated struct StubLibrarySource: LibrarySource {
    var files = [LibraryFile(id: LibraryFileID(rawValue: "file-1"), format: "epub", sizeBytes: 1_234_567, isPrimary: true)]
    var description: String? = "<p>Call me <i>Ishmael</i>.</p>"
    var downloadError: (any Error & Sendable)?
    /// How long a download takes; a cancelled one throws.
    var downloadTime: Duration = .zero

    func root() async throws -> LibraryRoot {
        LibraryRoot(title: "Stub server", chips: [], search: .unavailable)
    }

    func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        LibraryFeed()
    }

    func search(_ query: String) async throws -> LibrarySearchResults {
        LibrarySearchResults(query: query)
    }

    func details(for book: LibraryBook) async throws -> LibraryBookDetails {
        var full = book
        full.files = files
        return LibraryBookDetails(
            book: full,
            description: description,
            addedAt: Date(timeIntervalSince1970: 1_793_404_800),
            series: [LibrarySeriesPosition(name: "Sea Stories", position: 3)],
            collections: [
                LibraryEntry(kind: .collection, title: "Classics", link: LibraryLink(rawValue: "c/1")),
                LibraryEntry(kind: .collection, title: "Spike", link: LibraryLink(rawValue: "c/2")),
            ]
        )
    }

    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data {
        throw LibraryError.notFound
    }

    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(0.5)
        if downloadTime > .zero { try await Task.sleep(for: downloadTime) }
        if let downloadError { throw downloadError }
        try Data("not really an epub".utf8).write(to: destination)
        progress(1)
        return destination
    }
}

/// `CachedBookFiles` in a temporary directory of its own.
nonisolated struct TemporaryBookFiles {
    let directory: URL
    let store: CachedBookFiles

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "BookFilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = CachedBookFiles(directory: directory)
    }
}

/// Waits up to `timeout` for `condition`, checking every few milliseconds.
@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
