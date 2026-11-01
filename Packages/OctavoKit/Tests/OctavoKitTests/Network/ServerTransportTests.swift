import Foundation
@testable import OctavoKit
import Testing

struct ServerTransportTests {
    let resolver = FakeResolver()

    private func transport(_ server: StubServer, passwords: (any PasswordStore)? = nil) -> ServerTransport {
        ServerTransport(server: server.baseURL, passwords: passwords, policy: .testing(resolver), configuration: server.configuration)
    }

    private func homeServer(_ handler: @escaping @Sendable (StubServer.Request) -> StubServer.Response) -> StubServer {
        let server = StubServer(scheme: "http", domain: "lan", handler)
        resolver.set(server.baseURL.host()!, ["192.168.1.5"])
        return server
    }

    /// D25: checked on every connection, not only when the server is added.
    @Test func rechecksTheAddressBeforeEveryRequest() async throws {
        let server = homeServer { _ in .json("{}") }
        let transport = transport(server)
        var request = URLRequest(url: server.baseURL.appending(path: "opds"))
        request.setValue("Basic b2N0YXZvOnNlY3JldA==", forHTTPHeaderField: "Authorization")

        _ = try await transport.data(for: request)
        // Away from home, the saved name now answers with an internet address.
        resolver.set(server.baseURL.host()!, ["192.168.1.5", "203.0.113.9"])

        await #expect(throws: NetworkTrustError.insecureAddress(host: server.baseURL.host()!, reason: .internetAddress("203.0.113.9"))) {
            try await transport.data(for: request)
        }
        await #expect(throws: NetworkTrustError.self) {
            try await transport.download(for: request, delegate: nil)
        }
        #expect(server.requests.count == 1)
    }

    /// Plain http whose real connection can't be checked (a stub protocol
    /// has no address) fails closed, after the transfer.
    @Test func plainHTTPFailsClosedWhenTheConnectionCantBeVerified() async throws {
        let server = homeServer { _ in .json("{}") }
        let transport = ServerTransport(server: server.baseURL, policy: .testing(resolver, verifiesConnections: true), configuration: server.configuration)
        await #expect(throws: NetworkTrustError.insecureAddress(host: server.baseURL.host()!, reason: .unverifiedConnection)) {
            try await transport.data(for: URLRequest(url: server.baseURL.appending(path: "opds")))
        }
        await #expect(throws: NetworkTrustError.self) {
            try await transport.download(for: URLRequest(url: server.baseURL.appending(path: "book.epub")), delegate: nil)
        }
    }

    @Test func refusesHTTPSToHTTPRedirects() async throws {
        let target = homeServer { _ in .json("{}") }
        let server = StubServer { _ in StubServer.Response(status: 302, headers: ["Location": target.baseURL.appending(path: "x").absoluteString], body: Data()) }

        await #expect(throws: NetworkTrustError.insecureRedirect(target.baseURL.appending(path: "x").absoluteString)) {
            try await transport(server).data(for: URLRequest(url: server.baseURL.appending(path: "opds")))
        }
        #expect(target.requests.isEmpty)
    }

    @Test func refusesRedirectsToInternetAddresses() async throws {
        let outside = StubServer(scheme: "http", domain: "lan") { _ in .json("{}") }
        resolver.set(outside.baseURL.host()!, ["203.0.113.9"])
        let server = homeServer { _ in StubServer.Response(status: 302, headers: ["Location": outside.baseURL.absoluteString], body: Data()) }

        await #expect(throws: NetworkTrustError.self) {
            try await transport(server).data(for: URLRequest(url: server.baseURL.appending(path: "opds")))
        }
        #expect(outside.requests.isEmpty)
    }

    @Test func redirectsToAnotherHostLoseCredentials() async throws {
        let other = StubServer { _ in .json(#"{"ok":true}"#) }
        let server = StubServer { _ in StubServer.Response(status: 302, headers: ["Location": other.baseURL.appending(path: "file").absoluteString], body: Data()) }
        var request = URLRequest(url: server.baseURL.appending(path: "download"))
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("session=secret", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await transport(server).data(for: request)

        #expect(String(decoding: data, as: UTF8.self) == #"{"ok":true}"#)
        let forwarded = try #require(other.requests.first)
        #expect(forwarded.headers["authorization"] == nil)
        #expect(forwarded.headers["cookie"] == nil)
        #expect(forwarded.headers["accept"] == "application/json")
    }

    @Test func redirectsWithinTheServerKeepCredentials() async throws {
        let server = StubServer { request in
            request.path == "/old"
                ? StubServer.Response(status: 301, headers: ["Location": "/new"], body: Data())
                : .json("{}")
        }
        var request = URLRequest(url: server.baseURL.appending(path: "old"))
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")

        _ = try await transport(server).data(for: request)

        #expect(server.requests(to: "/new").first?.headers["authorization"] == "Bearer secret")
    }

    /// A catalog on the internet can't make the app poke at the home network
    /// (a router's admin page, say), by link or by redirect.
    @Test func internetServersCantReachHomeAddresses() async throws {
        let router = homeServer { _ in .json("{}") }
        let catalog = StubServer { _ in StubServer.Response(status: 302, headers: ["Location": router.baseURL.absoluteString], body: Data()) }
        let transport = transport(catalog)

        await #expect(throws: NetworkTrustError.insecureAddress(host: router.baseURL.host()!, reason: .localAddressFromInternetServer)) {
            try await transport.data(for: URLRequest(url: router.baseURL.appending(path: "cgi-bin/reboot")))
        }
        await #expect(throws: NetworkTrustError.self) {
            try await transport.data(for: URLRequest(url: catalog.baseURL.appending(path: "cover")))
        }
        #expect(router.requests.isEmpty)
    }

    /// A 307 or 308 resends the body: never to another server.
    @Test func redirectsDontCarryBodiesToAnotherServer() async throws {
        let other = StubServer { _ in .json("{}") }
        let server = StubServer { _ in StubServer.Response(status: 307, headers: ["Location": other.baseURL.appending(path: "auth/login").absoluteString], body: Data()) }
        var login = URLRequest(url: server.baseURL.appending(path: "api/v1/auth/login"))
        login.httpMethod = "POST"
        login.httpBody = Data(#"{"username":"octavo","password":"secret"}"#.utf8)

        await #expect(throws: NetworkTrustError.insecureRedirect(other.baseURL.appending(path: "auth/login").absoluteString)) {
            try await transport(server).data(for: login)
        }
        #expect(other.requests.isEmpty)
    }

    @Test func noCookieJarOrCredentialStorage() async throws {
        let server = StubServer { request in
            request.path == "/login"
                ? .json("{}", headers: ["Set-Cookie": "session=abc; Path=/"])
                : .json("{}")
        }
        let transport = transport(server)
        _ = try await transport.data(for: URLRequest(url: server.baseURL.appending(path: "login")))
        _ = try await transport.data(for: URLRequest(url: server.baseURL.appending(path: "feed")))
        #expect(server.requests(to: "/feed").first?.headers["cookie"] == nil)
    }

    /// Basic and Digest challenges get the stored password only from the
    /// server itself, and only once (a wrong password fails instead of looping).
    @Test func answersPasswordChallengesOnlyFromTheServer() async throws {
        let rules = TrustRules(
            server: URL(string: "http://nas.lan:8083/opds")!, pin: nil,
            passwords: InMemoryPasswordStore(PasswordCredentials(username: "octavo", password: "secret")),
            policy: .testing(resolver)
        )
        let guardian = TaskGuard(rules: rules, inner: nil)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "http://nas.lan:8083/opds")!)

        func answer(_ host: String, _ port: Int, _ scheme: String, method: String = NSURLAuthenticationMethodHTTPBasic, failures: Int = 0) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            let space = URLProtectionSpace(host: host, port: port, protocol: scheme, realm: "OPDS", authenticationMethod: method)
            let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: failures,
                                                       failureResponse: nil, error: nil, sender: NoSender())
            return await guardian.urlSession(session, task: task, didReceive: challenge)
        }

        let basic = await answer("nas.lan", 8083, "http")
        #expect(basic.0 == .useCredential)
        #expect(basic.1?.user == "octavo")
        #expect(basic.1?.password == "secret")
        #expect(basic.1?.persistence == URLCredential.Persistence.none)
        #expect(await answer("NAS.LAN", 8083, "http", method: NSURLAuthenticationMethodHTTPDigest).0 == .useCredential)
        #expect(await answer("nas.lan", 8083, "http", failures: 1).0 == .performDefaultHandling)
        #expect(await answer("cdn.lan", 8083, "http").0 == .performDefaultHandling)
        #expect(await answer("nas.lan", 80, "http").0 == .performDefaultHandling)
        #expect(await answer("nas.lan", 8083, "https").0 == .performDefaultHandling)
        task.cancel()
    }

    @Test func passwordsNeverPrint() {
        let credentials = PasswordCredentials(username: "octavo", password: "hunter2")
        #expect(!String(describing: credentials).contains("hunter2"))
        #expect(!String(reflecting: credentials).contains("hunter2"))
        #expect(!"\(credentials)".contains("hunter2"))
    }

    @Test func origins() throws {
        #expect(Origin(URL(string: "https://NAS.lan/x")!) == Origin(URL(string: "https://nas.lan:443/y")!))
        #expect(Origin(URL(string: "http://nas.lan/x")!) == Origin(URL(string: "http://nas.lan:80")!))
        #expect(Origin(URL(string: "http://nas.lan/x")!) != Origin(URL(string: "https://nas.lan/x")!))
        #expect(Origin(URL(string: "http://[::1]:3300/x")!) == Origin(scheme: "http", host: "::1", port: 3300))
        #expect(Origin(URL(string: "http://[::1]:3300/x")!) == Origin(scheme: "http", host: "[::1]", port: 3300))
    }
}

private final class NoSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
