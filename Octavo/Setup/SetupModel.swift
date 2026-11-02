import Foundation
import Observation
import OctavoKit

/// A setup screen after the first ("Add your books").
nonisolated enum SetupStep: Hashable, Sendable {
    case bookOrbit, opds, trust, sync
}

/// Adding the server on first launch (`docs/design/direction.md`,
/// Connecting, decisions 6 and 25): BookOrbit (sign in, then where reading
/// progress syncs) or an OPDS catalog (its address, then a sign-in only if
/// it asks), with "Trust this server" between when a certificate needs it.
/// Lives in the shell, so a fold keeps what's typed.
@Observable
final class SetupModel {
    var bookOrbitAddress = "" {
        didSet { if bookOrbitAddress != oldValue { error = nil } }
    }
    var bookOrbitUsername = ""
    var bookOrbitPassword = ""

    var catalogAddress = "" {
        didSet {
            guard catalogAddress != oldValue else { return }
            error = nil
            signIn = nil
        }
    }
    var catalogUsername = ""
    var catalogPassword = ""
    /// The catalog asked for a sign-in, so its fields show.
    private(set) var signIn: OPDSSignInRequest?

    /// Where reading progress syncs, for the sync step.
    var syncsProgress = true

    private(set) var working = false
    /// Shown under the fields (decision 22).
    private(set) var error: String?
    /// What the trust step asks about.
    private(set) var trustQuestion: TrustQuestion?
    /// A BookOrbit server signed in to, waiting for the sync step.
    private(set) var pending: SavedServer?

    /// Opens the next step.
    @ObservationIgnored var push: (SetupStep) -> Void = { _ in }
    /// Back from the trust step.
    @ObservationIgnored var pop: () -> Void = {}
    /// The server is added: the shell saves it and opens Home.
    @ObservationIgnored var finished: (SavedServer) -> Void = { _ in }

    /// Secrets are stored under this ID as setup goes (tokens, a password, a
    /// trusted certificate); it becomes the server's when setup finishes.
    @ObservationIgnored private var attempt = SavedServer.newID()
    /// The address `attempt`'s secrets are for.
    @ObservationIgnored private var attemptAddress: URL?
    /// What to try again once a certificate is trusted.
    @ObservationIgnored private var afterTrust: (() async -> Void)?

    // MARK: BookOrbit

    /// Sign in: on to the sync step.
    func signInToBookOrbit() async {
        guard !working, let parsed = parse(bookOrbitAddress) else { return }
        if let username = parsed.username {
            bookOrbitUsername = username
            bookOrbitPassword = parsed.password ?? bookOrbitPassword
            bookOrbitAddress = parsed.url.absoluteString
        }
        guard !bookOrbitUsername.isEmpty, !bookOrbitPassword.isEmpty else {
            error = "Enter your username and password."
            return
        }
        let id = attemptID(for: parsed.url)
        working = true
        defer { working = false }
        let client = SavedServer.bookOrbitClient(id: id, url: parsed.url)
        do {
            try await client.login(username: bookOrbitUsername, password: bookOrbitPassword)
            bookOrbitPassword = ""
            pending = SavedServer(
                id: id, kind: .bookOrbit, address: parsed.url.absoluteString, name: "BookOrbit",
                username: bookOrbitUsername, syncsProgress: true
            )
            syncsProgress = true
            push(.sync)
        } catch {
            failed(error, server: "BookOrbit") { [weak self] in await self?.signInToBookOrbit() }
        }
    }

    /// Done on the sync step.
    func finishBookOrbit() {
        guard var server = pending else { return }
        server.syncsProgress = syncsProgress
        finished(server)
    }

    // MARK: OPDS

    /// Connect, or Sign in once the catalog has asked.
    func connectToCatalog() async {
        guard !working, let parsed = parse(catalogAddress) else { return }
        if let username = parsed.username {
            catalogUsername = username
            catalogPassword = parsed.password ?? catalogPassword
            catalogAddress = parsed.url.absoluteString
        }
        let id = attemptID(for: parsed.url)
        let asked = signIn
        if asked != nil, catalogUsername.isEmpty || catalogPassword.isEmpty {
            error = "Enter your username and password."
            return
        }
        working = true
        defer { working = false }
        do {
            let passwords = KeychainPasswordStore(serverID: id.rawValue)
            try await passwords.save(asked == nil ? nil : PasswordCredentials(username: catalogUsername, password: catalogPassword))
            let secret = OPDSURLSecret.detect(in: parsed.url)
            let source = SavedServer.opdsSource(id: id, url: parsed.url, scheme: asked?.scheme, secret: secret)
            switch try await source.checkAccess() {
            case .open(let title):
                try KeychainCatalogSecretStore(serverID: id.rawValue).save(secret)
                let address = parsed.url.absoluteString
                finished(SavedServer(
                    id: id, kind: .opds, address: secret?.redact(address) ?? address,
                    name: Self.name(title ?? asked?.title, url: parsed.url),
                    username: asked == nil ? nil : catalogUsername, authScheme: asked?.scheme
                ))
            case .signInRequired(let request):
                if asked != nil {
                    error = "That username or password didn’t work."
                } else if request.scheme == nil {
                    error = "This catalog signs in a way Octavo can’t yet."
                } else {
                    signIn = request
                }
            }
        } catch {
            failed(error, server: "the catalog") { [weak self] in await self?.connectToCatalog() }
        }
    }

    /// The catalog's own name, or its address's host.
    static func name(_ title: String?, url: URL) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? url.host() ?? "OPDS catalog" : title
    }

    // MARK: Trust

    /// Trust or Cancel on the trust step: back to the form, and on if
    /// trusted.
    func decideTrust(_ trust: Bool) async {
        guard let question = trustQuestion else { return }
        pop()
        trustQuestion = nil
        guard trust else {
            error = "Not connected: the server’s certificate wasn’t trusted."
            return
        }
        do {
            try KeychainCertificatePinStore(serverID: attempt.rawValue).save(question.certificate.pinToSave)
        } catch {
            self.error = "Couldn’t keep the certificate. Try again."
            return
        }
        await afterTrust?()
    }

    // MARK: State

    /// Setup is done (or the server changed): start clean, keeping the
    /// finished attempt's secrets, which are the server's now.
    func reset() {
        bookOrbitAddress = ""
        bookOrbitUsername = ""
        bookOrbitPassword = ""
        catalogAddress = ""
        catalogUsername = ""
        catalogPassword = ""
        signIn = nil
        syncsProgress = true
        error = nil
        trustQuestion = nil
        pending = nil
        afterTrust = nil
        attempt = SavedServer.newID()
        attemptAddress = nil
    }

    private func parse(_ text: String) -> ServerAddress.Parsed? {
        error = nil
        do {
            return try ServerAddress.parse(text)
        } catch {
            self.error = switch error {
            case .empty: "Enter your server’s address."
            case .notAnAddress: "That isn’t an address Octavo can read."
            case .unsupportedScheme: "Use an address that starts with https:// or http://."
            }
            return nil
        }
    }

    /// The ID to keep secrets under for `url`. A different address starts
    /// over, so a certificate trusted for one server never applies to
    /// another.
    private func attemptID(for url: URL) -> LibrarySourceID {
        if let attemptAddress, attemptAddress != url {
            try? ServerCredentials.removeAll(serverID: attempt.rawValue)
            attempt = SavedServer.newID()
        }
        attemptAddress = url
        return attempt
    }

    private func failed(_ error: any Error, server: String, retry: @escaping () async -> Void) {
        let pin = try? KeychainCertificatePinStore(serverID: attempt.rawValue).load()
        if let question = TrustQuestion(error, trusted: pin) {
            trustQuestion = question
            afterTrust = retry
            push(.trust)
            return
        }
        self.error = Self.message(for: error, server: server, host: attemptAddress?.host())
    }

    /// What went wrong, in words, under the fields.
    static func message(for error: any Error, server: String, host: String?) -> String {
        let place = host ?? "the server"
        switch error {
        case NetworkTrustError.insecureAddress:
            return "Use https:// for servers on the internet. Octavo uses http:// only at home or over a VPN."
        case NetworkTrustError.unsupportedAddress:
            return "That isn’t an address Octavo can read."
        case NetworkTrustError.insecureRedirect:
            return "The server sent Octavo somewhere it won’t follow."
        case BookOrbitError.http(status: 401, _), BookOrbitError.http(status: 403, _), LibraryError.signedOut:
            return "That username or password didn’t work."
        case BookOrbitError.http(status: 429, _), LibraryError.server(status: 429, _):
            return "Too many tries. Wait a minute, then try again."
        case BookOrbitError.http(status: 404, _), BookOrbitError.invalidResponse:
            return "That doesn’t look like a BookOrbit server. Check the address."
        case LibraryError.notFound, LibraryError.invalidResponse:
            return "That doesn’t look like an OPDS catalog. Check the address."
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return "This iPhone is offline."
            case .cannotFindHost, .dnsLookupFailed:
                return "Can’t find \(place). Check the address."
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .serverCertificateUntrusted, .clientCertificateRejected:
                return "Couldn’t make a secure connection to \(place)."
            default:
                return "Can’t reach \(place). Check the address, and that this iPhone is on the right network."
            }
        default:
            return "Couldn’t connect to \(server). Try again."
        }
    }
}
