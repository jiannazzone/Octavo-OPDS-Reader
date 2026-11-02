import OctavoKit
import SwiftUI

/// The Library tab's top screen: the library's sections as shelves
/// (`docs/design/direction.md`, Library), each a heading over one row of
/// covers across both pages; the same layout for every server.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let server = library.server {
            if let root = library.root {
                LibraryContents(source: server.id, sections: Self.sections(root))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ConnectionBannerSlot()
                        .padding(.horizontal, 20)
                    if library.connectionProblem != nil {
                        // The banner says why, and retries.
                        Spacer(minLength: 0)
                    } else if library.rootFailed {
                        EmptyInvitation(
                            symbol: "exclamationmark.triangle", title: "Couldn’t load your library",
                            message: "The server didn’t send its lists.", actionTitle: "Try again"
                        ) { Task { await library.retry() } }
                    } else {
                        LibraryContentsPlaceholder()
                    }
                }
            }
        } else {
            NoLibraryInvitation()
        }
    }

    /// The server's own sections, with Recently added second when the server
    /// has such a list and doesn't already show it.
    static func sections(_ root: LibraryRoot) -> [LibraryEntry] {
        var sections = root.chips
        if let recent = root.recentlyAdded, !sections.contains(where: { $0.link == recent }) {
            sections.insert(LibraryEntry(kind: .feed, title: "Recently added", link: recent), at: min(1, sections.count))
        }
        return sections
    }
}

/// The sections as shelves, one under another.
struct LibraryContents: View {
    let source: LibrarySourceID
    let sections: [LibraryEntry]
    @Environment(\.spread) private var spread

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ConnectionBannerSlot()
                    .padding(.horizontal, SpreadMetrics.margin)
                    .frame(width: spread.pages?.leftWidth, alignment: .leading)
                ForEach(sections) { section in
                    LibraryShelf(entry: section, source: source)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

/// One section as a shelf: a heading ("All · 7 ›") that opens the section
/// over the whole spread, over one row of its covers running across both
/// pages (three folded). A book on the shelf opens its own screen; the
/// covers of a list of lists (series, authors) open the section.
struct LibraryShelf: View {
    let entry: LibraryEntry
    let source: LibrarySourceID
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.spread) private var spread

    var body: some View {
        // The section's own list, so its first page is ready when the shelf
        // is opened.
        let feed = library.feed(entry.link, from: source)
        VStack(alignment: .leading, spacing: 10) {
            heading(feed)
                .padding(.horizontal, SpreadMetrics.margin)
                .frame(width: spread.pages?.leftWidth, alignment: .leading)
            shelf(feed)
        }
        .task(id: entry.link) { await feed?.load() }
    }

    private func heading(_ feed: FeedModel?) -> some View {
        Button {
            shell.push(.feed(entry, from: source))
        } label: {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if let count = count(feed) {
                    Text(count, format: .number)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(feed))
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func shelf(_ feed: FeedModel?) -> some View {
        if let feed, !feed.books.isEmpty {
            SpreadGrid(items: feed.books.map { SourcedBook(source: source, book: $0) }, maxRows: 1, cell: { book in
                BookGridCell(book: book)
            })
        } else if let feed, !listCovers(feed).isEmpty {
            SpreadGrid(items: listCovers(feed), maxRows: 1, cell: { book in
                Button {
                    shell.push(.feed(entry, from: source))
                } label: {
                    BookCover(book: book)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            })
        } else if feed.map({ $0.state == .idle || $0.state == .loading }) ?? false {
            SpreadGrid(items: (0..<8).map { ShelfPlaceholder(id: $0) }, maxRows: 1, cell: { _ in
                ShelfPlaceholder.shape
            })
            .accessibilityHidden(true)
        }
    }

    /// For a list of lists (series, authors): the first cover each entry
    /// lists. Empty when the server doesn't list them (BookOrbit
    /// collections): the shelf is then just its heading.
    private func listCovers(_ feed: FeedModel) -> [SourcedBook] {
        feed.entries.compactMap(\.previewCovers.first).enumerated().map { index, cover in
            SourcedBook(source: source, book: LibraryBook(
                id: LibraryBookID(rawValue: "\(entry.link.rawValue)#\(index)"), title: "", cover: cover
            ))
        }
    }

    private func count(_ feed: FeedModel?) -> Int? {
        entry.count ?? feed?.total
    }

    private func accessibilityLabel(_ feed: FeedModel?) -> String {
        guard let count = count(feed) else { return entry.title }
        return "\(entry.title), \(count)"
    }
}

/// A blank cover shape, while a shelf's books load.
private struct ShelfPlaceholder: Identifiable {
    var id: Int

    static var shape: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .aspectRatio(2 / 3, contentMode: .fit)
    }
}

/// The shelves before the server has sent its sections.
struct LibraryContentsPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 140, height: 20)
                        .padding(.horizontal, SpreadMetrics.margin)
                    SpreadGrid(items: (0..<8).map { ShelfPlaceholder(id: $0) }, maxRows: 1, cell: { _ in
                        ShelfPlaceholder.shape
                    })
                }
            }
        }
        .padding(.top, 8)
        .accessibilityHidden(true)
    }
}

/// A list opened from the Library: a section, a collection's, series' or
/// author's books, or an OPDS feed's entries. Fills the spread.
struct FeedScreen: View {
    let entry: LibraryEntry
    let source: LibrarySourceID
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let feed = library.feed(entry.link, from: source) {
            FeedContent(feed: feed, numbered: entry.kind == .series) {
                if let summary = summary(feed) {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
            }
        } else {
            LibraryNotConnected()
        }
    }

    /// "5 books", "Series · 3 books". Nothing for lists of lists.
    private func summary(_ feed: FeedModel) -> String? {
        guard feed.entries.isEmpty, let count = feed.total ?? entry.count else { return nil }
        let books = count == 1 ? "1 book" : "\(count) books"
        return entry.kind == .series ? "Series · \(books)" : books
    }
}

/// One list from a library across the spread: entries flowing down the left
/// page and on down the right (authors under their letters), books as a
/// grid across both pages, or both when an OPDS feed mixes them. `header`
/// sits on the left page and scrolls with it.
struct FeedContent<Header: View>: View {
    let feed: FeedModel
    var numbered = false
    @ViewBuilder let header: () -> Header
    @Environment(LibraryModel.self) private var library
    @Environment(\.spread) private var spread

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header()
                    .frame(width: spread.pages?.leftWidth, alignment: .leading)
                if isEmpty, feed.state == .idle || feed.state == .loading {
                    SpreadGrid(items: (0..<9).map { Placeholder(id: $0) }, cell: { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .aspectRatio(2 / 3, contentMode: .fit)
                    })
                    .accessibilityHidden(true)
                }
                if !feed.entries.isEmpty {
                    SpreadList(items: listItems) { item in
                        listRow(item)
                    }
                }
                if !feed.books.isEmpty {
                    SpreadGrid(items: feed.books.map { SourcedBook(source: feed.source, book: $0) }) {
                        Task { await feed.loadMore() }
                    } cell: { book in
                        BookGridCell(book: book, numbered: numbered)
                    }
                }
                status
                    .frame(width: spread.pages?.leftWidth)
            }
            .padding(.bottom, 20)
        }
        .task(id: ObjectIdentifier(feed)) {
            await feed.load()
            // A list flows down one page and on down the next, so it loads
            // in full; a grid loads page by page as it scrolls.
            if feed.books.isEmpty, !feed.entries.isEmpty { await feed.loadAll() }
        }
        .refreshable { await feed.reload() }
    }

    private var isEmpty: Bool { feed.books.isEmpty && feed.entries.isEmpty }

    private var listItems: [ListItem] {
        guard feed.isAuthorList else { return feed.entries.map(ListItem.entry) }
        return feed.authorSections.flatMap { [ListItem.letter($0.letter)] + $0.entries.map(ListItem.entry) }
    }

    @ViewBuilder
    private func listRow(_ item: ListItem) -> some View {
        switch item {
        case .letter(let letter):
            Text(letter)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
        case .entry(let entry):
            VStack(spacing: 0) {
                EntryRow(entry: entry, source: feed.source)
                    .padding(.vertical, 10)
                Divider()
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch feed.state {
        case .loading where !isEmpty:
            // The next page of a grid.
            ProgressView()
                .padding(.vertical, 12)
        case .failed where library.connectionProblem == nil:
            if isEmpty {
                EmptyInvitation(
                    symbol: "exclamationmark.triangle", title: "Couldn’t load this list",
                    message: "The server didn’t send it.", actionTitle: "Try again"
                ) { Task { await feed.retry() } }
            } else {
                Button("Couldn’t load the rest · Try again") { Task { await feed.retry() } }
            }
        case .loaded where isEmpty:
            ContentUnavailableView("Nothing here yet", systemImage: "books.vertical")
        default:
            EmptyView()
        }
    }

    private enum ListItem: Identifiable {
        case letter(String)
        case entry(LibraryEntry)

        var id: String {
            switch self {
            case .letter(let letter): "letter:\(letter)"
            case .entry(let entry): "entry:\(entry.link.rawValue)"
            }
        }
    }

    private struct Placeholder: Identifiable {
        var id: Int
    }
}

/// A screen from a library that isn't connected (any more): a stale route
/// after the server changed, or a debug route into another library.
struct LibraryNotConnected: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if library.server == nil {
            NoLibraryInvitation()
        } else {
            ContentUnavailableView("Not connected", systemImage: "books.vertical", description: Text("This comes from a library that isn’t connected."))
        }
    }
}

/// No server yet. First run will make this impossible; until then a debug
/// build connects one from Settings.
struct NoLibraryInvitation: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        EmptyInvitation(
            symbol: "books.vertical", title: "No library connected",
            message: "Connect a server in Settings to see your books.", actionTitle: "Open Settings"
        ) { shell.openSettings() }
    }
}
