import Foundation

/// The chapter buttons on the progress bar (decision 35). A chapter is any
/// contents entry. Back goes to this chapter's start, and from there to the
/// chapter before, as in a music player.
///
/// Whether the page is already on a chapter's start isn't worked out here: an
/// entry's place is an estimate a page or two out until its section has been
/// laid out. So these are places to try in turn, moving on when going to one
/// leaves the page where it is (`ReaderModel.skipChapter`). That also steps
/// past a "Part Two" entry that starts on the page already showing.
nonisolated struct ReaderChapterSkip: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case back, forward
    }

    /// How many entries one tap tries before giving up.
    static let tries = 3

    /// How many entries the contents have.
    var count: Int
    /// The entry the page is in. `nil` before the first.
    var current: Int?
    /// The page holds the first entry's start, so there's nothing before it.
    var isOnFirstEntry: Bool

    /// A book with no contents has no buttons.
    var isAvailable: Bool { count > 0 }

    var canGoBack: Bool {
        current != nil && !(current == 0 && isOnFirstEntry)
    }

    var canGoForward: Bool {
        (current.map { $0 + 1 } ?? 0) < count
    }

    /// The entries to try in turn.
    func targets(_ direction: Direction) -> [Int] {
        switch direction {
        case .back:
            guard let current else { return [] }
            return (0..<Self.tries).map { current - $0 }.filter { $0 >= 0 }
        case .forward:
            let next = current.map { $0 + 1 } ?? 0
            return (0..<Self.tries).map { next + $0 }.filter { $0 < count }
        }
    }
}
