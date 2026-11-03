import Foundation
import OctavoKit
import Testing

/// End to end on the simulator, through the app's real ATS settings and
/// Keychain. Skipped unless the servers are named (xcodebuild passes
/// `TEST_RUNNER_`-prefixed variables to the tests without the prefix):
///
///     TEST_RUNNER_OCTAVO_LAN_BOOKORBIT=http://192.168.1.122:3300 \
///     TEST_RUNNER_OCTAVO_LAN_TRUST_HOST=192.168.1.122 xcodebuild test …
///
/// The first is the local BookOrbit by this Mac's Wi-Fi address (one sign-in;
/// BookOrbit allows 5 a minute), the second `dev/trust/` the same way.
@Suite(.serialized)
struct NetworkTrustLiveTests {
    static let environment = ProcessInfo.processInfo.environment
    static let bookOrbit = environment["OCTAVO_LAN_BOOKORBIT"].flatMap(URL.init(string:))
    static let trustHost = environment["OCTAVO_LAN_TRUST_HOST"]
    /// Step 16: `TEST_RUNNER_OCTAVO_LIVE_DNS=1` after
    /// `docs/notes/network-trust/mdns-probes.sh start`, and optionally
    /// `TEST_RUNNER_OCTAVO_LIVE_DNS_LOCAL_NAME=<Mac>.local` for the local
    /// BookOrbit by this Mac's Bonjour name.
    static let liveDNS = environment["OCTAVO_LIVE_DNS"] == "1"
    static let localName = environment["OCTAVO_LIVE_DNS_LOCAL_NAME"]

    /// Plain http to a home address passes ATS and the policy; the tokens
    /// land in the Keychain and a relaunch uses them without signing in.
    @Test(.enabled(if: bookOrbit != nil, "Set TEST_RUNNER_OCTAVO_LAN_BOOKORBIT"))
    func bookOrbitOverPlainHTTPOnTheLAN() async throws {
        let url = try #require(Self.bookOrbit)
        let serverID = "live-lan-\(UUID().uuidString)"
        let store = KeychainBookOrbitTokenStore(serverID: serverID)
        defer { try? ServerCredentials.removeAll(serverID: serverID) }

        let client = BookOrbitClient(baseURL: url, tokenStore: store, deviceLabel: "Octavo trust test", transport: ServerTransport(server: url))
        try await client.login(username: "octavo", password: "OctavoDev1")
        #expect(try await !client.libraries().isEmpty)
        #expect(try await store.load()?.refreshToken != nil)

        let relaunched = BookOrbitClient(baseURL: url, tokenStore: store, transport: ServerTransport(server: url))
        #expect(try await !relaunched.libraries().isEmpty)

        try await relaunched.signOut()
        #expect(try await store.load() == nil)
    }

    /// A self-signed certificate on a home IP: asked about, pinned, accepted;
    /// the other certificate on the same host is "changed".
    @Test(.enabled(if: trustHost != nil, "Set TEST_RUNNER_OCTAVO_LAN_TRUST_HOST and start dev/trust"))
    func selfSignedCertificateOnTheLAN() async throws {
        let host = try #require(Self.trustHost)
        let a = try #require(URL(string: "https://\(host):8443/"))
        let b = try #require(URL(string: "https://\(host):8444/"))

        var summary: CertificateSummary?
        do {
            _ = try await ServerTransport(server: a).data(for: URLRequest(url: a))
            Issue.record("A self-signed certificate was accepted without a pin")
        } catch NetworkTrustError.untrustedCertificate(let presented) {
            summary = presented
        }
        let pin = try #require(summary?.pinToSave)
        #expect(summary?.subject == "Octavo trust test a")

        let (data, _) = try await ServerTransport(server: a, pin: pin).data(for: URLRequest(url: a))
        #expect(String(decoding: data, as: UTF8.self).contains(#""cert":"a""#))

        await #expect(throws: NetworkTrustError.self) {
            try await ServerTransport(server: b, pin: pin).data(for: URLRequest(url: b))
        }
    }

    /// The decimal spelling of 1.1.1.1 got past ATS in the spike; the policy
    /// stops it before anything is sent.
    @Test func decimalAddressesAreStoppedBeforeATS() async throws {
        await #expect(throws: NetworkTrustError.unsupportedAddress("http://16843009")) {
            try await ServerTransport(server: URL(string: "http://16843009/")!).data(for: URLRequest(url: URL(string: "http://16843009/")!))
        }
    }

    /// Step 16 (#9): names ATS lets through by their shape (a single label,
    /// `.local`) are judged by where they resolve. `uz` is a top-level
    /// domain with an internet address; the probes are `.local` names
    /// answered over Bonjour with internet addresses. Each is refused before
    /// a task is even made (the refusal after a request, `verify`, gives the
    /// same error, so the test counts tasks). A `.local` name with a global
    /// IPv6 address on this network still reaches BookOrbit, which shows
    /// the count works.
    @Test(.enabled(if: liveDNS, "Set TEST_RUNNER_OCTAVO_LIVE_DNS=1 and start docs/notes/network-trust/mdns-probes.sh"))
    func namesAreJudgedByWhereTheyResolve() async throws {
        for address in ["http://uz/", "http://octavo-probe-public.local:3300/", "http://octavo-probe-v6.local:3300/"] {
            let url = try #require(URL(string: address))
            let tasks = TaskCounter()
            do {
                _ = try await ServerTransport(server: url).download(for: URLRequest(url: url), delegate: tasks)
                Issue.record("\(address) was loaded")
            } catch NetworkTrustError.insecureAddress(_, reason: .internetAddress) {
                #expect(tasks.count == 0, "\(address) was refused only after a request")
            }
        }
        try await HomeNetworkPolicy.system.check(#require(URL(string: "http://octavo-probe-home.local:3300/")))

        guard let localName = Self.localName else { return }
        let url = try #require(URL(string: "http://\(localName):3300/"))
        let tasks = TaskCounter()
        let (file, response) = try await ServerTransport(server: url).download(for: URLRequest(url: url), delegate: tasks)
        try? FileManager.default.removeItem(at: file)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(tasks.count == 1)
    }
}

/// Counts the tasks a transport makes.
private final class TaskCounter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var made = 0

    var count: Int { lock.withLock { made } }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { made += 1 }
    }
}
