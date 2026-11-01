import Foundation
import Synchronization

/// HTTP for one OPDS catalog: feeds, images, downloads and the sign-in check.
///
/// The `URLSession` is injected so the trust-aware session (#9) can replace
/// it. The Basic sign-in goes only to the catalog's own origin (scheme, host
/// and port): never to a cover or file on another host, and it's dropped
/// when a redirect leaves the origin or drops to http. Whether http may
/// carry it at all is the session's call (decision 25).
struct OPDSClient: Sendable {
    let catalogURL: URL
    let session: URLSession
    let credentials: any OPDSCredentialStore

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
        let (data, response) = try await session.data(for: request, delegate: TaskDelegate(origin: Self.origin(of: catalogURL)))
        return (data, try Self.check(response, data: data))
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
        let delegate = TaskDelegate(origin: Self.origin(of: catalogURL), progress: progress)
        let (temporaryURL, response) = try await session.download(for: request, delegate: delegate)
        do {
            _ = try Self.check(response, data: nil)
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
        let (data, response) = try await session.data(for: request, delegate: TaskDelegate(origin: Self.origin(of: catalogURL)))
        guard let http = response as? HTTPURLResponse else { throw LibraryError.invalidResponse }
        guard http.statusCode == 401 else {
            let feed = try Self.parseFeed(data, response: try Self.check(response, data: data), requested: catalogURL)
            return .open(title: feed.title)
        }
        // OPDS 2 servers answer with the Authentication Document, or link it.
        if http.mimeType?.lowercased().contains("json") == true, let document = OPDSSignInRequest.authenticationDocument(data) {
            return .signInRequired(document)
        }
        if let link = Self.authDocumentLink(in: http),
           let (body, _) = try? await self.data(at: link, accept: "application/opds-authentication+json, application/json"),
           let document = OPDSSignInRequest.authenticationDocument(body) {
            return .signInRequired(document)
        }
        let challenge = http.value(forHTTPHeaderField: "WWW-Authenticate")?.lowercased()
        return .signInRequired(OPDSSignInRequest(supportsBasic: challenge.map { $0.hasPrefix("basic") } ?? true))
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
        if Self.origin(of: url) == Self.origin(of: catalogURL), let credentials = try await credentials.load() {
            request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        return request
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

/// Per request: drops the sign-in on a redirect that leaves the catalog's
/// origin, and reports download progress. The async
/// `download(for:delegate:)` never calls `didWriteData`, so progress comes
/// from the task's `progress`, once the response is a success.
private final class TaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let origin: OPDSClient.Origin?
    private let report: (@Sendable (Double) -> Void)?
    private let observation = Mutex<NSKeyValueObservation?>(nil)

    init(origin: OPDSClient.Origin?, progress: (@Sendable (Double) -> Void)? = nil) {
        self.origin = origin
        self.report = progress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        guard let report else { return }
        let observation = task.progress.observe(\.fractionCompleted) { [weak task] progress, _ in
            guard let status = (task?.response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return }
            report(progress.fractionCompleted)
        }
        self.observation.withLock { $0 = observation }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        var request = request
        if let url = request.url, OPDSClient.origin(of: url) != origin {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
