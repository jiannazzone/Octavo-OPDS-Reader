import Foundation
import Observation
import OctavoKit

/// The KOReader sync account that books from OPDS catalogs and Files sync
/// their place with (`docs/notes/koreader-sync.md`). One for the app.
/// Settings sets it up; a DEBUG build can use the local server
/// (`-connectKOSync 1`, `dev/kosync/`).
@Observable
final class KOReaderConnection {
    private(set) var account: KOReaderAccount?

    func connect(_ account: KOReaderAccount?) {
        self.account = account
    }
}

/// One KOReader sync account: its client, and what its server last said
/// about each book.
nonisolated struct KOReaderAccount: Sendable {
    let client: KOSyncClient
    let places: KOSyncPlaces
    /// This install's, so KOReader can tell its places from its own.
    let deviceID: String

    /// What KOReader shows as the device a place came from.
    static let device = "Octavo"

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
            client: KOSyncClient(baseURL: url, key: key, transport: ServerTransport(server: url, maximumDataSize: 64 << 10)),
            places: KOSyncPlaces(file: placesFile(server: url, username: key.username, in: positions)),
            deviceID: deviceID()
        )
    }
    #endif
}
