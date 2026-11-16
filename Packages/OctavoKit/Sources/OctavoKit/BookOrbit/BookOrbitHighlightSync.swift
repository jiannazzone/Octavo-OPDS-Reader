import Foundation

/// Syncs one BookOrbit book's highlights (`books/{bookId}/annotations`,
/// #125), so they show in its web reader and on other devices. Always for
/// one file: without it the server's ranges would be for whichever file each
/// highlight was made on.
public struct BookOrbitHighlightSync: HighlightSync {
    public let client: BookOrbitClient
    public let bookID: Int
    public let fileID: Int

    public init(client: BookOrbitClient, bookID: Int, fileID: Int) {
        self.client = client
        self.bookID = bookID
        self.fileID = fileID
    }

    public func highlights() async throws -> [SyncedHighlight] {
        // A PDF's highlights belong to that file alone.
        try await client.annotations(bookID: bookID, fileID: fileID).filter { !$0.isPDF }.map(Self.synced)
    }

    public func add(_ highlight: NewHighlight) async throws -> SyncedHighlight {
        Self.synced(try await client.addAnnotation(highlight, bookID: bookID, fileID: fileID))
    }

    public func update(id: String, _ edit: HighlightEdit) async throws -> SyncedHighlight {
        guard let number = Int(id) else { throw HighlightSyncError.gone }
        do {
            return Self.synced(try await client.updateAnnotation(id: number, bookID: bookID, edit))
        } catch BookOrbitError.http(status: 404, _) {
            throw HighlightSyncError.gone
        }
    }

    public func remove(id: String) async throws {
        guard let number = Int(id) else { return }
        try await client.deleteAnnotation(id: number, bookID: bookID)
    }

    private static func synced(_ annotation: BookOrbitAnnotation) -> SyncedHighlight {
        SyncedHighlight(
            id: String(annotation.id), cfi: annotation.cfi, text: annotation.text ?? "", color: annotation.color,
            note: annotation.note, chapter: annotation.chapterTitle, updatedAt: annotation.updatedAt, createdAt: annotation.createdAt
        )
    }
}
