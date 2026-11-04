import Foundation
import Security

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

/// How a server asked for its password when it was added. Recorded with the
/// server, so a later challenge in a weaker scheme (an impostor at a home
/// http address asking for Basic) gets nothing.
public enum HTTPAuthScheme: String, Codable, Hashable, Sendable {
    case basic
    case digest
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
/// `LibrarySourceID` in the app): BookOrbit tokens, an OPDS password, the
/// secret a catalog's address carries and the trusted certificate's pin.
public enum ServerCredentials {
    static let tokenService = "com.ianazzone.ereader.bookorbit-tokens"
    static let passwordService = "com.ianazzone.ereader.server-password"
    static let pinService = "com.ianazzone.ereader.certificate-pin"
    static let catalogSecretService = "com.ianazzone.ereader.catalog-secret"
    static let allServices = [tokenService, passwordService, pinService, catalogSecretService]

    /// Remove server: deletes everything kept for `serverID`. Every item is
    /// tried, so one that can't be deleted doesn't keep the others; the
    /// first failure is thrown once they all have been.
    public static func removeAll(serverID: String) throws {
        var failure: (any Error)?
        for service in allServices {
            do {
                try KeychainItem(service: service, account: serverID).delete()
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
    }

    /// Sign out: deletes the sign-in kept for `serverID` (BookOrbit's
    /// tokens, an OPDS password), keeping its trusted certificate and a
    /// catalog's key. Every item is tried; the first failure is thrown.
    public static func removeSignIn(serverID: String) throws {
        var failure: (any Error)?
        for service in [tokenService, passwordService] {
            do {
                try KeychainItem(service: service, account: serverID).delete()
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
    }

    /// The launch sweep: deletes everything kept for servers `keeps` turns
    /// down, such as one whose Remove server couldn't clear the Keychain, or
    /// a setup left before it finished. Nothing is deleted unless every kind
    /// of item could be listed; then every server is tried, and the first
    /// failure is thrown once they all have been.
    /// - Returns: the servers whose items were deleted.
    @discardableResult
    public static func removeAll(keeping keeps: (String) -> Bool) throws -> Set<String> {
        var accounts: Set<String> = []
        for service in allServices {
            accounts.formUnion(try KeychainItem.accounts(service: service))
        }
        let removed = accounts.filter { !keeps($0) }
        var failure: (any Error)?
        for account in removed {
            do {
                try removeAll(serverID: account)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
        return removed
    }

    public static let installedKey = "ServerCredentials.installed"

    /// Keychain items outlive the app, but the list of servers they belong to
    /// doesn't. On the first launch after an install (no marker in
    /// `defaults`, which is deleted with the app), delete every item left
    /// from before, so a reinstall starts signed out.
    ///
    /// `hasSavedServer`: the saved server is deleted with the app too, so one
    /// without the marker means this install has run before and has simply
    /// never set it (builds from before it was set, or a delete that failed
    /// before the server was added). Its sign-in isn't a leftover: only the
    /// marker is set, and the launch sweep takes anything else.
    ///
    /// - Parameter scope: the servers it may delete from; tests narrow it to
    ///   their own.
    public static func removeLeftoversAfterInstall(
        hasSavedServer: Bool, defaults: UserDefaults = .standard, scope: (String) -> Bool = { _ in true }
    ) throws {
        guard !defaults.bool(forKey: installedKey) else { return }
        if !hasSavedServer {
            try removeAll { !scope($0) }
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

/// The secrets an OPDS catalog's address carries (Kavita's API key,
/// `OPDSURLSecret`), so the address can be saved with placeholders in their
/// place.
public struct KeychainCatalogSecretStore: Sendable {
    private let item: KeychainItem

    public init(serverID: String) {
        item = KeychainItem(service: ServerCredentials.catalogSecretService, account: serverID)
    }

    public func load() throws -> OPDSURLSecret? {
        try item.decoded(StoredValues.self).flatMap { OPDSURLSecret(values: $0.values) }
    }

    /// `nil` forgets the secret.
    public func save(_ secret: OPDSURLSecret?) throws {
        if let secret {
            try item.write(JSONEncoder().encode(StoredValues(values: secret.values)))
        } else {
            try item.delete()
        }
    }

    /// One secret as a JSON string, as step 8 saved Kavita's key; more as an
    /// array.
    private struct StoredValues: Codable {
        var values: [String]

        init(values: [String]) {
            self.values = values
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let one = try? container.decode(String.self) {
                values = [one]
            } else {
                values = try container.decode([String].self)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            if values.count == 1 {
                try container.encode(values[0])
            } else {
                try container.encode(values)
            }
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

    /// A pin that no longer decodes (another build's format) throws and is
    /// kept, unlike tokens and passwords: dropping it would let iOS alone
    /// judge the server, which an MDM or proxy root passes (step 16).
    /// Trusting the server again replaces it.
    public func load() throws -> CertificatePin? {
        guard let data = try item.read() else { return nil }
        do {
            return try JSONDecoder().decode(CertificatePin.self, from: data)
        } catch {
            throw KeychainError(status: errSecDecode)
        }
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
