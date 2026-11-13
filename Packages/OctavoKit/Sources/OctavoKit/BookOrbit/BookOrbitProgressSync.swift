import Foundation
import Synchronization

/// Syncs one BookOrbit file's reading position
/// (`GET`/`POST books/files/{fileId}/progress`).
public struct BookOrbitProgressSync: ProgressSync {
    public let client: BookOrbitClient
    public let fileID: Int
    private let start: Start?

    /// `unstarted`: the book, if its list shows it not started with a
    /// status that starting changes (Unread, Want to read). If the server
    /// still has no place for it, the first push that starts it then sets the
    /// status as BookOrbit's own reader does, which
    /// `books/files/{id}/progress` doesn't (#120, measured on v3.6.0), and
    /// tells `started`.
    public init(
        client: BookOrbitClient, fileID: Int, unstarted bookID: Int? = nil,
        started: @escaping @Sendable (LibraryReadStatus) -> Void = { _ in }
    ) {
        self.client = client
        self.fileID = fileID
        start = bookID.map { Start(bookID: $0, started: started) }
    }

    /// The book whose first push sets its status (`init`), for tests.
    public var unstartedBookID: Int? { start?.bookID }

    public func pull() async throws -> SyncedPosition? {
        guard let progress = try await client.progress(fileID: fileID) else { return nil }
        return SyncedPosition(position: progress.position, updatedAt: progress.updatedAt)
    }

    /// BookOrbit replaces the whole text position on every write, so a
    /// position without a CFI would clear the server's.
    public func push(_ position: ReadingPosition) async throws {
        let starts = position.fraction > 0 && position.fraction < 1
        if let start, starts { await start.check(client, fileID: fileID) }
        try await client.saveProgress(position, fileID: fileID)
        if let start, starts { await start.run(client) }
    }

    /// Setting the status once the book has started. The list's copy may be
    /// old, so the server's place is read before the push (BookOrbit's
    /// reader leaves a hand-set status alone on a book already started) and
    /// the status after it.
    private final class Start: Sendable {
        let bookID: Int
        let started: @Sendable (LibraryReadStatus) -> Void
        private let state = Mutex(State.unchecked)

        private enum State {
            case unchecked, busy
            /// The server had no place: the status is set after the push.
            case unstarted
            case done
        }

        init(bookID: Int, started: @escaping @Sendable (LibraryReadStatus) -> Void) {
            self.bookID = bookID
            self.started = started
        }

        /// Before the push. A check that fails is made again before the
        /// next one.
        func check(_ client: BookOrbitClient, fileID: Int) async {
            guard take(.unchecked) else { return }
            do {
                set(try await client.progress(fileID: fileID) == nil ? .unstarted : .done)
            } catch {
                set(.unchecked)
            }
        }

        /// After the push. One that fails is tried again after the next.
        func run(_ client: BookOrbitClient) async {
            guard take(.unstarted) else { return }
            do {
                if let status = try await client.book(id: bookID).status?.whenStarted {
                    try await client.setReadStatus(status.rawValue, bookID: bookID)
                    started(status)
                }
                set(.done)
            } catch {
                set(.unstarted)
            }
        }

        /// Moves from `expected` to busy, if that's the state.
        private func take(_ expected: State) -> Bool {
            state.withLock { state in
                guard state == expected else { return false }
                state = .busy
                return true
            }
        }

        private func set(_ new: State) {
            state.withLock { $0 = new }
        }
    }
}
