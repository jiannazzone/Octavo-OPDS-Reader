import Foundation
import OctavoKit

/// The four tabs in the side column (decision 2): Home, Library and Settings
/// in one group, Search last. The system draws Search inside the same tab
/// capsule on iOS 27.1 (`docs/notes/duo-tabbar.md`).
nonisolated enum ShellTab: String, Hashable, Sendable, CaseIterable {
    case home, library, settings, search
}

/// A screen a tab opens. A tab's root isn't a route; everything opened from
/// it is. Unfolded, routes show two at a time, one each side of the hinge.
///
/// `settingsPage` is a stand-in until #16 Settings; the cover page itself is
/// #14.
nonisolated enum ShellRoute: Hashable, Sendable {
    /// A list from a library: a collection, a series, an author's books, an
    /// OPDS feed.
    case feed(LibraryEntry, from: LibrarySourceID)
    case settingsPage(String)
    /// A book's cover page. Unfolding on it opens the book (decision 4).
    case cover(SourcedBook)

    /// Drawn as the pane's large title unfolded, the navigation title folded.
    /// `nil` for screens without one, such as a cover.
    var title: String? {
        switch self {
        case .feed(let entry, _): entry.title
        case .settingsPage(let name): name
        case .cover: nil
        }
    }

    /// The book that unfolding on this screen opens; `nil` everywhere but a
    /// cover, where unfolding keeps the same screen (decision 10).
    var bookOpenedOnUnfold: SourcedBook? {
        if case .cover(let book) = self { book } else { nil }
    }
}
