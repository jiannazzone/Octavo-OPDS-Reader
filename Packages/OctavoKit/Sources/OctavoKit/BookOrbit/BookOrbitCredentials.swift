import Foundation

/// A signed-in BookOrbit session.
///
/// BookOrbit 3.0+ hands native clients the refresh token in the response
/// body. Older servers only set it as an `HttpOnly` cookie, so the client
/// lifts it out of `Set-Cookie` and sends it back by hand. Either way it lives
/// here, so a token store can persist it.
public struct BookOrbitCredentials: Codable, Hashable, Sendable {
    public enum RefreshTransport: String, Codable, Sendable {
        /// `POST auth/refresh` with `{"refreshToken": …}`.
        case body
        /// `POST auth/refresh` with a `refresh_token` cookie.
        case cookie
    }

    public var accessToken: String
    public var accessTokenExpiresAt: Date?
    public var refreshToken: String?
    public var refreshTokenExpiresAt: Date?
    public var refreshTransport: RefreshTransport
    public var sessionID: Int?

    public init(
        accessToken: String,
        accessTokenExpiresAt: Date? = nil,
        refreshToken: String? = nil,
        refreshTokenExpiresAt: Date? = nil,
        refreshTransport: RefreshTransport = .body,
        sessionID: Int? = nil
    ) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.refreshTransport = refreshTransport
        self.sessionID = sessionID
    }
}

/// Where a `BookOrbitClient` keeps its credentials. One store per server.
/// A Keychain-backed store slots in here later.
public protocol BookOrbitTokenStore: Sendable {
    func load() async throws -> BookOrbitCredentials?
    /// `nil` clears the stored credentials (sign-out, or the session ended).
    func save(_ credentials: BookOrbitCredentials?) async throws
}

public actor InMemoryBookOrbitTokenStore: BookOrbitTokenStore {
    private var credentials: BookOrbitCredentials?

    public init(_ credentials: BookOrbitCredentials? = nil) {
        self.credentials = credentials
    }

    public func load() -> BookOrbitCredentials? {
        credentials
    }

    public func save(_ credentials: BookOrbitCredentials?) {
        self.credentials = credentials
    }
}
