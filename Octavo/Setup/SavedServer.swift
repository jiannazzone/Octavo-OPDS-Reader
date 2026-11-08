import Foundation
import OctavoKit

/// A server added in setup (decisions 1 and 36), as the app keeps it between
/// launches. Secrets aren't here: BookOrbit's tokens, an OPDS
/// password, a catalog's key and a trusted certificate are in the Keychain
/// under `id` (`ServerCredentials`).
nonisolated struct SavedServer: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case bookOrbit, opds
    }

    var id: LibrarySourceID
    var kind: Kind
    /// BookOrbit: the server's root. OPDS: the catalog's address, any secret
    /// it carries (Kavita's API key, a token in the query) written as a
    /// placeholder (`OPDSURLSecret`).
    var address: String
    /// "BookOrbit", or the catalog's own name, with a number if another
    /// server had that name when this one was added.
    var name: String
    /// The name you gave it (decision 36), kept on the iPhone. Optional, so a
    /// file saved before it existed still reads.
    var customName: String?
    var username: String?
    /// How an OPDS catalog asked for its password, recorded when it was
    /// added so a later answer can't ask for a weaker one.
    var authScheme: HTTPAuthScheme?
    /// Reading progress syncs with this BookOrbit server (decision 6). Off,
    /// the iPhone keeps its own place and ignores the server's. Only counts
    /// while setup offers the choice (`offersSyncChoice`).
    var syncsProgress = false
    /// Sign out was chosen, and nothing has signed in since. Saved before
    /// the sign-in is deleted, so the launch sweep (`KeychainSweep`) deletes
    /// it if the Keychain couldn't then. Optional, so a file saved before it
    /// existed still reads.
    var signedOut: Bool?
    /// A catalog's books sync their place with the KOReader account, while
    /// there is one (`docs/notes/koreader-sync-plan.md`, question 2).
    /// Optional, so a file saved before it existed still reads.
    var koreaderSync: Bool?

    /// Setup doesn't offer "Don't sync" for now (Adam, 2026-11-02): it skips
    /// the Reading progress step and every BookOrbit server syncs, whatever
    /// an earlier setup saved. Set to bring the step and the choice back.
    static let offersSyncChoice = false

    /// Whether this server's reading progress syncs.
    var progressSyncs: Bool { syncsProgress || !Self.offersSyncChoice }

    /// What the app calls it.
    var displayName: String { customName ?? name }

    /// A new server's ID, before anything is stored under it.
    static func newID() -> LibrarySourceID {
        LibrarySourceID(rawValue: "server-\(UUID().uuidString)")
    }

    /// "books.example.com · adam", for Settings.
    var detail: String {
        [host, username].compactMap { $0 }.joined(separator: " · ")
    }

    /// "books.example.com", "nas.local:8083": the server, without the path
    /// (or a secret in it).
    var host: String {
        let url = URL(string: OPDSURLSecret.masked(address))
        return url.flatMap { url in url.host().map { host in url.port.map { "\(host):\($0)" } ?? host } } ?? address
    }

    /// Whether this is the server at `url`, with this account. A catalog's
    /// key is put back to compare, and a key that can't be read matches
    /// nothing.
    func isAt(_ url: URL, username: String?) -> Bool {
        guard (self.username ?? "") == (username ?? "") else { return false }
        if OPDSURLSecret.isRedacted(address) {
            guard let secret = try? KeychainCatalogSecretStore(serverID: id.rawValue).load() else { return false }
            return secret.restore(address) == url.absoluteString
        }
        return address == url.absoluteString
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
                id: id, name: displayName, ownName: name, address: host, username: username, signsIn: true,
                origin: LibraryServer.origin(kind: kind, address: address),
                source: BookOrbitSource(client: client, includesProgress: progressSyncs),
                previewSource: BookOrbitSource(client: client, pageSize: 3, includesProgress: progressSyncs),
                syncsProgress: progressSyncs
            )
        case .opds:
            let secret = try? KeychainCatalogSecretStore(serverID: id.rawValue).load()
            if OPDSURLSecret.isRedacted(address), secret == nil { return nil }
            guard let url = URL(string: secret?.restore(address) ?? address) else { return nil }
            let source = Self.opdsSource(id: id, url: url, scheme: authScheme, secret: secret)
            return LibraryServer(
                id: id, name: displayName, ownName: name, address: host, username: username, signsIn: authScheme != nil,
                origin: LibraryServer.origin(kind: kind, address: address, secret: secret), source: source,
                syncsWithKOReader: koreaderSync == true
            )
        }
    }

    static let deviceLabel = "Octavo"

    /// The transports read the trusted certificate before their first
    /// request; a Keychain that can't be read fails the request rather than
    /// connecting without the pin (step 16).
    static func bookOrbitClient(id: LibrarySourceID, url: URL) -> BookOrbitClient {
        BookOrbitClient(
            baseURL: url,
            tokenStore: KeychainBookOrbitTokenStore(serverID: id.rawValue),
            deviceLabel: deviceLabel,
            transport: ServerTransport(server: url, pins: KeychainCertificatePinStore(serverID: id.rawValue))
        )
    }

    static func opdsSource(id: LibrarySourceID, url: URL, scheme: HTTPAuthScheme?, secret: OPDSURLSecret?) -> OPDSSource {
        let passwords = KeychainPasswordStore(serverID: id.rawValue)
        return OPDSSource(
            catalogURL: url,
            transport: ServerTransport(
                server: url, pins: KeychainCertificatePinStore(serverID: id.rawValue), passwords: passwords, authScheme: scheme
            ),
            credentials: passwords,
            authScheme: scheme,
            secret: secret
        )
    }
}

/// The servers added, in the order they were added, and the one the Library
/// shows (decision 36).
nonisolated struct SavedServers: Codable, Equatable, Sendable {
    var servers: [SavedServer] = []
    var chosen: LibrarySourceID?
    /// The KOReader sync account, while one is signed in. Optional, so a
    /// file saved before it existed still reads.
    var koreader: SavedKOReaderAccount?

    /// The Library's server: the one chosen, else the first.
    var chosenServer: SavedServer? {
        servers.first { $0.id == chosen } ?? servers.first
    }

    subscript(id: LibrarySourceID) -> SavedServer? {
        servers.first { $0.id == id }
    }

    /// The name a server calling itself `name` gets: its own, or "Calibre-Web
    /// 2" if another already goes by that.
    func uniqueName(_ name: String) -> String {
        let taken = Set(servers.flatMap { [$0.name, $0.displayName] })
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }
}

/// The KOReader sync account, as the list keeps it: only its ID. Its
/// address, username and key are in the Keychain under it
/// (`KeychainKOSyncAccountStore`), and its certificate's pin too.
nonisolated struct SavedKOReaderAccount: Codable, Hashable, Sendable {
    var id: String

    /// A new account's ID, before anything is stored under it.
    static func newID() -> String {
        "koreader-\(UUID().uuidString)"
    }
}

/// Where the servers are kept: one small JSON file, written atomically. It's
/// deleted with the app, and the Keychain's leftovers go on the first launch
/// after a reinstall, so a reinstall starts at setup.
///
/// An install from before there could be several has one server in
/// `Server.json`, which still reads as the list, until `ServerStorageMigration`
/// has moved it over.
nonisolated struct ServerStore: Sendable {
    let fileURL: URL
    let legacyFileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "Servers.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
        legacyFileURL = fileURL.deletingLastPathComponent().appending(path: "Server.json", directoryHint: .notDirectory)
    }

    /// There's a list, or a server from before there was one, readable or
    /// not: this install has run before.
    var hasFile: Bool {
        let manager = FileManager.default
        return manager.fileExists(atPath: fileURL.path) || manager.fileExists(atPath: legacyFileURL.path)
    }

    /// What's saved. Empty if it can't be read, as after a reinstall.
    func load() -> SavedServers {
        (try? read()) ?? SavedServers()
    }

    /// What's saved, empty if nothing is. Throws if a file is there but can't
    /// be read or decoded, which mustn't be taken for "no servers"
    /// (`KeychainSweep`).
    func read() throws -> SavedServers {
        do {
            return try JSONDecoder().decode(SavedServers.self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            guard let legacy = try readLegacy() else { return SavedServers() }
            return SavedServers(servers: [legacy], chosen: legacy.id)
        }
    }

    /// The one server in `Server.json`, `nil` if there isn't one.
    func readLegacy() throws -> SavedServer? {
        do {
            return try JSONDecoder().decode(SavedServer.self, from: Data(contentsOf: legacyFileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ saved: SavedServers) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: fileURL, options: .atomic)
    }

    /// Adds `server`, or replaces the one with its ID, and chooses it. A list
    /// that can't be decoded is replaced: nothing can be made of it, it reads
    /// as no servers, and the launch sweep can't run while it's there. A file
    /// that can't be read at all still throws, since it may be fine.
    func add(_ server: SavedServer) throws {
        var saved: SavedServers
        do {
            saved = try read()
        } catch is DecodingError {
            saved = SavedServers()
        }
        if let index = saved.servers.firstIndex(where: { $0.id == server.id }) {
            saved.servers[index] = server
        } else {
            saved.servers.append(server)
        }
        saved.chosen = server.id
        try save(saved)
    }

    /// Keeps the KOReader account, or forgets it (`nil`). Like `add`, a list
    /// that can't be decoded is replaced.
    func setKOReader(_ account: SavedKOReaderAccount?) throws {
        var saved: SavedServers
        do {
            saved = try read()
        } catch is DecodingError {
            saved = SavedServers()
        }
        saved.koreader = account
        try save(saved)
    }

    /// Changes the saved server `id`, if it's there.
    func update(_ id: LibrarySourceID, _ change: (inout SavedServer) -> Void) throws {
        var saved = try read()
        guard let index = saved.servers.firstIndex(where: { $0.id == id }) else { return }
        change(&saved.servers[index])
        try save(saved)
    }

    /// Takes `id` off the list. The list stays, empty if that was the last.
    func remove(_ id: LibrarySourceID) throws {
        var saved = try read()
        saved.servers.removeAll { $0.id == id }
        if saved.chosen == id { saved.chosen = saved.servers.first?.id }
        try save(saved)
    }

    /// Forgets `Server.json`, once the list holds its server.
    func removeLegacy() throws {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return }
        try FileManager.default.removeItem(at: legacyFileURL)
    }

    func choose(_ id: LibrarySourceID) throws {
        var saved = try read()
        guard saved[id] != nil else { return }
        saved.chosen = id
        try save(saved)
    }
}

/// An address as someone typed it, made into one Octavo can use (the
/// follow-ups in `docs/notes/network-trust.md`): a scheme if it has none
/// (http for a home address, else https), the host lowercased without a
/// trailing dot (`URL` writes an international name as `xn--`), and any
/// `user:password@` moved out to the account fields. Whether the address
/// may be used is `ServerTransport`'s to say, on every request.
nonisolated extension ServerStore {
    /// A server saved before step 16 recognised its address's secrets
    /// (Stump's key, a token in the query, a query on a BookOrbit address)
    /// has them moved out at launch: into the Keychain first, then the
    /// address saved with placeholders, so a crash between the two leaves
    /// the next launch to do it again.
    func moveSecretsOut() throws {
        var saved = try read()
        var moved = false
        // Every server is tried; the first failure is thrown after.
        var failure: (any Error)?
        for index in saved.servers.indices {
            do {
                if try Self.moveSecretsOut(of: &saved.servers[index]) { moved = true }
            } catch {
                failure = failure ?? error
            }
        }
        if moved { try save(saved) }
        if let failure { throw failure }
    }

    /// Whether `server`'s address changed.
    private static func moveSecretsOut(of server: inout SavedServer) throws -> Bool {
        switch server.kind {
        case .bookOrbit:
            guard let url = URL(string: server.address), url.query != nil else { return false }
            server.address = url.withoutQuery.absoluteString
        case .opds:
            let store = KeychainCatalogSecretStore(serverID: server.id.rawValue)
            let kept = try store.load()
            // A key that's gone already sends setup again; nothing to move.
            if OPDSURLSecret.isRedacted(server.address), kept == nil { return false }
            guard let url = URL(string: kept?.restore(server.address) ?? server.address),
                  let found = OPDSURLSecret.detect(in: url) else { return false }
            let new = found.values.filter { !(kept?.values.contains($0) ?? false) }
            guard let merged = new.isEmpty ? kept : OPDSURLSecret(values: (kept?.values ?? []) + new) else { return false }
            // Nothing new, but still in the address: the last try got as far
            // as the Keychain.
            let redacted = merged.redact(url.absoluteString)
            guard redacted != server.address else { return false }
            if !new.isEmpty { try store.save(merged) }
            server.address = redacted
        }
        return true
    }
}

nonisolated extension URL {
    /// The same address with no query.
    var withoutQuery: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true), components.query != nil else { return self }
        components.query = nil
        return components.url ?? self
    }
}

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
