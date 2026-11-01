import Foundation

/// A secret a catalog puts in its own URLs, kept out of everything
/// `OPDSSource` hands the app.
///
/// Kavita's OPDS address is `…/api/opds/<API key>`, and every link it sends
/// repeats the key (feeds, `apiKey=` on covers, downloads). Those links
/// become `LibraryLink`s, book and file IDs and cover values, which the app
/// saves (Continue reading's records). So the source writes `{key}` in their
/// place and puts the key back only to send a request to the catalog's own
/// origin. The key itself belongs in the Keychain, next to the server's
/// password (#12 stores it; #9's `KeychainPasswordStore`).
public struct OPDSURLSecret: Sendable {
    /// What stands in for the secret in handed-out strings.
    public static let placeholder = "{key}"

    public let value: String

    /// `nil` for anything too short to replace safely.
    public init?(_ value: String) {
        guard value.count >= 8, !value.contains("{"), !value.contains("}") else { return nil }
        self.value = value
    }

    /// The secret in a catalog address someone pasted, if it's a kind Octavo
    /// knows: Kavita's `/api/opds/<key>`.
    public static func detect(in catalogURL: URL) -> OPDSURLSecret? {
        let parts = catalogURL.pathComponents.filter { $0 != "/" }
        // The last `api/opds/<key>`: a proxy may put its own `opds` in front.
        guard let opds = parts.indices.last(where: { $0 > 0 && $0 + 1 < parts.count && parts[$0] == "opds" && parts[$0 - 1] == "api" }) else {
            return nil
        }
        return OPDSURLSecret(parts[opds + 1])
    }

    /// `string` with the secret replaced, as written or percent-encoded.
    public func redact(_ string: String) -> String {
        var string = string.replacingOccurrences(of: value, with: Self.placeholder)
        if let encoded = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved), encoded != value {
            string = string.replacingOccurrences(of: encoded, with: Self.placeholder, options: .caseInsensitive)
        }
        return string
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `string` with the placeholder replaced by the secret.
    public func restore(_ string: String) -> String {
        string.replacingOccurrences(of: Self.placeholder, with: value)
    }
}
