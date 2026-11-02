import CryptoKit
import Foundation
import OctavoKit

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
    /// the kind and full address (`origin`), else the shown address, then
    /// the account. Another account on the same server is another identity,
    /// as its places are its own.
    nonisolated var identity: String {
        "\(origin ?? address.lowercased())|\(username ?? "")"
    }

    /// `origin` for a server at `address` (as saved: scheme, host, port and
    /// path, a catalog's secret as its placeholder): "bookOrbit|https://…",
    /// with a digest of that secret, so two Kavita accounts on one server
    /// (told apart only by their keys) are two identities.
    nonisolated static func origin(kind: SavedServer.Kind, address: String, secret: OPDSURLSecret? = nil) -> String {
        let digest = secret.map { secret in
            "|" + SHA256.hash(data: Data(secret.value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        }
        return "\(kind.rawValue)|\(address)\(digest ?? "")"
    }
}
