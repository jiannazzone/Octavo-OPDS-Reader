import Foundation

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

/// A server's secrets in the Keychain, keyed by the server's ID (its
/// `LibrarySourceID` in the app): BookOrbit tokens, an OPDS password and the
/// trusted certificate's pin.
public enum ServerCredentials {
    static let tokenService = "com.ianazzone.ereader.bookorbit-tokens"
    static let passwordService = "com.ianazzone.ereader.server-password"
    static let pinService = "com.ianazzone.ereader.certificate-pin"
    static let allServices = [tokenService, passwordService, pinService]

    /// For Sign out and Remove server: deletes everything kept for `serverID`.
    public static func removeAll(serverID: String) throws {
        for service in allServices {
            try KeychainItem(service: service, account: serverID).delete()
        }
    }

    static let installedKey = "ServerCredentials.installed"

    /// Keychain items outlive the app, but the list of servers they belong to
    /// doesn't. On the first launch after an install (no marker in
    /// `defaults`, which is deleted with the app), delete every item left
    /// from before, so a reinstall starts signed out.
    public static func removeLeftoversAfterInstall(defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: installedKey) else { return }
        for service in allServices {
            try KeychainItem.deleteAll(service: service)
        }
        defaults.set(true, forKey: installedKey)
    }
}

/// BookOrbit tokens in the Keychain.
///
/// BookOrbit rotates the refresh token on every refresh, so `save` replaces
/// the stored credentials in one Keychain update: after a crash the item holds
/// the old token or the new one, never nothing (`BookOrbitClient` saves the
/// new one before it uses it).
public struct KeychainBookOrbitTokenStore: BookOrbitTokenStore {
    private let item: KeychainItem

    public init(serverID: String) {
        item = KeychainItem(service: ServerCredentials.tokenService, account: serverID)
    }

    public func load() async throws -> BookOrbitCredentials? {
        try item.decoded(BookOrbitCredentials.self)
    }

    public func save(_ credentials: BookOrbitCredentials?) async throws {
        if let credentials {
            try item.write(JSONEncoder().encode(credentials))
        } else {
            try item.delete()
        }
    }
}

/// An OPDS server's password in the Keychain.
public struct KeychainPasswordStore: PasswordStore {
    private let item: KeychainItem

    public init(serverID: String) {
        item = KeychainItem(service: ServerCredentials.passwordService, account: serverID)
    }

    public func load() async throws -> PasswordCredentials? {
        try item.decoded(PasswordCredentials.self)
    }

    public func save(_ credentials: PasswordCredentials?) async throws {
        if let credentials {
            try item.write(JSONEncoder().encode(credentials))
        } else {
            try item.delete()
        }
    }
}

/// A server's trusted certificate pin in the Keychain, next to its other
/// secrets so Remove server forgets it too.
public struct KeychainCertificatePinStore: CertificatePinStore {
    private let item: KeychainItem

    public init(serverID: String) {
        item = KeychainItem(service: ServerCredentials.pinService, account: serverID)
    }

    public func load() throws -> CertificatePin? {
        try item.decoded(CertificatePin.self)
    }

    public func save(_ pin: CertificatePin?) throws {
        if let pin {
            try item.write(JSONEncoder().encode(pin))
        } else {
            try item.delete()
        }
    }
}

extension KeychainItem {
    /// The stored value, or `nil` if there's none. One that no longer decodes
    /// (a corrupt write, an older format) is deleted, so the person signs in
    /// or trusts again instead of being stuck on an error.
    func decoded<Value: Decodable>(_ type: Value.Type) throws -> Value? {
        guard let data = try read() else { return nil }
        if let value = try? JSONDecoder().decode(type, from: data) { return value }
        try delete()
        return nil
    }
}
