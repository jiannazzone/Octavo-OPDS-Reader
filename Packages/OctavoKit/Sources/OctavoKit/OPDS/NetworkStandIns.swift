import Foundation

// Stand-ins for #9's types (OctavoKit `Network/ServerTransport.swift` and
// `Keychain/ServerCredentials.swift`, branch claude/issue-9-network-trust-68248d),
// with the same shapes so OPDS code against them unchanged. Whichever of #8
// and #9 merges second deletes this file and keeps #9's.
//
// There's deliberately no `URLSession` conformance: in the app every request
// goes through #9's `ServerTransport` and its trust rules.

/// How a server client sends requests: `ServerTransport` in the app, so every
/// request goes through the trust rules.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    /// The file at the returned URL is the caller's to move or delete.
    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse)
}

/// A username and password for an OPDS server (HTTP Basic or Digest).
public struct PasswordCredentials: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// Never prints the password.
    public var description: String { "PasswordCredentials(username: \(username), password: •••)" }
    public var debugDescription: String { description }
}

/// Where an OPDS server's password is kept. One store per server.
public protocol PasswordStore: Sendable {
    func load() async throws -> PasswordCredentials?
    /// `nil` forgets the password.
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
