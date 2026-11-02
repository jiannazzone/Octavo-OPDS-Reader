import Foundation

/// The books whose place this iPhone may still owe the server, by the key
/// their position is saved under. A saved position knows only that key, so
/// this remembers the book behind it, for sending the place without its
/// screen showing (`BookPlaces.retryUnsent`).
///
/// A book goes in when the reader opens it with sync, and comes out once
/// its place is sent. Kept beside the positions, so a place read offline
/// still goes after a relaunch.
nonisolated struct UnsentPlaces: Sendable {
    let fileURL: URL

    /// In `directory`'s own folder, apart from the positions' files.
    init(directory: URL) {
        fileURL = directory.appending(path: "Unsent", directoryHint: .isDirectory).appending(path: "places.json")
    }

    func load() -> [String: SourcedBook] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: SourcedBook].self, from: data)) ?? [:]
    }

    func save(_ books: [String: SourcedBook]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(books).write(to: fileURL, options: .atomic)
        } catch {
            // Lost, the place still goes when its book's screen shows.
        }
    }
}
