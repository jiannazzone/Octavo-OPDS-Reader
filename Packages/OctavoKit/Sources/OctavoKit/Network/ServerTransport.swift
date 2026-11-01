import Foundation
import Security
import Synchronization

/// How a server client sends requests: `ServerTransport` in the app, so every
/// request goes through the trust rules.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    /// The file at the returned URL is the caller's to move or delete.
    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse)
}

/// Sends one server's requests under D25's trust rules
/// (`docs/notes/network-trust.md`). Make one per server; a new pin needs a
/// new transport.
///
/// - Before every request and every redirect, `HomeNetworkPolicy` checks
///   the address (plain http only to home and VPN addresses), and a server on
///   the internet can't send the app to a home address.
/// - Once a certificate is pinned, the server must present exactly that one
///   (`NetworkTrustError.certificateChanged` otherwise, even if iOS would
///   trust the new one). With no pin, iOS decides; a certificate it doesn't
///   trust fails with `.untrustedCertificate`, which the "Trust this server"
///   step answers. Only the server's own host and port can be pinned.
/// - Redirects never go from https to http, never carry a request body to
///   another server, and lose `Authorization` and `Cookie` when they change
///   scheme, host or port.
/// - HTTP Basic and Digest challenges from the server itself are answered
///   from `passwords`, once per request.
/// - After each request, its metrics show where it actually connected;
///   a connection the checks wouldn't have allowed fails the request.
/// - No cookie jar, no shared credential storage, no cache, TLS 1.2 or later.
public final class ServerTransport: HTTPTransport {
    /// The server's root, e.g. `http://192.168.1.5:3300`.
    public let server: URL

    private let session: URLSession
    private let rules: TrustRules

    /// - Parameter configuration: copied; cookies, credential storage and the
    ///   cache are switched off on the copy.
    public init(
        server: URL,
        pin: CertificatePin? = nil,
        passwords: (any PasswordStore)? = nil,
        policy: HomeNetworkPolicy = .system,
        configuration: URLSessionConfiguration = .default
    ) {
        self.server = server
        rules = TrustRules(server: server, pin: pin, passwords: passwords, policy: policy)
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        // No cache: a cached answer would skip the connection checks, and
        // feeds can carry account details (Kavita puts its key in every link).
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        // No session delegate: challenges and redirects go to each task's
        // `TaskGuard`, which can tie a refusal to its request.
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await guarded(request, delegate: nil) { [session] request, guardian in
            try await session.data(for: request, delegate: guardian)
        }
    }

    public func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        try await guarded(request, delegate: delegate) { [session] request, guardian in
            try await session.download(for: request, delegate: guardian)
        }
    }

    private func guarded<Result>(
        _ request: URLRequest,
        delegate: (any URLSessionTaskDelegate)?,
        transfer: (URLRequest, TaskGuard) async throws -> Result
    ) async throws -> Result {
        guard let url = request.url else { throw URLError(.badURL) }
        try await rules.check(url)
        let guardian = TaskGuard(rules: rules, inner: delegate)
        let result: Result
        do {
            result = try await transfer(request, guardian)
        } catch {
            // The guard cancelled the task; say why instead of "cancelled".
            if let refusal = guardian.refusal { throw refusal }
            throw error
        }
        // The metrics showed a connection the checks wouldn't have allowed.
        // They matter for plain http and for an internet server's requests.
        let plainHTTP = url.scheme?.lowercased() == "http"
        if plainHTTP || !rules.serverIsLocal {
            let collected = await guardian.metricsCollected(within: .seconds(5))
            try Task.checkCancellation()
            if !collected, plainHTTP, rules.policy.verifiesConnections {
                guardian.refuse(.insecureAddress(host: url.connectionHost ?? "", reason: .unverifiedConnection))
            }
        }
        if let refusal = guardian.refusal {
            if let file = result as? (URL, URLResponse) { try? FileManager.default.removeItem(at: file.0) }
            throw refusal
        }
        return result
    }
}

/// What one transport enforces, shared by its tasks' guards.
struct TrustRules: Sendable {
    let policy: HomeNetworkPolicy
    let pin: CertificatePin?
    let passwords: (any PasswordStore)?
    private let origin: Origin?
    let serverIsLocal: Bool

    init(server: URL, pin: CertificatePin?, passwords: (any PasswordStore)?, policy: HomeNetworkPolicy) {
        self.policy = policy
        self.pin = pin
        self.passwords = passwords
        origin = Origin(server)
        serverIsLocal = HomeNetworkPolicy.isLocalAddress(server)
    }

    /// The policy check, plus: a server on the internet doesn't get to send
    /// the app to home addresses (a hostile catalog probing the router).
    func check(_ url: URL) async throws {
        try await policy.check(url)
        if !serverIsLocal, HomeNetworkPolicy.isLocalAddress(url) {
            throw NetworkTrustError.insecureAddress(host: url.host(percentEncoded: true) ?? "", reason: .localAddressFromInternetServer)
        }
    }

    /// The challenge came from the server itself, not from another host its
    /// pages link or redirect to.
    func isServer(_ space: URLProtectionSpace) -> Bool {
        guard let origin, let scheme = space.protocol?.lowercased() else { return false }
        return Origin(scheme: scheme, host: space.host, port: space.port) == origin
    }
}

/// Scheme, host and port, with default ports filled in.
struct Origin: Hashable {
    var scheme: String
    var host: String
    var port: Int

    /// - Parameter host: as `URLProtectionSpace` gives it (punycode, a raw
    ///   `%` before an IPv6 zone) or as `URL.connectionHost` does (`%25`).
    init(scheme: String, host: String, port: Int) {
        self.scheme = scheme.lowercased()
        var host = host.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        self.host = host.replacingOccurrences(of: "%25", with: "%")
        self.port = port > 0 ? port : (self.scheme == "https" ? 443 : 80)
    }

    init?(_ url: URL) {
        guard let scheme = url.scheme, let host = url.connectionHost else { return nil }
        self.init(scheme: scheme, host: host, port: url.port ?? 0)
    }
}

/// One request's delegate: checks certificates, redirects and password
/// challenges, and remembers why it refused. Other callbacks go to the
/// caller's delegate (download progress, say), except ones that could change
/// the request after it was checked.
final class TaskGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let rules: TrustRules
    private let inner: (any URLSessionTaskDelegate)?
    private let refusalStorage = Mutex<NetworkTrustError?>(nil)
    private let collected = AsyncStream.makeStream(of: Void.self)

    /// Never forwarded: they could swap the request after the checks.
    private static let withheld: Set<Selector> = [
        #selector(URLSessionTaskDelegate.urlSession(_:task:willBeginDelayedRequest:completionHandler:)),
        #selector(URLSessionTaskDelegate.urlSession(_:task:needNewBodyStream:)),
        #selector(URLSessionTaskDelegate.urlSession(_:task:needNewBodyStreamFrom:completionHandler:)),
    ]

    init(rules: TrustRules, inner: (any URLSessionTaskDelegate)?) {
        self.rules = rules
        self.inner = inner
    }

    var refusal: NetworkTrustError? { refusalStorage.withLock { $0 } }

    func refuse(_ error: NetworkTrustError) {
        refusalStorage.withLock { $0 = $0 ?? error }
    }

    /// Waits for `didFinishCollecting`, which can come after the transfer
    /// returns. `false` if it didn't come in time.
    func metricsCollected(within timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { [stream = collected.stream] group in
            group.addTask {
                for await _ in stream { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    // MARK: Forwarding to the caller's delegate

    override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        guard let selector, !Self.withheld.contains(selector) else { return false }
        return inner?.responds(to: selector) ?? false
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        guard let selector, !Self.withheld.contains(selector), inner?.responds(to: selector) == true else {
            return super.forwardingTarget(for: selector)
        }
        return inner
    }

    // MARK: Challenges

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            return serverTrust(challenge)
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            guard challenge.previousFailureCount == 0, rules.isServer(space),
                  let credentials = try? await rules.passwords?.load() else { return (.performDefaultHandling, nil) }
            return (.useCredential, URLCredential(user: credentials.username, password: credentials.password, persistence: .none))
        default:
            return (.performDefaultHandling, nil)
        }
    }

    private func serverTrust(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard let trust = space.serverTrust else { return (.cancelAuthenticationChallenge, nil) }
        let trustedBySystem = SecTrustEvaluateWithError(trust, nil)
        // Other hosts (a cover server, say): iOS decides, nothing to pin.
        guard rules.isServer(space) else { return (.performDefaultHandling, nil) }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return (.cancelAuthenticationChallenge, nil)
        }
        if let pin = rules.pin {
            if pin.matches(leaf) { return (.useCredential, URLCredential(trust: trust)) }
            refuse(.certificateChanged(CertificateSummary(leaf, host: space.host, port: space.port, isTrustedBySystem: trustedBySystem)))
            return (.cancelAuthenticationChallenge, nil)
        }
        // No pin: let the system (and ATS) decide as usual.
        if trustedBySystem { return (.performDefaultHandling, nil) }
        refuse(.untrustedCertificate(CertificateSummary(leaf, host: space.host, port: space.port)))
        return (.cancelAuthenticationChallenge, nil)
    }

    // MARK: Where it actually connected

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        defer {
            collected.continuation.yield()
            collected.continuation.finish()
        }
        // Every transaction: with no cache, each one went to the network.
        for transaction in metrics.transactionMetrics {
            guard let url = transaction.request.url else { continue }
            if let refusal = rules.policy.verify(url, connectedTo: transaction.remoteAddress,
                                                 throughProxy: transaction.isProxyConnection,
                                                 fromInternetServer: !rules.serverIsLocal) {
                refuse(refusal)
            }
        }
        inner?.urlSession?(session, task: task, didFinishCollecting: metrics)
    }

    // MARK: Redirects

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let from = task.currentRequest?.url ?? task.originalRequest?.url, let to = request.url else {
            task.cancel()
            return nil
        }
        let crossOrigin = Origin(from) != Origin(to)
        let method = request.httpMethod?.uppercased() ?? "GET"
        if from.scheme?.lowercased() == "https" && to.scheme?.lowercased() != "https"
            || crossOrigin && method != "GET" && method != "HEAD" {
            refuse(.insecureRedirect(to.trustDescription))
            task.cancel()
            return nil
        }
        do {
            try await rules.check(to)
        } catch {
            if let error = error as? NetworkTrustError { refuse(error) }
            task.cancel()
            return nil
        }
        var request = request
        if crossOrigin {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        return request
    }
}
