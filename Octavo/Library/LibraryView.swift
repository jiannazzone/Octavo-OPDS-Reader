import OctavoKit
import SwiftUI

/// The Library tab's root (frames 02, 04): the chips, and the chosen chip's
/// list under them. Unfolded, the right pane starts on the list's first
/// item, selected: a book's cover page, or a collection's books.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Group {
            if let server = library.server {
                if let root = library.root, let chip = library.chip, let feed = library.feed(chip, from: server.id) {
                    FeedContent(feed: feed) { header(root) }
                        .onChange(of: feed.firstRoute, initial: true) { _, route in
                            shell[path: .library].companion = route
                        }
                } else {
                    VStack {
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
                            ProgressView()
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
            } else {
                NoLibraryInvitation()
            }
        }
    }

    private func header(_ root: LibraryRoot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ConnectionBannerSlot()
                .padding(.horizontal, 20)
            ChipBar(chips: root.chips, selected: library.chip) { link in
                guard link != library.chip else { return }
                library.chip = link
                // The screens opened from the old chip go with it.
                shell[path: .library].routes = []
            }
        }
    }
}

/// A list opened from the Library (frames 30, 32, 33): a collection's,
/// series' or author's books, or an OPDS feed's entries.
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

/// One list from a library, shown by what it holds (decision 23): entries
/// as rows (authors A–Z with an index strip), books as a cover grid, or rows
/// above a grid when an OPDS feed mixes them. `header` scrolls with it.
struct FeedContent<Header: View>: View {
    let feed: FeedModel
    var numbered = false
    @ViewBuilder let header: () -> Header
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if feed.books.isEmpty, !feed.entries.isEmpty {
                list
            } else {
                grid
            }
        }
        // Keyed on the list too: switching chips keeps this view and hands
        // it another list.
        .task(id: LoadKey(feed: ObjectIdentifier(feed), isAuthorList: feed.isAuthorList)) {
            // The index strip jumps anywhere, so authors load in full.
            if feed.isAuthorList { await feed.loadAll() } else { await feed.load() }
        }
        .refreshable { await feed.reload() }
    }

    private struct LoadKey: Hashable {
        var feed: ObjectIdentifier
        var isAuthorList: Bool
    }

    private var list: some View {
        List {
            header()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            if feed.isAuthorList {
                ForEach(feed.authorSections) { section in
                    // The letter as a row, not a section header: plain
                    // lists space headers far apart (frame 31 is compact).
                    Section {
                        Text(section.letter)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
                            .listRowSeparator(.hidden)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.entries) { row($0) }
                    }
                    .sectionIndexLabel(section.letter)
                }
            } else {
                ForEach(feed.entries) { entry in
                    row(entry)
                        .onAppear {
                            if entry.id == feed.entries.last?.id { Task { await feed.loadMore() } }
                        }
                }
            }
            if feed.state == .failed, library.connectionProblem == nil {
                Button("Couldn’t load the rest · Try again") { Task { await feed.retry() } }
            }
        }
        .listStyle(.plain)
        // Level with the grid's header, so the chips don't move when a chip
        // switches between a list and a grid.
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .listSectionIndexVisibility(feed.isAuthorList ? .visible : .hidden)
    }

    private func row(_ entry: LibraryEntry) -> some View {
        EntryRow(entry: entry, source: feed.source)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header()
                if !feed.entries.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(feed.entries) { entry in
                            EntryRow(entry: entry, source: feed.source)
                                .padding(.vertical, 10)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if !feed.books.isEmpty {
                    BookGrid(books: feed.books.map { SourcedBook(source: feed.source, book: $0) }, numbered: numbered) {
                        await feed.loadMore()
                    }
                    .padding(.horizontal, 20)
                }
                status
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var status: some View {
        let isEmpty = feed.books.isEmpty && feed.entries.isEmpty
        switch feed.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, isEmpty ? 80 : 12)
        case .failed where library.connectionProblem == nil:
            if isEmpty {
                EmptyInvitation(
                    symbol: "exclamationmark.triangle", title: "Couldn’t load this list",
                    message: "The server didn’t send it.", actionTitle: "Try again"
                ) { Task { await feed.retry() } }
            } else {
                Button("Couldn’t load the rest · Try again") { Task { await feed.retry() } }
                    .frame(maxWidth: .infinity)
            }
        case .loaded where isEmpty:
            ContentUnavailableView("Nothing here yet", systemImage: "books.vertical")
        default:
            EmptyView()
        }
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

/// No server yet. First run (#12) will make this impossible; until then a
/// debug build connects one from Settings.
struct NoLibraryInvitation: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        EmptyInvitation(
            symbol: "books.vertical", title: "No library connected",
            message: "Connect a server in Settings to see your books.", actionTitle: "Open Settings"
        ) { shell.tab = .settings }
    }
}

extension FeedModel {
    /// The first item as shown, which the pane beside opens on before
    /// anything is tapped.
    var firstRoute: ShellRoute? {
        let entry = isAuthorList ? authorSections.first?.entries.first : entries.first
        if let entry { return .feed(entry, from: source) }
        return books.first.map { .cover(SourcedBook(source: source, book: $0)) }
    }
}
