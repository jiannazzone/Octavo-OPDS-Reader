import OctavoKit
import SwiftUI

// An OPDS list sorted or filtered on the iPhone (#131 step 2,
// `docs/notes/library-filters.md`): no catalog but COPS sorts, and none
// keeps a read status, so the list loads in full and is arranged here.

/// An OPDS list's sort and filter, picked on its screen. Not remembered:
/// every list opens in the catalog's order, so opening one never starts a
/// long load (Adam, 2026-11-11).
nonisolated struct LocalOrder: Equatable {
    static let sorts: [LibrarySort] = [.listOrder, .title, .author]

    var sort = LibrarySort.listOrder
    var filter = LibraryFilter.all

    /// Anything but the catalog's own order, all of it.
    var isOn: Bool { sort != .listOrder || filter != .all }
}

/// The whole list, up to `FeedModel.maxBooksToArrange` books: "Loading
/// books…" until every page is in, then all of them at once, sorted and
/// filtered (Adam, 2026-11-09).
struct ArrangedFeed: View {
    let feed: FeedModel
    /// The list's name, for the line under a filtered title.
    let list: String
    let sort: LibrarySort
    let filter: LibraryFilter
    let showAll: () -> Void
    @Environment(ShellModel.self) private var shell
    /// `nil` while the list loads.
    @State private var arranged: [SourcedBook]?
    @State private var attempt = 0

    var body: some View {
        content
            .task(id: Arrangement(feed: ObjectIdentifier(feed), sort: sort, filter: filter, attempt: attempt)) {
                arranged = nil
                if feed.state == .failed { await feed.retry() }
                await feed.loadAll(maxBooks: FeedModel.maxBooksToArrange)
                guard !Task.isCancelled, feed.state == .loaded else { return }
                arranged = arrange()
            }
            // Back from a book's screen, whose Finished mark may have moved it.
            .onAppear { if arranged != nil { arranged = arrange() } }
    }

    @ViewBuilder
    private var content: some View {
        if let arranged {
            if arranged.isEmpty, let wording = EmptyListWording(filter: filter) {
                EmptyPages(server: feed.source, excluding: feed.link) {
                    EmptyInvitation(
                        symbol: "books.vertical", title: wording.title, message: wording.message, actionTitle: "Show All Books", action: showAll
                    )
                    .scrollingOnItsPage()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(booksLine(arranged.count, in: filter == .all ? nil : list))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .onLeftPage()
                        SpreadGrid(items: arranged) { book in
                            BookGridCell(book: book)
                        }
                        if feed.hasMore {
                            Text("Only the first \(FeedModel.maxBooksToArrange.formatted()) books were loaded.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                                .onLeftPage(alignment: .center)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
                }
            }
        } else if feed.state == .failed {
            EmptyPages(server: nil) {
                EmptyInvitation(
                    symbol: "exclamationmark.triangle", title: "Couldn’t load this list",
                    message: "The server didn’t send it.", actionTitle: "Try again"
                ) { attempt += 1 }
                .scrollingOnItsPage()
            }
        } else {
            EmptyPages(server: nil) {
                VStack(spacing: 8) {
                    ProgressView()
                        .padding(.bottom, 4)
                    Text("Loading books…")
                    Text(progress)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "600 of 2,000", or "600 books" when the server doesn't say how many.
    private var progress: String {
        let cap = FeedModel.maxBooksToArrange
        let loaded = min(feed.books.count, cap)
        guard let total = feed.total else { return booksLine(loaded) }
        return "\(loaded.formatted()) of \(min(total, cap).formatted())"
    }

    private func arrange() -> [SourcedBook] {
        let sorted = BookOrder.sorted(Array(feed.books.prefix(FeedModel.maxBooksToArrange)), by: sort)
        let books = sorted.map { SourcedBook(source: feed.source, book: $0) }
        return filter == .all ? books : books.filter { shell.status(of: $0) == filter }
    }

    private struct Arrangement: Equatable {
        var feed: ObjectIdentifier
        var sort: LibrarySort
        var filter: LibraryFilter
        var attempt: Int
    }
}
