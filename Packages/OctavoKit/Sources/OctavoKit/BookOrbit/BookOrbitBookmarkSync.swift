import Foundation

/// Syncs one BookOrbit book's bookmarks (`books/{bookId}/bookmarks`), so
/// they show in its web reader and on other devices (decision 18).
public struct BookOrbitBookmarkSync: BookmarkSync {
    public let client: BookOrbitClient
    public let bookID: Int
    /// The file read, recorded with each new bookmark.
    public let fileID: Int?

    public init(client: BookOrbitClient, bookID: Int, fileID: Int?) {
        self.client = client
        self.bookID = bookID
        self.fileID = fileID
    }

    public func bookmarks() async throws -> [SyncedBookmark] {
        try await client.bookmarks(bookID: bookID).map(Self.synced)
    }

    public func add(cfi: String, title: String) async throws -> SyncedBookmark {
        Self.synced(try await client.addBookmark(cfi: cfi, title: title, bookID: bookID, fileID: fileID))
    }

    public func remove(id: String) async throws {
        guard let id = Int(id) else { return }
        try await client.deleteBookmark(id: id, bookID: bookID)
    }

    private static func synced(_ bookmark: BookOrbitBookmark) -> SyncedBookmark {
        SyncedBookmark(id: String(bookmark.id), cfi: bookmark.cfi, title: bookmark.title, createdAt: bookmark.createdAt)
    }
}
