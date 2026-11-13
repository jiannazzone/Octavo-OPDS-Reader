import Foundation
import OctavoKit
import Synchronization
@testable import Octavo

nonisolated extension LibrarySourceID {
    /// The server in tests that have one.
    static let test = LibrarySourceID(rawValue: "test-server")
}

nonisolated extension SourcedBook {
    /// `book` on the test server.
    static func test(_ book: LibraryBook) -> SourcedBook {
        SourcedBook(source: .test, book: book)
    }
}

nonisolated extension ServerStore {
    /// Saves `server` as the only one.
    func save(_ server: SavedServer) throws {
        try save(SavedServers(servers: [server], chosen: server.id))
    }
}

/// A source's covers: `data`, after `time`, and how many it has handed out.
nonisolated final class CoverSupply: Sendable {
    private let data: Data
    private let time: Duration
    private let count = Mutex(0)

    init(data: Data, time: Duration = .zero) {
        self.data = data
        self.time = time
    }

    var fetches: Int { count.withLock { $0 } }

    func fetch() async throws -> Data {
        count.withLock { $0 += 1 }
        if time > .zero { try await Task.sleep(for: time) }
        return data
    }
}

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
    /// What a download writes, if not a placeholder.
    var downloadData: Data?
    /// Its covers. Without it, it hasn't got any.
    var coverSupply: CoverSupply?

    /// With `finishedMarks`: it keeps a read status too, as BookOrbit does.
    var keepsStatus = false
    /// With `finishedMarks`: it keeps your rating too, as BookOrbit does.
    var keepsRating = false

    var tracksFinished: Bool { finishedMarks != nil }

    func setFinished(_ finished: Bool, for book: LibraryBook) async throws {
        guard let finishedMarks else { return }
        if finishedMarks.refuses { throw LibraryError.notFound }
        finishedMarks.sent.append(finished)
    }

    var tracksReadStatus: Bool { keepsStatus && finishedMarks != nil }

    func setReadStatus(_ status: LibraryReadStatus, for book: LibraryBook) async throws {
        guard let finishedMarks, keepsStatus else { return }
        if finishedMarks.refuses { throw LibraryError.notFound }
        finishedMarks.statuses.append(status)
    }

    var tracksRating: Bool { keepsRating && finishedMarks != nil }

    func setRating(_ rating: Int?, for book: LibraryBook) async throws {
        guard let finishedMarks, keepsRating else { return }
        if finishedMarks.holdsRatings {
            try await withCheckedThrowingContinuation { finishedMarks.hold(rating, $0) }
        } else if finishedMarks.refuses {
            throw LibraryError.notFound
        }
        finishedMarks.ratings.append(rating)
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
        guard let coverSupply else { throw LibraryError.notFound }
        return try await coverSupply.fetch()
    }

    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(0.5)
        if downloadTime > .zero { try await Task.sleep(for: downloadTime) }
        if let downloadError { throw downloadError }
        try (downloadData ?? Data("not really an epub".utf8)).write(to: destination)
        progress(1)
        return destination
    }
}

/// What a stub server was sent for Mark finished.
nonisolated final class FinishedMarks: @unchecked Sendable {
    var sent: [Bool] = []
    var statuses: [LibraryReadStatus] = []
    var ratings: [Int?] = []
    var refuses = false
    /// Ratings wait for `release(_:refusing:)`, to answer them out of order.
    var holdsRatings = false
    private let held = Mutex<[Int?: CheckedContinuation<Void, any Error>]>([:])

    func hold(_ rating: Int?, _ continuation: CheckedContinuation<Void, any Error>) {
        held.withLock { $0[rating] = continuation }
    }

    func isHolding(_ rating: Int?) -> Bool {
        held.withLock { $0[rating] != nil }
    }

    func release(_ rating: Int?, refusing: Bool) {
        let continuation = held.withLock { $0.removeValue(forKey: rating) }
        if refusing {
            continuation?.resume(throwing: LibraryError.notFound)
        } else {
            continuation?.resume()
        }
    }
}

/// `StoredBookFiles` in a temporary directory of its own.
nonisolated struct TemporaryBookFiles {
    let directory: URL
    let store: StoredBookFiles

    init() throws {
        // Downloads and imported books side by side, as in the app.
        let folder = URL.testDirectory.appending(path: "BookFilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        directory = folder.appending(path: "Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = StoredBookFiles(directory: directory, imported: ImportedBooks(directory: folder.appending(path: "Imported", directoryHint: .isDirectory)))
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

nonisolated extension ImportedBooks {
    /// A store of its own, never the app's.
    static func temporary() -> ImportedBooks {
        ImportedBooks(directory: URL.testDirectory.appending(path: "Imported-\(UUID().uuidString)", directoryHint: .isDirectory))
    }
}
