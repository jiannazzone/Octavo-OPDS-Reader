import Foundation
import Observation
import OctavoKit

/// The shell's state: the selected tab, each tab's screens and the shared
/// states. It lives with the scene, which folding or unfolding moves between
/// displays without rebuilding (`docs/notes/duo-spreads.md` §6), so a fold
/// keeps the same screens.
@Observable
final class ShellModel {
    private(set) var tab: ShellTab = .home
    // One property per tab, so navigating in one tab doesn't redraw the others.
    private var homePath = ShellPath()
    private var libraryPath = ShellPath()
    private var searchPath = ShellPath()
    private var setupPath = ShellPath()

    /// The books, and where they come from.
    let library: LibraryModel
    /// The book open in the reader, which covers the tabs.
    var reading: OpenedBook? {
        didSet {
            if let closed = oldValue, closed != reading {
                places.readerClosed()
                library.mergeContinueReading()
            }
        }
    }
    /// The library of the book in the reader, for its screen when a fold
    /// closes it.
    private var readingSource: LibrarySourceID?
    /// Downloads books and opens them in `reading`.
    let opener: BookOpener
    /// The library of each book asked to open, until it does.
    private var opening: [LibraryBookID: LibrarySourceID] = [:]
    /// The book screens' state, kept across folds.
    let pages = BookPages()
    /// Where each book opens, and whether its place has synced (step 13).
    let places: BookPlaces
    /// The Search tab's query and results.
    let search: SearchModel
    /// Adding the server, before there is one.
    let setup = SetupModel()
    /// Where the server is kept between launches.
    let servers: ServerStore
    /// A debug launch argument is connecting a server: the tabs show, not
    /// setup, while it does.
    private var connectingAtLaunch = false
    /// The spread a tab measured last, which a tab opening for the first
    /// time lays out for until it has measured its own (`ScreenStack`).
    @ObservationIgnored var lastSpread: Spread?

    /// A debug override for the cover's strip, to look at its states without
    /// a failing download.
    var coverStrip: CoverStripMessage?

    init(library: LibraryModel = LibraryModel(), opener: BookOpener = BookOpener(), servers: ServerStore = ServerStore()) {
        self.library = library
        self.opener = opener
        self.servers = servers
        places = BookPlaces { [library] in ShellModel.progressSync(for: $0, on: library.server) }
        search = SearchModel(library: library) { [opener] in opener.status(of: $0) == .downloaded }
        opener.onOpen = { [weak self] in self?.opened($0) }
        // Another server: its books' pages, the screens opened from them
        // and the search go.
        library.serverChanged = { [weak self] in
            guard let self else { return }
            pages.removeAll()
            places.reset()
            search.reset()
            setup.reset()
            for tab in ShellTab.allCases { self[path: tab].replace([]) }
        }
        setup.push = { [weak self] in self?[path: .setup].push(.setup($0)) }
        setup.pop = { [weak self] in self?[path: .setup].pop() }
        setup.finished = { [weak self] in self?.serverAdded($0) }
        // The saved server, at once: the first frame shows the tabs, which
        // load as it answers.
        if let saved = servers.load(), let server = saved.libraryServer() {
            library.use(server)
            Task { await library.loadServer() }
        }
        #if DEBUG
        applyLaunchArguments()
        #endif
    }

    subscript(path tab: ShellTab) -> ShellPath {
        get {
            switch tab {
            case .home: homePath
            case .library: libraryPath
            case .search: searchPath
            case .setup: setupPath
            }
        }
        set {
            switch tab {
            case .home: homePath = newValue
            case .library: libraryPath = newValue
            case .search: searchPath = newValue
            case .setup: setupPath = newValue
            }
        }
    }

    // MARK: Setup

    /// No server yet: setup shows instead of the tabs, with no way past it
    /// until one is added (decision 6).
    var needsSetup: Bool {
        library.server == nil && !connectingAtLaunch
    }

    /// Setup finished: keep the server and open Home on it.
    private func serverAdded(_ saved: SavedServer) {
        guard let server = saved.libraryServer() else { return }
        do {
            try servers.save(saved)
        } catch {
            // Still usable now; setup asks again next launch.
        }
        tab = .home
        library.use(server)
        Task { await library.loadServer() }
    }

    /// Sign in again, after the server signed you out: BookOrbit through the
    /// server's own client (so its requests pick up the new session), an
    /// OPDS catalog by keeping the new password and asking again. Then the
    /// tabs load what failed.
    func signInAgain(username: String, password: String) async throws {
        guard var saved = servers.load(), let server = library.server, server.id == saved.id else {
            throw LibraryError.signedOut
        }
        switch saved.kind {
        case .bookOrbit:
            guard let source = server.source as? BookOrbitSource else { throw LibraryError.signedOut }
            try await source.client.login(username: username, password: password)
        case .opds:
            guard let source = server.source as? OPDSSource else { throw LibraryError.signedOut }
            let passwords = KeychainPasswordStore(serverID: saved.id.rawValue)
            // Unreadable, nothing is changed: a failure would otherwise put
            // back "no password".
            let previous = try await passwords.load()
            try await passwords.save(PasswordCredentials(username: username, password: password))
            // Kept only once the catalog takes it: a refusal, a failure or a
            // try given up on puts the old one back.
            do {
                guard case .open = try await source.checkAccess() else { throw LibraryError.signedOut }
            } catch {
                try? await passwords.save(previous)
                throw error
            }
        }
        if saved.username != username {
            saved.username = username
            try? servers.save(saved)
        }
        await library.retry()
    }

    #if DEBUG
    /// Debug Disconnect: forgets the server and its secrets, so the next
    /// launch (and this one) starts at setup. Remove server, with its
    /// question about downloads, is step 14.
    func forgetServer() {
        if let saved = servers.load() {
            try? ServerCredentials.removeAll(serverID: saved.id.rawValue)
        }
        try? servers.remove()
        library.disconnect()
    }
    #endif

    // MARK: Navigation

    /// Choosing the tab that's showing goes back to its root, as iOS does.
    func select(_ tab: ShellTab) {
        if tab == self.tab {
            self[path: tab].popToRoot()
        } else {
            self.tab = tab
        }
    }

    /// Opens `route` on top of the current tab; setup's steps on top of
    /// setup.
    func push(_ route: ShellRoute) {
        if case .setup = route {
            self[path: .setup].push(route)
        } else {
            self[path: tab].push(route)
        }
    }

    /// Back.
    func pop(_ tab: ShellTab) {
        self[path: tab].pop()
    }

    func popToRoot(_ tab: ShellTab) {
        self[path: tab].popToRoot()
    }

    /// The Settings button at the top of the side column.
    func openSettings() {
        push(.settings)
    }

    // MARK: Books

    /// Opens `book` in the reader, downloading it first if it isn't on the
    /// iPhone yet, and once it opens puts it first in Continue reading.
    func openBook(_ book: SourcedBook) {
        guard let source = library.source(for: book.source), opener.canOpen(book.book) else { return }
        opening[book.book.id] = book.source
        if opener.status(of: book.book) != .downloaded { library.bookDownloading(book) }
        opener.open(book.book, from: source)
    }

    /// Downloads `book` without opening it (the details' Download button).
    func downloadBook(_ book: SourcedBook) {
        guard let source = library.source(for: book.source) else { return }
        library.bookDownloading(book)
        opener.download(book.book, from: source)
    }

    /// Only a book that reaches the reader joins Continue reading: not one
    /// whose download failed or was cancelled.
    private func opened(_ book: OpenedBook) {
        let source = opening.removeValue(forKey: book.book.id)
        if let source {
            library.bookOpened(SourcedBook(source: source, book: book.book))
        }
        readingSource = source
        reading = book
    }

    /// Where the open book's bookmarks sync (decision 18): BookOrbit's own,
    /// for its books. Anything else keeps them on the iPhone.
    var readingBookmarkSync: (any BookmarkSync)? {
        guard let book = reading, let readingSource, let source = library.source(for: readingSource) as? BookOrbitSource,
              let bookID = Int(book.book.id.rawValue)
        else { return nil }
        return BookOrbitBookmarkSync(client: source.client, bookID: bookID, fileID: Int(book.file.id.rawValue))
    }

    /// Where the open book's place syncs (decision 6), through `places`, so
    /// the reader reuses the pull its screen just made.
    var readingProgressSync: (any ProgressSync)? {
        guard let book = reading, let readingSource else { return nil }
        return places.readerSync(for: SourcedBook(source: readingSource, book: book.book))
    }

    /// The server's place for the open book as the library list gave it,
    /// where the reader opens if it can't pull.
    var readingListedPlace: SyncedPosition? {
        reading.flatMap { BookPlaces.listed($0.book) }
    }

    /// Where `book`'s place syncs: its BookOrbit server, if setup chose to
    /// sync there. Books from an OPDS catalog or Files keep their place on
    /// the iPhone.
    static func progressSync(for book: SourcedBook, on server: LibraryServer?) -> (any ProgressSync)? {
        guard let server, server.id == book.source, server.syncsProgress,
              let source = server.source as? BookOrbitSource,
              let file = book.book.readableFile, let fileID = BookOrbitSource.fileID(of: file)
        else { return nil }
        let sync = BookOrbitProgressSync(client: source.client, fileID: fileID)
        #if DEBUG
        let defaults = UserDefaults.standard
        let pullDelay = defaults.double(forKey: "syncPullDelay")
        let failsPushes = defaults.bool(forKey: "syncFailsPushes")
        if pullDelay > 0 || failsPushes {
            return DebugProgressSync(wrapping: sync, pullDelay: .seconds(pullDelay), failsPushes: failsPushes)
        }
        #endif
        return sync
    }

    /// The Duo as the book:
    /// - Unfolding on a book's screen opens the book, if it's on the iPhone.
    ///   If it isn't, the screen stays, as Cover | Details, and nothing
    ///   downloads until Download or Open is tapped.
    /// - Folding while reading closes the book back to its screen.
    ///
    /// The hinge reports an unfold before the scene moves to the inner
    /// display, so the folded screen is still the top one.
    func hingeChanged(_ transition: HingeTransition) {
        switch transition {
        case .unfold:
            guard reading == nil, case .cover(let book)? = self[path: tab].top,
                  opener.status(of: book.book) == .downloaded
            else { return }
            openBook(book)
        case .fold:
            guard let book = reading else { return }
            closeToItsScreen(book)
        case .none:
            break
        }
    }

    /// Closes the reader onto `book`'s screen, opening that screen if the
    /// book was opened from somewhere else (Home's debug launch argument).
    private func closeToItsScreen(_ book: OpenedBook) {
        reading = nil
        guard let source = readingSource else { return }
        if case .cover(let shown)? = self[path: tab].top, shown.book.id == book.book.id { return }
        self[path: tab].replace(self[path: tab].routes + [.cover(SourcedBook(source: source, book: book.book))])
    }

    #if DEBUG
    /// Launch arguments that set up a state to look at:
    /// `-connectBookOrbit 1` (the local server),
    /// `-connectOPDS calibreWeb|cops|komga|komga2|kavita` (`dev/opds/`),
    /// `-sampleLibrary 1|empty`
    /// (made-up books; `empty` has nothing in progress), `-shellTab library`,
    /// `-shellConnection unreachable|signedOut`,
    /// `-shellCoverStrip failed|offline|downloading`,
    /// `-shellOpen collection|deep|cover|settings` (sample books),
    /// `-shellReading 1` (the first book in Continue reading, once connected)
    /// `-searchQuery austen` (typed into Search, once connected),
    /// `-forgetServer 1` (start at setup), `-setupCatalog <address>`
    /// (setup's OPDS step, filled in), and for BookOrbit's position sync
    /// `-syncPullDelay <seconds>` (a slow server) and `-syncFailsPushes 1`
    /// (pushes fail as if offline: "Not synced yet").
    private func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "shellTab").flatMap(ShellTab.init(rawValue:)) {
            self.tab = tab
        }
        let problem: ConnectionProblem? = switch defaults.string(forKey: "shellConnection") {
        case "unreachable": .unreachable(server: "BookOrbit")
        case "signedOut": .signedOut(server: "BookOrbit")
        default: nil
        }
        switch defaults.string(forKey: "shellCoverStrip") {
        case "failed": coverStrip = .downloadFailed
        case "offline": coverStrip = .needsConnection
        case "downloading": coverStrip = .downloading(fraction: 0.42)
        default: break
        }
        let sample = defaults.string(forKey: "sampleLibrary")
        let connectsBookOrbit = defaults.bool(forKey: "connectBookOrbit")
        let opds = defaults.string(forKey: "connectOPDS").flatMap(LibraryModel.DebugOPDSServer.init(rawValue:))
        let opens = defaults.string(forKey: "shellOpen")
        let reads = defaults.bool(forKey: "shellReading")
        let query = defaults.string(forKey: "searchQuery")
        if defaults.bool(forKey: "forgetServer") { forgetServer() }
        if let catalog = defaults.string(forKey: "setupCatalog") {
            setup.catalogAddress = catalog
            self[path: .setup].replace([.setup(.opds)])
        }
        connectingAtLaunch = connectsBookOrbit || opds != nil || (sample != nil && sample != "0")
        Task {
            defer { connectingAtLaunch = false }
            if connectsBookOrbit {
                await library.connectLocalBookOrbit()
            } else if let opds {
                await library.connectLocalOPDS(opds)
            } else if let sample, sample != "0" {
                await library.connectSampleLibrary(nothingInProgress: sample == "empty")
            }
            // After connecting, which closes the screens opened before it.
            if let problem { library.connectionProblem = problem }
            let book = SourcedBook(source: SampleLibrarySource.id, book: SampleLibrarySource.books[0])
            let classics = ShellRoute.feed(
                LibraryEntry(kind: .collection, title: "Classics", count: 5, link: LibraryLink(rawValue: "collections/classics")),
                from: SampleLibrarySource.id
            )
            switch opens {
            case "collection": self[path: .library].replace([classics])
            case "deep": self[path: .library].replace([classics, .cover(book)])
            case "cover": self[path: .library].replace([.cover(book)])
            case "settings": self[path: tab].replace([.settings])
            default: break
            }
            if reads, let first = library.continueReading.first {
                openBook(first)
            }
            if let query { search.query = query }
        }
    }
    #endif
}

#if DEBUG
/// `-syncPullDelay` and `-syncFailsPushes`: a slow server, or one that
/// can't be reached to push.
nonisolated struct DebugProgressSync: ProgressSync {
    let wrapping: any ProgressSync
    let pullDelay: Duration
    let failsPushes: Bool

    func pull() async throws -> SyncedPosition? {
        try await Task.sleep(for: pullDelay)
        return try await wrapping.pull()
    }

    func push(_ position: ReadingPosition) async throws {
        if failsPushes { throw URLError(.notConnectedToInternet) }
        try await wrapping.push(position)
    }
}
#endif
