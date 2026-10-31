import Foundation

/// Syncs one BookOrbit file's reading position
/// (`GET`/`POST books/files/{fileId}/progress`).
public struct BookOrbitProgressSync: ProgressSync {
    public let client: BookOrbitClient
    public let fileID: Int

    public init(client: BookOrbitClient, fileID: Int) {
        self.client = client
        self.fileID = fileID
    }

    public func pull() async throws -> SyncedPosition? {
        guard let progress = try await client.progress(fileID: fileID) else { return nil }
        return SyncedPosition(position: progress.position, updatedAt: progress.updatedAt)
    }

    /// BookOrbit replaces the whole text position on every write, so a
    /// position without a CFI would clear the server's.
    public func push(_ position: ReadingPosition) async throws {
        try await client.saveProgress(position, fileID: fileID)
    }
}
