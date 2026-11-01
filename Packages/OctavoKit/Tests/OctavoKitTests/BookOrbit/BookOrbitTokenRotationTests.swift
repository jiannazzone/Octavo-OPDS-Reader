import Foundation
@testable import OctavoKit
import Synchronization
import Testing

/// BookOrbit as the spike measured it: every refresh retires the refresh
/// token, which still works for 30 s (`docs/notes/bookorbit-api.md`).
private struct RotatingServer {
    let stub: StubServer
    private let backend: RotatingBackend

    init(events: EventLog) {
        let backend = RotatingBackend(events: events)
        self.backend = backend
        stub = StubServer { backend.handle($0) }
    }

    /// More than 30 s have passed: retired tokens stop working.
    func closeGrace() {
        backend.graceOpen.withLock { $0 = false }
    }
}

private final class RotatingBackend: Sendable {
    private struct State {
        var issued = 1
        var current = "refresh-1"
        var retired: [String] = []
        var access = "access-1"
    }

    private let state = Mutex(State())
    /// Whether retired tokens are still inside their 30 s.
    let graceOpen = Mutex(true)
    let events: EventLog

    init(events: EventLog) {
        self.events = events
    }

    func handle(_ request: StubServer.Request) -> StubServer.Response {
        switch request.path {
        case "/api/v1/auth/refresh":
            let presented = request.json?["refreshToken"] as? String ?? ""
            events.append("server: refresh with \(presented)")
            return state.withLock { state in
                guard presented == state.current || (graceOpen.withLock { $0 } && state.retired.contains(presented)) else {
                    return .unauthorized
                }
                state.retired.append(state.current)
                state.issued += 1
                state.current = "refresh-\(state.issued)"
                state.access = "access-\(state.issued)"
                return .json(#"{"accessToken":"\#(state.access)","refreshToken":"\#(state.current)","sessionId":7}"#)
            }
        default:
            let authorization = request.headers["authorization"] ?? ""
            events.append("server: \(request.path) with \(authorization)")
            let valid = state.withLock { "Bearer \($0.access)" == authorization }
            return valid ? .json("[]") : .unauthorized
        }
    }
}

final class EventLog: Sendable {
    private let events = Mutex<[String]>([])
    func append(_ event: String) { events.withLock { $0.append(event) } }
    var all: [String] { events.withLock { $0 } }
}

/// A token store that can stand in for the app dying mid-save: `crash`
/// makes saves fail without storing anything.
private actor RecordingStore: BookOrbitTokenStore {
    private var stored: BookOrbitCredentials?
    private(set) var history: [BookOrbitCredentials?] = []
    var crash = false
    var failures = 0
    var delayNonNilSaves: Duration?
    let events: EventLog?

    init(_ credentials: BookOrbitCredentials?, events: EventLog? = nil) {
        stored = credentials
        self.events = events
    }

    func load() -> BookOrbitCredentials? { stored }

    func save(_ credentials: BookOrbitCredentials?) async throws {
        if credentials != nil, let delay = delayNonNilSaves { try await Task.sleep(for: delay) }
        if crash { throw CocoaError(.fileWriteUnknown) }
        if failures > 0 {
            failures -= 1
            throw CocoaError(.fileWriteUnknown)
        }
        stored = credentials
        history.append(credentials)
        events?.append("store: \(credentials?.refreshToken ?? "nil")")
    }

    func setCrash(_ value: Bool) { crash = value }
    func setFailures(_ value: Int) { failures = value }
    func setDelay(_ value: Duration?) { delayNonNilSaves = value }
}

struct BookOrbitTokenRotationTests {
    let events = EventLog()

    private func expiredSession() -> BookOrbitCredentials {
        BookOrbitCredentials(accessToken: "expired", refreshToken: "refresh-1")
    }

    /// The new token is in the store before the client uses it.
    @Test func savesTheRotatedTokenBeforeUsingIt() async throws {
        let server = RotatingServer(events: events)
        let store = RecordingStore(expiredSession(), events: events)
        let client = BookOrbitClient(baseURL: server.stub.baseURL, tokenStore: store, configuration: server.stub.configuration)

        _ = try await client.libraries()

        #expect(events.all == [
            "server: /api/v1/libraries with Bearer expired",
            "server: refresh with refresh-1",
            "store: refresh-2",
            "server: /api/v1/libraries with Bearer access-2",
        ])
        #expect(await store.history.allSatisfy { $0 != nil })
    }

    /// Issue #9: the app dies after BookOrbit rotated the token but before
    /// the new one reached the Keychain. The store still has the old token
    /// (never nothing), and inside BookOrbit's 30 s it still works.
    @Test func rotationSurvivesACrashBetweenReceivingAndSaving() async throws {
        let server = RotatingServer(events: events)
        let store = RecordingStore(expiredSession())
        await store.setCrash(true)
        let dying = BookOrbitClient(baseURL: server.stub.baseURL, tokenStore: store, configuration: server.stub.configuration)
        _ = try await dying.libraries()       // refreshed, but the save never landed
        #expect(await store.load()?.refreshToken == "refresh-1")

        // Relaunch.
        await store.setCrash(false)
        let relaunched = BookOrbitClient(baseURL: server.stub.baseURL, tokenStore: store, configuration: server.stub.configuration)
        _ = try await relaunched.libraries()

        #expect(await store.load()?.refreshToken == "refresh-3")
        #expect(await store.history.allSatisfy { $0 != nil })
    }

    /// After BookOrbit's grace the old token is dead: the client reports a
    /// signed-out session instead of retrying forever.
    @Test func aCrashAfterTheGraceEndsTheSession() async throws {
        let server = RotatingServer(events: events)
        let store = RecordingStore(expiredSession())
        await store.setCrash(true)
        _ = try await BookOrbitClient(baseURL: server.stub.baseURL, tokenStore: store, configuration: server.stub.configuration).libraries()
        await store.setCrash(false)
        server.closeGrace()

        let relaunched = BookOrbitClient(baseURL: server.stub.baseURL, tokenStore: store, configuration: server.stub.configuration)
        await #expect(throws: BookOrbitError.sessionExpired) { try await relaunched.libraries() }
        #expect(await store.load() == nil)
    }

    /// A Keychain write that fails doesn't lose the new token: it stays in
    /// memory and the next request saves it.
    @Test func retriesAFailedSaveOnTheNextRequest() async throws {
        let server = RotatingServer(events: events)
        let store = RecordingStore(expiredSession())
        await store.setFailures(1)
        let client = BookOrbitClient(baseURL: server.stub.baseURL, tokenStore: store, configuration: server.stub.configuration)

        _ = try await client.libraries()
        #expect(await store.load()?.refreshToken == "refresh-1")
        _ = try await client.libraries()

        #expect(await store.load()?.refreshToken == "refresh-2")
        #expect(server.stub.requests(to: "/api/v1/auth/refresh").count == 1)
    }

    /// Signing out while a refresh is on its way back must not bring the
    /// session back, even if the refresh's save is slower than the delete.
    @Test func signOutDuringARefreshStaysSignedOut() async throws {
        let refreshArrived = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        let server = StubServer { request in
            guard request.path == "/api/v1/auth/refresh" else { return .unauthorized }
            refreshArrived.continuation.yield()
            release.wait()
            return .json(#"{"accessToken":"access-2","refreshToken":"refresh-2"}"#)
        }
        let store = RecordingStore(expiredSession())
        await store.setDelay(.milliseconds(100))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)

        let request = Task { try await client.libraries() }
        var arrivals = refreshArrived.stream.makeAsyncIterator()
        await arrivals.next()
        try await client.signOut()
        release.signal()

        await #expect(throws: BookOrbitError.sessionExpired) { try await request.value }
        #expect(await store.load() == nil)
        await #expect(throws: BookOrbitError.notSignedIn) { try await client.libraries() }
    }

    /// Saves land in the order they were made, even when an earlier one is slow.
    @Test func savesLandInOrder() async throws {
        let server = RotatingServer(events: events)
        let store = RecordingStore(expiredSession())
        await store.setDelay(.milliseconds(100))
        let client = BookOrbitClient(baseURL: server.stub.baseURL, tokenStore: store, configuration: server.stub.configuration)

        async let request: Void = { _ = try? await client.libraries() }()
        try await Task.sleep(for: .milliseconds(30))
        try await client.signOut()
        await request

        #expect(await store.load() == nil)
    }
}
