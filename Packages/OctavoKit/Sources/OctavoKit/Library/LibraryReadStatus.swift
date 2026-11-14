import Foundation

/// A book's read status, as BookOrbit keeps it (#120,
/// `docs/notes/book-status.md`). The raw values are BookOrbit's (v3.6.0).
/// Other sources keep none.
public enum LibraryReadStatus: String, Hashable, Codable, Sendable, CaseIterable {
    /// BookOrbit's eight. Not `other`, which is never sent.
    public static let allCases: [LibraryReadStatus] = [
        .unread, .wantToRead, .reading, .onHold, .rereading, .read, .skimmed, .abandoned,
    ]

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
    /// One a newer BookOrbit added, which Octavo doesn't know: only under
    /// All books, and never sent.
    case other = "octavo.other"

    /// A server's (or an older record's) value; `other` if Octavo doesn't
    /// know it.
    public init(server value: String) {
        self = Self(rawValue: value).flatMap { $0 == .other ? nil : $0 } ?? .other
    }

    public init(from decoder: any Decoder) throws {
        self.init(server: try decoder.singleValueContainer().decode(String.self))
    }

    /// Whether BookOrbit's Continue Reading keeps a book you've started
    /// (measured on v3.6.0): a finished, skimmed, abandoned or unread one
    /// leaves it.
    public var staysInContinueReading: Bool {
        switch self {
        case .reading, .rereading, .onHold, .wantToRead: true
        case .unread, .read, .skimmed, .abandoned, .other: false
        }
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
        case .skimmed, .abandoned, .other: return nil
        }
    }
}
