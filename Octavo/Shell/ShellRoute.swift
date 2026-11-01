import Foundation

/// The four tabs in the side column (decision 2): Home, Library and Settings
/// in one group, Search last. The system draws Search inside the same tab
/// capsule on iOS 27.1 (`docs/notes/duo-tabbar.md`).
nonisolated enum ShellTab: String, Hashable, Sendable, CaseIterable {
    case home, library, settings, search
}

/// A screen a tab opens. A tab's root isn't a route; everything opened from
/// it is. Unfolded, routes show two at a time, one each side of the hinge.
///
/// Everything but `cover` is a stand-in until the real screens land (#13
/// Home and Library, #15 Search, #16 Settings); the cover page itself is #14.
nonisolated enum ShellRoute: Hashable, Sendable {
    case collections
    case collection(String)
    case settingsPage(String)
    /// A book's cover page. Unfolding on it opens the book (decision 4).
    case cover(PlaceholderBook)

    /// Drawn as the pane's large title unfolded, the navigation title folded.
    /// `nil` for screens without one, such as a cover.
    var title: String? {
        switch self {
        case .collections: "Collections"
        case .collection(let name), .settingsPage(let name): name
        case .cover: nil
        }
    }

    /// The book that unfolding on this screen opens; `nil` everywhere but a
    /// cover, where unfolding keeps the same screen (decision 10).
    var bookOpenedOnUnfold: PlaceholderBook? {
        if case .cover(let book) = self { book } else { nil }
    }
}

/// A stand-in for a library book until #7 and #13 bring real ones.
nonisolated struct PlaceholderBook: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var author: String
    /// Where the reader is, as the cover's strip shows it.
    var place: String
    var progress: Double

    static let samples = [
        PlaceholderBook(id: "moby-dick", title: "Moby-Dick", author: "Herman Melville", place: "Chapter 36 · 30%", progress: 0.3),
        PlaceholderBook(id: "frankenstein", title: "Frankenstein", author: "Mary Shelley", place: "Letter 4 · 71%", progress: 0.71),
        PlaceholderBook(id: "pride-and-prejudice", title: "Pride and Prejudice", author: "Jane Austen", place: "Not started", progress: 0),
        PlaceholderBook(id: "alice", title: "Alice’s Adventures in Wonderland", author: "Lewis Carroll", place: "Not started", progress: 0),
        PlaceholderBook(id: "sherlock", title: "The Adventures of Sherlock Holmes", author: "Arthur Conan Doyle", place: "Not started", progress: 0),
    ]
}
