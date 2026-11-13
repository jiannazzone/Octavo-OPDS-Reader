import Foundation

/// A book's read status, as BookOrbit keeps it (#120,
/// `docs/notes/book-status.md`). The raw values are BookOrbit's (v3.6.0).
/// Other sources keep none.
public enum LibraryReadStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case unread
    case wantToRead = "want_to_read"
    case reading
    case onHold = "on_hold"
    /// What BookOrbit makes `reading` once a book has been read.
    case rereading
    /// Finished.
    case read
    case skimmed
    case abandoned

    /// Whether BookOrbit's Continue Reading keeps a book you've started
    /// (measured on v3.6.0): a finished, skimmed, abandoned or unread one
    /// leaves it.
    public var staysInContinueReading: Bool {
        switch self {
        case .reading, .rereading, .onHold, .wantToRead: true
        case .unread, .read, .skimmed, .abandoned: false
        }
    }

    /// What starting the book makes it, as BookOrbit's own reader does:
    /// Unread and Want to read become Reading. `nil`: it stays. (On hold
    /// becomes Reading too, but the server does that for any progress.)
    public var whenStarted: LibraryReadStatus? {
        self == .unread || self == .wantToRead ? .reading : nil
    }
}

extension LibraryFilter {
    /// The filter that shows a BookOrbit book with `status` (`nil`: none) and
    /// `progress` (0...1), as BookOrbit's own filters do
    /// (`BookOrbitBookFilter`). `nil`: only All books, such as a skimmed or
    /// abandoned book.
    public static func showing(_ status: LibraryReadStatus?, progress: Double?) -> LibraryFilter? {
        let progress = progress ?? 0
        let started = progress > 0 && progress < 1
        switch status {
        case nil, .unread: return progress == 0 ? .unread : nil
        case .wantToRead: return progress == 0 ? .unread : started ? .reading : nil
        case .reading, .rereading: return .reading
        case .onHold: return started ? .reading : nil
        case .read: return .finished
        case .skimmed, .abandoned: return nil
        }
    }
}
