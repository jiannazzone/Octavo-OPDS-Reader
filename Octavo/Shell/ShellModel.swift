import Foundation
import Observation
import OctavoKit
import SwiftUI
import UIKit

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
    /// The reader over the tabs, the book in it and its cover's motion.
    let reader: ReaderPresenter
    /// Downloads books and opens them in the reader.
    let opener: BookOpener
    /// The book screens' state, kept across folds.
    let pages = BookPages()
    /// Where each book opens, and whether its place has synced (step 13).
    let places: BookPlaces
    /// The Search tab's query and results.
    let search: SearchModel
    /// When the connection comes back, for places that didn't go.
    let connection = ConnectionMonitor()
    /// Adding a server.
    let setup = SetupModel()
    /// Where the servers are kept between launches.
    let servers: ServerStore
    /// The servers Remove server took away, whose kept books wait for them.
    let removedServers: RemovedServerStore
    /// Bookmarks, for a removed server's (`RemovedServer`).
    let bookmarks: BookmarkStore
    /// Copies books in from Files.
    let importer: BookImporter
    /// Whether a new install's tour has played (decision 30).
    private let tourRecord: TourRecord
    /// Where the reading settings the shell acts on are kept.
    private let defaults: UserDefaults
    /// The Files picker is showing (Import from Files, or the Library's +).
    var picksFiles = false
    /// Files from the last import that didn't come in: a banner on On
    /// iPhone until OK (`docs/design/direction.md`, Other ways in).
    var importFailures: [ImportFailure] = []
    /// The same, under setup's choices, when nothing came in.
    var setupImportFailures: [ImportFailure] = []
    /// Imports copying files in (the picker and Open in can overlap).
    private var importsRunning = 0
    var isImporting: Bool { importsRunning > 0 }
    /// A debug launch argument is connecting a server: the tabs show, not
    /// setup, while it does.
    private var connectingAtLaunch = false
    /// The spread the tab on screen measured last, which a tab opening for
    /// the first time lays out for until it has measured its own
    /// (`ScreenStack`).
    @ObservationIgnored var lastSpread: Spread?
    /// Each tab's spread, as its own stack measured it. A tab out of sight
    /// still measures, without the hinge's region (switching tabs took two
    /// pages to one for every tab), so each goes by its own.
    @ObservationIgnored var spreads: [ShellTab: Spread] = [:]

    /// Two pages in `tab`, for navigation there: what `ShellPath` pairs up,
    /// and what the stack hides for it. The spread on screen, which a tap
    /// landed on (an unfold reports before the scene moves), not the hinge,
    /// which says open on a Duo turned sideways too.
    func isTwoPages(in tab: ShellTab) -> Bool {
        (spreads[tab] ?? lastSpread)?.isTwoPages == true
    }

    /// The tab whose screens are showing: setup's, while it shows instead of
    /// the tabs.
    func isShowing(_ tab: ShellTab) -> Bool {
        showsSetup ? tab == .setup : tab == self.tab
    }

    /// A debug override for the cover's strip, to look at its states without
    /// a failing download.
    var coverStrip: CoverStripMessage?

    init(
        library: LibraryModel = LibraryModel(), opener: BookOpener = BookOpener(), servers: ServerStore = ServerStore(),
        positions: ReadingPositionStore = ReadingPositionStore(), bookmarks: BookmarkStore = BookmarkStore(),
        removedServers: RemovedServerStore = RemovedServerStore(), importer: BookImporter? = nil,
        tourRecord: TourRecord = TourRecord(), defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.tourRecord = tourRecord
        self.defaults = defaults
        self.importer = importer ?? BookImporter(store: library.imported)
        self.opener = opener
        self.servers = servers
        self.bookmarks = bookmarks
        self.removedServers = removedServers
        places = BookPlaces(store: positions) { [library] in ShellModel.progressSync(for: $0, on: library.server($0.source)) }
        search = SearchModel(library: library) { [opener] in opener.status(of: $0) == .downloaded }
        reader = ReaderPresenter(library: library, opener: opener, places: places, defaults: defaults)
        reader.underneath = { [weak self] in
            guard let self else { return ReaderPresenter.Underneath() }
            return ReaderPresenter.Underneath(
                onHome: tab == .home && self[path: .home].top == nil,
                top: self[path: tab].top, twoPages: isTwoPages(in: tab), inTour: tour != nil
            )
        }
        library.serverAdded = { [weak self] in
            guard let self else { return }
            search.reset()
            // A server to send to, at launch too: places that didn't go.
            retryUnsentPlaces()
        }
        // A server went: its books' pages, the screens opened from them and
        // the search go.
        library.serverRemoved = { [weak self] id in
            guard let self else { return }
            pages.removeAll(in: id)
            places.reset(id)
            search.reset()
            for tab in ShellTab.allCases {
                let routes = self[path: tab].routes
                let kept = routes.filter { !$0.belongs(to: id) }
                if kept.count != routes.count { self[path: tab].replace(kept) }
            }
        }
        connection.onReturn = { [weak self] in self?.retryUnsentPlaces() }
        Task.detached(priority: .background) { ShellModel.clearOldInboxFiles() }
        setup.push = { [weak self] in
            guard let self else { return }
            self[path: setupTab].push(.setup($0))
        }
        setup.pop = { [weak self] in
            guard let self else { return }
            self[path: setupTab].pop()
        }
        setup.finished = { [weak self] in self?.serverAdded($0) }
        setup.saved = { [servers] in servers.load().servers }
        // The saved servers, at once: the first frame shows the tabs, which
        // load as each answers.
        let saved = servers.load()
        for server in saved.servers.compactMap({ $0.libraryServer() }) {
            library.add(server)
        }
        library.choose(saved.chosenServer?.id)
        Task { await library.loadServers() }
        #if DEBUG
        applyLaunchArguments()
        #endif
        prepareTour()
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

    /// No server and no books: setup shows instead of the tabs, with no way
    /// past it until one is added or a book imported (decision 6). A new
    /// install starts with the tour instead, which leaves the sample book on
    /// the shelf (decision 30), so this is after removing what was there.
    var needsSetup: Bool {
        library.server == nil && !connectingAtLaunch && !library.hasBooks && tour == nil && !tourWaitsForHinge
    }

    /// Setup's first screen shows instead of the tabs: no choice but setup,
    /// or the tour's Add books, which has Skip.
    var showsSetup: Bool {
        needsSetup || addsBooksAfterTour
    }

    /// Where setup's steps go: setup itself, or (adding a server later from
    /// Settings) the tab it was opened in.
    private var setupTab: ShellTab {
        showsSetup ? .setup : tab
    }

    /// Setup finished: keep the server. The first opens Home; another opens
    /// its own Library (decision 36).
    private func serverAdded(_ added: SavedServer) {
        var added = added
        let list = servers.load()
        added.name = list.uniqueName(added.name)
        guard let server = added.libraryServer() else { return }
        do {
            try servers.add(added)
            // Only once it's saved: next launch it would be gone, and them
            // with it.
            takeBackBooks(of: server)
        } catch {
            // Still usable now; setup asks again next launch.
        }
        let isFirst = library.connections.isEmpty
        addsBooksAfterTour = false
        for tab in ShellTab.allCases { self[path: tab].replace([]) }
        tab = isFirst ? .home : .library
        setup.reset()
        library.add(server)
        Task { await library.load(server.id) }
    }

    /// Sign in again, after `id` signed you out: BookOrbit through the
    /// server's own client (so its requests pick up the new session), an
    /// OPDS catalog by keeping the new password and asking again. Then what
    /// failed on it loads.
    func signInAgain(_ id: LibrarySourceID, username: String, password: String) async throws {
        // Another account is another server: this one's unsent places and
        // bookmarks would go to it. Add a server takes it.
        guard let saved = servers.load()[id], let server = library.server(id), saved.username == nil || saved.username == username else {
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
        if saved.username != username || saved.signedOut != nil {
            try? servers.update(id) {
                $0.username = username
                $0.signedOut = nil
            }
        }
        library.signedIn(id, as: username)
        await library.retry(id)
    }

    /// Sign in, from the signed-out banner or the server's page in Settings.
    func showSignIn(_ id: LibrarySourceID) {
        #if DEBUG
        if id == LibraryModel.localBookOrbitID {
            Task { await library.connectLocalBookOrbit() }
            return
        }
        #endif
        push(.signInAgain(id))
    }

    /// The menu in the Library's title. Remembered (decision 36).
    func chooseServer(_ id: LibrarySourceID) {
        library.choose(id)
        try? servers.choose(id)
    }

    /// The Name row on a server's page: the name you gave it, or its own
    /// again if it's empty (decision 36).
    func rename(_ id: LibrarySourceID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try? servers.update(id) { $0.customName = name.isEmpty ? nil : name }
        let own = library.server(id)?.ownName
        library.rename(id, to: name.isEmpty ? own ?? name : name)
    }

    // MARK: Other ways in

    /// Import from Files, the Library's +: the system's Files picker.
    func showFilePicker() {
        setupImportFailures = []
        picksFiles = true
    }

    /// The picked files (or one opened in Octavo from another app), copied
    /// in one by one. What came in shows on On iPhone, newest first, with a
    /// banner for any that didn't; with no server the Library itself lists
    /// them. If nothing came in, the Library's top screen shows the banner
    /// instead (Adam, 2026-11-02: a failed import doesn't move you to On
    /// iPhone), and on setup's first screen setup says why under its
    /// choices.
    func importBooks(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        // A new import's banner starts afresh; one overlapping another adds
        // to it.
        if importsRunning == 0 {
            importFailures = []
            setupImportFailures = []
        }
        importsRunning += 1
        defer {
            importsRunning -= 1
            startTourIfHingeKnown()
        }
        var failures: [ImportFailure] = []
        var imported: [SourcedBook] = []
        for url in urls {
            switch await importer.importFile(at: url) {
            case .success(let book): imported.append(SourcedBook(source: .files, book: book))
            case .failure(let failure): failures.append(failure)
            }
        }
        // The first picked ends up first.
        for book in imported.reversed() { try? library.onIPhone.record(book) }
        library.importedChanged()
        opener.filesChanged()
        // Sent here mid-tour with nothing that came in: the tour carries on,
        // and the Library's banner says why afterwards.
        if tour != nil || tourWaitsForHinge, imported.isEmpty {
            importFailures += failures
            return
        }
        if needsSetup || (addsBooksAfterTour && imported.isEmpty) {
            setupImportFailures += failures
            return
        }
        addsBooksAfterTour = false
        // Opened with this file on a new install: it's what they came for
        // (Adam, 2026-11-03). The sample book is there all the same.
        if tourWaitsForHinge {
            tourWaitsForHinge = false
            tourRecord.set(.played)
            if let sample = installSampleBook() { library.bookOpened(sample) }
        }
        finishTour()
        importFailures += failures
        setupImportFailures = []
        reader.close()
        tab = .library
        self[path: .library].replace(imported.isEmpty || library.server == nil ? [] : [.onIPhone])
    }

    /// Open in Octavo, from the share sheet of Files, Mail or Safari: iOS
    /// hands over a copy in Documents/Inbox, which goes once it's in.
    func openSharedFile(_ url: URL) async {
        guard url.isFileURL else { return }
        await importBooks([url])
        if Self.isInInbox(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Where iOS puts a copy of a shared file: `Documents/Inbox`, or
    /// `tmp/<bundle ID>-Inbox` with scenes.
    nonisolated static var inboxes: [URL] {
        let bundle = Bundle.main.bundleIdentifier ?? "com.ianazzone.ereader"
        return [
            URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory),
            URL.temporaryDirectory.appending(path: "\(bundle)-Inbox", directoryHint: .isDirectory),
        ]
    }

    /// Whether `url` is a file directly in an inbox. Compared with links
    /// resolved: on a device the same folder is `/var/…` or
    /// `/private/var/…`.
    nonisolated static func isInInbox(_ url: URL, inboxes: [URL] = inboxes) -> Bool {
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        return inboxes.contains { $0.resolvingSymlinksInPath().standardizedFileURL.path == folder }
    }

    /// At launch: inbox copies an import cut short left behind (anything an
    /// hour old; a file that just arrived is about to be imported).
    nonisolated static func clearOldInboxFiles(inboxes: [URL] = inboxes, now: Date = Date()) {
        let manager = FileManager.default
        for inbox in inboxes {
            guard let names = try? manager.contentsOfDirectory(atPath: inbox.path) else { continue }
            for name in names {
                let file = inbox.appending(path: name)
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if now.timeIntervalSince(modified) > 3600 { try? manager.removeItem(at: file) }
            }
        }
    }

    /// The sample book on the shelf (the tour opens it): from then on it's
    /// under On iPhone. Copied from the app's bundle if it isn't there.
    @discardableResult
    func installSampleBook() -> SourcedBook? {
        guard let book = try? SampleBook.install(into: library.imported) else { return nil }
        let sample = SourcedBook(source: .files, book: book)
        SampleBook.startAtFirstChapter(in: places.store)
        library.importedChanged()
        try? library.onIPhone.record(sample)
        opener.filesChanged()
        return sample
    }

    /// Every book whose file is on this iPhone that can open now: the
    /// server's downloads, imported books and the sample book once read,
    /// newest first. A removed server's kept books wait for it to return.
    func onIPhoneBooks() -> [SourcedBook] {
        _ = library.importedBooks
        return downloads().map(\.book).filter { library.source(for: $0.source) != nil }
    }

    /// Removes an imported book (or the sample book), confirmed first since
    /// it's the only copy. Its place and bookmarks stay, for the same file
    /// imported again. A screen showing it closes.
    func removeImported(_ book: SourcedBook) {
        guard book.source == .files else { return }
        opener.cancel(book)
        try? library.imported.remove(book.book.id)
        try? library.onIPhone.remove(book.id)
        try? library.recents.remove(book.id)
        library.importedChanged()
        opener.filesChanged()
        pages.remove(book.id)
        for tab in ShellTab.allCases {
            let routes = self[path: tab].routes
            let kept = routes.filter { $0 != .cover(book) }
            if kept.count != routes.count { self[path: tab].replace(kept) }
        }
    }

    // MARK: Settings

    /// Sign out, confirmed on the server's page: its sign-in goes, here and
    /// (BookOrbit) on the server, and the signed-out banner shows. The
    /// server stays, and so do its books, which still open.
    func signOut(_ id: LibrarySourceID) {
        guard let connection = library.connection(id), connection.server.signsIn else { return }
        let server = connection.server
        // Noted first: if the Keychain can't delete the sign-in now, the
        // next launch does (`KeychainSweep`).
        try? servers.update(id) { $0.signedOut = true }
        library.report(LibraryError.signedOut, server: id)
        Task { await Self.endSignIn(on: server) }
    }

    /// Remove server, confirmed on its page (decision 24). Its sign-in goes
    /// (here and on BookOrbit), then every secret the Keychain holds for it,
    /// its saved address, the places waiting to go to it and the records of
    /// its books that can't open without it. `removingBooks` deletes its
    /// downloads, places and bookmarks too; kept, they come back if the same
    /// server is added again, and Storage still lists the books. Imported
    /// books and the other servers' are left alone. Then setup, if that leaves no servers and no books at
    /// all (decision 6); the sample book counts as one.
    func removeServer(_ id: LibrarySourceID, removingBooks: Bool) async {
        guard let server = library.server(id) else { return }
        await Self.endSignIn(on: server)
        try? ServerCredentials.removeAll(serverID: id.rawValue)
        // Nothing still downloading lands, or opens, afterwards.
        opener.cancelAll(in: id)
        reader.forgetRequests(in: id)
        let downloads = downloads(on: id)
        if removingBooks {
            for download in downloads { opener.removeDownload(download.book) }
            // Also any no record names: one downloaded from a list entry
            // without its files is kept under a file its record doesn't list.
            opener.removeAllDownloads(of: id)
        }
        // Its books stay listed only while their files do, so Storage
        // shows the kept ones (some known only from Continue reading,
        // which goes next).
        let kept = removingBooks ? [] : downloads.map(\.book)
        for book in library.onIPhone.books() where book.source == id && !kept.contains(book) {
            try? library.onIPhone.remove(book.id)
        }
        for book in kept where !library.onIPhone.books().contains(book) {
            try? library.onIPhone.record(book)
        }
        library.forgetBooks(of: id)
        places.forget(server: id)
        if server.canReturn, !removingBooks {
            try? removedServers.add(RemovedServer(identity: server.identity, id: id))
        } else {
            // Remove books too leaves nothing of it on the iPhone (Adam,
            // 2026-11-05). A server that can't be recognised again could never
            // read these.
            places.store.removeAll(of: id)
            bookmarks.removeAll(of: id)
        }
        try? servers.remove(id)
        library.remove(id)
    }

    /// `server` is one removed before, coming back at a new ID: its kept
    /// books, places and bookmarks are its own again (`RemovedServer`). Any
    /// other server has its own, and finds none of them.
    private func takeBackBooks(of server: LibraryServer) {
        guard let removed = removedServers.load().first(where: { $0.identity == server.identity }) else { return }
        opener.moveAll(of: removed.id, to: server.id)
        places.store.moveAll(of: removed.id, to: server.id)
        bookmarks.moveAll(of: removed.id, to: server.id)
        try? library.onIPhone.moveAll(of: removed.id, to: server.id)
        try? removedServers.remove(removed)
    }

    /// Forgets `server`'s sign-in: BookOrbit's tokens, here and on the
    /// server (which isn't waited for), or a catalog's password.
    private static func endSignIn(on server: LibraryServer) async {
        switch server.source {
        case let source as BookOrbitSource: _ = try? await source.client.signOutEverywhere()
        case let source as OPDSSource: try? await source.signOut()
        default: break
        }
    }

    #if DEBUG
    /// Debug Disconnect: forgets the server and its secrets, so the next
    /// launch (and this one) starts at setup. Downloads stay.
    func forgetServer() {
        for id in Set(servers.load().servers.map(\.id) + library.connections.map(\.server.id)) {
            try? ServerCredentials.removeAll(serverID: id.rawValue)
        }
        try? servers.save(SavedServers())
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
            self[path: setupTab].open(route, twoPages: isTwoPages(in: setupTab))
        } else {
            self[path: tab].open(route, twoPages: isTwoPages(in: tab))
        }
    }

    /// Back.
    func pop(_ tab: ShellTab) {
        self[path: tab].pop()
    }

    /// Back, or a swipe from the edge.
    func back(_ tab: ShellTab) {
        self[path: tab].back(twoPages: isTwoPages(in: tab))
    }

    func popToRoot(_ tab: ShellTab) {
        self[path: tab].popToRoot()
    }

    /// Open Library on an empty list: the Library's top, showing the list's
    /// server. The list may have come from Search with another server chosen.
    func openLibrary(showing source: LibrarySourceID) {
        if library.server?.id != source, library.connection(source) != nil { chooseServer(source) }
        popToRoot(.library)
        tab = .library
    }

    /// The Settings button at the top of the side column.
    func openSettings() {
        push(.settings)
    }

    // MARK: Books

    /// Downloads `book` without opening it (the details' Download button).
    func downloadBook(_ book: SourcedBook) {
        guard let source = library.source(for: book.source) else { return }
        library.bookDownloading(book)
        opener.download(book, from: source)
    }

    /// Sends the places that didn't reach the server (`BookPlaces.retryUnsent`):
    /// when a server connects (launch too), when the app comes back and when
    /// the connection does. The open book's goes through its reader.
    func retryUnsentPlaces() {
        Task { await places.retryUnsent(except: reader.reading?.reader.id) }
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
        // Always, so the remote's `offline` can drop pushes mid-run.
        return DebugProgressSync(wrapping: sync, pullDelay: .seconds(pullDelay), failsPushes: failsPushes)
        #else
        return sync
        #endif
    }

    /// The Duo as the book:
    /// - Unfolding on a book's screen opens the book, if it's on the iPhone.
    ///   If it isn't, the screen stays, as Cover | Details, and nothing
    ///   downloads until Download or Open is tapped.
    /// - Folding while reading closes the book back to its screen, unless
    ///   Close book when folded is off. Then the reader follows the fold, as
    ///   it does unfolding (`ReaderModel.hingeChanged`), and no leaves play.
    ///
    /// The hinge reports an unfold before the scene moves to the inner
    /// display, so the folded screen is still the top one.
    ///
    /// Either way, a cover opening or closing a book goes: it's drawn for the
    /// display it started on, and the fold is the motion now.
    func hingeChanged(_ transition: HingeTransition) {
        if transition != .none { reader.coverMotion = nil }
        if tour != nil { return tourHingeChanged(transition) }
        switch transition {
        case .unfold:
            guard reader.reading == nil, case .cover(let book)? = self[path: tab].top,
                  opener.status(of: book) == .downloaded
            else { return }
            reader.open(book, .unfolded)
        case .fold:
            guard reader.reading != nil else { return }
            if ReaderSettings.closesBookWhenFolded(in: defaults) { closeToItsScreen() }
        case .none:
            break
        }
    }

    /// Closes the reader onto its book's screen, opening that screen if the
    /// book was opened from somewhere else (Home's debug launch argument).
    /// A book with no screen to go to goes back to setup.
    private func closeToItsScreen() {
        let book = reader.readingBook
        reader.close()
        guard !needsSetup, let book else { return }
        if case .cover(let shown)? = self[path: tab].top, shown.id == book.id { return }
        self[path: tab].replace(self[path: tab].routes + [.cover(book)])
    }

    // MARK: The tour (decisions 29 and 30)

    /// The tour, while it plays. It covers the tabs: `TourScreen` for its
    /// first two steps, the reader with its card for the rest.
    private(set) var tour: TourFlow?
    /// A new install's first launch, until the hinge says how the tour starts.
    private(set) var tourWaitsForHinge = false
    /// The tour's Add books: setup's first screen with Skip, until that or
    /// setup's own end.
    private(set) var addsBooksAfterTour = false
    /// A replay's place, so it never touches the book's (`TourReplayPlace`).
    private(set) var tourReplayPlace: TourReplayPlace?
    /// The hinge as last reported, `nil` while it's said nothing.
    @ObservationIgnored private var hingeFold: HingeTransition.Fold?
    @ObservationIgnored private var hingeIsSilent = false

    /// Whether this launch plays the tour: a new install (`TourRecord`), or
    /// one that didn't finish it.
    private func prepareTour() {
        #if DEBUG
        guard !debugLaunchSkipsTour else { return }
        #endif
        let manager = FileManager.default
        let hasEarlierData = servers.hasFile
            || !library.imported.all().isEmpty
            || !library.recents.records().isEmpty
            || !library.onIPhone.books().isEmpty
            || manager.fileExists(atPath: places.store.directory.path)
            || manager.fileExists(atPath: bookmarks.directory.path)
        tourWaitsForHinge = tourRecord.shouldPlay(
            hasEarlierData: hasEarlierData, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
        )
    }

    /// Every report from the hinge (`onHingeChange` fires once on appear): the
    /// first with a hinge says how a new install's tour starts. After that the
    /// tour follows it, even if the change itself was never reported, as when
    /// the iPhone was opened or closed while the app was away.
    func hingeReported(_ fold: HingeTransition.Fold?) {
        guard let fold else { return }
        #if DEBUG
        guard !UserDefaults.standard.bool(forKey: "tourNoFold") else { return }
        #endif
        hingeFold = fold
        if let step = tour?.step {
            if fold == .open, step == .cover {
                tourHingeChanged(.unfold)
            } else if fold == .closed, step != .cover {
                tourHingeChanged(.fold)
            }
        }
        startTourIfHingeKnown()
    }

    /// The hinge hasn't said anything by now: this iPhone has no fold.
    func hingeStayedSilent() {
        hingeIsSilent = true
        startTourIfHingeKnown()
    }

    /// Not while a file is coming in: opened with one, the tour waits to see
    /// whether it arrives (`importBooks`).
    private func startTourIfHingeKnown() {
        guard tourWaitsForHinge, importsRunning == 0 else { return }
        if let hingeFold {
            startTour(fold: hingeFold)
        } else if hingeIsSilent {
            startTour(fold: nil)
        }
    }

    private func startTour(fold: HingeTransition.Fold?) {
        tourWaitsForHinge = false
        tourRecord.set(.playing)
        guard installSampleBook() != nil else {
            // Nothing to teach with (no room for its copy): setup for now,
            // and the next launch tries again.
            tourRecord.set(.new)
            return
        }
        begin(TourFlow(fold: fold))
    }

    /// Show the tour, in Settings: from the beginning, and back to Settings.
    func showTour() {
        guard tour == nil, reader.reading == nil else { return }
        let place = TourReplayPlace()
        SampleBook.startAtFirstChapter(in: place.positions)
        tourReplayPlace = place
        begin(TourFlow(fold: hingeFold, isReplay: true))
    }

    private func begin(_ flow: TourFlow) {
        tour = flow
        if flow.isInBook { openTourBook() }
    }

    /// The sample book for the tour. A new install's is the one on the shelf,
    /// through the library, so it joins Continue reading. A replay's is the
    /// app's own copy with nowhere to save its place: nothing goes back on the
    /// shelf if it was removed, and no place moves if it wasn't.
    private func openTourBook(_ opening: ReaderPresenter.Opening = .tapped) {
        if tour?.isReplay == true {
            guard let url = SampleBook.bundledFile, let file = SampleBook.book.primaryFile else { return finishTour() }
            reader.open(copy: OpenedBook(book: SampleBook.book, source: .files, file: file, url: url), opening)
        } else if let sample = installSampleBook() {
            reader.open(sample, opening)
        } else {
            finishTour()
        }
    }

    /// One of the reader's events, or a card's Start or Done.
    func tourEvent(_ event: TourFlow.Event) {
        tour?.handle(event)
    }

    /// Mid-tour a fold closes the book, as always, and the step waits on the
    /// cover; unfolding on the cover opens the book at that step.
    ///
    /// Either way a cover opening or closing the book goes, as outside the
    /// tour (`hingeChanged`): this also hears a change made while the app was
    /// away (`hingeReported`).
    private func tourHingeChanged(_ transition: HingeTransition) {
        if transition != .none { reader.coverMotion = nil }
        switch transition {
        case .fold:
            reader.close { tour?.handle(.folded) }
        case .unfold:
            guard tour?.step == .cover else { return }
            tour?.handle(.unfolded)
            openTourBook(.unfolded)
        case .none:
            break
        }
    }

    /// Continue without closing: the cover at `coverFrame` (in the window)
    /// opens the book as a book's screen does (decision 28). No left page to
    /// start from, and the reader fades in.
    func tourContinueWithoutClosing(coverFrame: CGRect?) {
        guard tour?.step == .closeYourIPhone else { return }
        // Taken before the step changes the screen.
        let motion = coverFrame.flatMap(reader.sampleCoverMotion(from:))
        tour?.handle(.continueWithoutClosing)
        openTourBook(motion.map { .motion($0) } ?? .tapped)
    }

    /// Skip, on any tour screen, or Not now on the last card: Home with the
    /// sample book under Continue reading; replayed, back to Settings.
    func skipTour() {
        finishTour()
    }

    /// Add books on the last card: the reader closes for Add your books, whose
    /// steps end on Home as they always do. A server is already there on a
    /// replay, and this adds another (decision 36).
    func tourAddBooks() {
        let hasServer = library.server != nil
        finishTour()
        if hasServer {
            push(.setup(.choose))
        } else {
            setupImportFailures = []
            addsBooksAfterTour = true
        }
    }

    /// Skip on Add your books: wherever the tour would have landed.
    func skipAddingBooks() {
        addsBooksAfterTour = false
        setupImportFailures = []
        setup.reset()
        self[path: .setup].replace([])
    }

    private func finishTour() {
        guard let finished = tour else { return }
        reader.coverMotion = nil
        reader.close { tour = nil }
        tourReplayPlace?.clear()
        tourReplayPlace = nil
        guard !finished.isReplay else { return }
        tourRecord.set(.played)
        if let sample = installSampleBook() { library.bookOpened(sample) }
        tab = .home
    }

    #if DEBUG
    /// A launch argument setting up a state to look at means someone's
    /// checking something else, on what may be a fresh install.
    private var debugLaunchSkipsTour: Bool {
        let defaults = UserDefaults.standard
        // The test host isn't a new install, whatever its simulator says. Tests
        // of the tour pass a record of their own.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil, tourRecord.defaults === defaults { return true }
        return ["connectBookOrbit", "connectOPDS", "sampleLibrary", "shellOpen", "shellReading", "shellTab", "shellConnection",
                "shellCoverStrip", "searchQuery", "forgetServer", "setupCatalog"]
            .contains { defaults.object(forKey: $0) != nil }
    }

    /// The debug remote's reader commands: scripts check something else, on
    /// what may be a fresh install.
    func debugEndTour() {
        guard tour != nil || tourWaitsForHinge else { return }
        tourWaitsForHinge = false
        tourRecord.set(.played)
        reader.coverMotion = nil
        reader.close { tour = nil }
        tourReplayPlace?.clear()
        tourReplayPlace = nil
    }

    /// For the remote: where the tour is.
    var debugTourState: String {
        guard let tour else { return tourWaitsForHinge ? "waiting for the hinge" : "none, record \(tourRecord.state?.rawValue ?? "nil")" }
        return "\(tour.step) resumes \(String(describing: tour.resumes)) replay \(tour.isReplay) reading \(reader.reading != nil)"
    }
    #endif

    #if DEBUG
    /// Launch arguments that set up a state to look at:
    /// `-connectBookOrbit 1` (the local server),
    /// `-connectOPDS calibreWeb|cops|komga|komga2|kavita` (`dev/opds/`),
    /// `-sampleLibrary 1|empty|failing`
    /// (made-up books; `empty` has nothing in progress, `failing` sends no
    /// lists), `-shellTab library`,
    /// `-shellConnection unreachable|signedOut`,
    /// `-shellCoverStrip failed|offline|downloading|protected`,
    /// `-shellOpen collection|deep|cover|collections|authors` (sample books,
    /// and the lists of collections and authors),
    /// `-shellOpen settings|server|storage|licences` (Settings, or one of
    /// its pages),
    /// `-shellReading 1` (the first book in Continue reading, once connected)
    /// `-searchQuery austen` (typed into Search, once connected),
    /// `-forgetServer 1` (no server), `-setupCatalog <address>`
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
        case "protected": coverStrip = .protected
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
            // Both, for two servers at once. The first is the Library's.
            if connectsBookOrbit { await library.connectLocalBookOrbit() }
            if let opds {
                await library.connectLocalOPDS(opds)
                if connectsBookOrbit { library.choose(LibraryModel.localBookOrbitID) }
            }
            if !connectsBookOrbit, opds == nil, let sample, sample != "0" {
                await library.connectSampleLibrary(nothingInProgress: sample == "empty", listsFail: sample == "failing")
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
            case "collections", "authors":
                let title = opens == "authors" ? "Authors" : "Collections"
                let list = LibraryEntry(kind: .feed, title: title, link: LibraryLink(rawValue: opens ?? ""))
                self[path: .library].replace([.feed(list, from: SampleLibrarySource.id)])
            case "deep": self[path: .library].replace([classics, .cover(book)])
            case "cover": self[path: .library].replace([.cover(book)])
            case "settings": self[path: tab].replace([.settings])
            case "server":
                if let id = library.server?.id { self[path: tab].replace([.settings, .settingsPage(.server(id))]) }
            case "storage": self[path: tab].replace([.settings, .settingsPage(.storage)])
            case "licences": self[path: tab].replace([.settings, .settingsPage(.licences)])
            default: break
            }
            if reads, let first = library.continueReading.first {
                reader.open(first)
            }
            if let query { search.query = query }
        }
    }
    #endif
}

#if DEBUG
/// `-syncPullDelay` and `-syncFailsPushes`: a slow server, or one that
/// can't be reached to push. The debug remote's `offline` drops pushes
/// from then on, and its `connectionReturned` stands in for the connection
/// coming back.
nonisolated struct DebugProgressSync: ProgressSync {
    nonisolated(unsafe) static var offline = false
    let wrapping: any ProgressSync
    let pullDelay: Duration
    let failsPushes: Bool

    func pull() async throws -> SyncedPosition? {
        try await Task.sleep(for: pullDelay)
        return try await wrapping.pull()
    }

    func push(_ position: ReadingPosition) async throws {
        if failsPushes || Self.offline { throw URLError(.notConnectedToInternet) }
        try await wrapping.push(position)
    }
}
#endif
