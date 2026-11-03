import Foundation

/// Secrets a catalog puts in its own URLs, kept out of everything
/// `OPDSSource` hands the app.
///
/// Kavita's OPDS address is `…/api/opds/<API key>`, Stump's can be
/// `…/opds/<API key>/v1.2/catalog`, and others take a key or token in the
/// query (Bindery's `?apikey=`). Every link such a catalog sends repeats it
/// (feeds, covers, downloads). Those links become `LibraryLink`s, book and
/// file IDs and cover values, which the app saves (Continue reading's
/// records). So the source writes `{key}` in their place and puts the
/// secret back only to send a request to the catalog's own origin. The
/// secret itself is kept in the Keychain (`KeychainCatalogSecretStore`).
public struct OPDSURLSecret: Sendable {
    /// What stands in for the first secret in handed-out strings; a second
    /// is `{key2}`, and so on.
    public static let placeholder = "{key}"

    /// In the order found; each is written as `placeholder(at:)`.
    public let values: [String]

    /// The first secret.
    public var value: String { values[0] }

    /// `nil` for anything too short to replace safely.
    public init?(_ value: String) {
        self.init(values: [value])
    }

    /// `nil` if there are none, or any is too short to replace safely (or
    /// holds a brace, which would mix it up with a placeholder).
    public init?(values: [String]) {
        var unique: [String] = []
        for value in values where !unique.contains(value) {
            unique.append(value)
        }
        guard !unique.isEmpty, unique.allSatisfy(Self.isReplaceable) else { return nil }
        self.values = unique
    }

    static func isReplaceable(_ value: String) -> Bool {
        value.count >= 8 && !value.contains("{") && !value.contains("}")
    }

    public static func placeholder(at index: Int) -> String {
        index == 0 ? placeholder : "{key\(index + 1)}"
    }

    /// The secrets in a catalog address someone pasted, of the kinds Octavo
    /// knows: a key in the path (Kavita's `api/opds/<key>`, Stump's
    /// `opds/<key>/v1.2`) and query items named like a credential (`apikey`,
    /// `token`, `password`, …). One shorter than 8 characters can't be
    /// swapped out safely and stays as typed.
    public static func detect(in catalogURL: URL) -> OPDSURLSecret? {
        var found: [String] = []
        let parts = catalogURL.pathComponents.filter { $0 != "/" }
        // The last `api/opds/<key>`: a proxy may put its own `opds` in front.
        if let opds = parts.indices.last(where: { $0 > 0 && $0 + 1 < parts.count && parts[$0] == "opds" && parts[$0 - 1] == "api" }) {
            found.append(parts[opds + 1])
        } else if let opds = parts.indices.last(where: { $0 + 2 < parts.count && parts[$0] == "opds" && isVersion(parts[$0 + 2]) }),
                  parts[opds + 1].contains(where: \.isNumber) {
            // A key, not a word: `opds/discover/v1` is a path.
            found.append(parts[opds + 1])
        }
        let items = URLComponents(url: catalogURL, resolvingAgainstBaseURL: true)?.queryItems ?? []
        for item in items where isCredentialName(item.name) {
            if let value = item.value, isReplaceable(value) { found.append(value) }
        }
        return OPDSURLSecret(values: found.filter(isReplaceable))
    }

    /// `v1.2`, `v2.0`, `v2`: an OPDS version in a path.
    private static func isVersion(_ part: String) -> Bool {
        guard part.first == "v", part.count > 1 else { return false }
        return part.dropFirst().allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }

    /// A query item's name that says it's a credential. Erring wide costs
    /// nothing: a value taken for a secret is kept in the Keychain and put
    /// back in requests to the catalog the same way.
    static func isCredentialName(_ name: String) -> Bool {
        let name = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let words = ["key", "token", "secret", "pass", "pwd", "auth", "session", "sig", "jwt", "otp"]
        return name == "sid" || name == "code" || words.contains { name.contains($0) }
    }

    /// Whether `string` has a placeholder in it: an address saved with its
    /// secret written out.
    public static func isRedacted(_ string: String) -> Bool {
        string.contains("{key")
    }

    /// `string` with every placeholder as `key`, so a saved address reads as
    /// a URL (to show its host).
    public static func masked(_ string: String) -> String {
        string.replacing(/\{key[0-9]*\}/, with: "key")
    }

    /// `string` with the secrets replaced, as written or percent-encoded.
    public func redact(_ string: String) -> String {
        var string = string
        // Longest first, so a secret inside another doesn't split it.
        for (index, value) in values.enumerated().sorted(by: { $0.element.count > $1.element.count }) {
            let placeholder = Self.placeholder(at: index)
            string = string.replacingOccurrences(of: value, with: placeholder)
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved), encoded != value {
                string = string.replacingOccurrences(of: encoded, with: placeholder, options: .caseInsensitive)
            }
        }
        return string
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `string` with the placeholders replaced by the secrets.
    public func restore(_ string: String) -> String {
        var string = string
        for (index, value) in values.enumerated() {
            string = string.replacingOccurrences(of: Self.placeholder(at: index), with: value)
        }
        return string
    }
}
