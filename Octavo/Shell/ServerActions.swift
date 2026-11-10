import Foundation
import OctavoKit

/// What can be done to a saved server: keep one setup added, sign in again,
/// sign out, choose, rename and remove it (decisions 24 and 36). Each
/// changes the saved list, the Keychain and the library together; the shell
/// moves the screens (`docs/notes/settings.md`, `docs/notes/ui-audit.md`,
/// item 4). Changes here need the network-trust security review (CLAUDE.md).
final class ServerActions {
    private let library: LibraryModel
    private let servers: ServerStore
    private let removedServers: RemovedServerStore
    private let bookmarks: BookmarkStore
    private let places: BookPlaces
    private let opener: BookOpener
    private let reader: ReaderPresenter
    private let koreader: KOReaderConnection

    init(
        library: LibraryModel, servers: ServerStore, removedServers: RemovedServerStore, bookmarks: BookmarkStore,
        places: BookPlaces, opener: BookOpener, reader: ReaderPresenter, koreader: KOReaderConnection
    ) {
        self.library = library
        self.servers = servers
        self.removedServers = removedServers
        self.bookmarks = bookmarks
        self.places = places
        self.opener = opener
        self.reader = reader
        self.koreader = koreader
    }

    /// Setup finished: the server, under a name of its own, saved, and once
    /// it's saved its kept books back if it was removed before. `nil` if it
    /// can't be made.
    func keep(_ added: SavedServer) -> LibraryServer? {
        var added = added
        let list = servers.load()
        added.name = list.uniqueName(added.name)
        guard let server = added.libraryServer() else { return nil }
        do {
            try servers.add(added)
            // Only once it's saved: next launch it would be gone, and them
            // with it.
            takeBackBooks(of: server)
        } catch {
            // Still usable now; setup asks again next launch.
        }
        return server
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

    /// The menu in the Library's title. Remembered (decision 36).
    func choose(_ id: LibrarySourceID) {
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
    func remove(_ id: LibrarySourceID, removingBooks: Bool) async {
        guard let server = library.server(id) else { return }
        await Self.endSignIn(on: server)
        try? ServerCredentials.removeAll(serverID: id.rawValue)
        // Nothing still downloading lands, or opens, afterwards.
        opener.cancelAll(in: id)
        reader.forgetRequests(in: id)
        let downloads = opener.downloads(on: id, listedIn: library)
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
        SavedSorts.forget(id)
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

    // MARK: KOReader sync

    /// Sign in to KOReader sync, from Settings or a catalog's setup: the
    /// account has to sign in (`users/auth`). Then its address and key go to
    /// the Keychain under `id`, where the trust step kept any certificate,
    /// and then the list keeps the ID, so a crash between the two leaves the
    /// launch sweep to delete the key. Nothing is kept if any of it fails.
    func signInToKOReader(_ account: KOSyncAccount, id: String) async throws {
        try await KOReaderAccount.client(id: id, account: account).authorize()
        let store = KeychainKOSyncAccountStore(accountID: id)
        try store.save(account)
        // Only once the new one is kept: a failed save leaves the old.
        if let old = koreader.account, old.id != id { signOutOfKOReader() }
        do {
            try servers.setKOReader(SavedKOReaderAccount(id: id))
        } catch {
            try? store.save(nil)
            throw error
        }
        koreader.connect(KOReaderAccount(id: id, account: account, positions: places.store.directory))
    }

    /// KOReader sync's Sign out: every catalog and Files stop syncing, and
    /// each catalog's switch stays as it was. The list forgets the account
    /// first, so if the Keychain can't delete its key now, the next launch
    /// does (`KeychainSweep`). What its server said goes too, and the
    /// places waiting to go to it. The places themselves stay on the iPhone.
    func signOutOfKOReader() {
        guard let account = koreader.account else { return }
        try? servers.setKOReader(nil)
        try? ServerCredentials.removeAll(serverID: account.id)
        try? FileManager.default.removeItem(at: account.places.file)
        // A push or pull already under way stops before it sends the key
        // again, and can't write the file back.
        Task { await account.places.close() }
        koreader.connect(nil)
        let catalogs = library.connections.map(\.server).filter(\.syncsWithKOReader).map(\.id)
        forgetKOReaderPlaces(of: [.files] + catalogs)
    }

    /// A catalog's "Sync with KOReader", on its setup or its server page.
    /// Off, its books keep their places on the iPhone, and the ones waiting
    /// to go are dropped.
    func setKOReaderSync(_ id: LibrarySourceID, _ on: Bool) {
        try? servers.update(id) { $0.koreaderSync = on }
        library.setSyncsWithKOReader(id, on)
        if !on { forgetKOReaderPlaces(of: [id]) }
    }

    private func forgetKOReaderPlaces(of libraries: [LibrarySourceID]) {
        for id in libraries { places.stopSending(to: id) }
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
    func forgetAll() {
        for id in Set(servers.load().servers.map(\.id) + library.connections.map(\.server.id)) {
            try? ServerCredentials.removeAll(serverID: id.rawValue)
        }
        try? servers.save(SavedServers())
        library.disconnect()
    }
    #endif
}
