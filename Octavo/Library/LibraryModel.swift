import Foundation
import Observation
import OctavoKit
import UIKit

/// The connected library server, as the app sees it. v1 has one (decision 1).
struct LibraryServer {
    var id: LibrarySourceID
    /// "BookOrbit", or the OPDS catalog's name, for headings and banners.
    var name: String
    /// Where and who, for Settings: "localhost:3300 · octavo".
    var detail: String
    var source: any LibrarySource
    /// The same library asking for small pages, for the three covers on a
    /// collection's row. `nil`: rows load the list's first full page (which
    /// is then ready when the row is tapped).
    var previewSource: (any LibrarySource)? = nil
}

/// The app-wide library state: the connected server, its chips, Home's
/// lists, and every list opened so far, so a fold (which rebuilds the views)
/// shows them without loading again. Views find a book's library with
/// `source(for:)`.
@Observable
final class LibraryModel {
    private(set) var server: LibraryServer?
    private(set) var root: LibraryRoot?
    /// Shown as a banner at the top of Home and the Library (decision 22).
    var connectionProblem: ConnectionProblem?
    /// The Library tab's chip.
    var chip: LibraryLink?

    /// Home: at most five, server and iPhone together, newest first.
    private(set) var continueReading: [SourcedBook] = []
    /// Home: the server's newest books.
    private(set) var newBooks: [SourcedBook] = []
    /// Home has loaded once; until then it shows a spinner, not the empty state.
    private(set) var homeLoaded = false
    /// The server's Continue reading didn't load, so an empty list doesn't
    /// mean nothing is in progress.
    private(set) var continueReadingFailed = false
    /// The chips didn't load for a reason the banner doesn't cover.
    private(set) var rootFailed = false

    /// Changes with every connect and disconnect, so a screen holding the
    /// old server's source starts over.
    private(set) var connection = 0
    /// Called when the server changes (the shell closes its screens).
    @ObservationIgnored var serverChanged: () -> Void = {}

    let covers = CoverCache()
    @ObservationIgnored let recents: RecentBooks
    @ObservationIgnored private var feeds: [FeedKey: FeedModel] = [:]
    @ObservationIgnored private var previews: [FeedKey: FeedModel] = [:]
    @ObservationIgnored private var serverContinueReading: [SourcedBook] = []

    /// How many new books Home's row scrolls through.
    static let newBooksLimit = 20

    init(recents: RecentBooks = RecentBooks()) {
        self.recents = recents
    }

    /// The library `id` names, if it's connected.
    func source(for id: LibrarySourceID) -> (any LibrarySource)? {
        server?.id == id ? server?.source : nil
    }

    /// Replaces the server and loads its chips and Home.
    func connect(_ server: LibraryServer) async {
        self.server = server
        connection += 1
        serverChanged()
        root = nil
        chip = nil
        feeds = [:]
        previews = [:]
        serverContinueReading = []
        newBooks = []
        homeLoaded = false
        continueReadingFailed = false
        connectionProblem = nil
        await loadRoot()
        await loadHome()
    }

    func disconnect() {
        #if DEBUG
        // The debug servers' Keychain items, like Remove server will (#12).
        if let id = server?.id, id.rawValue.hasPrefix("debug-local-") {
            try? ServerCredentials.removeAll(serverID: id.rawValue)
        }
        #endif
        server = nil
        connection += 1
        serverChanged()
        root = nil
        chip = nil
        feeds = [:]
        previews = [:]
        serverContinueReading = []
        continueReading = []
        newBooks = []
        homeLoaded = false
        continueReadingFailed = false
        rootFailed = false
        connectionProblem = nil
    }

    // MARK: Lists

    /// The list at `link` in library `source`, made once and kept. `nil` if
    /// that library isn't connected.
    func feed(_ link: LibraryLink, from source: LibrarySourceID) -> FeedModel? {
        let key = FeedKey(source: source, link: link)
        if let feed = feeds[key] { return feed }
        guard let library = self.source(for: source) else { return nil }
        let feed = FeedModel(link: link, source: source, library: library) { [weak self] in self?.report($0) }
        feeds[key] = feed
        return feed
    }

    /// The first few books at `link`, for a collection's row: from the
    /// server's preview source when it has one, else the list itself.
    func preview(_ link: LibraryLink, from source: LibrarySourceID) -> FeedModel? {
        guard let server, server.id == source, let previewSource = server.previewSource else {
            return feed(link, from: source)
        }
        let key = FeedKey(source: source, link: link)
        if let preview = previews[key] { return preview }
        let preview = FeedModel(link: link, source: source, library: previewSource) { [weak self] in self?.report($0) }
        previews[key] = preview
        return preview
    }

    func coverImage(for book: SourcedBook, size: LibraryCoverSize) async -> UIImage? {
        guard let library = source(for: book.source) else { return nil }
        return await covers.image(for: book, size: size, from: library)
    }

    /// Retry on the banner: what failed loads again.
    func retry() async {
        connectionProblem = nil
        if root == nil { await loadRoot() }
        let failed = (Array(feeds.values) + Array(previews.values)).filter { $0.state == .failed }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHome() }
            for feed in failed {
                group.addTask { await feed.retry() }
            }
        }
    }

    private func loadRoot() async {
        guard let server else { return }
        rootFailed = false
        do {
            let root = try await server.source.root()
            self.root = root
            if !root.chips.contains(where: { $0.link == chip }) {
                // OPDS: the whole-library chip, not an empty "Keep Reading".
                let start = root.startChip.flatMap { start in root.chips.contains { $0.link == start } ? start : nil }
                chip = start ?? root.chips.first?.link
            }
        } catch {
            rootFailed = true
            report(error)
        }
    }

    // MARK: Home

    /// Continue reading and the newest books, from the server and the iPhone.
    func loadHome() async {
        guard let server else { return }
        if root == nil { await loadRoot() }
        async let reading = books(at: root?.continueReading, from: server)
        async let new = books(at: root?.recentlyAdded, from: server)
        let (readingBooks, newestBooks) = await (reading, new)
        // A failed list keeps what it showed.
        if let readingBooks { serverContinueReading = readingBooks }
        continueReadingFailed = readingBooks == nil
        if let newestBooks { newBooks = Array(newestBooks.prefix(Self.newBooksLimit)) }
        mergeContinueReading()
        homeLoaded = true
    }

    /// Opening a book puts it first in Continue reading.
    func bookOpened(_ book: SourcedBook) {
        try? recents.record(book)
        mergeContinueReading()
    }

    /// Lists Continue reading again, so its rows show the latest positions.
    func mergeContinueReading() {
        // Records from a server that's gone can't be opened.
        let iPhone = recents.records().filter { source(for: $0.book.source) != nil }
        continueReading = ContinueReading.merge(server: serverContinueReading, iPhone: iPhone)
    }

    /// `[]` with no list to load; `nil` if it failed.
    private func books(at link: LibraryLink?, from server: LibraryServer) async -> [SourcedBook]? {
        guard let link else { return [] }
        do {
            return try await server.source.feed(link).books.map { SourcedBook(source: server.id, book: $0) }
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: Errors

    /// Connection problems become the banner; anything else stays with the
    /// list that failed.
    func report(_ error: any Error) {
        let name = server?.name ?? "the server"
        switch error {
        case is CancellationError:
            break
        case let error as URLError where error.code == .cancelled:
            break
        case is URLError:
            connectionProblem = .unreachable(server: name)
        case LibraryError.signedOut:
            connectionProblem = .signedOut(server: name)
        default:
            break
        }
    }

    // MARK: Debug

    #if DEBUG
    enum DebugConnection: Equatable {
        case idle, connecting
        case failed(String)
    }

    private(set) var debugConnection = DebugConnection.idle

    /// Fixed, so the iPhone's records of its books match across launches.
    static let localBookOrbitID = LibrarySourceID(rawValue: "debug-local-bookorbit")

    /// The local BookOrbit from `dev/bookorbit/README.md`, until first run
    /// (#12) adds servers. Tokens are kept in the Keychain, so it signs in
    /// (BookOrbit allows 5 a minute) only when there are none or they've
    /// expired; Disconnect forgets them.
    func connectLocalBookOrbit() async {
        debugConnection = .connecting
        let client = BookOrbitClient(
            baseURL: URL(string: "http://localhost:3300")!,
            tokenStore: KeychainBookOrbitTokenStore(serverID: Self.localBookOrbitID.rawValue),
            deviceLabel: "Octavo (debug)",
            transport: ServerTransport(server: URL(string: "http://localhost:3300")!)
        )
        do {
            do {
                _ = try await client.libraries()
            } catch BookOrbitError.notSignedIn, BookOrbitError.sessionExpired {
                try await client.login(username: "octavo", password: "OctavoDev1")
            }
            debugConnection = .idle
            await connect(LibraryServer(
                id: Self.localBookOrbitID, name: "BookOrbit",
                detail: "localhost:3300 · octavo", source: BookOrbitSource(client: client),
                previewSource: BookOrbitSource(client: client, pageSize: 3)
            ))
        } catch {
            debugConnection = .failed(String(describing: error))
        }
    }

    /// The local OPDS servers from `dev/opds/README.md`, until first run
    /// (#12) adds servers. Passwords stay in memory.
    enum DebugOPDSServer: String, CaseIterable, Identifiable {
        case calibreWeb, cops, komga, komga2, kavita

        var id: Self { self }

        var name: String {
            switch self {
            case .calibreWeb: "Calibre-Web"
            case .cops: "COPS"
            case .komga, .komga2: "Komga"
            case .kavita: "Kavita"
            }
        }

        private var port: Int {
            switch self {
            case .calibreWeb: 3310
            case .cops: 3320
            case .komga, .komga2: 3330
            case .kavita: 3340
            }
        }

        private var base: URL { URL(string: "http://localhost:\(port)")! }

        var detail: String {
            switch self {
            case .calibreWeb: "localhost:3310 · OPDS 1.2 · octavo"
            case .cops: "localhost:3320 · OPDS 1.2"
            case .komga: "localhost:3330 · OPDS 1.2 · octavo@example.com"
            case .komga2: "localhost:3330 · OPDS 2.0 · octavo@example.com"
            case .kavita: "localhost:3340 · OPDS 1.2 · API key"
            }
        }

        var sourceID: LibrarySourceID { LibrarySourceID(rawValue: "debug-local-\(rawValue)") }

        var credentials: PasswordCredentials? {
            switch self {
            case .calibreWeb: PasswordCredentials(username: "octavo", password: "OctavoDev1")
            case .komga, .komga2: PasswordCredentials(username: "octavo@example.com", password: "OctavoDev1")
            case .cops, .kavita: nil
            }
        }

        func catalogURL() async throws -> URL {
            switch self {
            case .calibreWeb: return base.appending(path: "opds")
            case .cops: return base.appending(path: "feed")
            case .komga: return base.appending(path: "opds/v1.2/catalog")
            case .komga2: return base.appending(path: "opds/v2/catalog")
            case .kavita:
                // The OPDS address carries the account's API key, which
                // Kavita's REST login returns (its settings page shows it too).
                var request = URLRequest(url: base.appending(path: "api/Account/login"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["username": "octavo", "password": "OctavoDev1"])
                let (data, _) = try await ServerTransport(server: base).data(for: request)
                struct Login: Decodable { var apiKey: String }
                return base.appending(path: "api/opds/\(try JSONDecoder().decode(Login.self, from: data).apiKey)")
            }
        }
    }

    func connectLocalOPDS(_ server: DebugOPDSServer) async {
        debugConnection = .connecting
        let catalog: URL
        do {
            catalog = try await server.catalogURL()
        } catch {
            debugConnection = .failed(String(describing: error))
            return
        }
        let secret = OPDSURLSecret.detect(in: catalog)
        // The password goes to the Keychain, as first run (#12) will do.
        let passwords = KeychainPasswordStore(serverID: server.sourceID.rawValue)
        if let credentials = server.credentials { try? await passwords.save(credentials) }
        // All four local servers ask for Basic (dev/opds/README.md).
        let scheme: HTTPAuthScheme? = server.credentials == nil ? nil : .basic
        let source = OPDSSource(
            catalogURL: catalog,
            transport: ServerTransport(server: catalog, passwords: passwords, authScheme: scheme),
            credentials: passwords,
            authScheme: scheme,
            secret: secret
        )
        await connect(LibraryServer(id: server.sourceID, name: server.name, detail: server.detail, source: source))
        debugConnection = root == nil ? .failed("\(server.name) didn’t send its catalog.") : .idle
    }

    /// Made-up books, no network: for screenshots and previews.
    func connectSampleLibrary(nothingInProgress: Bool = false) async {
        await connect(LibraryServer(
            id: SampleLibrarySource.id, name: "BookOrbit", detail: "Sample library",
            source: SampleLibrarySource(nothingInProgress: nothingInProgress)
        ))
    }
    #endif
}

private struct FeedKey: Hashable {
    var source: LibrarySourceID
    var link: LibraryLink
}
