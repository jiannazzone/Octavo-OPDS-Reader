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

    func save(_ position: ReadingPosition, forBook bookID: String, needsPush: Bool = false, chapter: String? = nil) throws {
        try save(LocalReadingProgress(position: position, modifiedAt: .now, needsPush: needsPush, chapter: chapter), forBook: bookID)
    }

    func save(_ progress: LocalReadingProgress, forBook bookID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(progress).write(to: fileURL(forBook: bookID), options: .atomic)
    }

    /// Clears `needsPush` if `position` is still the saved one.
    func markPushed(_ position: ReadingPosition, forBook bookID: String) throws {
        guard var progress = progress(forBook: bookID), progress.position == position, progress.needsPush else { return }
        progress.needsPush = false
        try save(progress, forBook: bookID)
    }

    func removePosition(forBook bookID: String) {
        try? FileManager.default.removeItem(at: fileURL(forBook: bookID))
    }

    /// Book IDs can be file names or server IDs; percent-encode anything that
    /// isn't safe in a file name.
    func fileURL(forBook bookID: String) -> URL {
        let safe = bookID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? bookID
        return directory.appending(path: safe + ".json", directoryHint: .notDirectory)
    }
}
