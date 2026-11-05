import Foundation
import Observation
import OctavoKit

/// A setup screen after the first ("Add your books").
nonisolated enum SetupStep: Hashable, Sendable {
    /// The kinds of server, opened from Settings' Add a server once books
    /// were imported without one.
    case choose
    case bookOrbit, opds, trust, sync
}

/// Adding the server on first launch (`docs/design/direction.md`,
/// Connecting, decisions 6 and 25): BookOrbit (sign in; where reading
/// progress syncs only while `SavedServer.offersSyncChoice`) or an OPDS catalog (its address, then a sign-in only if
/// it asks), with "Trust this server" between when a certificate needs it.
/// Lives in the shell, so a fold keeps what's typed.
@Observable
final class SetupModel {
    var bookOrbitAddress = "" {
        didSet { if bookOrbitAddress != oldValue { edited() } }
    }
    /// The name you gave it, if any (decision 36).
    var bookOrbitName = ""
    var bookOrbitUsername = "" {
        didSet { if bookOrbitUsername != oldValue { edited() } }
    }
    var bookOrbitPassword = "" {
        didSet { if bookOrbitPassword != oldValue { edited() } }
    }

    var catalogAddress = "" {
        didSet {
            guard catalogAddress != oldValue else { return }
            edited()
            signIn = nil
        }
    }
    /// The name you gave it, if any (decision 36).
    var catalogName = ""
    var catalogUsername = "" {
        didSet { if catalogUsername != oldValue { edited() } }
    }
    var catalogPassword = "" {
        didSet { if catalogPassword != oldValue { edited() } }
    }
    /// The catalog asked for a sign-in, so its fields show.
    private(set) var signIn: OPDSSignInRequest?

    /// Where reading progress syncs, for the sync step.
    var syncsProgress = true

    /// Signing in or connecting: one try at a time, with a time limit.
    let connecting = Attempt()
    var working: Bool { connecting.running }
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
    /// The server is added: the shell saves it and opens it.
    @ObservationIgnored var finished: (SavedServer) -> Void = { _ in }
    /// The servers already added, for telling the same one twice.
    @ObservationIgnored var saved: () -> [SavedServer] = { [] }

    /// Secrets are stored under this ID as setup goes (tokens, a password, a
    /// trusted certificate); it becomes the server's when setup finishes.
    @ObservationIgnored private var attemptID = SavedServer.newID()
    /// The address `attemptID`'s secrets are for.
    @ObservationIgnored private var attemptAddress: URL?
    /// What to try again once a certificate is trusted.
    @ObservationIgnored private var afterTrust: (() -> Void)?

    // MARK: BookOrbit

    /// Sign in: done, or on to the sync step while it's offered.
    func signInToBookOrbit() {
        guard let parsed = parse(bookOrbitAddress) else { return }
        // An account in the address moves to the fields, and nothing is sent
        // until the address that's left has been seen: in `nas.lan@evil.com`
        // the server is evil.com.
        if let username = parsed.username {
            bookOrbitUsername = username
            if let password = parsed.password { bookOrbitPassword = password }
            bookOrbitAddress = parsed.url.absoluteString
            error = Self.accountMoved
            return
        }
        guard !bookOrbitUsername.isEmpty, !bookOrbitPassword.isEmpty else {
            error = "Enter your username and password."
            return
        }
        // BookOrbit's address is its root: a query (a token pasted with it)
        // is never sent or saved.
        let root = parsed.url.withoutQuery
        guard !isAdded(.bookOrbit, root, username: bookOrbitUsername) else { return }
        let id = serverID(for: root)
        let (username, password) = (bookOrbitUsername, bookOrbitPassword)
        let client = SavedServer.bookOrbitClient(id: id, url: root)
        connecting.start { [weak self] isCurrent in
            do {
                try await client.login(username: username, password: password)
                guard isCurrent(), let self else { return }
                pending = SavedServer(
                    id: id, kind: .bookOrbit, address: root.absoluteString, name: "BookOrbit",
                    customName: Self.customName(bookOrbitName), username: username, syncsProgress: true
                )
                syncsProgress = true
                bookOrbitPassword = ""
                if SavedServer.offersSyncChoice {
                    push(.sync)
                } else {
                    finishBookOrbit()
                }
            } catch {
                guard isCurrent() else { return }
                self?.failed(error, server: "BookOrbit") { [weak self] in self?.signInToBookOrbit() }
            }
        } timedOut: { [weak self] in
            self?.timedOut(root)
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
    func connectToCatalog() {
        guard let parsed = parse(catalogAddress) else { return }
        if let username = parsed.username {
            catalogUsername = username
            if let password = parsed.password { catalogPassword = password }
            catalogAddress = parsed.url.absoluteString
            error = Self.accountMoved
            return
        }
        let asked = signIn
        if asked != nil, catalogUsername.isEmpty || catalogPassword.isEmpty {
            error = "Enter your username and password."
            return
        }
        guard asked == nil || !isAdded(.opds, parsed.url, username: catalogUsername) else { return }
        let id = serverID(for: parsed.url)
        let credentials = asked == nil ? nil : PasswordCredentials(username: catalogUsername, password: catalogPassword)
        connecting.start { [weak self] isCurrent in
            do {
                let passwords = KeychainPasswordStore(serverID: id.rawValue)
                try await passwords.save(credentials)
                let secret = OPDSURLSecret.detect(in: parsed.url)
                let source = SavedServer.opdsSource(id: id, url: parsed.url, scheme: asked?.scheme, secret: secret)
                let access = try await source.checkAccess()
                guard isCurrent(), let self else { return }
                switch access {
                case .open(let title):
                    guard !isAdded(.opds, parsed.url, username: credentials?.username) else {
                        try? ServerCredentials.removeAll(serverID: id.rawValue)
                        return
                    }
                    try KeychainCatalogSecretStore(serverID: id.rawValue).save(secret)
                    let address = parsed.url.absoluteString
                    finished(SavedServer(
                        id: id, kind: .opds, address: secret?.redact(address) ?? address,
                        name: Self.name(title ?? asked?.title, url: parsed.url),
                        customName: Self.customName(catalogName),
                        username: credentials?.username, authScheme: asked?.scheme
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
                guard isCurrent() else { return }
                self?.failed(error, server: "the catalog") { [weak self] in self?.connectToCatalog() }
            }
        } timedOut: { [weak self] in
            self?.timedOut(parsed.url)
        }
    }

    static let accountMoved = "The account in the address is now in the fields. Check the address, then try again."

    /// The server at `url` with this account is already added: it says so,
    /// under the fields (decision 36). Compared with the addresses as they
    /// really are, a catalog's key put back in, only here on the iPhone.
    private func isAdded(_ kind: SavedServer.Kind, _ url: URL, username: String?) -> Bool {
        guard saved().contains(where: { $0.kind == kind && $0.isAt(url, username: username) }) else { return false }
        error = "You’ve already added this server."
        return true
    }

    /// What was typed for a name, if anything.
    private static func customName(_ typed: String) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The catalog's own name, or its address's host.
    static func name(_ title: String?, url: URL) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? url.host() ?? "OPDS catalog" : title
    }

    // MARK: Trust

    /// Trust or Cancel on the trust step: back to the form, and on if
    /// trusted.
    func decideTrust(_ trust: Bool) {
        guard let question = trustQuestion else { return }
        pop()
        trustQuestion = nil
        guard trust else {
            error = "Not connected: the server’s certificate wasn’t trusted."
            return
        }
        do {
            try KeychainCertificatePinStore(serverID: attemptID.rawValue).save(question.certificate.pinToSave)
        } catch {
            self.error = "Couldn’t keep the certificate. Try again."
            return
        }
        afterTrust?()
    }

    // MARK: State

    /// Setup is done (or the server changed): start clean, keeping the
    /// finished attempt's secrets, which are the server's now.
    func reset() {
        connecting.cancel()
        bookOrbitAddress = ""
        bookOrbitName = ""
        bookOrbitUsername = ""
        bookOrbitPassword = ""
        catalogAddress = ""
        catalogName = ""
        catalogUsername = ""
        catalogPassword = ""
        signIn = nil
        syncsProgress = true
        error = nil
        trustQuestion = nil
        pending = nil
        afterTrust = nil
        attemptID = SavedServer.newID()
        attemptAddress = nil
    }

    /// Back out of a step: stop waiting for its server.
    func leftStep() {
        connecting.cancel()
    }

    /// Something typed: the try still running is for what was there before,
    /// so it stops, and the next Sign in or Connect starts afresh.
    private func edited() {
        connecting.cancel()
        error = nil
    }

    /// The server didn't answer in time.
    private func timedOut(_ url: URL) {
        error = "\(url.host() ?? "The server") didn’t answer. Check the address, including any port (such as :3300), and that this iPhone is on the same network."
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
    private func serverID(for url: URL) -> LibrarySourceID {
        if let attemptAddress, attemptAddress != url {
            try? ServerCredentials.removeAll(serverID: attemptID.rawValue)
            attemptID = SavedServer.newID()
        }
        attemptAddress = url
        return attemptID
    }

    private func failed(_ error: any Error, server: String, retry: @escaping () -> Void) {
        let pin = try? KeychainCertificatePinStore(serverID: attemptID.rawValue).load()
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
                return "Can’t reach \(place). Check the address, including any port (such as :3300), and that this iPhone is on the same network."
            }
        default:
            return "Couldn’t connect to \(server). Try again."
        }
    }
}
