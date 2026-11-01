import Foundation
import Synchronization

/// A fake HTTP server for one test. Each instance gets its own host, so tests
/// running in parallel never see each other's requests.
final class StubServer: Sendable {
    struct Request: Sendable {
        var method: String
        var path: String
        var query: [String: String]
        /// Lowercased names.
        var headers: [String: String]
        var body: Data

        var json: [String: Any]? {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    struct Response: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data

        static func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> Response {
            Response(status: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a }, body: Data(body.utf8))
        }

        static func json(_ body: String, headers: [String: String] = [:]) -> Response {
            json(200, body, headers: headers)
        }

        static let unauthorized = json(401, #"{"statusCode":401,"message":"Unauthorized"}"#)
    }

    let baseURL: URL
    private let handler: @Sendable (Request) -> Response
    private let log = Mutex<[Request]>([])

    /// - Parameters:
    ///   - scheme: `http` needs a domain that `HomeNetworkPolicy` counts as
    ///     local (`lan`) and a policy whose resolver knows the host.
    init(scheme: String = "https", domain: String = "stub.test", _ handler: @escaping @Sendable (Request) -> Response) {
        let host = "\(UUID().uuidString.lowercased()).\(domain)"
        baseURL = URL(string: "\(scheme)://\(host)")!
        self.handler = handler
        StubURLProtocol.register(self, host: host)
    }

    var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    var requests: [Request] { log.withLock { $0 } }

    func requests(to path: String) -> [Request] {
        requests.filter { $0.path == path }
    }

    fileprivate func handle(_ request: Request) -> Response {
        log.withLock { $0.append(request) }
        return handler(request)
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let servers = Mutex<[String: StubServer]>([:])

    static func register(_ server: StubServer, host: String) {
        servers.withLock { $0[host] = server }
    }

    private static func server(for request: URLRequest) -> StubServer? {
        guard let host = request.url?.host else { return nil }
        return servers.withLock { $0[host] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        server(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let server = Self.server(for: request),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let stubRequest = StubServer.Request(
            method: request.httpMethod ?? "GET",
            path: components.path,
            query: (components.queryItems ?? []).reduce(into: [:]) { $0[$1.name] = $1.value },
            headers: (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value },
            body: request.httpBody ?? request.httpBodyStream.map(Self.readAll) ?? Data()
        )
        let response = server.handle(stubRequest)
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        if (300..<400).contains(response.status), let location = response.headers["Location"],
           let target = URL(string: location, relativeTo: url)?.absoluteURL {
            var redirected = request
            redirected.url = target
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: http)
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
