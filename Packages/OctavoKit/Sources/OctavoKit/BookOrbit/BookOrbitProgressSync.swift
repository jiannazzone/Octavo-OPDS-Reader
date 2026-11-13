import Foundation
import Synchronization

/// Syncs one BookOrbit file's reading position
/// (`GET`/`POST books/files/{fileId}/progress`).
public struct BookOrbitProgressSync: ProgressSync {
    public let client: BookOrbitClient
    public let fileID: Int
    private let start: Start?

    /// `unstarted`: the book, if its list shows it not started with a
    /// status that starting changes (Unread, Want to read). The first push
    /// that starts it then sets the status as BookOrbit's own reader does,
    /// which `books/files/{id}/progress` doesn't (#120, measured on v3.6.0),
    /// and tells `started`.
    public init(
        client: BookOrbitClient, fileID: Int, unstarted bookID: Int? = nil,
        started: @escaping @Sendable (LibraryReadStatus) -> Void = { _ in }
    ) {
        self.client = client
        self.fileID = fileID
        start = bookID.map { Start(bookID: $0, started: started) }
    }

    public func pull() async throws -> SyncedPosition? {
        guard let progress = try await client.progress(fileID: fileID) else { return nil }
        return SyncedPosition(position: progress.position, updatedAt: progress.updatedAt)
    }

    /// BookOrbit replaces the whole text position on every write, so a
    /// position without a CFI would clear the server's.
    public func push(_ position: ReadingPosition) async throws {
        try await client.saveProgress(position, fileID: fileID)
        if let start, position.fraction > 0, position.fraction < 1 { await start.run(client) }
    }

    /// Setting the status once the book has started. The status is read
    /// again first, since the list's may be old.
    private final class Start: Sendable {
        let bookID: Int
        let started: @Sendable (LibraryReadStatus) -> Void
        private let claimed = Mutex(false)

        init(bookID: Int, started: @escaping @Sendable (LibraryReadStatus) -> Void) {
            self.bookID = bookID
            self.started = started
        }

        func run(_ client: BookOrbitClient) async {
            let first = claimed.withLock { claimed in
                defer { claimed = true }
                return !claimed
            }
            guard first else { return }
            do {
                guard let status = try await client.book(id: bookID).status?.whenStarted else { return }
                try await client.setReadStatus(status.rawValue, bookID: bookID)
                started(status)
            } catch {
                // Tried again with the next push.
                claimed.withLock { $0 = false }
            }
        }
    }
}
