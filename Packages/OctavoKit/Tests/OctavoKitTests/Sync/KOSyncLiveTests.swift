import Foundation
@testable import OctavoKit
import Testing

/// Runs against the local KOReader sync server seeded by `dev/kosync/seed.sh`.
/// Skipped unless all three variables are set:
///
///     OCTAVO_KOSYNC_URL=http://localhost:3350 OCTAVO_KOSYNC_USER=octavo \
///     OCTAVO_KOSYNC_PASS=OctavoDev1 swift test --filter KOSyncLiveTests
///
/// Places go only to made-up documents. With `OCTAVO_SAMPLE_BOOKS` (the
/// `SampleBooks` folder) it also checks Alice's document against KOReader's.
@Suite(.serialized, .enabled(if: LiveKOSync.isConfigured, "Set OCTAVO_KOSYNC_URL, OCTAVO_KOSYNC_USER and OCTAVO_KOSYNC_PASS"))
struct KOSyncLiveTests {
    private func client(password: String = LiveKOSync.pass) -> KOSyncClient {
        KOSyncClient(
            baseURL: LiveKOSync.url, key: KOSyncKey(username: LiveKOSync.user, password: password),
            transport: ServerTransport(server: LiveKOSync.url, maximumDataSize: 64 << 10)
        )
    }

    private func madeUpDocument() -> KOSyncDocument {
        KOSyncDocument(id: UUID().uuidString.replacingOccurrences(of: "-", with: ""))!
    }

    @Test func signsIn() async throws {
        try await client().authorize()
        await #expect(throws: KOSyncError.unauthorized) { try await client(password: "wrong").authorize() }
    }

    @Test func aBookNotSeenHasNoPlace() async throws {
        #expect(try await client().progress(of: madeUpDocument()) == nil)
    }

    @Test func aPlaceComesBackAsSent() async throws {
        let document = madeUpDocument()
        let sent = Date.now

        try await client().update(document, progress: "/body/DocFragment[7]/body/div/p[3].0", percentage: 0.4412, device: "Octavo", deviceID: "octavo-live-tests")
        let place = try #require(try await client().progress(of: document))

        #expect(place.progress == "/body/DocFragment[7]/body/div/p[3].0")
        #expect(place.percentage == 0.4412)
        #expect(place.device == "Octavo")
        #expect(place.deviceID == "octavo-live-tests")
        let timestamp = try #require(place.timestamp)
        #expect(abs(timestamp.timeIntervalSince(sent)) < 60)
    }

    @Test func aNewerPlaceReplacesIt() async throws {
        let document = madeUpDocument()

        try await client().update(document, progress: "/body/DocFragment[3].0", percentage: 0.1, device: "Kindle", deviceID: "AAAA")
        try await client().update(document, progress: "/body/DocFragment[9]/body/p[2].0", percentage: 0.6, device: "Octavo", deviceID: "BBBB")

        let place = try #require(try await client().progress(of: document))
        #expect(place.progress == "/body/DocFragment[9]/body/p[2].0")
        #expect(place.device == "Octavo")
    }

    @Test(.enabled(if: LiveKOSync.sampleBooks != nil, "Set OCTAVO_SAMPLE_BOOKS"))
    func aliceIsTheDocumentKOReaderNamesIt() throws {
        let alice = try #require(LiveKOSync.sampleBooks).appending(path: "alice-in-wonderland.epub")
        // KOReader v2026.07.1's `util.partialMD5` (docs/notes/koreader-sync.md).
        #expect(try KOSyncDocument(fileAt: alice).id == "59feb863c3a0652fe66a99c0978404f9")
    }
}

enum LiveKOSync {
    private static let environment = ProcessInfo.processInfo.environment

    static var isConfigured: Bool {
        ["OCTAVO_KOSYNC_URL", "OCTAVO_KOSYNC_USER", "OCTAVO_KOSYNC_PASS"].allSatisfy { environment[$0]?.isEmpty == false }
    }

    static var url: URL { URL(string: environment["OCTAVO_KOSYNC_URL"]!)! }
    static var user: String { environment["OCTAVO_KOSYNC_USER"]! }
    static var pass: String { environment["OCTAVO_KOSYNC_PASS"]! }
    static var sampleBooks: URL? { environment["OCTAVO_SAMPLE_BOOKS"].map { URL(filePath: $0, directoryHint: .isDirectory) } }
}
