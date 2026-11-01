import Foundation

/// A reading position as a sync backend stores it.
public struct SyncedPosition: Hashable, Sendable {
    public var position: ReadingPosition
    /// When the backend last saw the position move, on the backend's clock.
    /// `nil` if the backend doesn't say.
    public var updatedAt: Date?

    public init(position: ReadingPosition, updatedAt: Date? = nil) {
        self.position = position
        self.updatedAt = updatedAt
    }
}

/// Where progress for one book goes: pull the backend's position when the book
/// opens, push the reader's position as it moves.
///
/// One instance per book. Where books come from (`LibrarySource`) is a
/// separate concern, so any library can pair with any backend.
public protocol ProgressSync: Sendable {
    /// The backend's position, or `nil` if it has none for this book.
    func pull() async throws -> SyncedPosition?
    func push(_ position: ReadingPosition) async throws
}

/// The reader's own record of a book's position, kept on the device.
public struct LocalReadingProgress: Codable, Hashable, Sendable {
    public var position: ReadingPosition
    /// When the reader last moved, on the device's clock.
    public var modifiedAt: Date
    /// The position changed since the last successful push (for example, it
    /// was read offline).
    public var needsPush: Bool
    /// The chapter the position is in, as the book's contents name it, for
    /// showing the place without opening the book. Never synced.
    public var chapter: String?

    public init(position: ReadingPosition, modifiedAt: Date, needsPush: Bool, chapter: String? = nil) {
        self.position = position
        self.modifiedAt = modifiedAt
        self.needsPush = needsPush
        self.chapter = chapter
    }
}

/// Picks the position a book opens at, from the local record and the
/// backend's position.
///
/// The rule:
/// 1. The backend has a CFI and the device has nothing unpushed: open at the
///    backend's position. Every move is pushed, so the backend is at least as
///    new as the device, and newer if another reader moved it since.
/// 2. Both moved (the device has an unpushed position and the backend has a
///    CFI): the later timestamp wins. The backend wins ties and positions
///    without a timestamp. This is the only case that compares clocks.
/// 3. The backend has no CFI (never opened, or a percentage-only writer such
///    as kosync): open at the local position, else at the backend's fraction,
///    else at the start.
public enum OpeningPosition: Equatable, Sendable {
    case remote(ReadingPosition)
    case local(ReadingPosition)
    case start

    public static func choose(local: LocalReadingProgress?, remote: SyncedPosition?) -> OpeningPosition {
        if let remote, remote.position.cfi != nil {
            guard let local, local.needsPush else { return .remote(remote.position) }
            if let remoteDate = remote.updatedAt, local.modifiedAt > remoteDate { return .local(local.position) }
            return .remote(remote.position)
        }
        if let local { return .local(local.position) }
        if let remote, remote.position.fraction > 0 { return .remote(remote.position) }
        return .start
    }

    public var position: ReadingPosition? {
        switch self {
        case .remote(let position), .local(let position): position
        case .start: nil
        }
    }
}
