import Foundation
@testable import OctavoKit
import Synchronization
import Testing

/// A KOReader sync server in memory. `rewrite` stands in for a server that
/// stores its own form of a place, as Kavita does.
private final class FakeKOSyncServer: Sendable {
    private final class State: Sendable {
        let stored = Mutex<[String: String]>([:])
        let puts = Mutex(0)
    }

    let stub: StubServer
    private let state: State

    /// `racedBy`: another device's place, stored just after each push.
    init(rewrite: @escaping @Sendable (String) -> String = { $0 }, racedBy: String? = nil) {
        let state = State()
        self.state = state
        stub = StubServer { request in
            if request.method == "PUT", let body = request.json, let document = body["document"] as? String {
                state.puts.withLock { $0 += 1 }
                var kept = body
                kept["progress"] = rewrite(body["progress"] as? String ?? "")
                kept["timestamp"] = 1_794_002_803
                let json = String(decoding: try! JSONSerialization.data(withJSONObject: kept), as: UTF8.self)
                state.stored.withLock { $0[document] = json }
                if let racedBy {
                    state.stored.withLock {
                        $0[document] = #"{"document":"\#(document)","progress":"\#(racedBy)","percentage":0.6,"device":"Kindle","device_id":"AAAA","timestamp":1794002804}"#
                    }
                }
                return .json(#"{"document":"\#(document)","timestamp":1794002803}"#)
            }
            let document = request.path.components(separatedBy: "/").last ?? ""
            return .json(state.stored.withLock { $0[document] } ?? "{}")
        }
    }

    var pushes: Int { state.puts.withLock { $0 } }

    /// Another device's place.
    func set(_ document: KOSyncDocument, progress: String, percentage: Double) {
        state.stored.withLock {
            $0[document.id] = #"{"document":"\#(document.id)","progress":"\#(progress)","percentage":\#(percentage),"device":"Kindle","device_id":"AAAA","timestamp":1794002803}"#
        }
    }
}

@Suite(.serialized)
struct KOSyncTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "kosync-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// A file of its own, so its document is its own.
    private func book() throws -> (URL, KOSyncDocument) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(UUID().uuidString).epub")
        try Data(UUID().uuidString.utf8).write(to: url)
        return (url, try KOSyncDocument(fileAt: url))
    }

    private func sync(_ server: FakeKOSyncServer, file: URL, places: KOSyncPlaces) -> KOSync {
        let client = KOSyncClient(
            baseURL: server.stub.baseURL, key: KOSyncKey(username: "octavo", password: "OctavoDev1"),
            transport: ServerTransport(server: server.stub.baseURL, configuration: server.stub.configuration)
        )
        return KOSync(client: client, file: file, places: places, device: "Octavo", deviceID: "BBBB")
    }

    private func places() -> KOSyncPlaces {
        KOSyncPlaces(file: folder.appending(path: "places.json"))
    }

    private let theirs = "/body/DocFragment[6]/body/div/p[12]/text().10"
    private let ours = ReadingPosition(cfi: "epubcfi(/6/14!/4/2/2)", fraction: 0.41, xpointer: "/body/DocFragment[7]/body/div/p[3].0")

    @Test func anotherReadersPlaceIsNewTheFirstTime() async throws {
        let server = FakeKOSyncServer()
        let (file, document) = try book()
        server.set(document, progress: theirs, percentage: 0.37)

        let remote = try #require(try await sync(server, file: file, places: places()).pull())

        #expect(remote.position == ReadingPosition(fraction: 0.37, xpointer: theirs))
        #expect(remote.origin == SyncedPosition.Origin.elsewhere(.first))
        #expect(remote.updatedAt == Date(timeIntervalSince1970: 1_794_002_803))
    }

    @Test func aPlaceOpenedAtIsUnchangedUntilAnotherReaderMovesIt() async throws {
        let server = FakeKOSyncServer()
        let (file, document) = try book()
        server.set(document, progress: theirs, percentage: 0.37)
        let sync = sync(server, file: file, places: places())

        await sync.adopted(try #require(try await sync.pull()))
        #expect(try await sync.pull()?.origin == SyncedPosition.Origin.elsewhere(.unchanged))

        server.set(document, progress: "/body/DocFragment[9]/body/p.0", percentage: 0.6)
        #expect(try await sync.pull()?.origin == SyncedPosition.Origin.elsewhere(.moved))
    }

    /// Kavita keeps only the element: the place read back is what counts.
    @Test(arguments: [false, true])
    func itsOwnPlaceComesBackUnchanged(serverRewrites: Bool) async throws {
        let rewrite: @Sendable (String) -> String = { place in
            serverRewrites ? place.replacingOccurrences(of: "/div/p[3].0", with: "/div/p[3]/text().0") : place
        }
        let server = FakeKOSyncServer(rewrite: rewrite)
        let (file, _) = try book()
        let sync = sync(server, file: file, places: places())
        #expect(try await sync.pull() == nil)

        try await sync.push(ours)

        #expect(server.pushes == 1)
        #expect(try await sync.pull()?.origin == SyncedPosition.Origin.elsewhere(.unchanged))
    }

    /// Another device's place landing between the push and its read-back
    /// isn't taken for this iPhone's.
    @Test func aPlaceSentInBetweenIsStillAnotherReaders() async throws {
        let server = FakeKOSyncServer(racedBy: "/body/DocFragment[9]/body/p[2].0")
        let (file, _) = try book()
        let sync = sync(server, file: file, places: places())
        #expect(try await sync.pull() == nil)

        try await sync.push(ours)

        #expect(try await sync.pull()?.origin == SyncedPosition.Origin.elsewhere(.moved))
    }

    /// A reader that was offline doesn't overwrite another device's place
    /// unasked: the reader offers it first.
    @Test func theFirstPushSinceLaunchStopsAtAPlaceItHasntSeen() async throws {
        let server = FakeKOSyncServer()
        let (file, document) = try book()
        server.set(document, progress: theirs, percentage: 0.37)

        await #expect(throws: KOSyncError.serverMoved) { try await sync(server, file: file, places: places()).push(ours) }
        #expect(server.pushes == 0)
        #expect(!KOSyncError.serverMoved.isPermanent)
    }

    @Test func butGoesWhenTheServerHasNothingOrItsOwnPlace() async throws {
        let server = FakeKOSyncServer()
        let (file, _) = try book()
        let places = places()

        try await sync(server, file: file, places: places).push(ours)
        // A new launch: what it saw is on file.
        try await sync(server, file: file, places: KOSyncPlaces(file: places.file)).push(ours)

        #expect(server.pushes == 2)
    }

    @Test func theVeryStartIsNoPlace() async throws {
        let server = FakeKOSyncServer()
        let (file, document) = try book()
        // Kavita, for a book never read.
        server.set(document, progress: "/body/DocFragment[1].0", percentage: 0)

        #expect(try await sync(server, file: file, places: places()).pull() == nil)
    }

    @Test func aPlaceWithoutKOReadersFormIsntSent() async throws {
        let server = FakeKOSyncServer()
        let (file, _) = try book()

        await #expect(throws: KOSyncError.invalidPlace) {
            try await sync(server, file: file, places: places()).push(ReadingPosition(cfi: "epubcfi(/6/4!/4)", fraction: 0.2))
        }
        #expect(server.pushes == 0)
    }

    @Test func whatItSawOutlivesALaunchAndForgettingClearsIt() async throws {
        let server = FakeKOSyncServer()
        let (file, document) = try book()
        server.set(document, progress: theirs, percentage: 0.37)
        let first = places()
        let sync = sync(server, file: file, places: first)
        await sync.adopted(try #require(try await sync.pull()))

        let relaunched = KOSyncPlaces(file: first.file)
        #expect(try await self.sync(server, file: file, places: relaunched).pull()?.origin == SyncedPosition.Origin.elsewhere(.unchanged))
        #expect(await relaunched.wasPulled(document))
        #expect(!(await KOSyncPlaces(file: first.file).wasPulled(document)))

        await relaunched.forget()
        #expect(try await self.sync(server, file: file, places: relaunched).pull()?.origin == SyncedPosition.Origin.elsewhere(.first))
    }

    /// The address may hold Kavita's key.
    @Test func itsFileNamesNeitherServerNorAccount() {
        let name = KOSyncPlaces.fileName(server: URL(string: "https://books.example.com/api/koreader/0123456789abcdef")!, username: "adam")
        #expect(!name.contains("0123456789abcdef"))
        #expect(!name.contains("adam"))
        #expect(!name.contains("books"))
        #expect(name != KOSyncPlaces.fileName(server: URL(string: "https://books.example.com/api/koreader/0123456789abcdef")!, username: "other"))
    }
}
