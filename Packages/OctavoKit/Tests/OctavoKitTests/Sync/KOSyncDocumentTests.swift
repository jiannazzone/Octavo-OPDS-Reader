import Foundation
@testable import OctavoKit
import Testing

struct KOSyncDocumentTests {
    /// Byte i is (31i + 7) mod 256. The digests come from the Python version
    /// in `docs/notes/koreader-sync/tools`, which matched KOReader's own
    /// `util.partialMD5` on the sample books.
    @Test(arguments: [
        (0, "d41d8cd98f00b204e9800998ecf8427e"),
        (1, "89e74e640b8c46257a29de0616794d5d"),
        (1023, "aa217140da10ed9796690dd1ed22a21a"),
        (1024, "63b2177a7af739b5cc52ab1d1c714702"),
        (1025, "31d56d8e673d2856b7a4eee144ee8275"),
        (4096, "fbb2e3b38a23c7d820533df281b4b6ec"),
        (4097, "54e1f2b6c88f9a465ba73a6df32c93ee"),
        (70_000, "7c495b34b24f561520622156e96f834d"),
        (1_049_600, "9176994efdf840ffd6a4fb8d1cd31fb1"),
        // Nothing after the last sample counts.
        (1_100_000, "9176994efdf840ffd6a4fb8d1cd31fb1"),
    ])
    func digestsTheSamples(size: Int, expected: String) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kosync-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: url)

        #expect(try KOSyncDocument(fileAt: url).id == expected)
    }

    @Test func samplesWhereKOReaderDoes() {
        #expect(KOSyncDocument.sampleOffsets == [0, 1024, 4096, 16384, 65536, 262_144, 1_048_576, 4_194_304, 16_777_216, 67_108_864, 268_435_456, 1_073_741_824])
    }

    @Test func readsAServersSpellingOfIt() {
        #expect(KOSyncDocument(id: "59FEB863C3A0652FE66A99C0978404F9")?.id == "59feb863c3a0652fe66a99c0978404f9")
        #expect(KOSyncDocument(id: "59feb863c3a0652fe66a99c0978404f") == nil)
        #expect(KOSyncDocument(id: "59feb863c3a0652fe66a99c0978404fg") == nil)
        #expect(KOSyncDocument(id: "../../users/auth/0000000000000000") == nil)
        // Fullwidth "Ａ" is a hex digit to `isHexDigit`: 31 ASCII digits and it.
        #expect(KOSyncDocument(id: "59feb863c3a0652fe66a99c0978404f\u{FF21}") == nil)
    }

    @Test func aMissingFileThrows() {
        #expect(throws: (any Error).self) {
            try KOSyncDocument(fileAt: FileManager.default.temporaryDirectory.appending(path: "kosync-missing-\(UUID().uuidString)"))
        }
    }
}
