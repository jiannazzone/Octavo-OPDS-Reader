import Foundation

/// Search in book (decision 19): the query, the matches as they arrive, and
/// the one being shown while stepping through them. Lives with the open
/// book, so reopening Search keeps the last search.
@Observable
final class ReaderSearch {
    typealias Match = ReaderMessage.SearchMatch

    /// What's typed.
    var query = ""
    /// The query the matches are for.
    private(set) var searched: String?
    private(set) var matches: [Match] = []
    private(set) var isSearching = false
    /// Stopped at the bridge's limit; there are more.
    private(set) var isTruncated = false
    /// The match on the page, while stepping through them.
    private(set) var current: Int?
    /// Tags a search's results; a newer search ignores an older one's.
    private(set) var token = 0

    /// A match in the list. It carries the match itself, so a row drawn
    /// while a newer search replaces the matches never looks one up that's
    /// gone; the token in its ID keeps one search's rows from being taken
    /// for another's.
    struct Item: Identifiable, Equatable {
        let id: String
        /// Its place in `matches`, for stepping.
        let index: Int
        let match: Match
    }

    /// A section of the results: matches under one contents entry.
    struct Group: Identifiable, Equatable {
        let id: String
        let chapter: String?
        let items: [Item]
    }

    /// Consecutive matches under the same chapter, in the book's order.
    /// Built as matches arrive, not on every redraw (the field redraws the
    /// panel with each letter).
    private(set) var groups: [Group] = []

    private func group(_ new: [Match]) {
        for match in new {
            let index = matches.count
            matches.append(match)
            let item = Item(id: "\(token)-\(index)", index: index, match: match)
            if let last = groups.last, last.chapter == match.chapter {
                groups[groups.count - 1] = Group(id: last.id, chapter: last.chapter, items: last.items + [item])
            } else {
                groups.append(Group(id: "\(token)-\(index)", chapter: match.chapter, items: [item]))
            }
        }
    }

    var isStepping: Bool { current != nil }
    var canGoBack: Bool { (current ?? 0) > 0 }
    var canGoForward: Bool { current.map { $0 < matches.count - 1 } ?? false }

    /// The query trimmed, if it's worth searching: two characters as you
    /// type, one on Return.
    func searchable(submitted: Bool) -> String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= (submitted ? 1 : 2) ? text : nil
    }

    /// A new search; returns its token.
    func begin(_ text: String) -> Int {
        token += 1
        searched = text
        matches = []
        groups = []
        current = nil
        isTruncated = false
        isSearching = true
        return token
    }

    func receive(_ batch: ReaderMessage.SearchBatch) {
        guard batch.token == token, isSearching else { return }
        group(batch.matches)
        if batch.done {
            isSearching = false
            isTruncated = batch.truncated
        }
    }

    func show(_ index: Int) {
        guard matches.indices.contains(index) else { return }
        current = index
    }

    /// Clears everything, the query included (✕ on the step bar).
    func end() {
        token += 1
        query = ""
        searched = nil
        matches = []
        groups = []
        current = nil
        isSearching = false
        isTruncated = false
    }

    /// The field emptied: no results, nothing shown.
    func clear() {
        token += 1
        searched = nil
        matches = []
        groups = []
        current = nil
        isSearching = false
        isTruncated = false
    }
}
