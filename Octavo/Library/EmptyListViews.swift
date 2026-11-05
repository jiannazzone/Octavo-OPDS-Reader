import OctavoKit
import SwiftUI

// Empty screens (decision 22, #30): what's missing and one way forward on the
// left page, and a server's newest books on the right.

/// What an empty list says: what's missing, and where its books come from.
nonisolated struct EmptyListWording: Equatable {
    var title: String
    var message: String

    init(kind: LibraryEntry.Kind, server: String) {
        message = "Books show here when \(server) lists them."
        switch kind {
        case .collection:
            title = "No books in this collection"
            message = "Books you add to it on \(server) show here."
        case .smartCollection:
            title = "No books in this collection"
        case .series:
            title = "No books in this series"
        case .author:
            title = "No books by this author"
        case .feed:
            title = "No books in this list"
        }
    }
}

/// A list that came back with nothing in it.
struct EmptyFeed: View {
    let entry: LibraryEntry
    let feed: FeedModel
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let wording = EmptyListWording(kind: entry.kind, server: library.server(feed.source)?.name ?? "the server")
        EmptyPages(server: feed.source, excluding: entry.link) {
            // In a scroll view to pull down, centred on its page as on Home.
            ScrollView {
                EmptyInvitation(
                    symbol: "books.vertical", title: wording.title,
                    message: wording.message, actionTitle: "Open Library"
                ) { shell.openLibrary(showing: feed.source) }
                .containerRelativeFrame(.vertical)
            }
        }
        .refreshable { await feed.reload() }
    }
}

/// An empty screen across the spread: folded, the invitation; unfolded, the
/// invitation on the left page and a server's newest books on the right.
struct EmptyPages<Invitation: View>: View {
    /// Whose newest books go on the right page. `nil`: none.
    let server: LibrarySourceID?
    /// The list that's empty, which can't be shown beside itself.
    var excluding: LibraryLink?
    @ViewBuilder let invitation: () -> Invitation
    @Environment(LibraryModel.self) private var library
    @Environment(\.spread) private var spread

    var body: some View {
        if let pages = spread.pages {
            HStack(alignment: .top, spacing: 0) {
                invitation()
                    .frame(width: pages.leftWidth)
                Color.clear
                    .frame(width: pages.hingeWidth)
                NewestBooksPage(newest: newest, source: server, width: pages.rightWidth)
                    .frame(width: pages.rightWidth)
            }
        } else {
            invitation()
        }
    }

    /// `nil` if the server has no such list, or it's the empty one.
    private var newest: LibraryEntry? {
        guard let root = server.flatMap({ library.connection($0)?.root }),
              let newest = LibraryView.newest(root), newest.link != excluding else { return nil }
        return newest
    }
}

/// The right page beside an empty screen: the newest books as a shelf, with
/// the page to itself. Blank if there are no covers to show.
private struct NewestBooksPage: View {
    let newest: LibraryEntry?
    let source: LibrarySourceID?
    let width: CGFloat
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ScrollView {
            if let newest, let source, let feed = library.feed(newest.link, from: source), shows(feed) {
                LibraryShelf(entry: newest, source: source, maxRows: 3)
                    .environment(\.spread, Spread(width: width, pages: nil))
                    .padding(.top, 8)
            }
        }
    }

    private func shows(_ feed: FeedModel) -> Bool {
        switch feed.state {
        case .idle, .loading: true
        case .failed: false
        case .loaded: !feed.books.isEmpty || feed.entries.contains { !$0.previewCovers.isEmpty }
        }
    }
}
