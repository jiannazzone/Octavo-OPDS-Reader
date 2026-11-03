import Foundation
import OctavoKit

/// The tabs in the side column: Home, Library and Search. Settings isn't a
/// tab; a button at the top of the column opens it (`docs/design/direction.md`).
/// `setup` isn't a tab either: it's the screens before there's a server,
/// shown instead of the tabs.
nonisolated enum ShellTab: String, Hashable, Sendable, CaseIterable {
    case home, library, search, setup
}

/// A page of Settings, opened from its list.
nonisolated enum SettingsPage: Hashable, Sendable, CaseIterable {
    case server, storage, licences
}

/// A screen a tab opens. A tab's root isn't a route; everything opened from
/// it is, and the deepest one fills the spread.
nonisolated enum ShellRoute: Hashable, Sendable {
    /// A list from a library: a collection, a series, an author's books, an
    /// OPDS feed.
    case feed(LibraryEntry, from: LibrarySourceID)
    /// Settings' list. Unfolded it's beside a page (`SettingsScreen`).
    case settings
    /// Folded, a page over the list; unfolded, the list with this page
    /// chosen.
    case settingsPage(SettingsPage)
    /// A book's screen. Unfolding on it opens the book if it's on the iPhone.
    case cover(SourcedBook)
    /// A step in adding the server.
    case setup(SetupStep)
    /// Every book on the iPhone (`ShellModel.onIPhoneBooks`): the Library's
    /// last shelf, and where an import lands.
    case onIPhone
    /// The server signed you out (or its password changed): sign in again.
    case signInAgain

    /// Drawn as the screen's large title. `nil` for a book's screen, and for
    /// Settings, which draws a title on each page.
    var title: String? {
        switch self {
        case .feed(let entry, _): entry.kind == .author ? AuthorIndex.displayName(entry) : entry.title
        case .settings, .settingsPage, .cover: nil
        case .onIPhone: "On iPhone"
        case .setup(.choose): "Add a server"
        case .setup(.bookOrbit): "Sign in to BookOrbit"
        case .setup(.opds): "Add an OPDS catalog"
        case .setup(.trust): "Trust this server?"
        case .setup(.sync): "Reading progress"
        case .signInAgain: "Sign in again"
        }
    }
}
