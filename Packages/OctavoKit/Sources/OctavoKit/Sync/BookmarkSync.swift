import Foundation

/// A bookmark as a sync backend keeps it.
public struct SyncedBookmark: Hashable, Sendable {
    public var id: String
    public var cfi: String
    public var title: String?
    public var createdAt: Date?

    public init(id: String, cfi: String, title: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.cfi = cfi
        self.title = title
        self.createdAt = createdAt
    }
}

/// Where one book's bookmarks sync (decision 18): BookOrbit's own, for its
/// books. Books from anywhere else keep their bookmarks on the device.
public protocol BookmarkSync: Sendable {
    func bookmarks() async throws -> [SyncedBookmark]
    func add(cfi: String, title: String) async throws -> SyncedBookmark
    /// Removing one that's already gone succeeds.
    func remove(id: String) async throws
}

/// The device's record of a bookmark, synced or not.
public struct LocalBookmark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// The point where the page starts, as positions are kept.
    public var cfi: String
    public var createdAt: Date
    /// The backend's ID, once the backend has it.
    public var remoteID: String?
    /// Removed here while the backend still has it; the removal is retried.
    public var isRemoved: Bool
    /// What the list shows, worked out by the reader from the book. Never
    /// synced.
    public var chapter: String?
    public var excerpt: String?
    /// Where it falls in the book, 0...1.
    public var fraction: Double?

    public init(
        id: UUID = UUID(), cfi: String, createdAt: Date = .now, remoteID: String? = nil, isRemoved: Bool = false,
        chapter: String? = nil, excerpt: String? = nil, fraction: Double? = nil
    ) {
        self.id = id
        self.cfi = cfi
        self.createdAt = createdAt
        self.remoteID = remoteID
        self.isRemoved = isRemoved
        self.chapter = chapter
        self.excerpt = excerpt
        self.fraction = fraction
    }

    /// Placed, so the list can show it.
    public var isDescribed: Bool { fraction != nil }
}

/// Brings the device's bookmarks and the backend's together.
///
/// - The backend's list is the truth for bookmarks it has seen: one it no
///   longer has was removed elsewhere, and one the device doesn't know was
///   added elsewhere.
/// - Bookmarks made here that the backend doesn't have yet are added, unless
///   the backend has one at the very same CFI, which means an earlier add
///   got there but its answer didn't come back.
/// - Bookmarks removed here are removed from the backend, then forgotten.
public enum BookmarkReconciliation {
    public struct Result: Equatable, Sendable {
        public var bookmarks: [LocalBookmark]
        /// Made here, still to add to the backend.
        public var toAdd: [LocalBookmark.ID]
        /// The backend's IDs of bookmarks removed here.
        public var toRemove: [String]
    }

    public static func reconcile(local: [LocalBookmark], remote: [SyncedBookmark]) -> Result {
        var unmatched = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var bookmarks: [LocalBookmark] = []
        var toAdd: [LocalBookmark.ID] = []
        var toRemove: [String] = []

        for var bookmark in local {
            if let remoteID = bookmark.remoteID {
                guard let synced = unmatched.removeValue(forKey: remoteID) else { continue }
                if bookmark.isRemoved {
                    toRemove.append(remoteID)
                    bookmarks.append(bookmark)
                    continue
                }
                if synced.cfi != bookmark.cfi {
                    bookmark = LocalBookmark(id: bookmark.id, cfi: synced.cfi, createdAt: bookmark.createdAt, remoteID: remoteID)
                }
                bookmarks.append(bookmark)
            } else if !bookmark.isRemoved {
                if let landed = unmatched.values.filter({ $0.cfi == bookmark.cfi }).min(by: { $0.id < $1.id }) {
                    unmatched[landed.id] = nil
                    bookmark.remoteID = landed.id
                } else {
                    toAdd.append(bookmark.id)
                }
                bookmarks.append(bookmark)
            }
        }
        for synced in remote where unmatched[synced.id] != nil {
            bookmarks.append(LocalBookmark(cfi: synced.cfi, createdAt: synced.createdAt ?? .now, remoteID: synced.id, chapter: synced.title))
        }
        return Result(bookmarks: bookmarks, toAdd: toAdd, toRemove: toRemove)
    }
}
