import CryptoKit
import Foundation

/// One book's place on a KOReader sync server (`docs/notes/koreader-sync.md`).
///
/// - The book is its file's `KOSyncDocument`, read when it's needed.
/// - Places go and come as KOReader's own (`ReadingPosition.xpointer`), with
///   the percentage beside them. A position without one isn't sent.
/// - What comes back is another reader's place (`Origin.elsewhere`), marked
///   by whether it changed since this iPhone last saw it (`KOSyncPlaces`), so
///   `OpeningPosition.choose` can keep a better local place.
/// - Before its first push since launch it asks the server, and a place it
///   hasn't seen stops the push (`KOSyncError.serverMoved`): a reader that
///   was offline doesn't overwrite another device's place unasked.
/// - After each push it reads the place back, since a server may store its
///   own form of it (Kavita does), and remembers that.
public struct KOSync: ProgressSync {
    public let client: KOSyncClient
    public let file: URL
    public let places: KOSyncPlaces
    /// What KOReader shows as the place's device, and this install's ID.
    public let device: String
    public let deviceID: String

    public init(client: KOSyncClient, file: URL, places: KOSyncPlaces, device: String, deviceID: String) {
        self.client = client
        self.file = file
        self.places = places
        self.device = device
        self.deviceID = deviceID
    }

    public var wantsXPointers: Bool { true }

    public func pull() async throws -> SyncedPosition? {
        guard await places.isOpen else { throw KOSyncError.signedOut }
        let document = try await document()
        let progress = try await client.progress(of: document)
        await places.pulled(document)
        return await position(progress, of: document)
    }

    public func push(_ position: ReadingPosition) async throws {
        guard let xpointer = position.xpointer else { throw KOSyncError.invalidPlace }
        guard await places.isOpen else { throw KOSyncError.signedOut }
        let document = try await document()
        if await !places.wasPulled(document) {
            let remote = try await client.progress(of: document)
            await places.pulled(document)
            if let seen = await self.position(remote, of: document), seen.origin != .elsewhere(.unchanged) {
                throw KOSyncError.serverMoved
            }
        }
        // Signed out while this was under way: the key isn't sent again.
        guard await places.isOpen else { throw KOSyncError.signedOut }
        try await client.update(document, progress: xpointer, percentage: position.fraction, device: device, deviceID: deviceID)
        let sent = KOSyncProgress(progress: xpointer, percentage: position.fraction)
        let readBack = try? await client.progress(of: document)
        await places.said(readBack.flatMap { isOwn($0, sent: sent) ? $0 : nil } ?? sent, about: document)
    }

    /// Whether the place read back is the one just sent, in the server's
    /// form: this install's, or in the same file section. Another device's
    /// that landed in between is left to be offered.
    private func isOwn(_ readBack: KOSyncProgress, sent: KOSyncProgress) -> Bool {
        if readBack.deviceID == deviceID { return true }
        guard let section = ReadingPosition(fraction: 0, xpointer: readBack.progress).spineIndex else { return false }
        return section == ReadingPosition(fraction: 0, xpointer: sent.progress).spineIndex
    }

    public func adopted(_ remote: SyncedPosition) async {
        guard case .elsewhere = remote.origin, let xpointer = remote.position.xpointer,
              let document = try? await document() else { return }
        await places.said(KOSyncProgress(progress: xpointer, percentage: remote.position.fraction), about: document)
    }

    /// The server's place as a position, `nil` at the very start: there's
    /// nothing to offer there, and Kavita answers that for a book never read.
    private func position(_ progress: KOSyncProgress?, of document: KOSyncDocument) async -> SyncedPosition? {
        guard let progress, progress.percentage > 0 else { return nil }
        return SyncedPosition(
            position: ReadingPosition(fraction: progress.percentage, xpointer: progress.progress),
            updatedAt: progress.timestamp,
            origin: .elsewhere(await places.change(of: document, to: progress))
        )
    }

    private func document() async throws -> KOSyncDocument {
        let file = file
        return try await Task.detached { try KOSyncDocument(fileAt: file) }.value
    }
}

/// What one KOReader sync account's server last said about each book, so its
/// place coming back unchanged (this iPhone's own, read back) isn't taken for
/// another reader's. Kept in one small file per account, keyed by document;
/// which books were pulled since launch is kept in memory only.
public actor KOSyncPlaces {
    public nonisolated let file: URL
    private var lastSaid: [String: Said]?
    private var pulledSinceLaunch: Set<String> = []
    /// Until Sign out (`close`).
    public private(set) var isOpen = true

    private struct Said: Codable, Equatable {
        var progress: String
        var percentage: Double
    }

    public init(file: URL) {
        self.file = file
    }

    /// A file name for `username` on `server`, without either: the address
    /// may hold a key (Kavita's), so only a digest of it is written.
    public static func fileName(server: URL, username: String) -> String {
        let digest = SHA256.hash(data: Data("\(server.absoluteString)\n\(username)".utf8))
        return "koreader-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    func change(of document: KOSyncDocument, to progress: KOSyncProgress) -> SyncedPosition.Change {
        guard let last = load()[document.id] else { return .first }
        return last == Said(progress: progress.progress, percentage: progress.percentage) ? .unchanged : .moved
    }

    func said(_ progress: KOSyncProgress, about document: KOSyncDocument) {
        guard isOpen else { return }
        var all = load()
        all[document.id] = Said(progress: progress.progress, percentage: progress.percentage)
        lastSaid = all
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
    }

    func pulled(_ document: KOSyncDocument) {
        guard isOpen else { return }
        pulledSinceLaunch.insert(document.id)
    }

    func wasPulled(_ document: KOSyncDocument) -> Bool {
        pulledSinceLaunch.contains(document.id)
    }

    /// Sign out: nothing it said applies any more, and nothing more is
    /// asked or sent (`KOSync` checks), so a push or pull already under way
    /// can't bring the file back.
    public func close() {
        isOpen = false
        lastSaid = [:]
        pulledSinceLaunch = []
        try? FileManager.default.removeItem(at: file)
    }

    private func load() -> [String: Said] {
        if let lastSaid { return lastSaid }
        let loaded = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: Said].self, from: $0) } ?? [:]
        lastSaid = loaded
        return loaded
    }
}
