import Foundation
import OctavoKit

/// Keeps the last reading position per book on disk, one small JSON file per
/// book, written atomically so a killed app never leaves a torn file.
///
/// Local only. Syncing to a server is a `ProgressSync` backend's job; the
/// store just remembers whether the latest position still needs a push.
nonisolated struct ReadingPositionStore: Sendable {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "ReadingPositions", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func position(forBook bookID: String) -> ReadingPosition? {
        progress(forBook: bookID)?.position
    }

    /// Files written before sync existed hold a bare `ReadingPosition`; they
    /// read back as already pushed.
    func progress(forBook bookID: String) -> LocalReadingProgress? {
        guard let data = try? Data(contentsOf: fileURL(forBook: bookID)) else { return nil }
        if let progress = try? JSONDecoder().decode(LocalReadingProgress.self, from: data) { return progress }
        guard let position = try? JSONDecoder().decode(ReadingPosition.self, from: data) else { return nil }
        return LocalReadingProgress(position: position, modifiedAt: .distantPast, needsPush: false)
    }

    /// The chapter of the saved position (`LocalReadingProgress.chapter`),
    /// for a book's place line.
    func chapter(forBook bookID: String) -> String? {
        progress(forBook: bookID)?.chapter
    }

    /// `syncedAt` defaults to the saved record's: moving on keeps the time of
    /// the last sync.
    func save(
        _ position: ReadingPosition, forBook bookID: String, needsPush: Bool = false, chapter: String? = nil, syncedAt: Date? = nil
    ) throws {
        let syncedAt = syncedAt ?? progress(forBook: bookID)?.syncedAt
        let progress = LocalReadingProgress(position: position, modifiedAt: .now, needsPush: needsPush, chapter: chapter, syncedAt: syncedAt)
        try save(progress, forBook: bookID)
    }

    func save(_ progress: LocalReadingProgress, forBook bookID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(progress).write(to: fileURL(forBook: bookID), options: .atomic)
    }

    /// `position` reached the backend at `date`: clears `needsPush` and
    /// records the sync, if `position` is still the saved one.
    func markPushed(_ position: ReadingPosition, forBook bookID: String, at date: Date = .now) throws {
        guard var progress = progress(forBook: bookID), progress.position == position else { return }
        progress.needsPush = false
        progress.syncedAt = date
        try save(progress, forBook: bookID)
    }

    func removePosition(forBook bookID: String) {
        try? FileManager.default.removeItem(at: fileURL(forBook: bookID))
        saveTrip(nil, forBook: bookID)
    }

    // MARK: Trips (decision 33)

    /// Kept beside the positions, and never synced.
    var tripsDirectory: URL {
        directory.appending(path: "Trips", directoryHint: .isDirectory)
    }

    func trip(forBook bookID: String) -> ReaderTrip? {
        guard let data = try? Data(contentsOf: Self.fileURL(forBook: bookID, in: tripsDirectory)) else { return nil }
        return try? JSONDecoder().decode(ReaderTrip.self, from: data)
    }

    /// `nil` ends it.
    func saveTrip(_ trip: ReaderTrip?, forBook bookID: String) {
        let url = Self.fileURL(forBook: bookID, in: tripsDirectory)
        guard let trip else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: tripsDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(trip).write(to: url, options: .atomic)
    }

    /// Every place and trip of `library`'s books.
    func removeAll(of library: LibrarySourceID) {
        StoredBookKeys.removeFiles(of: library, in: directory)
        StoredBookKeys.removeFiles(of: library, in: tripsDirectory)
    }

    /// Gives `library`'s places and trips to `other` (`RemovedServer`).
    func moveAll(of library: LibrarySourceID, to other: LibrarySourceID) {
        StoredBookKeys.moveFiles(of: library, to: other, in: directory)
        StoredBookKeys.moveFiles(of: library, to: other, in: tripsDirectory)
    }

    /// Book IDs can be file names or server IDs; percent-encode anything that
    /// isn't safe in a file name.
    func fileURL(forBook bookID: String) -> URL {
        Self.fileURL(forBook: bookID, in: directory)
    }

    /// The JSON file for `bookID` in `directory`; `BookmarkStore` names its
    /// files the same way.
    static func fileURL(forBook bookID: String, in directory: URL) -> URL {
        let safe = bookID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? bookID
        return directory.appending(path: safe + ".json", directoryHint: .notDirectory)
    }
}
