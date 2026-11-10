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

    /// The Unread shelf's list, once every book has been started (#131).
    static let unread = EmptyListWording(title: "No unread books", message: "Books you haven’t started show here.")

    private init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// A list that came back with nothing in it.
struct EmptyFeed: View {
    let entry: LibraryEntry
    let feed: FeedModel
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        EmptyPages(server: feed.source, excluding: entry.link) {
            // A reload that failed, unless the problem's banner says why. It
            // stays this screen: `FeedContent` would load the list again.
            if feed.state == .failed, library.connection(feed.source)?.problem == nil {
                FeedFailedInvitation(feed: feed)
                    .scrollingOnItsPage()
            } else {
                let wording = entry.link == library.connection(feed.source)?.root?.unread
                    ? .unread
                    : EmptyListWording(kind: entry.kind, server: library.server(feed.source)?.name ?? "the server")
                EmptyInvitation(
                    symbol: "books.vertical", title: wording.title,
                    message: wording.message, actionTitle: "Open Library"
                ) { shell.openLibrary(showing: feed.source) }
                .scrollingOnItsPage()
            }
        }
        .refreshable { await feed.reload() }
    }
}

/// A list the server didn't send.
struct FeedFailedInvitation: View {
    let feed: FeedModel

    var body: some View {
        EmptyInvitation(
            symbol: "exclamationmark.triangle", title: "Couldn’t load this list",
            message: "The server didn’t send it.", actionTitle: "Try again"
        ) { Task { await feed.retry() } }
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

    var body: some View {
        SpreadPages(alignment: .top, folded: .left) { _ in
            invitation()
        } right: { width in
            if let width {
                NewestBooksPage(newest: newest, source: server, width: width)
            }
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
            if let newest, let source, let feed = library.feed(newest.link, from: source), LibraryShelf.hasCovers(feed, from: source) {
                LibraryShelf(entry: newest, source: source, maxRows: 3)
                    .environment(\.spread, Spread(width: width, pages: nil))
                    .padding(.top, 8)
            }
        }
    }
}
