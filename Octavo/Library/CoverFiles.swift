import CryptoKit
import Foundation
import OctavoKit

/// Covers kept on the iPhone, so a launch doesn't fetch them all again.
///
/// In Caches: out of the backup, and iOS can clear it when it needs the room.
/// A server's covers are in a folder of their own, which goes when the server
/// does. Each is named by a hash of its key, since a cover's key can hold an
/// address, and an address can hold a secret.
nonisolated struct CoverFiles: Sendable {
    /// All the covers together, trimmed at launch. A cover that's gone is
    /// fetched again when it's next shown.
    static let limit = 500 * 1024 * 1024
    /// How long a cover whose source can't say when it changes
    /// (`LibraryCover.version`) goes before it's fetched again.
    static let refreshAge: TimeInterval = 24 * 60 * 60

    let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "Covers", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    @concurrent func read(_ key: String, in source: LibrarySourceID) async -> Data? {
        try? Data(contentsOf: url(for: key, in: source))
    }

    @concurrent func write(_ data: Data, as key: String, in source: LibrarySourceID) async {
        try? FileManager.default.createDirectory(at: folder(of: source), withIntermediateDirectories: true)
        try? data.write(to: url(for: key, in: source), options: .atomic)
    }

    /// Whether the cover was written less than `refreshAge` ago.
    @concurrent func isRecent(_ key: String, in source: LibrarySourceID, now: Date = .now) async -> Bool {
        let values = try? url(for: key, in: source).resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate.map { now.timeIntervalSince($0) < Self.refreshAge } ?? false
    }

    @concurrent func removeAll(in source: LibrarySourceID) async {
        try? FileManager.default.removeItem(at: folder(of: source))
    }

    /// Removes the covers written longest ago until the rest fit in `limit`.
    @concurrent func trim(to limit: Int = Self.limit) async {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let found = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys))?.allObjects as? [URL] ?? []
        let covers = found.compactMap { file -> (file: URL, size: Int, written: Date)? in
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let size = values.fileSize, let written = values.contentModificationDate
            else { return nil }
            return (file, size, written)
        }
        var total = covers.reduce(0) { $0 + $1.size }
        for cover in covers.sorted(by: { $0.written < $1.written }) {
            guard total > limit else { return }
            try? FileManager.default.removeItem(at: cover.file)
            total -= cover.size
        }
    }

    func url(for key: String, in source: LibrarySourceID) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder(of: source).appending(path: name, directoryHint: .notDirectory)
    }

    func folder(of source: LibrarySourceID) -> URL {
        directory.appending(path: source.rawValue, directoryHint: .isDirectory)
    }
}
