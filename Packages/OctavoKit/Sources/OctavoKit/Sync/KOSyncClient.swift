import CryptoKit
import Foundation

public enum KOSyncError: Error, Equatable, Sendable {
    /// 401: the username or password is wrong, or the account is gone.
    case unauthorized
    /// The server doesn't have this file (Kavita answers 400, Komga 404). A
    /// standalone server has every file, and answers `{}` for one it hasn't
    /// seen.
    case unknownDocument
    /// Any other 4xx: sending it again won't help.
    case rejected(status: Int)
    /// 408, 429 or a 5xx: try again later.
    case unavailable(status: Int)
    /// A place this client won't send: empty, too long, or not a finite
    /// percentage. KOReader opens a book at page 1 for a place it can't read.
    case invalidPlace
    case invalidResponse

    /// Whether sending it again later can't work.
    public var isPermanent: Bool {
        switch self {
        case .unavailable, .invalidResponse: false
        case .unauthorized, .unknownDocument, .rejected, .invalidPlace: true
        }
    }
}

/// A KOReader sync account as the protocol sends it: the username, and the
/// password's MD5 in lowercase hex, which is all the server ever checks. The
/// key stands in for the password, so it's kept like one (in the Keychain)
/// and never printed.
public struct KOSyncKey: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var username: String
    public var key: String

    /// Keeps the password's MD5, not the password.
    public init(username: String, password: String) {
        self.init(username: username, key: Insecure.MD5.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined())
    }

    public init(username: String, key: String) {
        self.username = username
        self.key = key
    }

    public var description: String { "KOSyncKey(username: \(username), key: •••)" }
    public var debugDescription: String { description }
}

/// A book's place as a sync server holds it. Everything in it came from the
/// server, so it's checked here and treated as untrusted after.
public struct KOSyncProgress: Equatable, Sendable {
    /// KOReader's position: an xpointer in a reflowing book, a page number in
    /// a paged one. At most `KOSyncClient.maximumPlaceLength` characters.
    public var progress: String
    /// 0...1.
    public var percentage: Double
    /// What the sending device called itself, as it said.
    public var device: String?
    public var deviceID: String?
    /// When the server took it. `nil` if it doesn't say (Komga) or says
    /// something impossible (Kavita's year 1 for a book never read).
    public var timestamp: Date?

    public init(progress: String, percentage: Double, device: String? = nil, deviceID: String? = nil, timestamp: Date? = nil) {
        self.progress = progress
        self.percentage = percentage
        self.device = device
        self.deviceID = deviceID
        self.timestamp = timestamp
    }
}

/// Talks to one KOReader sync server (`docs/notes/koreader-sync.md`): a
/// standalone `koreader-sync-server`, or the same protocol under another
/// server's address (Kavita's `/api/koreader/{key}`, Komga's `/koreader`).
///
/// - `GET users/auth`, `GET syncs/progress/{document}` and
///   `PUT syncs/progress`, each with `x-auth-user` and `x-auth-key` and the
///   vendor `Accept` the standalone server insists on.
/// - Only 200 counts. Answers vary by server, so they're read loosely, and
///   a PUT's body is ignored.
/// - The transport should be the account's own `ServerTransport` with a
///   small `maximumDataSize`: the answers are a few hundred bytes.
public struct KOSyncClient: Sendable {
    /// The protocol's root, e.g. `https://sync.example.com` or
    /// `https://books.example.com/koreader`.
    public let baseURL: URL

    private let key: KOSyncKey
    private let transport: any HTTPTransport

    /// The longest `progress` sent or read. An xpointer is well under 1 KB.
    public static let maximumPlaceLength = 2048
    static let maximumNameLength = 128
    static let mediaType = "application/vnd.koreader.v1+json"

    public init(baseURL: URL, key: KOSyncKey, transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.key = key
        self.transport = transport
    }

    /// `GET users/auth`: returns if the account signs in, else throws.
    public func authorize() async throws {
        _ = try await send(request("users/auth"))
    }

    /// `GET syncs/progress/{document}`: the server's place for the book, or
    /// `nil` if it has none (or only one this client couldn't use).
    public func progress(of document: KOSyncDocument) async throws -> KOSyncProgress? {
        let data = try await send(request("syncs/progress/\(document.id)"))
        guard let body = try? JSONDecoder().decode(ProgressBody.self, from: data) else { throw KOSyncError.invalidResponse }
        return body.progress
    }

    /// `PUT syncs/progress`. `progress` has to be a place KOReader can read:
    /// it opens a book at page 1 for one it can't.
    public func update(_ document: KOSyncDocument, progress: String, percentage: Double, device: String, deviceID: String) async throws {
        guard !progress.isEmpty, progress.count <= Self.maximumPlaceLength, percentage.isFinite else { throw KOSyncError.invalidPlace }
        var request = request("syncs/progress")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(UpdateBody(
            document: document.id, progress: progress, percentage: min(max(percentage, 0), 1), device: device, deviceID: deviceID
        ))
        _ = try await send(request)
    }

    // MARK: - Plumbing

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue(Self.mediaType, forHTTPHeaderField: "Accept")
        request.setValue(key.username, forHTTPHeaderField: "x-auth-user")
        request.setValue(key.key, forHTTPHeaderField: "x-auth-key")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw KOSyncError.invalidResponse }
        switch response.statusCode {
        case 200: return data
        case 401: throw KOSyncError.unauthorized
        case 400, 404: throw KOSyncError.unknownDocument
        case 408, 429, 500...: throw KOSyncError.unavailable(status: response.statusCode)
        default: throw KOSyncError.rejected(status: response.statusCode)
        }
    }

    private struct UpdateBody: Encodable {
        var document: String
        var progress: String
        var percentage: Double
        var device: String
        var deviceID: String

        enum CodingKeys: String, CodingKey {
            case document, progress, percentage, device
            case deviceID = "device_id"
        }
    }

    /// A GET's answer, as any of the servers send it: `{}` or a message for
    /// no place, a percentage as a number or a string, and a timestamp in
    /// seconds, as a string, or as a date.
    private struct ProgressBody: Decodable {
        var progress: KOSyncProgress?

        enum CodingKeys: String, CodingKey {
            case progress, percentage, device, timestamp
            case deviceID = "device_id"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let place = Self.text(container, .progress, limit: KOSyncClient.maximumPlaceLength),
                  let percentage = Self.number(container, .percentage), percentage.isFinite
            else { return }
            progress = KOSyncProgress(
                progress: place,
                percentage: min(max(percentage, 0), 1),
                device: Self.text(container, .device, limit: KOSyncClient.maximumNameLength),
                deviceID: Self.text(container, .deviceID, limit: KOSyncClient.maximumNameLength),
                timestamp: Self.date(container, .timestamp)
            )
        }

        /// Non-empty, no control characters, at most `limit` characters.
        private static func text(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, limit: Int) -> String? {
            guard let value = try? container.decodeIfPresent(String.self, forKey: key),
                  !value.isEmpty, value.count <= limit,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { return nil }
            return value
        }

        private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
            return (try? container.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap(Double.init)
        }

        /// Seconds since 1970 (as a number or a string) or ISO 8601, between
        /// 2000 and 2100.
        private static func date(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
            let date: Date? = if let seconds = number(container, key) {
                Date(timeIntervalSince1970: seconds)
            } else if let string = try? container.decodeIfPresent(String.self, forKey: key) {
                (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string)) ?? (try? Date.ISO8601FormatStyle().parse(string))
            } else {
                nil
            }
            guard let date, (Self.earliest...Self.latest).contains(date) else { return nil }
            return date
        }

        private static let earliest = Date(timeIntervalSince1970: 946_684_800)
        private static let latest = Date(timeIntervalSince1970: 4_102_444_800)
    }
}
