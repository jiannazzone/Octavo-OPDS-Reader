import Foundation
import OctavoKit

/// The server added in setup (decision 1: one in v1), as the app keeps it
/// between launches. Secrets aren't here: BookOrbit's tokens, an OPDS
/// password, a catalog's key and a trusted certificate are in the Keychain
/// under `id` (`ServerCredentials`).
nonisolated struct SavedServer: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case bookOrbit, opds
    }

    var id: LibrarySourceID
    var kind: Kind
    /// BookOrbit: the server's root. OPDS: the catalog's address, any secret
    /// it carries (Kavita's API key) written as `OPDSURLSecret.placeholder`.
    var address: String
    /// "BookOrbit", or the catalog's own name.
    var name: String
    var username: String?
    /// How an OPDS catalog asked for its password, recorded when it was
    /// added so a later answer can't ask for a weaker one.
    var authScheme: HTTPAuthScheme?
    /// Reading progress syncs with this BookOrbit server (decision 6). Off,
    /// the iPhone keeps its own place and ignores the server's. Only counts
    /// while setup offers the choice (`offersSyncChoice`).
    var syncsProgress = false

    /// Setup doesn't offer "Don't sync" for now (Adam, 2026-11-02): it skips
    /// the Reading progress step and every BookOrbit server syncs, whatever
    /// an earlier setup saved. Set to bring the step and the choice back.
    static let offersSyncChoice = false

    /// Whether this server's reading progress syncs.
    var progressSyncs: Bool { syncsProgress || !Self.offersSyncChoice }

    /// A new server's ID, before anything is stored under it.
    static func newID() -> LibrarySourceID {
        LibrarySourceID(rawValue: "server-\(UUID().uuidString)")
    }

    /// "books.example.com · adam", for Settings.
    var detail: String {
        let url = URL(string: address.replacingOccurrences(of: OPDSURLSecret.placeholder, with: "key"))
        let host = url.flatMap { url in url.host().map { host in url.port.map { "\(host):\($0)" } ?? host } } ?? address
        return [host, username].compactMap { $0 }.joined(separator: " · ")
    }

    /// The server's library, with its secrets from the Keychain. `nil` if
    /// the address no longer reads, or a catalog's key is gone (the
    /// Keychain was wiped): setup starts again.
    func libraryServer() -> LibraryServer? {
        switch kind {
        case .bookOrbit:
            guard let url = URL(string: address) else { return nil }
            let client = Self.bookOrbitClient(id: id, url: url)
            return LibraryServer(
                id: id, name: name, detail: detail, source: BookOrbitSource(client: client, includesProgress: progressSyncs),
                previewSource: BookOrbitSource(client: client, pageSize: 3, includesProgress: progressSyncs),
                syncsProgress: progressSyncs
            )
        case .opds:
            let secret = try? KeychainCatalogSecretStore(serverID: id.rawValue).load()
            if address.contains(OPDSURLSecret.placeholder), secret == nil { return nil }
            guard let url = URL(string: secret?.restore(address) ?? address) else { return nil }
            let source = Self.opdsSource(id: id, url: url, scheme: authScheme, secret: secret)
            return LibraryServer(id: id, name: name, detail: detail, source: source)
        }
    }

    static let deviceLabel = "Octavo"

    static func bookOrbitClient(id: LibrarySourceID, url: URL) -> BookOrbitClient {
        let pin = try? KeychainCertificatePinStore(serverID: id.rawValue).load()
        return BookOrbitClient(
            baseURL: url,
            tokenStore: KeychainBookOrbitTokenStore(serverID: id.rawValue),
            deviceLabel: deviceLabel,
            transport: ServerTransport(server: url, pin: pin)
        )
    }

    static func opdsSource(id: LibrarySourceID, url: URL, scheme: HTTPAuthScheme?, secret: OPDSURLSecret?) -> OPDSSource {
        let pin = try? KeychainCertificatePinStore(serverID: id.rawValue).load()
        let passwords = KeychainPasswordStore(serverID: id.rawValue)
        return OPDSSource(
            catalogURL: url,
            transport: ServerTransport(server: url, pin: pin, passwords: passwords, authScheme: scheme),
            credentials: passwords,
            authScheme: scheme,
            secret: secret
        )
    }
}

/// Where the server is kept: one small JSON file, written atomically. It's
/// deleted with the app, and the Keychain's leftovers go on the first launch
/// after a reinstall, so a reinstall starts at setup.
nonisolated struct ServerStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "Server.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
    }

    func load() -> SavedServer? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SavedServer.self, from: data)
    }

    func save(_ server: SavedServer) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(server).write(to: fileURL, options: .atomic)
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

/// An address as someone typed it, made into one Octavo can use (the
/// follow-ups in `docs/notes/network-trust.md`): a scheme if it has none
/// (http for a home address, else https), the host lowercased without a
/// trailing dot (`URL` writes an international name as `xn--`), and any
/// `user:password@` moved out to the account fields. Whether the address
/// may be used is `ServerTransport`'s to say, on every request.
nonisolated enum ServerAddress {
    struct Parsed: Equatable {
        var url: URL
        var username: String?
        var password: String?

        /// Plain http: shown as "Not encrypted" under the field.
        var isPlainHTTP: Bool { url.scheme == "http" }
    }

    enum Problem: Error, Equatable {
        case empty
        case notAnAddress
        /// Not http or https.
        case unsupportedScheme
    }

    static func parse(_ text: String) throws(Problem) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        var written = trimmed
        if trimmed.range(of: "://") == nil {
            // Judged by the host as it will be: without an account or a
            // trailing dot (`adam@nas.lan.` is at home).
            var probe = URLComponents(string: "http://\(trimmed)")
            probe?.user = nil
            probe?.password = nil
            if var host = probe?.host?.lowercased() {
                while host.hasSuffix(".") { host.removeLast() }
                probe?.host = host
            }
            let local = probe?.url.map(HomeNetworkPolicy.isLocalAddress) ?? false
            written = (local ? "http://" : "https://") + trimmed
        }
        guard var components = URLComponents(string: written), let scheme = components.scheme?.lowercased() else {
            throw .notAnAddress
        }
        guard scheme == "http" || scheme == "https" else { throw .unsupportedScheme }
        components.scheme = scheme
        let username = components.user?.removingPercentEncoding
        let password = components.password?.removingPercentEncoding
        components.user = nil
        components.password = nil
        components.fragment = nil
        guard var host = components.host?.lowercased(), !host.isEmpty else { throw .notAnAddress }
        while host.hasSuffix(".") { host.removeLast() }
        components.host = host
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let url = components.url, url.host() != nil else { throw .notAnAddress }
        return Parsed(url: url, username: username, password: password)
    }
}
