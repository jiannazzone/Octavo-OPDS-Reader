import Foundation
import OctavoKit

/// BookOrbit books whose highlights have changes still to send (#125), so
/// they're retried with the reader closed: at launch, when the app comes
/// back and when the connection does, as places are
/// (`BookPlaces.retryUnsent`). The open book's go through its reader.
///
/// It also hands out each book's `ReaderHighlights`, one at a time per book,
/// so a retry and a reader opening the same book share one list rather than
/// saving over each other.
@MainActor
final class HighlightsWaiting {
    /// Where a book's highlights sync.
    struct Book: Codable, Hashable, Sendable {
        var source: LibrarySourceID
        var bookID: Int
        var fileID: Int
    }

    private let store: HighlightStore
    private let fileURL: URL
    private let sync: (Book) -> (any HighlightSync)?
    private var books: [String: Book]
    private var isRetrying = false
    private var live: [String: Weak] = [:]

    private struct Weak {
        weak var highlights: ReaderHighlights?
    }

    init(store: HighlightStore = HighlightStore(), sync: @escaping (Book) -> (any HighlightSync)?) {
        self.store = store
        self.sync = sync
        // In the store's own folder, apart from the books' files.
        fileURL = store.directory.appending(path: "Unsent", directoryHint: .isDirectory).appending(path: "books.json")
        books = (try? JSONDecoder().decode([String: Book].self, from: Data(contentsOf: fileURL))) ?? [:]
    }

    /// The reader opened `key`'s highlights with a sync: changes it leaves
    /// unsent go here.
    func record(_ book: Book, key: String) {
        guard books[key] != book else { return }
        books[key] = book
        save()
    }

    /// `key`'s highlights: the list already in use, if there is one, else a
    /// new one syncing with `sync`.
    func highlights(forBook key: String, sync: (any HighlightSync)?) -> ReaderHighlights {
        if let inUse = live[key]?.highlights { return inUse }
        let highlights = ReaderHighlights(bookID: key, store: store, sync: sync)
        live = live.filter { $0.value.highlights != nil }
        live[key] = Weak(highlights: highlights)
        return highlights
    }

    func retry(except open: String? = nil) async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        for (key, book) in books where key != open {
            guard hasWaiting(key) else {
                books[key] = nil
                continue
            }
            // Its server isn't connected (or was removed): kept for later.
            guard let backend = sync(book) else { continue }
            await highlights(forBook: key, sync: backend).refresh()
            if !hasWaiting(key) { books[key] = nil }
        }
        save()
    }

    var waitingKeys: Set<String> { Set(books.keys) }

    private func hasWaiting(_ key: String) -> Bool {
        store.items(forBook: key).contains(where: \.isWaiting)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(books).write(to: fileURL, options: .atomic)
        } catch {
            // Lost, the changes still go when the book next opens.
        }
    }
}
