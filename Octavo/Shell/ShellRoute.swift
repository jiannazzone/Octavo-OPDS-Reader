import Foundation
import OctavoKit

/// The tabs in the side column: Home, Library and Search. `settings` isn't a
/// tab: the gear opens it as a sheet over the tabs (Adam, 2026-11-08), with
/// screens of its own. `setup` isn't a tab either: it's the screens before
/// there's a server, shown instead of the tabs.
nonisolated enum ShellTab: String, Hashable, Sendable, CaseIterable {
    case home, library, search, setup, settings
}

/// A page of Settings, opened from its list.
nonisolated enum SettingsPage: Hashable, Sendable {
    case server(LibrarySourceID)
    case koreader, storage, licences
}

/// A screen a tab opens. A tab's list isn't a route; everything picked or
/// opened from it is (`TabSplit`).
nonisolated enum ShellRoute: Hashable, Sendable {
    /// A list from a library: a collection, a series, an author's books, an
    /// OPDS feed.
    case feed(LibraryEntry, from: LibrarySourceID)
    /// A page of Settings, picked in its list (`SettingsSheet`).
    case settingsPage(SettingsPage)
    /// A book's screen. Unfolding on it opens the book if it's on the iPhone.
    case cover(SourcedBook)
    /// A step in adding the server.
    case setup(SetupStep)
    /// Every book on the iPhone (`ShellModel.onIPhoneBooks`): the Library's
    /// last shelf, and where an import lands.
    case onIPhone
    /// A server signed you out (or its password changed): sign in again.
    case signInAgain(LibrarySourceID)

    /// The screen's large title. `nil` for a book's screen, and for a page of
    /// Settings, which names itself.
    @MainActor var title: String? {
        switch self {
        case .feed(let entry, _): entry.kind == .author ? AuthorIndex.displayName(entry) : entry.title
        case .settingsPage, .cover: nil
        case .onIPhone: "On \(ThisDevice.name)"
        case .setup(.choose): "Add a server"
        case .setup(.bookOrbit): "Sign in to BookOrbit"
        case .setup(.opds): "Add an OPDS catalog"
        case .setup(.trust), .setup(.koreaderTrust): "Trust this server?"
        case .setup(.sync): "Reading progress"
        case .signInAgain: "Sign in again"
        }
    }

    /// The screen shows `library`'s books or details, so goes when it does.
    func belongs(to library: LibrarySourceID) -> Bool {
        switch self {
        case .feed(_, let source): source == library
        case .cover(let book): book.source == library
        case .settingsPage(.server(let id)), .signInAgain(let id): id == library
        case .settingsPage, .setup, .onIPhone: false
        }
    }
}
