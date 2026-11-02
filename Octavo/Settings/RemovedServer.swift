import Foundation

/// The server Remove server took away, kept until the next one is added
/// (security review, 2026-11-02). A book's file, place and bookmarks are kept
/// by its file's ID alone, and BookOrbit numbers its files from 1 on every
/// server, so another server's book 17 would otherwise find a removed
/// server's: shown as downloaded, opened at its place, its bookmarks and
/// unsent place sent to the wrong server. The same server and account
/// coming back finds its books, places and bookmarks again ("Keep books on
/// iPhone"); any other finds none of them.
nonisolated struct RemovedServer: Codable, Equatable, Sendable {
    /// `LibraryServer.identity`.
    var identity: String
}

/// One small JSON file, written atomically.
nonisolated struct RemovedServerStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "RemovedServer.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
    }

    func load() -> RemovedServer? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(RemovedServer.self, from: data)
    }

    func save(_ server: RemovedServer) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(server).write(to: fileURL, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension LibraryServer {
    /// Which server and account this is, whatever ID it was added under:
    /// "books.example.com|adam". Another account on the same server is
    /// another identity, as its places are its own.
    nonisolated var identity: String {
        "\(address.lowercased())|\(username ?? "")"
    }
}
