import Foundation
import Observation
import OctavoKit

/// "Trust this server" between a try and its retry (decision 25), for
/// setup and for KOReader sync's sign-in: the question a certificate asks,
/// the ID its pin is kept under until the server or account is kept, and
/// what to try again once it's trusted. The owner opens and closes the step.
@Observable
final class TrustStep {
    private(set) var question: TrustQuestion?

    /// Secrets are stored under this ID as a try goes (a trusted
    /// certificate, and setup's tokens or password); it becomes the server's
    /// or account's once it's kept.
    @ObservationIgnored private(set) var id: String
    /// The address `id`'s secrets are for.
    @ObservationIgnored private var address: URL?
    /// What to try again once a certificate is trusted.
    @ObservationIgnored private var retry: (() -> Void)?
    @ObservationIgnored private let newID: () -> String

    init(newID: @escaping () -> String) {
        self.newID = newID
        id = newID()
    }

    /// The ID to keep secrets under for `url`. A different address starts
    /// over, so a certificate trusted for one server never applies to
    /// another.
    func id(for url: URL) -> String {
        if let address, address != url {
            try? ServerCredentials.removeAll(serverID: id)
            id = newID()
        }
        address = url
        return id
    }

    /// The address the current try is for.
    var host: String? { address?.host() }

    /// If `error` is a certificate's that can be trusted, asks about it and
    /// returns true; the owner opens the step.
    func ask(_ error: any Error, retry: @escaping () -> Void) -> Bool {
        let pin = try? KeychainCertificatePinStore(serverID: id).load()
        guard let question = TrustQuestion(error, trusted: pin) else { return false }
        self.question = question
        self.retry = retry
        return true
    }

    /// Trust or Cancel, once the owner has closed the step: tries again if
    /// trusted. Returns what went wrong, if anything did.
    func decide(_ trust: Bool) -> String? {
        guard let question else { return nil }
        self.question = nil
        guard trust else { return "Not connected: the server’s certificate wasn’t trusted." }
        do {
            try KeychainCertificatePinStore(serverID: id).save(question.certificate.pinToSave)
        } catch {
            return "Couldn’t keep the certificate. Try again."
        }
        retry?()
        return nil
    }

    /// The try is done or abandoned: a new ID for the next, keeping this
    /// one's secrets, which are the server's or account's now.
    func reset() {
        question = nil
        retry = nil
        id = newID()
        address = nil
    }
}
