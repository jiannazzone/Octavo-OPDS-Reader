import Foundation

// Stand-ins for #9's network types (OctavoKit `Network/`, branch
// claude/issue-9-network-trust-68248d), with the same shapes so OPDS code
// against them unchanged. Whichever of #8 and #9 merges second deletes this
// file and keeps #9's.

/// Sends a request. #9's `ServerTransport` adds the per-request address
/// check, certificate pinning and redirect hygiene; a plain `URLSession`
/// does none of that (tests, and debug builds until #9 lands).
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse)
}

extension URLSession: HTTPTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

/// A username and password a server asked for.
public struct PasswordCredentials: Codable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Where a server's password is kept. One store per server.
public protocol PasswordStore: Sendable {
    func load() async throws -> PasswordCredentials?
    /// `nil` clears it.
    func save(_ credentials: PasswordCredentials?) async throws
}

public actor InMemoryPasswordStore: PasswordStore {
    private var credentials: PasswordCredentials?

    public init(_ credentials: PasswordCredentials? = nil) {
        self.credentials = credentials
    }

    public func load() -> PasswordCredentials? {
        credentials
    }

    public func save(_ credentials: PasswordCredentials?) {
        self.credentials = credentials
    }
}
