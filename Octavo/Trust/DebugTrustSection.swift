#if DEBUG
import OctavoKit
import SwiftUI

/// Tries the "Trust this server" step against any https address until first
/// run (#12) and Settings (#16) have it: `dev/trust/` serves a self-signed
/// certificate on 8443 and another on 8444 (the first one, changed). In the
/// Settings stand-in; debug builds only. `-debugTrust <url>` connects on launch.
struct DebugTrustSection: View {
    @State private var address = UserDefaults.standard.string(forKey: "debugTrust") ?? "https://localhost:8443/"
    @State private var result: String?
    @State private var question: TrustQuestion?
    @State private var connectsOnAppear = UserDefaults.standard.string(forKey: "debugTrust") != nil

    /// One pin for whatever address is tried.
    private let pins = KeychainCertificatePinStore(serverID: "debug-trust-test")

    var body: some View {
        Section {
            TextField("https://localhost:8443/", text: $address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Connect") {
                Task { await connect() }
            }
            Button("Forget the trusted certificate", role: .destructive) {
                result = (try? pins.save(nil)) != nil ? "Forgotten." : "Couldn’t forget it."
            }
            if let result {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Debug trust")
        } footer: {
            Text("Debug builds only. dev/trust serves certificate a on 8443 and b on 8444.")
        }
        .sheet(item: $question) { question in
            TrustServerView(question: question) { trust in
                self.question = nil
                guard trust else {
                    result = "Not trusted."
                    return
                }
                do {
                    try pins.save(question.certificate.pinToSave)
                    Task { await connect() }
                } catch {
                    result = "Couldn’t save the pin: \(error)"
                }
            }
            .presentationDetents([.large])
        }
        .task {
            guard connectsOnAppear else { return }
            connectsOnAppear = false
            await connect()
        }
    }

    private func connect() async {
        guard let url = URL(string: address) else {
            result = "Not an address."
            return
        }
        let pin = try? pins.load()
        let transport = ServerTransport(server: url, pin: pin)
        result = "Connecting…"
        do {
            let (data, response) = try await transport.data(for: URLRequest(url: url))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            result = "HTTP \(status) · \(String(decoding: data.prefix(80), as: UTF8.self))"
        } catch {
            if let question = TrustQuestion(error, trusted: pin) {
                result = nil
                self.question = question
            } else {
                result = String(describing: error)
            }
        }
    }
}
#endif
