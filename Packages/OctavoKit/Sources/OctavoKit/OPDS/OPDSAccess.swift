import Foundation

extension PasswordCredentials {
    /// HTTP Basic, sent before the server asks.
    var basicAuthorization: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}

/// What a catalog needs before it lists anything, from
/// `OPDSSource.checkAccess`: for the add-server form (#12), which shows the
/// account fields only when a server asks (decision 6).
public enum OPDSAccess: Hashable, Sendable {
    /// The catalog answered; no sign-in needed (or the stored one works).
    case open(title: String?)
    /// The catalog wants a username and password.
    case signInRequired(OPDSSignInRequest)
}

/// How a catalog asked for a sign-in: its OPDS Authentication Document if it
/// sent one, else only `WWW-Authenticate: Basic`.
public struct OPDSSignInRequest: Hashable, Sendable {
    /// The catalog's own name (Komga: "Komga").
    public var title: String?
    public var description: String?
    /// Field labels the server suggests ("Email", "Password").
    public var usernameLabel: String?
    public var passwordLabel: String?
    /// `false` if the server offers only methods Octavo can't do (OAuth,
    /// SAML…): show that it isn't supported rather than the fields.
    public var supportsBasic: Bool

    public init(title: String? = nil, description: String? = nil, usernameLabel: String? = nil, passwordLabel: String? = nil, supportsBasic: Bool = true) {
        self.title = title
        self.description = description
        self.usernameLabel = usernameLabel
        self.passwordLabel = passwordLabel
        self.supportsBasic = supportsBasic
    }

    /// Reads an OPDS Authentication Document (`application/opds-authentication+json`).
    static func authenticationDocument(_ data: Data) -> OPDSSignInRequest? {
        struct Document: Decodable {
            struct Method: Decodable {
                struct Labels: Decodable { var login: String?; var password: String? }
                var type: String
                var labels: Labels?
            }
            var title: String?
            var description: String?
            var authentication: [Method]
        }
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else { return nil }
        let basic = document.authentication.first { $0.type == "http://opds-spec.org/auth/basic" }
        return OPDSSignInRequest(
            title: document.title,
            description: document.description,
            usernameLabel: basic?.labels?.login,
            passwordLabel: basic?.labels?.password,
            supportsBasic: basic != nil
        )
    }
}
