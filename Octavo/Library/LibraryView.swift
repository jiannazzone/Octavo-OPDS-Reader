import OctavoKit
import SwiftUI

/// The Library tab's top screen (`TabStack`): the library's sections as
/// shelves (`docs/design/direction.md`, Library), each a heading over one row
/// of covers across both pages; the same layout for every server. A heading
/// or a cover pushes its screen with the system's Back.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        content
            // With several servers, the chosen one's name; the side column
            // has the menu of them (`ServersMenu`, decision 36).
            .navigationTitle(library.hasSeveralServers ? library.server?.name ?? "Library" : "Library")
            .toolbarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private var content: some View {
        if let server = library.server {
            if let root = library.root {
                LibraryContents(source: server.id, sections: Self.sections(root))
                    // Another server's lists, which may be at the same links,
                    // and from the top.
                    .id(server.id)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // On the left page, as over the shelves (`LibraryContents`).
                    ConnectionBannerSlot()
                        .padding(.horizontal, SpreadMetrics.margin)
                        .onLeftPage()
                    ImportFailureBanner()
                        .padding(.horizontal, SpreadMetrics.margin)
                        .onLeftPage()
                    if library.connectionProblem != nil {
                        // The banner says why, and retries; what's on the
                        // iPhone still reads (decision 22).
                        ScrollView {
                            OnIPhoneShelf()
                                .padding(.top, SpreadMetrics.margin)
                        }
                    } else if library.rootFailed {
                        // On the left page, the right one empty: no lists
                        // came to show beside it.
                        EmptyPages(server: nil) {
                            EmptyInvitation(
                                symbol: "exclamationmark.triangle", title: "Couldn’t load your library",
                                message: "The server didn’t send its lists.", actionTitle: "Try again"
                            ) { Task { await library.retry() } }
                        }
                    } else {
                        LibraryContentsPlaceholder()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if !shell.onIPhoneBooks().isEmpty {
            // Books imported, no server yet: the books themselves (Adam,
            // 2026-11-02).
            OnIPhoneContent(offersServer: true)
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

    /// The server's newest books, by the name its shelf has. `nil` if the
    /// server has no such list.
    static func newest(_ root: LibraryRoot) -> LibraryEntry? {
        sections(root).first { $0.link == root.recentlyAdded }
    }
}

/// The servers, in the side column with several (decision 36): the chosen
/// one checked, then Add a server.
struct ServersMenu: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Menu("Servers", systemImage: "server.rack") {
            Picker("Server", selection: chosen) {
                ForEach(library.connections, id: \.server.id) { connection in
                    Text(connection.server.name).tag(Optional(connection.server.id))
                }
            }
            Divider()
            Button("Add a server", systemImage: "plus") {
                shell.push(.setup(.choose))
            }
        }
    }

    private var chosen: Binding<LibrarySourceID?> {
        Binding { library.server?.id } set: { id in
            if let id { shell.serverActions.choose(id) }
        }
    }
}

/// The sections as shelves, one under another, in one scroll view across
/// both pages.
struct LibraryContents: View {
    let source: LibrarySourceID
    let sections: [LibraryEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ConnectionBannerSlot()
                    .padding(.horizontal, SpreadMetrics.margin)
                    .onLeftPage()
                // Files an import couldn't take, when none came in (with
                // one that did, On iPhone shows it).
                ImportFailureBanner()
                    .padding(.horizontal, SpreadMetrics.margin)
                    .onLeftPage()
                ForEach(sections) { section in
                    LibraryShelf(entry: section, source: source)
                }
                // Last, after the server's own sections (Adam, 2026-11-02).
                OnIPhoneShelf()
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

/// One section as a shelf: a heading ("All · 7 ›") that opens the section,
/// over one row of its covers (running across both pages on a spread). A book on the shelf opens its own screen; a list
/// of lists (series, authors) shows a tile for each that opens it. A list
/// whose entries list no covers (BookOrbit collections) is just its
/// heading.
struct LibraryShelf: View {
    let entry: LibraryEntry
    let source: LibrarySourceID
    var maxRows = 1
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.menuColumn) private var menu

    /// Whether a shelf of `feed` has covers to show, or may once it loads.
    static func hasCovers(_ feed: FeedModel, from source: LibrarySourceID) -> Bool {
        switch feed.state {
        case .idle, .loading: true
        case .failed: false
        case .loaded:
            !feed.books.isEmpty
                || feed.entries.contains { !$0.previewCovers.isEmpty }
        }
    }

    var body: some View {
        // The section's own list, so its first page is ready when the shelf
        // is opened.
        let feed = library.feed(entry.link, from: source)
        VStack(alignment: .leading, spacing: 10) {
            heading(feed)
                .padding(.horizontal, SpreadMetrics.margin)
                .onLeftPage()
            shelf(feed)
        }
        .task(id: entry.link) { await feed?.load() }
    }

    private func heading(_ feed: FeedModel?) -> some View {
        Button {
            shell.open(.feed(entry, from: source), inMenuOf: menu)
        } label: {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(untilLargerText: 1)
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
            SpreadGrid(items: feed.books.map { SourcedBook(source: source, book: $0) }, maxRows: maxRows, cell: { book in
                BookGridCell(book: book)
            })
        } else if let feed, !feed.entries.isEmpty, feed.entries.contains(where: { !$0.previewCovers.isEmpty }) {
            // A list of lists (series, authors): each a tile that opens it.
            SpreadGrid(items: feed.entries, maxRows: maxRows, cell: { entry in
                EntryTile(entry: entry, source: source)
            })
        } else if feed.map({ $0.state == .idle || $0.state == .loading }) ?? false {
            SpreadGrid(items: (0..<8).map { ShelfPlaceholder(id: $0) }, maxRows: maxRows, cell: { _ in
                ShelfPlaceholder.shape
            })
            .accessibilityHidden(true)
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
            if feed.cameBackEmpty {
                EmptyFeed(entry: entry, feed: feed)
            } else {
                FeedContent(feed: feed, numbered: entry.kind == .series) {
                    if let summary = summary(feed) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
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

    var body: some View {
        ScrollViewReader { scroller in
            list
                .overlay(alignment: .trailing) {
                    if showsIndex {
                        LetterIndex(letters: feed.authorSections.map(\.letter)) { letter in
                            scroller.scrollTo(ListItem.letter(letter).id, anchor: .top)
                        }
                    }
                }
        }
        .task(id: ObjectIdentifier(feed)) {
            await feed.load()
            // A list flows down one page and on down the next, so it loads
            // in full; a grid loads page by page as it scrolls.
            if feed.books.isEmpty, !feed.entries.isEmpty { await feed.loadAll() }
        }
        .refreshable { await feed.reload() }
    }

    /// An A–Z strip once the authors run past a couple of screens.
    private var showsIndex: Bool {
        feed.isAuthorList && feed.entries.count >= Self.indexMinimum && feed.authorSections.count > 1
    }

    static var indexMinimum: Int { 30 }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header()
                    .onLeftPage()
                if isEmpty, feed.state == .idle || feed.state == .loading {
                    SpreadGrid(items: (0..<9).map { Placeholder(id: $0) }, cell: { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .aspectRatio(2 / 3, contentMode: .fit)
                    })
                    .accessibilityHidden(true)
                }
                if feed.isSeriesList {
                    SpreadGrid(items: feed.entries, cell: { entry in
                        EntryTile(entry: entry, source: feed.source)
                    })
                } else if !feed.entries.isEmpty {
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
                    .onLeftPage(alignment: .center)
            }
            // With only the left page's width in it, a scroll view would
            // centre this across the hinge.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)
        }
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
                .id(item.id)
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
        case .failed where library.connection(feed.source)?.problem == nil:
            if isEmpty {
                FeedFailedInvitation(feed: feed)
            } else {
                Button("Couldn’t load the rest · Try again") { Task { await feed.retry() } }
            }
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

/// The A–Z strip at the trailing edge of a long author list: tap or slide
/// along it to jump to a letter.
struct LetterIndex: View {
    let letters: [String]
    let jump: (String) -> Void
    @State private var current: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                    .frame(maxHeight: 16)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in select(at: value.location.y) }
                .onEnded { _ in current = nil }
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .padding(.trailing, 2)
        .accessibilityElement()
        .accessibilityLabel("Index")
        .accessibilityAdjustableAction { direction in
            let index = current.flatMap(letters.firstIndex) ?? -1
            let next = direction == .increment ? index + 1 : index - 1
            guard letters.indices.contains(next) else { return }
            current = letters[next]
            jump(letters[next])
        }
    }

    @State private var height: CGFloat = 0

    private func select(at y: CGFloat) {
        guard !letters.isEmpty, height > 12 else { return }
        let fraction = min(max((y - 6) / (height - 12), 0), 0.999)
        let letter = letters[Int(fraction * CGFloat(letters.count))]
        guard letter != current else { return }
        current = letter
        jump(letter)
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
            EmptyPages(server: nil) {
                ContentUnavailableView("Not connected", systemImage: "books.vertical", description: Text("This comes from a library that isn’t connected."))
            }
        }
    }
}

/// No server yet. First run will make this impossible; until then a debug
/// build connects one from Settings.
struct NoLibraryInvitation: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        // On the left page, as every empty screen's invitation is.
        EmptyPages(server: nil) {
            EmptyInvitation(
                symbol: "books.vertical", title: "No library connected",
                message: "Connect a server in Settings to see your books.", actionTitle: "Open Settings"
            ) { shell.openSettings() }
        }
    }
}
