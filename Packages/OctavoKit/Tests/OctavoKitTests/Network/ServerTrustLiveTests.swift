import Foundation
@testable import OctavoKit
import Security
import Testing

/// Against the self-signed servers in `dev/trust/` (certificate `a` on 8443,
/// `b` on 8444). Skipped unless `OCTAVO_TRUST_HOST` names where they run:
///
///     (cd dev/trust && ./make-certs.sh && docker compose -p octavo-trust up -d)
///     OCTAVO_TRUST_HOST=localhost swift test --filter ServerTrustLiveTests
@Suite(.enabled(if: TrustServers.host != nil, "Set OCTAVO_TRUST_HOST and start dev/trust"))
struct ServerTrustLiveTests {
    @Test func untrustedCertificateCarriesItsDetails() async throws {
        let transport = ServerTransport(server: TrustServers.a)
        let expected = try TrustServers.certificate("a")

        let error = await #expect(throws: NetworkTrustError.self) {
            try await transport.data(for: URLRequest(url: TrustServers.a))
        }
        guard case .untrustedCertificate(let summary) = error else {
            Issue.record("Expected untrustedCertificate, got \(String(describing: error))")
            return
        }
        #expect(summary.subject == "Octavo trust test a")
        #expect(summary.isSelfSigned)
        #expect(!summary.isTrustedBySystem)
        #expect(summary.pin == CertificatePin(expected))
        #expect(summary.pinToSave == CertificatePin(expected))
        #expect(summary.fingerprint == TrustServers.openSSLFingerprint("a"))
        #expect(summary.host == TrustServers.host)
        #expect(summary.port == 8443)
        #expect(try #require(summary.notValidAfter) > .now.addingTimeInterval(365 * 86_400))
    }

    @Test func pinnedCertificateIsAccepted() async throws {
        let transport = ServerTransport(server: TrustServers.a, pin: CertificatePin(try TrustServers.certificate("a")))
        let (data, _) = try await transport.data(for: URLRequest(url: TrustServers.a))
        #expect(String(decoding: data, as: UTF8.self).contains(#""cert":"a""#))
    }

    @Test func changedCertificateAsksAgain() async throws {
        let transport = ServerTransport(server: TrustServers.b, pin: CertificatePin(try TrustServers.certificate("a")))
        let error = await #expect(throws: NetworkTrustError.self) {
            try await transport.data(for: URLRequest(url: TrustServers.b))
        }
        guard case .certificateChanged(let summary) = error else {
            Issue.record("Expected certificateChanged, got \(String(describing: error))")
            return
        }
        #expect(summary.subject == "Octavo trust test b")
        #expect(summary.fingerprint == TrustServers.openSSLFingerprint("b"))
    }

    /// A pin covers the server's own host and port, not another address
    /// that happens to present the same certificate.
    @Test func pinCoversOnlyTheServer() async throws {
        let transport = ServerTransport(server: TrustServers.a, pin: CertificatePin(try TrustServers.certificate("a")))
        var other = URLComponents(url: TrustServers.a, resolvingAgainstBaseURL: false)!
        other.host = TrustServers.host == "localhost" ? "127.0.0.1" : "localhost"
        await #expect(throws: (any Error).self) {
            try await transport.data(for: URLRequest(url: other.url!))
        }
    }
}

enum TrustServers {
    static let host = ProcessInfo.processInfo.environment["OCTAVO_TRUST_HOST"]
    static var a: URL { URL(string: "https://\(host ?? "localhost"):8443/")! }
    static var b: URL { URL(string: "https://\(host ?? "localhost"):8444/")! }

    private static var certificates: URL {
        URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../../dev/trust/certs").standardized
    }

    static func certificate(_ name: String) throws -> SecCertificate {
        let pem = try String(contentsOf: certificates.appending(path: "\(name).crt"), encoding: .utf8)
        let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        let der = try #require(Data(base64Encoded: base64))
        return try #require(SecCertificateCreateWithData(nil, der as CFData))
    }

    /// What `make-certs.sh` printed: `openssl x509 -fingerprint -sha256`.
    static func openSSLFingerprint(_ name: String) -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["openssl", "x509", "-noout", "-fingerprint", "-sha256", "-in", certificates.appending(path: "\(name).crt").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.split(separator: "=").last.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }
}
