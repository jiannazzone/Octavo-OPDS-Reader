import Foundation

/// Where books come from: browse, search, details, covers and download.
///
/// Where progress goes is a separate concern (`ProgressSync`), so any library
/// can pair with any backend. Implementations: `BookOrbitSource`, and the
/// OPDS 1.2/2.0 source.
///
/// Every list is a `LibraryFeed` reached through a `LibraryLink`: the chips,
/// a collection, a series, an author, the next page. The app never builds
/// links; it follows the ones the source hands out. Errors are `LibraryError`,
/// or `URLError` when the server can't be reached.
public protocol LibrarySource: Sendable {
    /// The Library tab's chips and what search supports.
    func root() async throws -> LibraryRoot

    /// One page of the list at `link`.
    func feed(_ link: LibraryLink) async throws -> LibraryFeed

    /// Books (and, where supported, series and authors) matching `query`.
    /// Throws nothing for an unsupported search; the results are empty.
    func search(_ query: String) async throws -> LibrarySearchResults

    /// The details sheet for `book`. Takes the list's book because some
    /// servers (OPDS) have no separate detail request.
    func details(for book: LibraryBook) async throws -> LibraryBookDetails

    /// The image bytes (JPEG, PNG, …).
    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data

    /// Downloads `file` to `destination`, replacing anything there.
    /// `progress` gets 0...1 as bytes arrive. Cancelling the calling task
    /// cancels the download and leaves `destination` as it was.
    @discardableResult
    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL

    /// Whether the server keeps a finished mark (BookOrbit's read status).
    /// Where it doesn't (OPDS), the app keeps the mark on the iPhone.
    var tracksFinished: Bool { get }

    /// Marks `book` finished, or not, on the server.
    func setFinished(_ finished: Bool, for book: LibraryBook) async throws

    /// What the list at `link` can be sorted and filtered by, and how it is
    /// now. `nil`: neither (lists of series or authors, search).
    func order(of link: LibraryLink) -> LibraryListOrder?

    /// The list at `link` sorted by `sort` and showing `filter`, as
    /// `order(of:)` offers them.
    func link(_ link: LibraryLink, sortedBy sort: LibrarySort?, showing filter: LibraryFilter) -> LibraryLink

    /// The list at `link` in pages as large as the server allows, up to
    /// `count` items, for loading it whole to sort or filter on the iPhone.
    func wholeList(_ link: LibraryLink, upTo count: Int) -> LibraryLink
}

extension LibrarySource {
    public var tracksFinished: Bool { false }

    public func setFinished(_ finished: Bool, for book: LibraryBook) async throws {}

    public func order(of link: LibraryLink) -> LibraryListOrder? { nil }

    public func link(_ link: LibraryLink, sortedBy sort: LibrarySort?, showing filter: LibraryFilter) -> LibraryLink { link }

    public func wholeList(_ link: LibraryLink, upTo count: Int) -> LibraryLink { link }

    @discardableResult
    public func download(_ file: LibraryFile, to destination: URL) async throws -> URL {
        try await download(file, to: destination, progress: { _ in })
    }
}
