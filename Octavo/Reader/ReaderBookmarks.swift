import Foundation
import OctavoKit
import os

/// Keeps each book's bookmarks on disk, one small JSON file per book, like
/// `ReadingPositionStore`. Synced bookmarks are kept too, so the list works
/// offline.
nonisolated struct BookmarkStore: Sendable {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Bookmarks", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func bookmarks(forBook bookID: String) -> [LocalBookmark] {
        guard let data = try? Data(contentsOf: fileURL(forBook: bookID)) else { return [] }
        return (try? JSONDecoder().decode([LocalBookmark].self, from: data)) ?? []
    }

    func save(_ bookmarks: [LocalBookmark], forBook bookID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(bookmarks).write(to: fileURL(forBook: bookID), options: .atomic)
    }

    func fileURL(forBook bookID: String) -> URL {
        ReadingPositionStore.fileURL(forBook: bookID, in: directory)
    }
}

/// Where a bookmark falls and what it starts with, worked out from the book
/// (`bridge.js` `describe`).
nonisolated struct BookmarkPlace: Codable, Equatable, Sendable {
    var fraction: Double?
    var chapter: String?
    var excerpt: String?
}

/// One book's bookmarks (decisions 17–18): kept on the iPhone, and synced
/// with BookOrbit for its books. Changes show at once and sync behind;
/// a change that can't reach the server waits for the next open.
@Observable
final class ReaderBookmarks {
    /// Everything kept, removals still to sync included.
    private(set) var all: [LocalBookmark]
    /// The bookmarks on the visible page (both pages of a spread).
    private(set) var onPage: Set<LocalBookmark.ID> = []

    @ObservationIgnored let bookID: String
    @ObservationIgnored private let store: BookmarkStore
    @ObservationIgnored private let sync: (any BookmarkSync)?
    /// Adds and removals on their way, so a refresh doesn't send them twice.
    @ObservationIgnored private var sending: Set<LocalBookmark.ID> = []
    @ObservationIgnored private let log = Logger(subsystem: "com.ianazzone.ereader", category: "Bookmarks")

    init(bookID: String, store: BookmarkStore = BookmarkStore(), sync: (any BookmarkSync)? = nil) {
        self.bookID = bookID
        self.store = store
        self.sync = sync
        all = store.bookmarks(forBook: bookID)
    }

    /// The list, in the book's order.
    var list: [LocalBookmark] {
        all.filter { !$0.isRemoved }.sorted {
            ($0.fraction ?? .infinity, $0.createdAt) < ($1.fraction ?? .infinity, $1.createdAt)
        }
    }

    var pageIsBookmarked: Bool { !onPage.isEmpty }

    /// Bookmarks the list can't place yet (synced from elsewhere, or moved).
    var undescribed: [LocalBookmark] { all.filter { !$0.isRemoved && !$0.isDescribed } }

    func setOnPage(_ ids: Set<LocalBookmark.ID>) {
        if ids != onPage { onPage = ids }
    }

    func describe(_ id: LocalBookmark.ID, as place: BookmarkPlace) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].fraction = place.fraction
        all[index].chapter = place.chapter ?? all[index].chapter
        all[index].excerpt = place.excerpt
        save()
    }

    /// Bookmarks placed again in the current layout.
    func place(_ fractions: [LocalBookmark.ID: Double]) {
        var changed = false
        for (id, fraction) in fractions {
            guard let index = all.firstIndex(where: { $0.id == id }), all[index].fraction != fraction else { continue }
            all[index].fraction = fraction
            changed = true
        }
        if changed { save() }
    }

    /// Bookmarks the page starting at `cfi`.
    @discardableResult
    func add(cfi: String, place: BookmarkPlace?) -> LocalBookmark {
        let bookmark = LocalBookmark(cfi: cfi, chapter: place?.chapter, excerpt: place?.excerpt, fraction: place?.fraction)
        all.append(bookmark)
        onPage.insert(bookmark.id)
        save()
        Task { await send(bookmark.id) }
        return bookmark
    }

    func remove(_ id: LocalBookmark.ID) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        onPage.remove(id)
        // An add on its way removes it once the server has answered.
        if all[index].remoteID == nil, !sending.contains(id) {
            all.remove(at: index)
        } else {
            all[index].isRemoved = true
        }
        save()
        Task { await send(id) }
    }

    /// The page's Bookmark button: removes the page's bookmarks, or adds one
    /// where the page starts.
    func toggle(pageStart cfi: String?, place: BookmarkPlace?) {
        if pageIsBookmarked {
            for id in onPage { remove(id) }
        } else if let cfi {
            add(cfi: cfi, place: place)
        }
    }

    /// The server's bookmarks merged in and changes made offline sent.
    func refresh() async {
        guard let sync else { return }
        let remote: [SyncedBookmark]
        do {
            remote = try await sync.bookmarks()
        } catch {
            log.error("Couldn't fetch bookmarks: \(error)")
            return
        }
        let result = BookmarkReconciliation.reconcile(local: all, remote: remote)
        // One whose add is still on its way stays, so its answer finds it
        // (and removes it from the server, if it was removed meanwhile).
        let inFlight = all.filter { bookmark in sending.contains(bookmark.id) && !result.bookmarks.contains { $0.id == bookmark.id } }
        all = result.bookmarks + inFlight
        onPage = onPage.filter { id in all.contains { $0.id == id && !$0.isRemoved } }
        save()
        for id in result.toAdd where !sending.contains(id) { await send(id) }
        for id in all.filter({ $0.isRemoved }).map(\.id) where !sending.contains(id) { await send(id) }
    }

    /// Sends one bookmark's add or removal, if it has one waiting.
    private func send(_ id: LocalBookmark.ID) async {
        guard let sync, !sending.contains(id), let bookmark = all.first(where: { $0.id == id }) else { return }
        sending.insert(id)
        defer { sending.remove(id) }
        do {
            if bookmark.isRemoved, let remoteID = bookmark.remoteID {
                try await sync.remove(id: remoteID)
                all.removeAll { $0.id == id }
            } else if !bookmark.isRemoved, bookmark.remoteID == nil {
                let synced = try await sync.add(cfi: bookmark.cfi, title: Self.title(for: bookmark))
                guard let index = all.firstIndex(where: { $0.id == id }) else { return }
                all[index].remoteID = synced.id
                // Kept before anything else can fail, so a removal that
                // doesn't get through is retried rather than forgotten.
                save()
                // Removed while the add was on its way.
                if all[index].isRemoved {
                    try await sync.remove(id: synced.id)
                    all.removeAll { $0.id == id }
                }
            } else {
                return
            }
            save()
        } catch {
            log.error("Couldn't sync a bookmark: \(error)")
        }
    }

    /// What BookOrbit's web reader lists: the chapter, else the first words.
    static func title(for bookmark: LocalBookmark) -> String {
        if let chapter = bookmark.chapter, !chapter.isEmpty { return chapter }
        if let excerpt = bookmark.excerpt, !excerpt.isEmpty { return String(excerpt.prefix(80)) }
        return String(localized: "Bookmark", comment: "A bookmark's title on the server when its page has no chapter or words")
    }

    private func save() {
        do {
            try store.save(all, forBook: bookID)
        } catch {
            log.error("Couldn't save bookmarks: \(error)")
        }
    }
}
