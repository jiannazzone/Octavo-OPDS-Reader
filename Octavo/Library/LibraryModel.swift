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

    let covers = CoverCache()
    @ObservationIgnored let recents: RecentBooks
    @ObservationIgnored private var feeds: [FeedKey: FeedModel] = [:]
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
        root = nil
        chip = nil
        feeds = [:]
        serverContinueReading = []
        newBooks = []
        homeLoaded = false
        connectionProblem = nil
        await loadRoot()
        await loadHome()
    }

    func disconnect() {
        server = nil
        root = nil
        chip = nil
        feeds = [:]
        serverContinueReading = []
        continueReading = []
        newBooks = []
        homeLoaded = false
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

    func coverImage(for book: SourcedBook, size: LibraryCoverSize) async -> UIImage? {
        guard let library = source(for: book.source) else { return nil }
        return await covers.image(for: book, size: size, from: library)
    }

    /// Retry on the banner: what failed loads again.
    func retry() async {
        connectionProblem = nil
        if root == nil { await loadRoot() }
        await loadHome()
        for feed in feeds.values where feed.state == .failed {
            await feed.retry()
        }
    }

    private func loadRoot() async {
        guard let server else { return }
        do {
            let root = try await server.source.root()
            self.root = root
            if !root.chips.contains(where: { $0.link == chip }) {
                chip = root.chips.first?.link
            }
        } catch {
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
        if let newestBooks { newBooks = Array(newestBooks.prefix(Self.newBooksLimit)) }
        mergeContinueReading()
        homeLoaded = true
    }

    /// Opening a book puts it first in Continue reading.
    func bookOpened(_ book: SourcedBook) {
        try? recents.record(book)
        mergeContinueReading()
    }

    private func mergeContinueReading() {
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
    /// (#12) adds servers. Tokens stay in memory until #9, so every launch
    /// signs in once (BookOrbit allows 5 a minute).
    func connectLocalBookOrbit() async {
        debugConnection = .connecting
        let client = BookOrbitClient(baseURL: URL(string: "http://localhost:3300")!, deviceLabel: "Octavo (debug)")
        do {
            try await client.login(username: "octavo", password: "OctavoDev1")
            debugConnection = .idle
            await connect(LibraryServer(
                id: Self.localBookOrbitID, name: "BookOrbit",
                detail: "localhost:3300 · octavo", source: BookOrbitSource(client: client)
            ))
        } catch {
            debugConnection = .failed(String(describing: error))
        }
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
