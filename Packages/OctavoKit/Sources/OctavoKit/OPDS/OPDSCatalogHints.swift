import Foundation

/// Guesses about a root feed that OPDS doesn't spell out (Adam, 2026-11-01).
///
/// - **Recently added** for Home: the `sort/new` link (COPS), else the entry
///   that is clearly the newest books: Calibre-Web `/opds/new`, Kavita
///   `recentlyAdded`, Komga `latestBooks`, or a title like "Recently added".
/// - **Start chip** for the Library: the chip that lists the whole library
///   (Calibre-Web Alphabetical Books, COPS All books, Komga All series,
///   Kavita All Libraries), so it doesn't open on an empty "Keep Reading".
///   The chips keep the server's order.
struct OPDSCatalogHints {
    let feed: OPDSFeed

    private static let newIDs: Set<String> = ["recentlyadded", "latestbooks", "cops:recentbooks", "/opds/new"]
    private static let newPaths = ["/opds/new", "/recently-added", "/books/latest", "/recent"]
    private static let newTitles: Set<String> = [
        "recently added", "recently added books", "recent additions", "latest books", "new books", "newest books", "new", "newest",
    ]

    var recentlyAdded: URL? {
        if let link = feed.link(rel: OPDSRel.sortNew)?.url { return link }
        if let item = feed.navigation.first(where: { $0.link.has(rel: OPDSRel.sortNew) }) { return item.link.url }
        if let item = feed.navigation.first(where: isNewest) { return item.link.url }
        return feed.groups.first { Self.newTitles.contains(Self.key($0.title)) }?
            .links.first { $0.has(rel: "self") }?.url
    }

    private func isNewest(_ item: OPDSNavigation) -> Bool {
        if let id = item.identifier.map(Self.key), Self.newIDs.contains(id) { return true }
        let path = item.link.url?.path.lowercased() ?? ""
        if Self.newPaths.contains(where: { path.hasSuffix($0) }) { return true }
        return Self.newTitles.contains(Self.key(item.title))
    }

    /// Best first: every book, then every series, then the libraries.
    private static let wholeLibrary: [(ids: Set<String>, titles: Set<String>)] = [
        (["cops:books", "/opds/books", "allbooks", "books"], ["all books", "alphabetical books", "books", "all"]),
        (["allseries"], ["all series"]),
        (["alllibraries", "libraries"], ["all libraries", "libraries", "library", "browse"]),
    ]

    /// The chip to open first, or `nil` for the first one.
    func startChip(among chips: [LibraryEntry]) -> LibraryLink? {
        let items = feed.navigation.compactMap { item in item.link.url.map { (item, OPDSSource.link($0)) } }
        for level in Self.wholeLibrary {
            for chip in chips {
                let item = items.first { $0.1 == chip.link }?.0
                if let id = item?.identifier.map(Self.key), level.ids.contains(id) { return chip.link }
                if level.titles.contains(Self.key(chip.title)) { return chip.link }
            }
        }
        return nil
    }

    private static func key(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
