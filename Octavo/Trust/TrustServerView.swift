import OctavoKit
import SwiftUI

/// What the "Trust this server" step is asked about.
struct TrustQuestion: Identifiable {
    var certificate: CertificateSummary
    /// The certificate trusted before, if this one replaced it.
    var trusted: CertificatePin?

    var id: CertificatePin { certificate.pin }
    var changed: Bool { trusted != nil }

    /// The question a `ServerTransport` refusal asks, if it asks one.
    init?(_ error: any Error, trusted: CertificatePin?) {
        switch error as? NetworkTrustError {
        case .untrustedCertificate(let summary): self.init(certificate: summary, trusted: nil)
        case .certificateChanged(let summary): self.init(certificate: summary, trusted: trusted)
        default: return nil
        }
    }

    init(certificate: CertificateSummary, trusted: CertificatePin?) {
        self.certificate = certificate
        self.trusted = trusted
    }
}

/// "Trust this server" (D25): the server's certificate isn't one iOS trusts
/// (first connect), or isn't the one trusted before (it changed). Shows who
/// it's issued to and its fingerprint to compare with the server's own.
/// Proposed in #9; its real places are first run (#12) and Settings (#16).
struct TrustServerView: View {
    let question: TrustQuestion
    /// `true`: trust it (store `certificate.pinToSave`).
    let decide: (Bool) -> Void

    private var certificate: CertificateSummary { question.certificate }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: question.changed ? "exclamationmark.shield" : "lock.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(question.changed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    Text(question.changed ? "This server’s certificate changed" : "Trust this server?")
                        .font(.title2.bold())
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section("Certificate") {
                LabeledContent("Server", value: certificate.port == 443 ? certificate.host : "\(certificate.host):\(certificate.port)")
                LabeledContent("Issued to", value: certificate.subject.isEmpty ? "No name" : certificate.subject)
                if certificate.isSelfSigned {
                    LabeledContent("Issued by", value: "Itself (self-signed)")
                }
                if let expiry = certificate.notValidAfter {
                    LabeledContent(expiry < .now ? "Expired" : "Expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
                }
            }
            Section {
                Fingerprint(sha256: certificate.pin.sha256)
            } header: {
                Text(question.changed ? "New fingerprint (SHA-256)" : "Fingerprint (SHA-256)")
            } footer: {
                if !question.changed {
                    Text("Your server shows its certificate’s SHA-256 fingerprint in its settings or admin page.")
                }
            }
            if let trusted = question.trusted {
                Section("The one you trusted") {
                    Fingerprint(sha256: trusted.sha256)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if question.changed {
                    wideButton("Don’t connect") { decide(false) }
                        .buttonStyle(.glassProminent)
                    wideButton(certificate.isTrustedBySystem ? "Use the new certificate" : "Trust the new certificate", role: .destructive) { decide(true) }
                        .buttonStyle(.glass)
                        .foregroundStyle(.red)
                } else {
                    wideButton("Trust") { decide(true) }
                        .buttonStyle(.glassProminent)
                    wideButton("Cancel", role: .cancel) { decide(false) }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
            .frame(maxWidth: 420)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .interactiveDismissDisabled()
    }

    private func wideButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private var message: String {
        if !question.changed {
            return "iOS can’t confirm who runs this server. That’s normal for a server at home with a self-signed certificate. Check that the fingerprint matches the one your server shows."
        }
        if certificate.isTrustedBySystem {
            return "It now has a certificate iOS trusts, as it would after you set one up from a certificate authority. If you didn’t change anything, don’t connect."
        }
        return "It isn’t the certificate you trusted. That’s expected if you renewed or replaced it. If you didn’t, someone may be intercepting the connection: don’t connect."
    }
}

/// A SHA-256 fingerprint in four rows of eight bytes, easy to compare.
private struct Fingerprint: View {
    let sha256: Data

    var body: some View {
        let pairs = sha256.map { String(format: "%02X", $0) }
        let rows = stride(from: 0, to: pairs.count, by: 8).map { pairs[$0..<min($0 + 8, pairs.count)].joined(separator: " ") }
        Text(rows.joined(separator: "\n"))
            .font(.body.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
