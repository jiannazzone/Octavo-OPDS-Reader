import CryptoKit
import Foundation

/// How a KOReader sync server names a book: KOReader's default "Binary"
/// document matching, an MD5 over 1 KiB samples of the file at offset 0 and
/// then 1024 × 4ⁱ for i = 0...10, stopping at the first one past the end
/// (`docs/notes/koreader-sync.md`, matched against KOReader's own).
///
/// Two copies are the same book only if those bytes match, so a copy that
/// calibre converted or edited is another book, and nothing can tell.
public struct KOSyncDocument: Hashable, Sendable, CustomStringConvertible {
    /// 32 lowercase hex digits, as KOReader sends it.
    public let id: String

    /// `nil` unless `id` is 32 hex digits. Kavita stores them uppercase.
    public init?(id: String) {
        guard id.utf8.count == 32, id.allSatisfy(\.isHexDigit) else { return nil }
        self.id = id.lowercased()
    }

    /// The document of the file at `url`. Reads at most 12 KiB, so it's fine
    /// off the main actor but not on it.
    public init(fileAt url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var md5 = Insecure.MD5()
        for offset in Self.sampleOffsets {
            try handle.seek(toOffset: offset)
            guard let sample = try handle.read(upToCount: Self.sampleSize), !sample.isEmpty else { break }
            md5.update(data: sample)
        }
        id = md5.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { id }

    static let sampleSize = 1024
    /// KOReader's loop starts at i = -1, where its shift by -2 comes out as 0.
    static let sampleOffsets: [UInt64] = [0] + (0...10).map { UInt64(sampleSize) << (2 * $0) }
}
