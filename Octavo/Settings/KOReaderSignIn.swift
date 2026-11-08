import Foundation
import Observation
import OctavoKit

/// Signing in to KOReader sync, from its page in Settings or a catalog's
/// setup: the sync server's address, the account, "Trust this server" if
/// its certificate needs it, and what went wrong under the fields. Lives in
/// the shell, so a fold keeps what's typed.
@Observable
final class KOReaderSignIn {
    var address = "" {
        didSet { if address != oldValue { edited() } }
    }
    var username = "" {
        didSet { if username != oldValue { edited() } }
    }
    var password = "" {
        didSet { if password != oldValue { edited() } }
    }

    let connecting = Attempt()
    var working: Bool { connecting.running }
    /// Shown under the fields.
    private(set) var error: String?
    let trust = TrustStep { SavedKOReaderAccount.newID() }

    /// Opens the trust step.
    @ObservationIgnored var push: (SetupStep) -> Void = { _ in }
    /// Back from it.
    @ObservationIgnored var pop: () -> Void = {}

    /// Sign in: the account is kept (`ServerActions.signInToKOReader`), then
    /// `done` runs.
    func signIn(with actions: ServerActions, done: @escaping () -> Void = {}) {
        error = nil
        let parsed: ServerAddress.Parsed
        do {
            parsed = try ServerAddress.parse(address)
        } catch {
            self.error = switch error {
            case .empty: "Enter your sync server’s address."
            case .notAnAddress: "That isn’t an address Octavo can read."
            case .unsupportedScheme: "Use an address that starts with https:// or http://."
            }
            return
        }
        // As in setup: an account in the address moves to the fields, and
        // nothing is sent until the address that's left has been seen.
        if let username = parsed.username {
            self.username = username
            if let password = parsed.password { self.password = password }
            address = parsed.url.absoluteString
            error = SetupModel.accountMoved
            return
        }
        guard !username.isEmpty, !password.isEmpty else {
            error = "Enter your username and password."
            return
        }
        let id = trust.id(for: parsed.url)
        let account = KOSyncAccount(address: parsed.url, key: KOSyncKey(username: username, password: password))
        connecting.start { [weak self] isCurrent in
            do {
                try await actions.signInToKOReader(account, id: id)
                guard isCurrent(), let self else { return }
                reset()
                done()
            } catch {
                guard isCurrent(), let self else { return }
                failed(error) { [weak self] in self?.signIn(with: actions, done: done) }
            }
        } timedOut: { [weak self] in
            self?.error = "\(parsed.url.host() ?? "The server") didn’t answer. Check the address, including any port (such as :7200)."
        }
    }

    /// Trust or Cancel on the trust step.
    func decideTrust(_ trusted: Bool) {
        guard trust.question != nil else { return }
        pop()
        if let message = trust.decide(trusted) { error = message }
    }

    /// Signed in, or given up: start clean.
    func reset() {
        connecting.cancel()
        address = ""
        username = ""
        password = ""
        error = nil
        trust.reset()
    }

    /// Back out: stop waiting for the server.
    func left() {
        connecting.cancel()
    }

    private func edited() {
        connecting.cancel()
        error = nil
    }

    private func failed(_ error: any Error, retry: @escaping () -> Void) {
        if trust.ask(error, retry: retry) {
            push(.koreaderTrust)
            return
        }
        self.error = Self.message(for: error, host: trust.host)
    }

    /// What went wrong, in words, under the fields.
    static func message(for error: any Error, host: String?) -> String {
        switch error {
        case KOSyncError.unauthorized:
            return "That username or password didn’t work."
        case KOSyncError.notASyncServer, KOSyncError.invalidResponse:
            return "That doesn’t look like a KOReader sync server. Check the address."
        case KOSyncError.unavailable(status: 429):
            return "Too many tries. Wait a minute, then try again."
        case KOSyncError.unavailable:
            return "The sync server isn’t working right now. Try again later."
        default:
            return SetupModel.message(for: error, server: "the sync server", host: host)
        }
    }
}
