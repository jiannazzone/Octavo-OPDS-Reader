import Foundation
import OctavoKit

/// The tabs in the side column: Home, Library and Search. Settings isn't a
/// tab; a button at the top of the column opens it (`docs/design/direction.md`).
/// `setup` isn't a tab either: it's the screens before there's a server,
/// shown instead of the tabs.
nonisolated enum ShellTab: String, Hashable, Sendable, CaseIterable {
    case home, library, search, setup
}

/// A screen a tab opens. A tab's root isn't a route; everything opened from
/// it is, and the deepest one fills the spread.
///
/// `settingsPage` is a stand-in until Settings is designed.
nonisolated enum ShellRoute: Hashable, Sendable {
    /// A list from a library: a collection, a series, an author's books, an
    /// OPDS feed.
    case feed(LibraryEntry, from: LibrarySourceID)
    case settings
    case settingsPage(String)
    /// A book's screen. Unfolding on it opens the book if it's on the iPhone.
    case cover(SourcedBook)
    /// A step in adding the server.
    case setup(SetupStep)
    /// The server signed you out (or its password changed): sign in again.
    case signInAgain

    /// Whether the screen has its two-page layout yet; one that hasn't keeps
    /// to the left page unfolded.
    var fillsSpread: Bool {
        switch self {
        case .feed, .cover, .setup, .signInAgain: true
        case .settings, .settingsPage: false
        }
    }

    /// Drawn as the screen's large title. `nil` for a book's screen.
    var title: String? {
        switch self {
        case .feed(let entry, _): entry.kind == .author ? AuthorIndex.displayName(entry) : entry.title
        case .settings: "Settings"
        case .settingsPage(let name): name
        case .cover: nil
        case .setup(.bookOrbit): "Sign in to BookOrbit"
        case .setup(.opds): "Add an OPDS catalog"
        case .setup(.trust): "Trust this server?"
        case .setup(.sync): "Reading progress"
        case .signInAgain: "Sign in again"
        }
    }
}
