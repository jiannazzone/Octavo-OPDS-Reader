import Foundation

/// A reading position as a sync backend stores it.
public struct SyncedPosition: Hashable, Sendable {
    public var position: ReadingPosition
    /// When the backend last saw the position move, on the backend's clock.
    /// `nil` if the backend doesn't say.
    public var updatedAt: Date?
    /// How far it's trusted (`OpeningPosition.choose`).
    public var origin: Origin

    public init(position: ReadingPosition, updatedAt: Date? = nil, origin: Origin = .exact) {
        self.position = position
        self.updatedAt = updatedAt
        self.origin = origin
    }

    public enum Origin: Hashable, Sendable {
        /// A foliate reader's exact place, as BookOrbit's: at least as new
        /// as the iPhone's unless the iPhone has a place it hasn't sent.
        case exact
        /// Another reader's place in its own form, as KOReader's
        /// (`docs/notes/koreader-sync.md`). It moves you only forward, and
        /// only once it has changed since this iPhone last saw it.
        case elsewhere(Change)
    }

    /// Since this iPhone last saw the backend's place.
    public enum Change: Hashable, Sendable {
        /// It hasn't seen one before.
        case first
        /// It's what the backend last said: this iPhone's own place read
        /// back, or one it opened at.
        case unchanged
        /// Another reader moved it.
        case moved
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
    /// The backend's position as it is now, never a recent pull kept for
    /// reuse: an open reader asking whether another reader moved on.
    func pullLatest() async throws -> SyncedPosition?
    func push(_ position: ReadingPosition) async throws
    /// The backend needs KOReader's place in every position it's sent
    /// (`ReadingPosition.xpointer`), so the reader asks the bridge for it.
    var wantsXPointers: Bool { get }
    /// The reader opened at `remote`, or went to it: it's this iPhone's
    /// place now, so it isn't offered again.
    func adopted(_ remote: SyncedPosition) async
}

extension ProgressSync {
    public func pullLatest() async throws -> SyncedPosition? {
        try await pull()
    }

    public var wantsXPointers: Bool { false }

    public func adopted(_ remote: SyncedPosition) async {}
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
    /// When the iPhone and the backend last agreed on the position (a push
    /// landed, or the book opened at the backend's), for "Synced 2 min ago".
    /// `nil` if they never have.
    public var syncedAt: Date?

    public init(position: ReadingPosition, modifiedAt: Date, needsPush: Bool, chapter: String? = nil, syncedAt: Date? = nil) {
        self.position = position
        self.modifiedAt = modifiedAt
        self.needsPush = needsPush
        self.chapter = chapter
        self.syncedAt = syncedAt
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
/// 3. The backend has no CFI (never opened, or a percentage only): open at
///    the local position, else at the backend's fraction, else at the start.
///
/// Another reader's place (`SyncedPosition.Origin.elsewhere`, KOReader's) is
/// trusted less, since it's another engine's and may be a device that was
/// offline (`docs/notes/koreader-sync-plan.md`, chunk 3):
/// - With no local position, open at it.
/// - Open at it only if it moved since this iPhone last saw it, is ahead of
///   the local position, and the device has nothing unsent. Otherwise open
///   at the local position, and the reader offers it.
public enum OpeningPosition: Equatable, Sendable {
    case remote(ReadingPosition)
    case local(ReadingPosition)
    case start

    /// How much further on, within one spine item, another reader's place
    /// has to be to count as ahead. KOReader's percentage and foliate's
    /// differ by a point or so in the same place.
    public static let aheadMargin = 0.01

    public static func choose(local: LocalReadingProgress?, remote: SyncedPosition?) -> OpeningPosition {
        if let remote, case .elsewhere(let change) = remote.origin {
            guard let local else {
                return remote.position.xpointer != nil || remote.position.fraction > 0 ? .remote(remote.position) : .start
            }
            guard change == .moved, !local.needsPush, isAhead(remote.position, of: local.position) else { return .local(local.position) }
            return .remote(remote.position)
        }
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

    /// Whether `remote` is further on than `local`: in a later spine item,
    /// else at least `aheadMargin` further in the same one.
    public static func isAhead(_ remote: ReadingPosition, of local: ReadingPosition) -> Bool {
        if let theirs = remote.spineIndex, let ours = local.spineIndex, theirs != ours { return theirs > ours }
        return remote.fraction >= local.fraction + aheadMargin
    }

    /// Whether the device's unsent position may go over `remote` with no
    /// reader open to offer it: it's where the book opens, and another
    /// reader's place is one this iPhone has already seen.
    public static func mayPush(_ local: LocalReadingProgress, over remote: SyncedPosition?) -> Bool {
        guard local.needsPush, choose(local: local, remote: remote) == .local(local.position) else { return false }
        guard let remote, case .elsewhere(let change) = remote.origin else { return true }
        return change == .unchanged
    }
}
