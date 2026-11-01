import CryptoKit
import Foundation
import Security
import Synchronization

/// Why `ServerTransport` refused a connection. Like `URLError`, these mean
/// "can't use this server as it is"; the certificate cases carry what the
/// "Trust this server" step shows.
public enum NetworkTrustError: Error, Equatable, Sendable {
    public enum InsecureReason: Equatable, Sendable {
        /// A name that isn't local (`books.example.com`): it needs https.
        case notALocalName
        /// It is, or resolves to, this address on the internet.
        case internetAddress(String)
        /// The system would send it through a proxy, which resolves the name
        /// itself, wherever it is.
        case throughProxy
        /// A server on the internet linked or redirected to a home address.
        case localAddressFromInternetServer
        /// Plain http whose connection couldn't be checked afterwards (no
        /// address in the task's metrics, or none in time).
        case unverifiedConnection
    }

    /// Plain http to something that isn't a home or VPN address.
    case insecureAddress(host: String, reason: InsecureReason)
    /// Not a standard address (`3232235777`, `0177.0.0.1`, `nas.lan.`), not
    /// http(s), or with `user:password@`. Carries scheme, host and port only.
    case unsupportedAddress(String)
    /// iOS doesn't trust the server's certificate and none is pinned for it.
    case untrustedCertificate(CertificateSummary)
    /// The server's certificate isn't the one that was trusted.
    case certificateChanged(CertificateSummary)
    /// A redirect to plain http from https, or one that would send a
    /// request body (a password, a token) on to another server. Carries the
    /// target's scheme, host and port only.
    case insecureRedirect(String)
}

/// One trusted certificate: the SHA-256 of its DER bytes, the same
/// fingerprint Safari, `openssl x509 -fingerprint -sha256` and NAS admin pages
/// show, so a person can compare them.
public struct CertificatePin: Codable, Hashable, Sendable {
    public var sha256: Data

    public init(sha256: Data) {
        self.sha256 = sha256
    }

    public init(_ certificate: SecCertificate) {
        sha256 = Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }

    public func matches(_ certificate: SecCertificate) -> Bool {
        CertificatePin(certificate).sha256 == sha256
    }
}

/// What the "Trust this server" step shows about a certificate.
public struct CertificateSummary: Hashable, Sendable {
    /// The server the certificate was presented for.
    public var host: String
    public var port: Int
    /// "Issued to": the certificate's subject (usually its common name).
    public var subject: String
    /// Issuer and subject are the same: nobody else vouched for it.
    public var isSelfSigned: Bool
    /// iOS trusts it (a public certificate authority, or one installed on the
    /// iPhone); it only needs asking about because a different one was pinned.
    public var isTrustedBySystem: Bool
    public var notValidAfter: Date?
    /// Pin this to trust the certificate.
    public var pin: CertificatePin

    /// `90:F5:83:CD:…`, as `openssl` prints it.
    public var fingerprint: String {
        pin.sha256.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// What to store when the person trusts this certificate: its pin, or
    /// none if iOS trusts it anyway (so its renewals don't ask again).
    public var pinToSave: CertificatePin? {
        isTrustedBySystem ? nil : pin
    }

    public init(host: String, port: Int, subject: String, isSelfSigned: Bool, isTrustedBySystem: Bool = false, notValidAfter: Date?, pin: CertificatePin) {
        self.host = host
        self.port = port
        self.subject = subject
        self.isSelfSigned = isSelfSigned
        self.isTrustedBySystem = isTrustedBySystem
        self.notValidAfter = notValidAfter
        self.pin = pin
    }

    public init(_ certificate: SecCertificate, host: String, port: Int, isTrustedBySystem: Bool = false) {
        let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate) as Data?
        let subjectSequence = SecCertificateCopyNormalizedSubjectSequence(certificate) as Data?
        self.init(
            host: host,
            port: port,
            subject: SecCertificateCopySubjectSummary(certificate) as String? ?? "",
            isSelfSigned: issuer != nil && issuer == subjectSequence,
            isTrustedBySystem: isTrustedBySystem,
            notValidAfter: SecCertificateCopyNotValidAfterDate(certificate) as Date?,
            pin: CertificatePin(certificate)
        )
    }
}

/// Where a server's trusted certificate is kept. One store per server.
public protocol CertificatePinStore: Sendable {
    func load() throws -> CertificatePin?
    /// `nil` forgets the pin.
    func save(_ pin: CertificatePin?) throws
}

public final class InMemoryCertificatePinStore: CertificatePinStore {
    private let pin: Mutex<CertificatePin?>

    public init(_ pin: CertificatePin? = nil) {
        self.pin = Mutex(pin)
    }

    public func load() -> CertificatePin? {
        pin.withLock { $0 }
    }

    public func save(_ pin: CertificatePin?) {
        self.pin.withLock { $0 = pin }
    }
}
