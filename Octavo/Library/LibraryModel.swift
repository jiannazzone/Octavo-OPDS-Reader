import Foundation
import Observation
import OctavoKit
import UIKit

/// A connected library server, as the app sees it (decision 36).
struct LibraryServer {
    var id: LibrarySourceID
    /// What the app calls it, in headings and banners: the name you gave it,
    /// else `ownName` (`SavedServer`).
    var name: String
    /// "BookOrbit", or the OPDS catalog's own name, with a number if another
    /// server had that name when this one was added.
    var ownName: String? = nil
    /// Where, for Settings: "books.example.com", "localhost:3300".
    var address = ""
    /// Who's signed in, if anyone: "adam".
    var username: String?
    /// There's a sign-in to sign out of: BookOrbit's, or the password an
    /// OPDS catalog asked for.
    var signsIn = false
    /// The server's kind and full address, for `identity` (Remove server).
    var origin: String?
    var source: any LibrarySource
    /// The same library asking for small pages, for the three covers on a
    /// collection's row. `nil`: rows load the list's first full page (which
    /// is then ready when the row is tapped).
    var previewSource: (any LibrarySource)? = nil
    /// Reading progress syncs with this server (setup's choice, decision 6).
    var syncsProgress = false
    /// A catalog's books sync their place with the KOReader account
    /// (`SavedServer.koreaderSync`).
    var syncsWithKOReader = false

    /// Where and who, for Settings: "localhost:3300 · octavo".
    var detail: String {
        [address, username ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One connected server and what it has said (decision 36): its sections,
/// its books in progress, and whether it can be reached.
@Observable
final class ServerConnection {
    fileprivate(set) var server: LibraryServer
    fileprivate(set) var root: LibraryRoot?
    /// The sections didn't load for a reason the banner doesn't cover.
    fileprivate(set) var rootFailed = false
    /// A banner in the Library for this server, and on Home if it needs you
    /// (decision 22, `LibraryModel.homeProblems`).
    fileprivate(set) var problem: ConnectionProblem?
    @ObservationIgnored fileprivate var continueReading: [SourcedBook] = []
    /// Its Continue reading has loaded once.
    fileprivate(set) var homeLoaded = false
    fileprivate(set) var continueReadingFailed = false

    fileprivate init(server: LibraryServer) {
        self.server = server
    }
}

/// The app-wide library state: the connected servers, each one's sections,
/// Home's lists, and every list opened so far, so a fold (which rebuilds the
/// views) shows them without loading again. Views find a book's library with
/// `source(for:)`.
///
/// Each server is its own library (decision 36): `server`, `root` and
/// `connectionProblem` are the one the Library shows, and Home and Search go
/// through `connections`.
@Observable
final class LibraryModel {
    /// In the order they were added.
    private(set) var connections: [ServerConnection] = []
    private var chosenID: LibrarySourceID?
    /// The Library's server: the one chosen, else the first.
    var chosen: ServerConnection? {
        connections.first { $0.server.id == chosenID } ?? connections.first
    }
    var server: LibraryServer? { chosen?.server }
    var root: LibraryRoot? { chosen?.root }
    var rootFailed: Bool { chosen?.rootFailed ?? false }
    /// Shown as a banner at the top of the Library (decision 22).
    var connectionProblem: ConnectionProblem? {
        get { chosen?.problem }
        set { chosen?.problem = newValue }
    }
    /// The Library tab's chip.
    var chip: LibraryLink?

    /// Home: the books in progress, every server's and the iPhone's together,
    /// newest first. The first is the book you're reading.
    private(set) var continueReading: [SourcedBook] = []

    /// Home has loaded once from any server; until then it shows
    /// placeholders, not the empty state. A slow server's books join later.
    var homeLoaded: Bool {
        connections.contains(where: \.homeLoaded)
    }

    /// No server's Continue reading loaded, so an empty list doesn't mean
    /// nothing is in progress.
    var continueReadingFailed: Bool {
        !connections.isEmpty && connections.allSatisfy(\.continueReadingFailed)
    }

    /// There's more than one server, so books and sections name theirs
    /// (decision 36).
    var hasSeveralServers: Bool {
        connections.count > 1
    }

    /// The banners on Home. With one server, whatever's wrong with it. With
    /// several, only a sign-in, which needs you: a server you can't reach
    /// right now shows in the Library and in Search, or Home would nag
    /// whenever you're away from a server at home (decision 36).
    var homeProblems: [(server: LibrarySourceID, problem: ConnectionProblem)] {
        connections.compactMap { connection in
            guard let problem = connection.problem else { return nil }
            if hasSeveralServers, case .unreachable = problem { return nil }
            return (connection.server.id, problem)
        }
    }

    /// Changes with every server added or removed, so a screen holding a
    /// server's source starts over.
    private(set) var connection = 0
    /// A server was added (the shell starts its search over).
    @ObservationIgnored var serverAdded: () -> Void = {}
    /// `id` is gone (the shell closes what showed its books).
    @ObservationIgnored var serverRemoved: (LibrarySourceID) -> Void = { _ in }

    let covers: CoverCache
    @ObservationIgnored let recents: RecentBooks
    @ObservationIgnored let finished: FinishedBooks
    /// What `finished` holds, so a cover doesn't read the file.
    private(set) var finishedOnIPhone: Set<SourcedBook.ID> = []
    /// The latest word on a server's mark where a list's copy of the book may
    /// be older: marked here, or its details disagreed.
    private(set) var readMarks: [SourcedBook.ID: ReadMark] = [:]
    @ObservationIgnored let onIPhone: BooksOnIPhone
    /// Books imported from Files, and the sample book once read.
    @ObservationIgnored let imported: ImportedBooks
    @ObservationIgnored let importedSource: ImportedBooksSource
    /// What `imported` holds, newest first, so the shell sees an import.
    private(set) var importedBooks: [SourcedBook] = []
    @ObservationIgnored private var feeds: [FeedKey: FeedModel] = [:]
    @ObservationIgnored private var previews: [FeedKey: FeedModel] = [:]
    /// The whole list kept for each server (`wholeFeed`).
    @ObservationIgnored private var wholeLists: [LibrarySourceID: LibraryLink] = [:]

    /// The book you're reading and the others in progress Home shows.
    static let continueReadingLimit = 8

    init(
        recents: RecentBooks = RecentBooks(), finished: FinishedBooks = FinishedBooks(), onIPhone: BooksOnIPhone = BooksOnIPhone(),
        imported: ImportedBooks = ImportedBooks(), covers: CoverCache = CoverCache()
    ) {
        self.covers = covers
        self.recents = recents
        self.finished = finished
        finishedOnIPhone = finished.books()
        self.onIPhone = onIPhone
        self.imported = imported
        importedSource = ImportedBooksSource(store: imported)
        imported.clearIncoming()
        importedChanged()
    }

    func connection(_ id: LibrarySourceID) -> ServerConnection? {
        connections.first { $0.server.id == id }
    }

    func server(_ id: LibrarySourceID) -> LibraryServer? {
        connection(id)?.server
    }

    /// The library `id` names, if it's connected. Imported books' always is.
    func source(for id: LibrarySourceID) -> (any LibrarySource)? {
        if id == .files { return importedSource }
        return server(id)?.source
    }

    /// What's beside a book's place with several servers: its server's name.
    /// Imported books have none (decision 36).
    func label(for book: SourcedBook) -> String? {
        hasSeveralServers ? server(book.source)?.name : nil
    }

    /// A book on the shelf, imported or the sample: enough to leave setup
    /// without a server (decisions 6 and 30).
    var hasBooks: Bool {
        !importedBooks.isEmpty
    }

    /// `imported` changed: an import, a removal, the sample book read.
    func importedChanged() {
        importedBooks = imported.all().map { SourcedBook(source: .files, book: $0.book) }
        mergeContinueReading()
    }

    /// Adds the server, or replaces the one with its ID, shows it in the
    /// Library, and loads its sections and Home.
    func connect(_ server: LibraryServer) async {
        add(server)
        await load(server.id)
    }

    /// Adds the server, or replaces the one with its ID, and shows it in the
    /// Library, without loading anything: at launch, so the first frame shows
    /// the tabs rather than setup.
    func add(_ server: LibraryServer) {
        if let index = connections.firstIndex(where: { $0.server.id == server.id }) {
            forgetLists(of: server.id)
            connections[index] = ServerConnection(server: server)
        } else {
            connections.append(ServerConnection(server: server))
        }
        chosenID = server.id
        chip = nil
        connection += 1
        serverAdded()
    }

    /// The Library shows `id`.
    func choose(_ id: LibrarySourceID?) {
        guard let id, connection(id) != nil else { return }
        chosenID = id
    }

    /// Every server's sections, then its Home, each as it answers.
    func loadServers() async {
        await withTaskGroup(of: Void.self) { group in
            for connection in connections {
                let id = connection.server.id
                group.addTask { await self.load(id) }
            }
        }
    }

    /// `id`'s sections, then its Home.
    func load(_ id: LibrarySourceID) async {
        guard let connection = connection(id) else { return }
        await loadRoot(connection)
        await loadHome(connection)
    }

    /// Takes `id` away. What's left of it goes with it.
    func remove(_ id: LibrarySourceID) {
        connections.removeAll { $0.server.id == id }
        if chosenID == id { chosenID = connections.first?.server.id }
        forgetLists(of: id)
        chip = nil
        connection += 1
        mergeContinueReading()
        serverRemoved(id)
        Task { await covers.removeFiles(of: id) }
    }

    /// Every server goes, as after a debug disconnect.
    func disconnect() {
        for id in connections.map(\.server.id) { remove(id) }
    }

    private func forgetLists(of id: LibrarySourceID) {
        feeds = feeds.filter { $0.key.source != id }
        previews = previews.filter { $0.key.source != id }
    }

    /// Sign in again worked as `username`.
    func signedIn(_ id: LibrarySourceID, as username: String) {
        connection(id)?.server.username = username
    }

    /// A catalog's "Sync with KOReader" changed.
    func setSyncsWithKOReader(_ id: LibrarySourceID, _ on: Bool) {
        connection(id)?.server.syncsWithKOReader = on
    }

    /// The name you gave `id` (decision 36), or its own again.
    func rename(_ id: LibrarySourceID, to name: String) {
        guard let connection = connection(id) else { return }
        connection.server.name = name
        connection.problem = switch connection.problem {
        case .unreachable: .unreachable(server: name)
        case .signedOut: .signedOut(server: name)
        case nil: nil
        }
    }

    /// Remove server: the records of `server`'s books that can't be opened
    /// once it's gone (Continue reading, finished marks). Its books on the
    /// iPhone stay listed, so Storage shows the ones kept.
    func forgetBooks(of server: LibrarySourceID) {
        try? recents.remove(source: server)
        try? finished.remove(source: server)
        finishedOnIPhone = finished.books()
        readMarks = readMarks.filter { $0.key.source != server }
    }

    // MARK: Lists

    /// The list at `link` in library `source`, made once and kept. `nil` if
    /// that library isn't connected.
    func feed(_ link: LibraryLink, from source: LibrarySourceID) -> FeedModel? {
        let key = FeedKey(source: source, link: link)
        if let feed = feeds[key] { return feed }
        guard let library = self.source(for: source) else { return nil }
        let feed = FeedModel(link: link, source: source, library: library, report: reporter(for: source)) { [weak self] books in
            self?.listed(books, from: source)
        }
        feeds[key] = feed
        return feed
    }

    /// A list loaded whole in pages of its own (Komga's `size=2000`, #131):
    /// `feed(_:from:)`, keeping only the latest per server, so up to 2,000
    /// books aren't held for every list that was ever sorted.
    func wholeFeed(_ link: LibraryLink, of shown: LibraryLink, from source: LibrarySourceID) -> FeedModel? {
        if link != shown {
            if let last = wholeLists[source], last != link { feeds[FeedKey(source: source, link: last)] = nil }
            wholeLists[source] = link
        }
        return feed(link, from: source)
    }

    /// Back to the catalog's order: its whole list goes.
    func dropWholeFeed(from source: LibrarySourceID) {
        guard let last = wholeLists.removeValue(forKey: source) else { return }
        feeds[FeedKey(source: source, link: last)] = nil
    }

    /// Lists filtered by read status (#131), which a new mark changes.
    private func reloadFiltered(from source: LibrarySourceID) {
        guard let library = self.source(for: source) else { return }
        for (key, feed) in feeds where key.source == source && feed.state == .loaded && (library.order(of: key.link)?.filter ?? .all) != .all {
            Task { await feed.reload() }
        }
    }

    /// A sorted or filtered list the reader moved off (#131): dropped, so
    /// trying each order doesn't keep every one for good. A list in its own
    /// order, and the Unread shelf's, stay for the shelves.
    func moved(off link: LibraryLink, from source: LibrarySourceID) {
        guard let order = self.source(for: source)?.order(of: link), order.sort != order.sorts.first || order.filter != .all,
              link != connection(source)?.root?.unread else { return }
        feeds[FeedKey(source: source, link: link)] = nil
    }

    /// The first few books at `link`, for a collection's row: from the
    /// server's preview source when it has one, else the list itself.
    func preview(_ link: LibraryLink, from source: LibrarySourceID) -> FeedModel? {
        guard let previewSource = server(source)?.previewSource else {
            return feed(link, from: source)
        }
        let key = FeedKey(source: source, link: link)
        if let preview = previews[key] { return preview }
        let preview = FeedModel(link: link, source: source, library: previewSource, report: reporter(for: source))
        previews[key] = preview
        return preview
    }

    func coverImage(for book: SourcedBook, size: LibraryCoverSize) async -> UIImage? {
        guard let library = source(for: book.source) else { return nil }
        return await covers.image(for: book, size: size, from: library)
    }

    /// An author's photo, from the library that listed them.
    func portraitImage(_ portrait: LibraryCover, from source: LibrarySourceID) async -> UIImage? {
        guard let library = self.source(for: source) else { return nil }
        return await covers.image(for: portrait, in: source, size: .thumbnail, from: library)
    }

    /// Retry on the banner: what failed on `id`, else on the Library's
    /// server, loads again.
    func retry(_ id: LibrarySourceID? = nil) async {
        guard let connection = id.flatMap(connection(_:)) ?? chosen else { return }
        let source = connection.server.id
        connection.problem = nil
        if connection.root == nil { await loadRoot(connection) }
        let failed = (feeds.filter { $0.key.source == source }.map(\.value) + previews.filter { $0.key.source == source }.map(\.value))
            .filter { $0.state == .failed }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHome(connection) }
            for feed in failed {
                group.addTask { await feed.retry() }
            }
        }
    }

    private func loadRoot(_ connection: ServerConnection) async {
        connection.rootFailed = false
        do {
            let root = try await connection.server.source.root()
            // Removed meanwhile: this answer is the old one's.
            guard isConnected(connection) else { return }
            connection.root = root
            if connection === chosen, !root.chips.contains(where: { $0.link == chip }) {
                // OPDS: the whole-library chip, not an empty "Keep Reading".
                let start = root.startChip.flatMap { start in root.chips.contains { $0.link == start } ? start : nil }
                chip = start ?? root.chips.first?.link
            }
        } catch {
            guard isConnected(connection) else { return }
            connection.rootFailed = true
            report(error, on: connection)
        }
    }

    private func isConnected(_ connection: ServerConnection) -> Bool {
        connections.contains { $0 === connection }
    }

    // MARK: Home

    /// The books in progress, from every server and the iPhone. New arrivals
    /// live in the Library, not here.
    func loadHome() async {
        await withTaskGroup(of: Void.self) { group in
            for connection in connections {
                group.addTask { await self.loadHome(connection) }
            }
        }
    }

    private func loadHome(_ connection: ServerConnection) async {
        guard isConnected(connection) else { return }
        if connection.root == nil { await loadRoot(connection) }
        guard isConnected(connection) else { return }
        let readingBooks = await books(at: connection.root?.continueReading, from: connection)
        guard isConnected(connection) else { return }
        // A failed list keeps what it showed.
        if let readingBooks { connection.continueReading = readingBooks }
        connection.continueReadingFailed = readingBooks == nil
        mergeContinueReading()
        connection.homeLoaded = true
    }

    /// Whether a cover shows `book` as finished. Lists and the iPhone's
    /// records each hold a copy of the book, so a mark set since then wins.
    func isFinished(_ book: SourcedBook) -> Bool {
        readMarks[book.id]?.finished ?? book.book.isFinished ?? finishedOnIPhone.contains(book.id)
    }

    /// `book`'s read status on its server (BookOrbit's, #120), as
    /// `isFinished` reads the mark.
    func readStatus(of book: SourcedBook) -> LibraryReadStatus? {
        readMarks[book.id].map(\.status) ?? book.book.readStatus
    }

    /// A book marked finished leaves Home: BookOrbit drops it from its own
    /// list, and this takes it off the iPhone's. Marked unfinished, it comes
    /// back once it's read again.
    func markedFinished(_ book: SourcedBook.ID, _ finished: Bool) {
        if let source = source(for: book.source), source.tracksFinished {
            // Not finished is BookOrbit's `reading` (`BookOrbitSource.setFinished`).
            keepMarks([book: source.tracksReadStatus ? ReadMark(finished ? .read : .reading) : ReadMark(finished: finished)])
        } else {
            finishedOnIPhone = self.finished.books()
        }
        marked(book, leavesHome: finished)
    }

    /// A read status set on the book's screen, or by starting the book
    /// (#120). As on BookOrbit's own Continue Reading, a book skimmed,
    /// abandoned, finished or unread leaves Home.
    func markedStatus(_ book: SourcedBook.ID, _ status: LibraryReadStatus) {
        keepMarks([book: ReadMark(status)])
        marked(book, leavesHome: !status.staysInContinueReading)
    }

    private func marked(_ book: SourcedBook.ID, leavesHome: Bool) {
        reloadFiltered(from: book.source)
        guard leavesHome else { return }
        try? recents.remove(book)
        connection(book.source)?.continueReading.removeAll { $0.id == book }
        mergeContinueReading()
    }

    /// A book's screen loaded its details, which may be newer than the copy
    /// its cover came from.
    func detailsLoaded(_ book: SourcedBook) {
        guard let mark = book.book.readMark, mark != readMarks[book.id] else { return }
        keepMarks([book.id: mark])
    }

    private func keepMarks(_ marks: [SourcedBook.ID: ReadMark]) {
        readMarks.merge(marks) { $1 }
        try? onIPhone.update(marks: marks)
        try? recents.update(marks: marks)
    }

    /// A list from a server that keeps the mark: the latest word on its
    /// books. Lists don't add to `readMarks`, so that loading one doesn't
    /// redraw every cover on screen.
    private func listed(_ books: [LibraryBook], from source: LibrarySourceID) {
        var marks: [SourcedBook.ID: ReadMark] = [:]
        for book in books {
            marks[SourcedBook.ID(source: source, book: book.id)] = book.readMark
        }
        guard !marks.isEmpty else { return }
        for (id, mark) in marks where readMarks[id].map({ $0 != mark }) == true {
            readMarks[id] = mark
        }
        try? onIPhone.update(marks: marks)
        try? recents.update(marks: marks)
    }

    /// Opening a book puts it first in Continue reading.
    func bookOpened(_ book: SourcedBook) {
        try? recents.record(book.withMarks(from: readMarks))
        mergeContinueReading()
    }

    /// A download (or an Open that downloads) is starting, so Search can
    /// find the book once it's on the iPhone.
    func bookDownloading(_ book: SourcedBook) {
        try? onIPhone.record(book.withMarks(from: readMarks))
    }

    /// The connected servers' books this iPhone has asked for, and the
    /// imported ones, newest first,
    /// including ones opened before `onIPhone` kept a list. Whether each is
    /// still on the iPhone is the opener's to say.
    func iPhoneBooks() -> [SourcedBook] {
        var seen = Set<SourcedBook.ID>()
        return (onIPhone.books() + recents.records().map(\.book))
            .filter { source(for: $0.source) != nil && seen.insert($0.id).inserted }
    }

    /// Lists Continue reading again, so its rows show the latest positions.
    func mergeContinueReading() {
        // Records from a server that's gone can't be opened.
        let iPhone = recents.records().filter { source(for: $0.book.source) != nil }
        continueReading = ContinueReading.merge(
            server: connections.flatMap(\.continueReading), iPhone: iPhone, limit: Self.continueReadingLimit
        )
    }

    /// `[]` with no list to load; `nil` if it failed.
    private func books(at link: LibraryLink?, from connection: ServerConnection) async -> [SourcedBook]? {
        guard let link else { return [] }
        let server = connection.server
        do {
            return try await server.source.feed(link).books.map { SourcedBook(source: server.id, book: $0) }
        } catch {
            if isConnected(connection) { report(error, on: connection) }
            return nil
        }
    }

    // MARK: Errors

    /// A list's problems, for its server's banner, while that server is
    /// connected. Imported books have no banner.
    private func reporter(for id: LibrarySourceID) -> (any Error) -> Void {
        let connection = connection(id)
        return { [weak self, weak connection] error in
            guard let self, let connection, isConnected(connection) else { return }
            report(error, on: connection)
        }
    }

    /// Connection problems on `id` become its banner; anything else stays
    /// with the list that failed.
    func report(_ error: any Error, server id: LibrarySourceID) {
        guard let connection = connection(id) else { return }
        report(error, on: connection)
    }

    private func report(_ error: any Error, on connection: ServerConnection) {
        let name = connection.server.name
        switch error {
        case is CancellationError:
            break
        case let error as URLError where error.code == .cancelled:
            break
        case is URLError:
            connection.problem = .unreachable(server: name)
        case LibraryError.signedOut:
            connection.problem = .signedOut(server: name)
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
                id: Self.localBookOrbitID, name: "BookOrbit", address: "localhost:3300", username: "octavo",
                signsIn: true, origin: LibraryServer.origin(kind: .bookOrbit, address: "http://localhost:3300"),
                source: BookOrbitSource(client: client),
                previewSource: BookOrbitSource(client: client, pageSize: 3), syncsProgress: true
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
        await connect(LibraryServer(
            id: server.sourceID, name: server.name, address: catalog.host().map { host in catalog.port.map { "\(host):\($0)" } ?? host } ?? "",
            username: server.credentials?.username, signsIn: server.credentials != nil,
            origin: LibraryServer.origin(kind: .opds, address: secret?.redact(catalog.absoluteString) ?? catalog.absoluteString, secret: secret),
            source: source, syncsWithKOReader: UserDefaults.standard.bool(forKey: "connectKOSync")
        ))
        debugConnection = self.server(server.sourceID).flatMap { _ in connection(server.sourceID)?.root } == nil
            ? .failed("\(server.name) didn’t send its catalog.") : .idle
    }

    /// Made-up books, no network: for screenshots and previews.
    func connectSampleLibrary(nothingInProgress: Bool = false, listsFail: Bool = false) async {
        await connect(LibraryServer(
            id: SampleLibrarySource.id, name: "BookOrbit", address: "Sample library",
            source: SampleLibrarySource(nothingInProgress: nothingInProgress, listsFail: listsFail)
        ))
    }
    #endif
}

private struct FeedKey: Hashable {
    var source: LibrarySourceID
    var link: LibraryLink
}
