import Foundation
import Synchronization

/// HTTP for one OPDS catalog: feeds, images, downloads and the sign-in check.
///
/// Every request goes through the injected transport: #9's `ServerTransport`
/// checks the address before every request, pins certificates, refuses
/// https → http and strips credentials from redirects that change scheme,
/// host or port. It also answers the server's own Basic or Digest challenge.
/// Only a server recorded as Basic (`authScheme`) gets the password up front,
/// and only on the catalog's own origin (scheme, host and port): never on a
/// cover or file from another host.
struct OPDSClient: Sendable {
    let catalogURL: URL
    let transport: any HTTPTransport
    let credentials: any PasswordStore
    let authScheme: OPDSAuthScheme?
    /// The password, read once rather than from the Keychain per request.
    private let cache = CredentialCache()

    init(catalogURL: URL, transport: any HTTPTransport, credentials: any PasswordStore, authScheme: OPDSAuthScheme?) {
        self.catalogURL = catalogURL
        self.transport = transport
        self.credentials = credentials
        self.authScheme = authScheme
    }

    static let feedAccept = "application/opds+json, application/atom+xml;profile=opds-catalog, application/atom+xml;q=0.9, application/json;q=0.8, application/xml;q=0.7, */*;q=0.5"

    // MARK: Feeds

    /// The feed (or single entry) at `url`, Atom or JSON.
    func feed(at url: URL) async throws -> OPDSFeed {
        let (data, response) = try await data(at: url, accept: Self.feedAccept)
        return try Self.parseFeed(data, response: response, requested: url)
    }

    /// The bytes at `url`; throws `LibraryError` for a non-2xx answer.
    func data(at url: URL, accept: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let request = try await request(url, accept: accept)
        let (data, response) = try await send(request)
        return (data, try await checked(response, data: data))
    }

    static func parseFeed(_ data: Data, response: HTTPURLResponse, requested: URL) throws -> OPDSFeed {
        let base = response.url ?? requested
        let type = response.mimeType?.lowercased() ?? ""
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        let first = body.first { !Set<UInt8>([0x20, 0x09, 0x0A, 0x0D]).contains($0) }
        if type.contains("json") || first == UInt8(ascii: "{") {
            return try OPDSJSONParser.parse(Data(body), url: base)
        }
        // A login page or an error page isn't a catalog.
        guard type != "text/html", first == UInt8(ascii: "<") else { throw LibraryError.invalidResponse }
        return try OPDSAtomParser.parse(Data(body), url: base)
    }

    // MARK: Downloads

    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let request = try await request(url, accept: nil)
        let (temporaryURL, response) = try await withoutURLs { try await transport.download(for: request, delegate: DownloadProgress(progress)) }
        do {
            _ = try await checked(response, data: nil)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    // MARK: Sign-in

    /// Loads the catalog's first page to see whether it needs a sign-in,
    /// with the stored credentials if there are any.
    func checkAccess() async throws -> OPDSAccess {
        let request = try await request(catalogURL, accept: Self.feedAccept)
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw LibraryError.invalidResponse }
        guard http.statusCode == 401 else {
            let feed = try Self.parseFeed(data, response: try await checked(response, data: data), requested: catalogURL)
            return .open(title: feed.title)
        }
        await cache.clear()
        let challenge = http.value(forHTTPHeaderField: "WWW-Authenticate")
        let offered = challenge.flatMap(OPDSAuthScheme.init(challenge:))
        // OPDS 2 servers answer with the Authentication Document, or link it.
        var document: OPDSSignInRequest?
        if http.mimeType?.lowercased().contains("json") == true {
            document = OPDSSignInRequest.authenticationDocument(data)
        }
        if document == nil, let link = Self.authDocumentLink(in: http),
           Self.origin(of: link) == Self.origin(of: catalogURL),
           let (body, _) = try? await self.data(at: link, accept: "application/opds-authentication+json, application/json") {
            document = OPDSSignInRequest.authenticationDocument(body)
        }
        var signIn = document ?? OPDSSignInRequest()
        // The challenge decides when there is one: Digest beats a document's
        // Basic. No challenge and no document: Basic, the only one OPDS defines.
        if challenge != nil || document == nil { signIn.scheme = challenge == nil ? .basic : offered }
        // A server recorded as Digest stays Digest: a later answer (perhaps
        // from someone else at its home address) can't talk it down.
        if authScheme == .digest { signIn.scheme = .digest }
        return .signInRequired(signIn)
    }

    /// `Link: <…>; rel="http://opds-spec.org/auth/document"`.
    private static func authDocumentLink(in response: HTTPURLResponse) -> URL? {
        guard let header = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in header.split(separator: ",") where part.contains(OPDSRel.authDocument) {
            guard let open = part.firstIndex(of: "<"), let close = part.firstIndex(of: ">"), open < close else { continue }
            let href = part[part.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: href, relativeTo: response.url)?.absoluteURL, url.scheme == "http" || url.scheme == "https" else { continue }
            return url
        }
        return nil
    }

    // MARK: Requests

    private func request(_ url: URL, accept: String?) async throws -> URLRequest {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw LibraryError.invalidLink }
        var request = URLRequest(url: url)
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        if authScheme == .basic, Self.origin(of: url) == Self.origin(of: catalogURL), let credentials = try await cache.load(from: credentials) {
            request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withoutURLs { try await transport.data(for: request) }
    }

    /// A `URLError` from the transport, without the failing URL: it's the
    /// real one, with any secret (Kavita's key) put back, and error text
    /// ends up on screen and in logs.
    private func withoutURLs<T>(_ transfer: () async throws -> T) async throws -> T {
        do {
            return try await transfer()
        } catch let error as URLError {
            throw URLError(error.code)
        }
    }

    /// `check`, and a 401 forgets the cached password so the next request
    /// reads the store again (after the user signs in anew).
    private func checked(_ response: URLResponse, data: Data?) async throws -> HTTPURLResponse {
        if (response as? HTTPURLResponse)?.statusCode == 401 { await cache.clear() }
        return try Self.check(response, data: data)
    }

    struct Origin: Hashable {
        var scheme: String
        var host: String
        var port: Int
    }

    static func origin(of url: URL) -> Origin? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else { return nil }
        return Origin(scheme: scheme, host: host, port: url.port ?? (scheme == "https" ? 443 : 80))
    }

    static func check(_ response: URLResponse, data: Data?) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw LibraryError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return http
        case 401:
            throw LibraryError.signedOut
        case 404, 410:
            throw LibraryError.notFound
        default:
            let message = http.mimeType == "text/plain" ? data.map { String(decoding: $0.prefix(200), as: UTF8.self) } : nil
            throw LibraryError.server(status: http.statusCode, message: message)
        }
    }
}

/// Reports a download's progress. The async `download(for:delegate:)` never
/// calls `didWriteData`, so this watches the task's `progress`, once the
/// response is a success.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @Sendable (Double) -> Void
    private let observation = Mutex<NSKeyValueObservation?>(nil)

    init(_ report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let report = report
        let observation = task.progress.observe(\.fractionCompleted) { [weak task] progress, _ in
            guard let status = (task?.response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return }
            report(progress.fractionCompleted)
        }
        self.observation.withLock { $0 = observation }
    }
}

private actor CredentialCache {
    private var loaded = false
    private var credentials: PasswordCredentials?

    func load(from store: any PasswordStore) async throws -> PasswordCredentials? {
        if !loaded {
            credentials = try await store.load()
            loaded = true
        }
        return credentials
    }

    func clear() {
        loaded = false
        credentials = nil
    }
}
