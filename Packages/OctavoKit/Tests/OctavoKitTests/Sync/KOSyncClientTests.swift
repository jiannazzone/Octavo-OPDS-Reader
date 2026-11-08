import Foundation
@testable import OctavoKit
import Testing

private let alice = KOSyncDocument(id: "59feb863c3a0652fe66a99c0978404f9")!
private let key = KOSyncKey(username: "octavo", password: "OctavoDev1")

private func client(_ server: StubServer, path: String = "") -> KOSyncClient {
    KOSyncClient(
        baseURL: server.baseURL.appending(path: path), key: key,
        transport: ServerTransport(server: server.baseURL, configuration: server.configuration)
    )
}

struct KOSyncClientTests {
    @Test func signsInWithTheUsernameAndThePasswordsMD5() async throws {
        let server = StubServer { _ in .json(#"{"authorized":"OK"}"#) }

        try await client(server).authorize()

        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/users/auth")
        #expect(request.headers["x-auth-user"] == "octavo")
        // `printf OctavoDev1 | md5`
        #expect(request.headers["x-auth-key"] == "904550cde7194d5e8ffb8c620ee3a545")
        #expect(request.headers["accept"] == "application/vnd.koreader.v1+json")
    }

    @Test func keepsAServersPath() async throws {
        let server = StubServer { _ in .json(#"{"authorized":"OK"}"#) }

        try await client(server, path: "api/koreader/abc123").authorize()

        #expect(server.requests.first?.path == "/api/koreader/abc123/users/auth")
    }

    @Test func aWrongPasswordIsUnauthorized() async {
        let server = StubServer { _ in .json(401, #"{"code":2001,"message":"Unauthorized"}"#) }

        await #expect(throws: KOSyncError.unauthorized) { try await client(server).authorize() }
    }

    @Test(arguments: [
        // The standalone server, for a book it hasn't seen.
        #"{}"#,
        // Komga, for a book with no place.
        #"{"timestamp":"2026-11-06T22:04:30.950+00:00","status":200,"error":"OK","message":"No progress found for this book","path":"/koreader/syncs/progress/x"}"#,
        // An empty place, or one without a percentage.
        #"{"document":"x","progress":"","percentage":0.5,"device":"Octavo"}"#,
        #"{"document":"x","progress":"/body/DocFragment[3]","device":"Octavo"}"#,
    ])
    func noPlaceIsNil(body: String) async throws {
        let server = StubServer { _ in .json(body) }

        #expect(try await client(server).progress(of: alice) == nil)
    }

    @Test func readsTheStandaloneServersPlace() async throws {
        let server = StubServer { _ in
            .json(#"{"document":"59feb863c3a0652fe66a99c0978404f9","device_id":"AAAA","progress":"\/body\/DocFragment[6]\/body\/div\/p[12]\/text().10","percentage":0.3712,"timestamp":1794002803,"device":"Kindle"}"#)
        }

        let place = try #require(try await client(server).progress(of: alice))

        #expect(server.requests.first?.path == "/syncs/progress/59feb863c3a0652fe66a99c0978404f9")
        #expect(place == KOSyncProgress(
            progress: "/body/DocFragment[6]/body/div/p[12]/text().10", percentage: 0.3712,
            device: "Kindle", deviceID: "AAAA", timestamp: Date(timeIntervalSince1970: 1_794_002_803)
        ))
    }

    @Test func readsKavitasPlace() async throws {
        let server = StubServer { _ in
            .json(#"{"document":"59feb863c3a0652fe66a99c0978404f9","device_id":"835433DDCDD4E747292FED0D8A45D945895E3113D9E4D0BD7E77BB7ECA6CF20E","device":"Kavita","percentage":0.33333334,"progress":"/body/DocFragment[6]/body/div/p[12].0","timestamp":1794002567}"#)
        }

        let place = try #require(try await client(server).progress(of: alice))

        #expect(place.progress == "/body/DocFragment[6]/body/div/p[12].0")
        #expect(place.device == "Kavita")
        #expect(place.timestamp == Date(timeIntervalSince1970: 1_794_002_567))
    }

    /// In whole seconds since 1970.
    @Test(arguments: [
        // Kavita, for a book never read: year 1.
        (#""timestamp":-62135596800"#, nil as Double?),
        (#""timestamp":"1794002803""#, 1_794_002_803),
        // .NET's seven digits, as in Kavita's PUT answer.
        (#""timestamp":"2026-11-06T22:02:47.9205884Z""#, 1_794_002_567),
        (#""timestamp":"2026-11-06T22:02:47Z""#, 1_794_002_567),
        (#""timestamp":99999999999"#, nil),
        (#""timestamp":null"#, nil),
    ])
    func readsTimestampsLoosely(field: String, expected: Double?) async throws {
        let server = StubServer { _ in .json(#"{"progress":"/body/DocFragment[1].0","percentage":0,\#(field)}"#) }

        let timestamp = try await client(server).progress(of: alice)?.timestamp
        #expect(timestamp.map { $0.timeIntervalSince1970.rounded(.down) } == expected)
    }

    @Test func clampsAPercentageAndDropsBadNames() async throws {
        let server = StubServer { _ in
            .json(#"{"progress":"/body/DocFragment[2].0","percentage":"1.7","device":"Kin\u0007dle","device_id":"\#(String(repeating: "a", count: 200))"}"#)
        }

        let place = try #require(try await client(server).progress(of: alice))

        #expect(place.percentage == 1)
        #expect(place.device == nil)
        #expect(place.deviceID == nil)
    }

    @Test func dropsAPlaceTooLongToBeOne() async throws {
        let server = StubServer { _ in .json(#"{"progress":"\#(String(repeating: "p", count: 2049))","percentage":0.5}"#) }

        #expect(try await client(server).progress(of: alice) == nil)
    }

    @Test func sendsAPlace() async throws {
        let server = StubServer { _ in .json(#"{"document":"59feb863c3a0652fe66a99c0978404f9","timestamp":1794002803}"#) }

        try await client(server).update(alice, progress: "/body/DocFragment[7]/body/div/p[3].0", percentage: 0.44, device: "Octavo", deviceID: "BBBB")

        let request = try #require(server.requests.first)
        #expect(request.method == "PUT")
        #expect(request.path == "/syncs/progress")
        #expect(request.headers["content-type"] == "application/json")
        #expect(request.headers["x-auth-key"] == key.key)
        let body = try #require(request.json)
        #expect(Set(body.keys) == ["document", "progress", "percentage", "device", "device_id"])
        #expect(body["document"] as? String == alice.id)
        #expect(body["progress"] as? String == "/body/DocFragment[7]/body/div/p[3].0")
        #expect(body["percentage"] as? Double == 0.44)
        #expect(body["device"] as? String == "Octavo")
        #expect(body["device_id"] as? String == "BBBB")
    }

    /// Komga's PUT answers with an empty body, Kavita's timestamp is a string.
    @Test(arguments: ["", #"{"document":"x","timestamp":"2026-11-06T22:02:47.9205884Z"}"#])
    func ignoresWhatAPutSaysBack(body: String) async throws {
        let server = StubServer { _ in StubServer.Response(status: 200, headers: [:], body: Data(body.utf8)) }

        try await client(server).update(alice, progress: "/body/DocFragment[1].0", percentage: 0, device: "Octavo", deviceID: "BBBB")
    }

    @Test(arguments: ["", String(repeating: "p", count: 2049)])
    func neverSendsAPlaceKOReaderCantRead(progress: String) async {
        let server = StubServer { _ in .json("{}") }

        await #expect(throws: KOSyncError.invalidPlace) {
            try await client(server).update(alice, progress: progress, percentage: 0.5, device: "Octavo", deviceID: "BBBB")
        }
        await #expect(throws: KOSyncError.invalidPlace) {
            try await client(server).update(alice, progress: "/body/DocFragment[1].0", percentage: .nan, device: "Octavo", deviceID: "BBBB")
        }
        #expect(server.requests.isEmpty)
    }

    @Test func clampsAPercentageItSends() async throws {
        let server = StubServer { _ in .json("{}") }

        try await client(server).update(alice, progress: "/body/DocFragment[1].0", percentage: 1.2, device: "Octavo", deviceID: "BBBB")

        #expect(server.requests.first?.json?["percentage"] as? Double == 1)
    }

    @Test(arguments: [
        (400, KOSyncError.unknownDocument), (404, .unknownDocument),
        (403, .rejected(status: 403)), (412, .rejected(status: 412)),
        (429, .unavailable(status: 429)), (502, .unavailable(status: 502)),
    ])
    func sortsFailures(status: Int, expected: KOSyncError) async {
        let server = StubServer { _ in .json(status, #"{"message":"no"}"#) }

        await #expect(throws: expected) { try await client(server).progress(of: alice) }
        #expect(expected.isPermanent == !(status == 429 || status == 502))
    }

    @Test func neverPrintsTheKey() {
        #expect(!String(describing: key).contains(key.key))
        #expect(!String(reflecting: key).contains(key.key))
    }
}
