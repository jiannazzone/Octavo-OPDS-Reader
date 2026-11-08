import Foundation
import Observation
import OctavoKit

/// The KOReader sync account that books from Files, and from catalogs
/// switched on for it, sync their place with (`docs/notes/koreader-sync.md`).
/// One for the app. Settings and a catalog's setup sign in
/// (`ServerActions`); a DEBUG build can use the local server
/// (`-connectKOSync 1`, `dev/kosync/`).
@Observable
final class KOReaderConnection {
    private(set) var account: KOReaderAccount?

    func connect(_ account: KOReaderAccount?) {
        self.account = account
    }

    /// At launch: the saved account, from the Keychain. One the Keychain no
    /// longer has (it was wiped) is forgotten; one it can't read now (before
    /// the first unlock) waits for the next launch.
    func load(_ saved: SavedKOReaderAccount?, servers: ServerStore, positions: URL) {
        guard let saved else { return }
        do {
            guard let stored = try KeychainKOSyncAccountStore(accountID: saved.id).load() else {
                try? servers.setKOReader(nil)
                return
            }
            account = KOReaderAccount(id: saved.id, account: stored, positions: positions)
        } catch {
            account = nil
        }
    }
}

/// One KOReader sync account: its client, and what its server last said
/// about each book.
nonisolated struct KOReaderAccount: Sendable {
    /// What its secrets are kept under (`SavedKOReaderAccount`).
    let id: String
    let address: URL
    let username: String
    let client: KOSyncClient
    let places: KOSyncPlaces
    /// This install's, so KOReader can tell its places from its own.
    let deviceID: String

    /// What KOReader shows as the device a place came from.
    static let device = "Octavo"

    /// The answers are a few hundred bytes.
    static let maximumDataSize = 64 << 10

    init(id: String, address: URL, username: String, client: KOSyncClient, places: KOSyncPlaces, deviceID: String) {
        self.id = id
        self.address = address
        self.username = username
        self.client = client
        self.places = places
        self.deviceID = deviceID
    }

    /// A saved account, its transport reading the pin kept under its ID
    /// before the first request (step 16).
    init(id: String, account: KOSyncAccount, positions: URL, deviceID: String = Self.deviceID()) {
        self.init(
            id: id, address: account.address, username: account.key.username,
            client: Self.client(id: id, account: account),
            places: KOSyncPlaces(file: Self.placesFile(server: account.address, username: account.key.username, in: positions)),
            deviceID: deviceID
        )
    }

    static func client(id: String, account: KOSyncAccount) -> KOSyncClient {
        KOSyncClient(
            baseURL: account.address, key: account.key,
            transport: ServerTransport(
                server: account.address, pins: KeychainCertificatePinStore(serverID: id), maximumDataSize: maximumDataSize
            )
        )
    }

    /// "sync.example.com", "nas.local:7200": the server, without the path
    /// (or a key in it).
    var host: String {
        address.host().map { host in address.port.map { "\(host):\($0)" } ?? host } ?? ""
    }

    func sync(for file: URL) -> KOSync {
        KOSync(client: client, file: file, places: places, device: Self.device, deviceID: deviceID)
    }

    /// The account's places file, beside the reading positions.
    static func placesFile(server: URL, username: String, in positions: URL) -> URL {
        positions.appending(path: "KOReader", directoryHint: .isDirectory)
            .appending(path: KOSyncPlaces.fileName(server: server, username: username), directoryHint: .notDirectory)
    }

    /// Made once per install. Not a secret: KOReader sends its own in the clear.
    static func deviceID(defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: "koreaderDeviceID") { return id }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(id, forKey: "koreaderDeviceID")
        return id
    }

    #if DEBUG
    /// The local server in `dev/kosync/`, with its dev account.
    static func local(positions: URL) -> KOReaderAccount {
        let url = URL(string: "http://localhost:3350")!
        let key = KOSyncKey(username: "octavo", password: "OctavoDev1")
        return KOReaderAccount(
            id: "debug-koreader", address: url, username: key.username,
            client: KOSyncClient(baseURL: url, key: key, transport: ServerTransport(server: url, maximumDataSize: maximumDataSize)),
            places: KOSyncPlaces(file: placesFile(server: url, username: key.username, in: positions)),
            deviceID: deviceID()
        )
    }
    #endif
}
