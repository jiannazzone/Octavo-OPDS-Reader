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

/// How the password is sent (#9's `HTTPAuthScheme`). Recorded when the
/// server is added (#12) and passed to `OPDSSource` and #9's transport from
/// then on, so a later answer can't talk Octavo down to a weaker scheme:
/// over home http, anyone answering at the server's address could ask for
/// Basic to get the password in clear. `.basic`: the password goes with
/// every request, up front. `.digest`: never up front; the transport answers
/// the server's own Digest challenge, which never carries the password.
extension HTTPAuthScheme {
    /// From a 401's `WWW-Authenticate`: Digest when the server offers it,
    /// even alongside Basic. `nil` if it offers neither. Only scheme names
    /// count, not words in parameters (`Bearer realm="basic"` is neither).
    init?(challenge: String) {
        let schemes = Self.schemes(in: challenge)
        if schemes.contains("digest") {
            self = .digest
        } else if schemes.contains("basic") {
            self = .basic
        } else {
            return nil
        }
    }

    /// The scheme names in a `WWW-Authenticate` value, lowercased. Challenges
    /// and their parameters are both comma-separated; a piece whose first
    /// word has no `=` starts a challenge.
    static func schemes(in challenge: String) -> Set<String> {
        var schemes = Set<String>()
        for piece in challenge.split(separator: ",") {
            guard let first = piece.split(whereSeparator: \.isWhitespace).first, !first.contains("="), !first.contains("\"") else { continue }
            schemes.insert(first.lowercased())
        }
        return schemes
    }
}

/// How a catalog asked for a sign-in: its OPDS Authentication Document if it
/// sent one, and its `WWW-Authenticate` challenge.
public struct OPDSSignInRequest: Hashable, Sendable {
    /// The catalog's own name (Komga: "Komga").
    public var title: String?
    public var description: String?
    /// Field labels the server suggests ("Email", "Password").
    public var usernameLabel: String?
    public var passwordLabel: String?
    /// The scheme to record with the server. `nil` if the server offers
    /// only methods Octavo can't do (OAuth, SAML…): show that it isn't
    /// supported rather than the fields.
    public var scheme: HTTPAuthScheme?

    public init(title: String? = nil, description: String? = nil, usernameLabel: String? = nil, passwordLabel: String? = nil, scheme: HTTPAuthScheme? = .basic) {
        self.title = title
        self.description = description
        self.usernameLabel = usernameLabel
        self.passwordLabel = passwordLabel
        self.scheme = scheme
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
            scheme: basic != nil ? .basic : nil
        )
    }
}
