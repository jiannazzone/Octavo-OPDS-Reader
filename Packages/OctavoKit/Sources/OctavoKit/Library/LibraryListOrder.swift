import Foundation

// A list of books' Sort and Filter buttons (#131 step 2,
// `docs/notes/library-filters.md`). The source says what a list offers and
// hands out a link for each choice, so a sorted or filtered list loads as
// any list does.

/// How a list of books is sorted.
public enum LibrarySort: String, Hashable, Codable, Sendable {
    /// A series' own order.
    case readingOrder
    case title
    /// By the first author's sort name.
    case author
    /// Newest first.
    case recentlyAdded
}

/// Which books a list shows.
public enum LibraryFilter: String, Hashable, Codable, Sendable, CaseIterable {
    case all
    /// Not started.
    case unread
    /// Started, not finished.
    case reading
    case finished
}

/// What a list's Sort and Filter buttons offer, and what's picked.
public struct LibraryListOrder: Hashable, Sendable {
    /// The list's own order first. Empty: no Sort button.
    public var sorts: [LibrarySort]
    /// Empty: no Filter button.
    public var filters: [LibraryFilter]
    /// `nil` when there are no `sorts`.
    public var sort: LibrarySort?
    public var filter: LibraryFilter
    /// Whether the list opens in the sort remembered for its server (All,
    /// collections), rather than always in its own (a series' reading
    /// order).
    public var takesRememberedSort: Bool

    public init(
        sorts: [LibrarySort], filters: [LibraryFilter], sort: LibrarySort?, filter: LibraryFilter,
        takesRememberedSort: Bool
    ) {
        self.sorts = sorts
        self.filters = filters
        self.sort = sort
        self.filter = filter
        self.takesRememberedSort = takesRememberedSort
    }
}
