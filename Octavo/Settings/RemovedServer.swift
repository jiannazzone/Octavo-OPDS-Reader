import Foundation
import OctavoKit

/// A server Remove server took away, whose kept books, places and bookmarks
/// are still on the iPhone under its ID. The same server and account coming
/// back, at its new ID, finds them again ("Keep books on iPhone"); any other
/// server has its own, so finds none of them (security review, 2026-11-02).
nonisolated struct RemovedServer: Codable, Equatable, Sendable {
    /// `LibraryServer.identity`.
    var identity: String
    /// The ID its books are kept under.
    var id: LibrarySourceID
}

/// One small JSON file, written atomically.
nonisolated struct RemovedServerStore: Sendable {
    let fileURL: URL
    /// From when there was one server: its kept books had no ID of their own
    /// until `ServerStorageMigration` gave them one.
    let legacyFileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "RemovedServers.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
        legacyFileURL = fileURL.deletingLastPathComponent().appending(path: "RemovedServer.json", directoryHint: .notDirectory)
    }

    func load() -> [RemovedServer] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([RemovedServer].self, from: data)) ?? []
    }

    func add(_ server: RemovedServer) throws {
        try save(load().filter { $0.identity != server.identity } + [server])
    }

    func remove(_ server: RemovedServer) throws {
        try save(load().filter { $0 != server })
    }

    private func save(_ servers: [RemovedServer]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(servers).write(to: fileURL, options: .atomic)
    }

    /// The identity in `RemovedServer.json`, if there's one.
    func readLegacyIdentity() -> String? {
        struct Legacy: Decodable { var identity: String }
        guard let data = try? Data(contentsOf: legacyFileURL) else { return nil }
        return (try? JSONDecoder().decode(Legacy.self, from: data))?.identity
    }

    var hasLegacyFile: Bool {
        FileManager.default.fileExists(atPath: legacyFileURL.path)
    }

    func removeLegacy() {
        try? FileManager.default.removeItem(at: legacyFileURL)
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

    /// Whether this server could ever be recognised again: not a catalog with
    /// a key (`origin(kind:address:secret:)`).
    nonisolated var canReturn: Bool {
        !(origin ?? "").contains(LibraryServer.unmatchedMark)
    }

    private nonisolated static var unmatchedMark: String { "|key:" }

    /// `origin` for a server at `address` (as saved: scheme, host, port and
    /// path, a catalog's secret as its placeholder): "bookOrbit|https://…".
    /// Two Kavita accounts on one server differ only by their keys, and
    /// nothing derived from a key is kept outside the Keychain, so a catalog
    /// with a key never counts as the same server again.
    nonisolated static func origin(kind: SavedServer.Kind, address: String, secret: OPDSURLSecret? = nil) -> String {
        let unmatched = secret == nil ? "" : "\(unmatchedMark)\(UUID().uuidString)"
        return "\(kind.rawValue)|\(address)\(unmatched)"
    }
}
