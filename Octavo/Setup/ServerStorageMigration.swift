import Foundation
import OctavoKit

/// Moves an install from one server to the list (decision 36,
/// `docs/notes/more-than-one-server.md`). With one server, a book's file,
/// place and bookmarks were kept under its file's ID alone
/// (`LibraryFile.storageKey`), and they're now kept under the server's ID as
/// well (`storageKey(in:)`). Runs once at launch while `Server.json` or
/// `RemovedServer.json` is there, and each is deleted last, so a launch cut
/// short does the rest next time: what has moved no longer has the old name,
/// and the rest goes under the same ID.
///
/// - A saved server's: everything under a plain name but the imported books',
///   which stay as they are, is the server's.
/// - No saved server, but one removed with its books kept: everything is that
///   one's, under an ID made for it, as if it had been removed since.
/// - Neither: nothing has a server to go to, and nothing moves.
///
/// Only a development install can need this: no release has had one server.
nonisolated struct ServerStorageMigration: Sendable {
    var servers: ServerStore
    var removed = RemovedServerStore()
    var books = StoredBookFiles()
    var positions = ReadingPositionStore()
    var bookmarks = BookmarkStore()
    var onIPhone = BooksOnIPhone()

    func run() throws {
        let legacy: SavedServer?
        do {
            legacy = try servers.readLegacy()
        } catch is DecodingError where FileManager.default.fileExists(atPath: servers.fileURL.path) {
            // Unreadable, and a server added since has started the list.
            try servers.removeLegacy()
            return
        }
        if let legacy {
            try move(to: legacy.id)
            // A list saved already (only by a launch that couldn't run this,
            // as before the first unlock) stays; else it starts with this one.
            if !FileManager.default.fileExists(atPath: servers.fileURL.path) {
                try servers.save(SavedServers(servers: [legacy], chosen: legacy.id))
            }
            removed.removeLegacy()
            try servers.removeLegacy()
        } else if removed.hasLegacyFile {
            if let identity = removed.readLegacyIdentity() {
                // Listed first, so a launch cut short carries on under the
                // same ID.
                let id = removed.load().first { $0.identity == identity }?.id ?? LibrarySourceID(rawValue: "removed-\(UUID().uuidString)")
                try removed.add(RemovedServer(identity: identity, id: id))
                try move(to: id)
            }
            removed.removeLegacy()
        }
    }

    /// Gives every book under a plain name, but the imported ones, to `id`.
    private func move(to id: LibrarySourceID) throws {
        let imported = importedKeys()
        var failure: (any Error)?
        for directory in [books.directory, positions.directory, positions.tripsDirectory, bookmarks.directory] {
            do {
                try Self.moveFiles(in: directory, keeping: imported, to: id)
            } catch {
                failure = failure ?? error
            }
        }
        moveUnsent(keeping: imported, to: id)
        // A book was kept as this server's, whichever ID it was first listed
        // under. Not one of a server added since (a launch that couldn't run
        // this), whose files already have its name.
        let others = Set(servers.load().servers.map(\.id) + removed.load().map(\.id)).subtracting([id])
        let records = onIPhone.books()
        var seen = Set<SourcedBook.ID>()
        try onIPhone.replace(records.compactMap { record in
            let isOwn = record.source != .files && !others.contains(record.source)
            let book = isOwn ? SourcedBook(source: id, book: record.book) : record
            return seen.insert(book.id).inserted ? book : nil
        })
        if let failure { throw failure }
    }

    private func importedKeys() -> Set<String> {
        var keys = Set(books.imported.all().compactMap { $0.book.primaryFile?.storageKey })
        // Its place stays, even if the book was removed.
        if let sample = SampleBook.book.primaryFile?.storageKey { keys.insert(sample) }
        return keys
    }

    /// Plain names are `book-` and a hash; anything else in the folder (the
    /// unsent places, a list) isn't a book's.
    private static func moveFiles(in directory: URL, keeping imported: Set<String>, to id: LibrarySourceID) throws {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        let prefix = StoredBookKeys.prefix(of: id)
        var failure: (any Error)?
        for name in names where name.hasPrefix("book-") && !imported.contains((name as NSString).deletingPathExtension) {
            let target = directory.appending(path: prefix + name, directoryHint: .notDirectory)
            guard !manager.fileExists(atPath: target.path) else { continue }
            do {
                try manager.moveItem(at: directory.appending(path: name, directoryHint: .notDirectory), to: target)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
    }

    /// The places waiting to go are the server's, under their new names. A
    /// book listed under an old ID of the same server goes under this one.
    private func moveUnsent(keeping imported: Set<String>, to id: LibrarySourceID) {
        let file = UnsentPlaces(directory: positions.directory)
        let unsent = file.load()
        guard !unsent.isEmpty else { return }
        var moved: [String: SourcedBook] = [:]
        for (key, book) in unsent {
            if imported.contains(key) || !key.hasPrefix("book-") {
                moved[key] = book
            } else {
                moved[StoredBookKeys.prefix(of: id) + key] = SourcedBook(source: id, book: book.book)
            }
        }
        file.save(moved)
    }
}
