import Foundation
import Synchronization

public enum BookOrbitError: Error, Equatable, Sendable {
    /// No stored credentials. Call `login` first.
    case notSignedIn
    /// The server rejected the refresh token (or the refreshed access token).
    /// Credentials are cleared; sign in again.
    case sessionExpired
    /// Any other non-2xx answer. `message` is BookOrbit's error text.
    case http(status: Int, message: String?)
    case invalidResponse
}

/// Talks to one BookOrbit server's REST API (`/api/v1`).
///
/// Signs in as a native client, so the refresh token comes back in the body
/// and is kept in `tokenStore`. On a 401 it refreshes once (one refresh at a
/// time, since BookOrbit rotates refresh tokens) and retries the request.
/// Servers older than BookOrbit 3.0 only hand out a refresh cookie; the client
/// lifts that out of `Set-Cookie` and replays it by hand, so it never depends
/// on a cookie jar.
public actor BookOrbitClient {
    /// The server root, e.g. `http://localhost:3300`.
    public nonisolated let baseURL: URL

    private let session: URLSession
    private let tokenStore: any BookOrbitTokenStore
    private let deviceLabel: String
    private let requestsNativeCredentials: Bool
    private let decoder = BookOrbitClient.makeDecoder()
    private let encoder = JSONEncoder()

    private var credentials: BookOrbitCredentials?
    private var credentialsLoaded = false
    private var refreshTask: Task<BookOrbitCredentials, any Error>?

    /// - Parameters:
    ///   - deviceLabel: shown in BookOrbit's list of signed-in sessions.
    ///   - configuration: copied; cookie handling is switched off on the copy.
    public init(
        baseURL: URL,
        tokenStore: any BookOrbitTokenStore = InMemoryBookOrbitTokenStore(),
        deviceLabel: String = "Octavo",
        configuration: URLSessionConfiguration = .default
    ) {
        self.init(
            baseURL: baseURL,
            tokenStore: tokenStore,
            deviceLabel: deviceLabel,
            configuration: configuration,
            requestsNativeCredentials: true
        )
    }

    /// `requestsNativeCredentials: false` signs in like the web app (refresh
    /// cookie only), to exercise the pre-3.0 path against a current server.
    init(
        baseURL: URL,
        tokenStore: any BookOrbitTokenStore,
        deviceLabel: String,
        configuration: URLSessionConfiguration,
        requestsNativeCredentials: Bool
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.deviceLabel = deviceLabel
        self.requestsNativeCredentials = requestsNativeCredentials
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    // MARK: - Auth

    /// `POST auth/login`. Stores the new credentials.
    @discardableResult
    public func login(username: String, password: String) async throws -> BookOrbitUser {
        var (data, response) = try await postLogin(username: username, password: password, native: requestsNativeCredentials)
        // Before 3.0 the server rejects the unknown `clientKind` field.
        if requestsNativeCredentials, response.statusCode == 400,
           errorMessage(in: data)?.contains("clientKind") == true {
            (data, response) = try await postLogin(username: username, password: password, native: false)
        }
        try check(response, data)
        let body = try decode(LoginResponse.self, from: data)
        guard let user = body.user else { throw BookOrbitError.invalidResponse }
        try await store(credentials(from: body, response: response, previous: nil))
        return user
    }

    /// Forgets the stored credentials. Doesn't end the session on the server.
    public func signOut() async throws {
        try await store(nil)
    }

    private func postLogin(username: String, password: String, native: Bool) async throws -> (Data, HTTPURLResponse) {
        struct Body: Encodable {
            var username: String
            var password: String
            var clientKind: String?
            var deviceLabel: String?
        }
        let body = Body(
            username: username,
            password: password,
            clientKind: native ? "native" : nil,
            deviceLabel: native ? deviceLabel : nil
        )
        let (data, response) = try await session.data(for: jsonRequest("auth/login", method: "POST", body: body))
        return (data, try http(response))
    }

    /// Credentials loaded from the store on first use.
    private func currentCredentials() async throws -> BookOrbitCredentials {
        if !credentialsLoaded {
            credentials = try await tokenStore.load()
            credentialsLoaded = true
        }
        guard let credentials else { throw BookOrbitError.notSignedIn }
        return credentials
    }

    private func store(_ new: BookOrbitCredentials?) async throws {
        credentials = new
        credentialsLoaded = true
        try await tokenStore.save(new)
    }

    /// Fresh credentials after `staleAccessToken` got a 401. Concurrent
    /// callers share one refresh.
    private func refreshedCredentials(replacing staleAccessToken: String) async throws -> BookOrbitCredentials {
        if let credentials, credentials.accessToken != staleAccessToken { return credentials }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// `POST auth/refresh`. A 401 ends the session; other failures (offline,
    /// 5xx) leave the credentials alone.
    private func performRefresh() async throws -> BookOrbitCredentials {
        let current = try await currentCredentials()
        guard let refreshToken = current.refreshToken else {
            try await store(nil)
            throw BookOrbitError.sessionExpired
        }
        var request: URLRequest
        switch current.refreshTransport {
        case .body:
            request = try jsonRequest("auth/refresh", method: "POST", body: ["refreshToken": refreshToken])
        case .cookie:
            request = try jsonRequest("auth/refresh", method: "POST", body: [String: String]())
            request.setValue("refresh_token=\(refreshToken)", forHTTPHeaderField: "Cookie")
        }
        let (data, urlResponse) = try await session.data(for: request)
        let response = try http(urlResponse)
        if response.statusCode == 401 {
            try await store(nil)
            throw BookOrbitError.sessionExpired
        }
        try check(response, data)
        let fresh = credentials(from: try decode(LoginResponse.self, from: data), response: response, previous: current)
        try await store(fresh)
        return fresh
    }

    private func credentials(from body: LoginResponse, response: HTTPURLResponse, previous: BookOrbitCredentials?) -> BookOrbitCredentials {
        var result = BookOrbitCredentials(
            accessToken: body.accessToken,
            accessTokenExpiresAt: body.accessTokenExpiresAt,
            refreshToken: body.refreshToken,
            refreshTokenExpiresAt: body.refreshTokenExpiresAt,
            refreshTransport: .body,
            sessionID: body.sessionId ?? previous?.sessionID
        )
        if body.refreshToken == nil {
            result.refreshTransport = .cookie
            if let cookie = refreshCookie(in: response) {
                result.refreshToken = cookie.value
                result.refreshTokenExpiresAt = cookie.expiresDate
            } else {
                result.refreshToken = previous?.refreshToken
                result.refreshTokenExpiresAt = previous?.refreshTokenExpiresAt
            }
        }
        return result
    }

    private func refreshCookie(in response: HTTPURLResponse) -> HTTPCookie? {
        guard let url = response.url else { return nil }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let key = field.key as? String, let value = field.value as? String { result[key] = value }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .first { $0.name == "refresh_token" && !$0.value.isEmpty }
    }

    // MARK: - Library

    /// `GET libraries`.
    public func libraries() async throws -> [BookOrbitLibrary] {
        try await get("libraries")
    }

    /// `GET collections`: the user's own collections plus public ones.
    public func collections() async throws -> [BookOrbitCollection] {
        try await get("collections", as: LossyArray<BookOrbitCollection>.self).elements
    }

    // Paged lists below: `page` is 0-based. BookOrbit 3.6 allows `size` up to
    // 100 for series and authors, 200 for `books/query`.

    /// `GET collections/{id}/books`.
    public func collectionBooks(collectionID: Int, page: Int = 0, size: Int = 50) async throws -> BookOrbitPage<BookOrbitBook> {
        try await get("collections/\(collectionID)/books", query: pageQuery(page, size))
    }

    /// `GET smart-scopes`: saved filters, the user's own plus public ones.
    public func smartScopes() async throws -> [BookOrbitSmartScope] {
        try await get("smart-scopes", as: LossyArray<BookOrbitSmartScope>.self).elements
    }

    /// `GET smart-scopes/{id}/books`, in the scope's own sort order.
    public func smartScopeBooks(scopeID: Int, page: Int = 0, size: Int = 50) async throws -> BookOrbitPage<BookOrbitBook> {
        try await get("smart-scopes/\(scopeID)/books", query: pageQuery(page, size))
    }

    /// `POST books/query`: books across every library the user can see.
    /// `query` matches titles, authors and series.
    public func books(matching query: String? = nil, sort: [BookOrbitBookSort] = [], page: Int = 0, size: Int = 50) async throws -> BookOrbitPage<BookOrbitBook> {
        struct Body: Encodable {
            struct Pagination: Encodable { var page: Int; var size: Int }
            var q: String?
            var sort: [BookOrbitBookSort]
            var pagination: Pagination
        }
        let body = Body(q: query, sort: sort, pagination: .init(page: page, size: size))
        return try decode(BookOrbitPage<BookOrbitBook>.self, from: try await send(jsonRequest("books/query", method: "POST", body: body)))
    }

    /// `GET series`, by name.
    public func series(page: Int = 0, size: Int = 50) async throws -> BookOrbitPage<BookOrbitSeries> {
        try await get("series", query: pageQuery(page, size) + sortQuery("name", "asc"))
    }

    /// `GET series/{id}/books`, in reading order.
    public func seriesBooks(seriesID: Int, page: Int = 0, size: Int = 50) async throws -> BookOrbitPage<BookOrbitBook> {
        try await get("series/\(seriesID)/books", query: pageQuery(page, size) + sortQuery("seriesIndex", "asc"))
    }

    /// `GET authors`, by sort name ("Austen, Jane").
    public func authors(page: Int = 0, size: Int = 50) async throws -> BookOrbitPage<BookOrbitAuthor> {
        try await get("authors", query: pageQuery(page, size) + sortQuery("sortName", "asc"))
    }

    /// `GET authors/{id}/books`, by title.
    public func authorBooks(authorID: Int, page: Int = 0, size: Int = 50) async throws -> BookOrbitPage<BookOrbitBook> {
        try await get("authors/\(authorID)/books", query: pageQuery(page, size) + sortQuery("title", "asc"))
    }

    /// `GET search`: books, series and authors matching `query`, up to
    /// `limit` (1–10) of each. BookOrbit needs at least 2 characters.
    public func search(_ query: String, limit: Int = 10) async throws -> BookOrbitSearchResults {
        try await get("search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    /// `GET dashboard/scrollers/continue-reading`: the books BookOrbit's own
    /// home lists under Continue reading, most recently read first, up to
    /// `limit`.
    public func continueReading(limit: Int = 20) async throws -> [BookOrbitBook] {
        struct Scroller: Decodable { var books: LossyArray<BookOrbitBook> }
        return try await get("dashboard/scrollers/continue-reading", query: [URLQueryItem(name: "limit", value: String(limit))],
                             as: Scroller.self).books.elements
    }

    /// `GET books/{id}`.
    public func book(id: Int) async throws -> BookOrbitBook {
        try await get("books/\(id)")
    }

    /// `GET books/{id}/thumbnail` (about 386×600) or `books/{id}/cover` (the
    /// original): the image bytes.
    public func cover(bookID: Int, thumbnail: Bool = true) async throws -> Data {
        var request = URLRequest(url: apiURL("books/\(bookID)/\(thumbnail ? "thumbnail" : "cover")"))
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    /// `GET books/files/{fileId}/serve`, saved to `destination` (replaced if
    /// it exists). `progress` gets 0...1 as bytes arrive; it stays at 0 if
    /// the server doesn't send a length. Cancelling the task cancels the
    /// download and leaves `destination` alone.
    @discardableResult
    public func download(fileID: Int, to destination: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let request = URLRequest(url: apiURL("books/files/\(fileID)/serve"))
        let (temporaryURL, response) = try await authorized(request) { [session] request in
            let (url, response) = try await session.download(for: request, delegate: progress.map(DownloadProgress.init))
            // The retry downloads again; drop the 401's body.
            if (response as? HTTPURLResponse)?.statusCode == 401 { try? FileManager.default.removeItem(at: url) }
            return (url, response)
        }
        guard (200..<300).contains(response.statusCode) else {
            let data = (try? Data(contentsOf: temporaryURL)) ?? Data()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error(for: response, data)
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    // MARK: - Progress

    /// `GET books/files/{fileId}/progress`. `nil` if the file has no saved
    /// position.
    public func progress(fileID: Int) async throws -> BookOrbitProgress? {
        try await get("books/files/\(fileID)/progress", as: ProgressResponse.self).progress
    }

    /// `POST books/files/{fileId}/progress`. Replaces the stored text
    /// position (last write wins), CFI included.
    public func saveProgress(_ position: ReadingPosition, fileID: Int) async throws {
        let request = try jsonRequest("books/files/\(fileID)/progress", method: "POST", body: SaveProgressRequest(position))
        _ = try await send(request)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        var url = apiURL(path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try decode(type, from: try await send(request))
    }

    /// Sends an authorized request and checks the status.
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await authorized(request) { [session] in try await session.data(for: $0) }
        try check(response, data)
        return data
    }

    /// Adds the bearer token; on a 401, refreshes and retries once.
    private func authorized<Result: Sendable>(
        _ request: URLRequest,
        transport: (URLRequest) async throws -> (Result, URLResponse)
    ) async throws -> (Result, HTTPURLResponse) {
        let credentials = try await currentCredentials()
        var request = request
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        let (result, response) = try await transport(request)
        let first = try http(response)
        guard first.statusCode == 401 else { return (result, first) }

        let fresh = try await refreshedCredentials(replacing: credentials.accessToken)
        request.setValue("Bearer \(fresh.accessToken)", forHTTPHeaderField: "Authorization")
        let (retryResult, retryResponse) = try await transport(request)
        let retry = try http(retryResponse)
        if retry.statusCode == 401 { throw BookOrbitError.sessionExpired }
        return (retryResult, retry)
    }

    private func pageQuery(_ page: Int, _ size: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "size", value: String(size))]
    }

    private func sortQuery(_ sort: String, _ order: String) -> [URLQueryItem] {
        [URLQueryItem(name: "sort", value: sort), URLQueryItem(name: "order", value: order)]
    }

    private func apiURL(_ path: String) -> URL {
        baseURL.appending(path: "api/v1/" + path)
    }

    private func jsonRequest(_ path: String, method: String, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: apiURL(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func http(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else { throw BookOrbitError.invalidResponse }
        return response
    }

    private func check(_ response: HTTPURLResponse, _ data: Data) throws {
        guard (200..<300).contains(response.statusCode) else { throw error(for: response, data) }
    }

    private func error(for response: HTTPURLResponse, _ data: Data) -> BookOrbitError {
        .http(status: response.statusCode, message: errorMessage(in: data))
    }

    private func errorMessage(in data: Data) -> String? {
        (try? decoder.decode(ErrorResponse.self, from: data))?.message
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw BookOrbitError.invalidResponse
        }
    }

    /// BookOrbit sends ISO 8601 dates, with or without milliseconds.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(string)")
        }
        return decoder
    }
}

/// Reports a download's progress. The async `download(for:delegate:)` never
/// calls `didWriteData` on a task delegate, so this watches the task's
/// `progress` instead, and only once the response is a success (a 401's
/// body would otherwise count before the retry).
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
