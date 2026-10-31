import Foundation
import OctavoKit

/// Keeps the last reading position per book on disk, one small JSON file per
/// book, written atomically so a killed app never leaves a torn file.
///
/// Local only. Syncing to a server is a `ProgressSync` backend's job.
nonisolated struct ReadingPositionStore: Sendable {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "ReadingPositions", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func position(forBook bookID: String) -> ReadingPosition? {
        guard let data = try? Data(contentsOf: fileURL(forBook: bookID)) else { return nil }
        return try? JSONDecoder().decode(ReadingPosition.self, from: data)
    }

    func save(_ position: ReadingPosition, forBook bookID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(position).write(to: fileURL(forBook: bookID), options: .atomic)
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
