import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// A source for the cover page and opener tests: one book, details, and a
/// download that writes a small file, waits, or fails as asked.
nonisolated struct StubLibrarySource: LibrarySource {
    var files = [LibraryFile(id: LibraryFileID(rawValue: "file-1"), format: "epub", sizeBytes: 1_234_567, isPrimary: true)]
    var description: String? = "<p>Call me <i>Ishmael</i>.</p>"
    var downloadError: (any Error & Sendable)?
    /// How long a download takes; a cancelled one throws.
    var downloadTime: Duration = .zero
    /// Set for a server that keeps the finished mark, as BookOrbit does.
    var finishedMarks: FinishedMarks?

    var tracksFinished: Bool { finishedMarks != nil }

    func setFinished(_ finished: Bool, for book: LibraryBook) async throws {
        guard let finishedMarks else { return }
        if finishedMarks.refuses { throw LibraryError.notFound }
        finishedMarks.sent.append(finished)
    }

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

/// What a stub server was sent for Mark finished.
nonisolated final class FinishedMarks: @unchecked Sendable {
    var sent: [Bool] = []
    var refuses = false
}

/// Gives each test case a temporary folder of its own, `URL.testDirectory`,
/// and removes it when the case ends, so test files don't pile up in the
/// app's `tmp`. Every suite that writes files takes it: `@Suite(.temporaryFiles)`.
nonisolated struct TemporaryFiles: SuiteTrait, TestTrait, TestScoping {
    @TaskLocal static var directory: URL?

    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        let directory = URL.temporaryDirectory.appending(path: "OctavoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.$directory.withValue(directory) { try await function() }
    }
}

extension Trait where Self == TemporaryFiles {
    static var temporaryFiles: Self { TemporaryFiles() }
}

extension URL {
    /// The running test case's temporary folder, removed when it ends.
    nonisolated static var testDirectory: URL {
        if let directory = TemporaryFiles.directory { return directory }
        Issue.record("This suite writes files: give it @Suite(.temporaryFiles), or they stay in tmp.")
        return .temporaryDirectory
    }
}

/// `StoredBookFiles` in a temporary directory of its own.
nonisolated struct TemporaryBookFiles {
    let directory: URL
    let store: StoredBookFiles

    init() throws {
        directory = URL.testDirectory.appending(path: "BookFilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = StoredBookFiles(directory: directory)
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
