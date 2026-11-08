import Foundation
import Observation
import OctavoKit
import Testing
@testable import Octavo

/// A backend that answers from memory, counts its calls, and can hold
/// pulls until `release()`.
actor FakeProgressSync: ProgressSync {
    var remote: SyncedPosition?
    var pushError: (any Error)?
    var holdsPulls = false
    private(set) var pulls = 0
    private(set) var pushes: [ReadingPosition] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(remote: SyncedPosition? = nil) {
        self.remote = remote
    }

    func set(remote: SyncedPosition?) { self.remote = remote }
    func set(pushError: (any Error)?) { self.pushError = pushError }
    func hold() { holdsPulls = true }

    func release() {
        holdsPulls = false
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    func pull() async throws -> SyncedPosition? {
        pulls += 1
        let answer = remote
        if holdsPulls { await withCheckedContinuation { waiting.append($0) } }
        return answer
    }

    func push(_ position: ReadingPosition) async throws {
        if let pushError { throw pushError }
        pushes.append(position)
        remote = SyncedPosition(position: position, updatedAt: .now)
    }
}

/// Where a book opens and whether its place synced (step 13).
@MainActor
@Suite(.temporaryFiles)
struct BookPlacesTests {
    static let file = LibraryFile(id: LibraryFileID(rawValue: "3"), format: "epub", isPrimary: true)
    /// The library list says 30%, as BookOrbit's lists do.
    static let book = SourcedBook(
        source: LibrarySourceID(rawValue: "server"),
        book: LibraryBook(id: LibraryBookID(rawValue: "3"), title: "Moby-Dick", files: [file], progress: 0.3)
    )
    static let serverPlace = ReadingPosition(cfi: "epubcfi(/6/8!/4/352)", fraction: 0.6)
    static let iPhonePlace = ReadingPosition(cfi: "epubcfi(/6/6!/4/20/1:0)", fraction: 0.5)
    /// Before any position the store saves (it stamps them with the real time).
    static let longAgo = Date(timeIntervalSince1970: 0)

    let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "places-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    let clock = TestClock()
    var key: String { Self.file.storageKey(in: Self.book.source) }

    func places(_ backend: FakeProgressSync?) -> BookPlaces {
        BookPlaces(store: store, now: { [clock] in clock.now }) { _ in backend }
    }

    // MARK: The place

    // Before a pull: the iPhone's place, else the list's percentage.
    // MARK: Trips (decision 33)

    private func tripFromTheIPhonesPlace() -> ReaderTrip {
        var trip = ReaderTrip(place: Self.iPhonePlace, placePage: 487, placeFraction: 0.5)
        trip.landed(on: ReadingPosition(cfi: "epubcfi(/6/30!/4/2)", fraction: 0.9), fraction: 0.9)
        return trip
    }

    @Test func aTripShowsWhileItsPlaceIsWhereTheBookOpens() throws {
        let places = places(FakeProgressSync())
        try store.save(Self.iPhonePlace, forBook: key)
        store.saveTrip(tripFromTheIPhonesPlace(), forBook: key)
        #expect(places.trip(of: Self.book) == tripFromTheIPhonesPlace())
        // The place line stays your place.
        #expect(places.progress(of: Self.book) == 0.5)
    }

    @Test func noTripNoLine() throws {
        let places = places(FakeProgressSync())
        try store.save(Self.iPhonePlace, forBook: key)
        #expect(places.trip(of: Self.book) == nil)
    }

    /// Another reader moved your place: the line shows the new place.
    @Test func aTripDoesntShowOnceAnotherReaderMovedYourPlace() async throws {
        try store.save(Self.iPhonePlace, forBook: key)
        store.saveTrip(tripFromTheIPhonesPlace(), forBook: key)
        let places = places(FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: .now)))
        #expect(places.trip(of: Self.book) != nil)
        places.refresh(Self.book)
        #expect(await eventually { places.trip(of: Self.book) == nil })
    }

    /// The server has your place in its own spelling: the same place.
    @Test func aTripShowsWithYourPlaceInTheServersSpelling() async throws {
        try store.save(Self.iPhonePlace, forBook: key)
        var trip = tripFromTheIPhonesPlace()
        trip.placeOnServer = Self.serverPlace.cfi
        store.saveTrip(trip, forBook: key)
        let places = places(FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: .now)))
        places.refresh(Self.book)
        #expect(await eventually { places.progress(of: Self.book) == Self.serverPlace.fraction })
        #expect(places.trip(of: Self.book) == trip)
    }

    @Test func beforeAPullThePlaceIsTheIPhonesElseTheLists() throws {
        let places = places(FakeProgressSync())
        #expect(places.progress(of: Self.book) == 0.3)
        try store.save(Self.iPhonePlace, forBook: key)
        #expect(places.progress(of: Self.book) == 0.5)
    }

    // The server moved on (another device read on): its position wins, as it
    // will when the book opens.
    @Test func thePulledServerPositionWins() async throws {
        try store.save(Self.iPhonePlace, forBook: key)
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: clock.now))
        let places = places(backend)

        places.refresh(Self.book)

        #expect(await eventually { places.progress(of: Self.book) == 0.6 })
        #expect(places.opening(of: Self.book) == .remote(Self.serverPlace))
        #expect(places.status(of: Self.book) == .synced(clock.now))
    }

    // A percentage without a position (what the book's screen shows from
    // the list) is where the book opens, not the start.
    @Test func aServerPercentageWithoutAPositionIsWhereTheBookOpens() async {
        let places = places(FakeProgressSync(remote: SyncedPosition(position: ReadingPosition(fraction: 0.42))))
        places.refresh(Self.book)
        #expect(await eventually { places.progress(of: Self.book) == 0.42 })
        #expect(places.opening(of: Self.book) == .remote(ReadingPosition(fraction: 0.42)))
    }

    // Read offline: the iPhone's newer place stays, says it isn't synced,
    // and goes to the server when the book's screen shows.
    @Test func anUnsentPlaceIsSentWhenItsScreenShows() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        let places = places(backend)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)
        #expect(places.status(of: Self.book) == .notSynced)

        places.refresh(Self.book)

        #expect(await eventuallyAwaiting { await backend.pushes == [Self.iPhonePlace] })
        #expect(await eventually { places.status(of: Self.book) == .synced(clock.now) })
        #expect(store.progress(forBook: key)?.needsPush == false)
        #expect(store.progress(forBook: key)?.syncedAt == clock.now)
        #expect(places.progress(of: Self.book) == 0.5)
    }

    /// Another reader's place this iPhone hasn't seen isn't sent over from
    /// the book's screen: the reader offers it first (KOReader).
    @Test(arguments: [SyncedPosition.Change.first, .moved])
    func anUnsentPlaceWaitsForAKOReaderPlaceItHasntSeen(change: SyncedPosition.Change) async throws {
        let theirs = ReadingPosition(fraction: 0.2, xpointer: "/body/DocFragment[2]/body/p[3].0")
        let backend = FakeProgressSync(remote: SyncedPosition(position: theirs, origin: .elsewhere(change)))
        let places = places(backend)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)

        places.refresh(Self.book)

        #expect(await eventuallyAwaiting { await backend.pulls == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(await backend.pushes.isEmpty)
        #expect(store.progress(forBook: key)?.needsPush == true)
        #expect(places.progress(of: Self.book) == 0.5)
    }

    @Test func butGoesOverOneItHasSeen() async throws {
        let theirs = ReadingPosition(fraction: 0.2, xpointer: "/body/DocFragment[2]/body/p[3].0")
        let backend = FakeProgressSync(remote: SyncedPosition(position: theirs, origin: .elsewhere(.unchanged)))
        let places = places(backend)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)

        places.refresh(Self.book)

        #expect(await eventuallyAwaiting { await backend.pushes == [Self.iPhonePlace] })
    }

    @Test func aRetryThatFailsStaysNotSynced() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        await backend.set(pushError: URLError(.notConnectedToInternet))
        let places = places(backend)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)

        places.refresh(Self.book)

        #expect(await eventuallyAwaiting { await backend.pulls == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(places.status(of: Self.book) == .notSynced)
        #expect(store.progress(forBook: key)?.needsPush == true)
    }

    // Offline: the last sync's time, kept with the position.
    @Test func offlineTheStatusIsTheLastSync() throws {
        let synced = clock.now.addingTimeInterval(-86_400)
        try store.save(Self.iPhonePlace, forBook: key, syncedAt: synced)
        #expect(places(FakeProgressSync()).status(of: Self.book) == .synced(synced))
    }

    // Books that don't sync show no status (Adam: nothing beside the place).
    @Test func aBookThatDoesntSyncHasNoStatus() throws {
        try store.save(Self.iPhonePlace, forBook: key, syncedAt: clock.now)
        let places = places(nil)
        #expect(places.status(of: Self.book) == nil)
        #expect(places.progress(of: Self.book) == 0.5)
        places.refresh(Self.book)
    }

    @Test func aBookNotStartedAnywhereHasNoStatus() async {
        let book = SourcedBook(source: Self.book.source, book: LibraryBook(id: LibraryBookID(rawValue: "3"), title: "Moby-Dick", files: [Self.file]))
        let backend = FakeProgressSync()
        let places = places(backend)
        places.refresh(book)
        #expect(await eventuallyAwaiting { await backend.pulls == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(places.progress(of: book) == nil)
        #expect(places.status(of: book) == nil)
    }

    // The place lines read the saved position again once the reader closes.
    @Test func closingTheReaderRedrawsThePlace() throws {
        let places = places(FakeProgressSync())
        let changed = Flag()
        withObservationTracking { _ = places.progress(of: Self.book) } onChange: { changed.isSet = true }
        try store.save(Self.iPhonePlace, forBook: key)
        places.readerClosed()
        #expect(changed.isSet)
    }

    // MARK: Retrying unsent places (Adam, 2026-11-02: while the app is open)

    // Read offline and closed: the place goes at the next launch, return to
    // the app or reconnection, though its screen never shows. A failure
    // leaves it for the next one, and a place that went is forgotten.
    @Test func anUnsentPlaceGoesWithoutItsScreen() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        let places = places(backend)
        _ = places.readerSync(for: Self.book)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)

        await backend.set(pushError: URLError(.notConnectedToInternet))
        await places.retryUnsent()
        #expect(await backend.pushes.isEmpty)
        #expect(places.status(of: Self.book) == .notSynced)

        await backend.set(pushError: nil)
        await places.retryUnsent()
        #expect(await backend.pushes == [Self.iPhonePlace])
        #expect(places.status(of: Self.book) == .synced(clock.now))

        let pulls = await backend.pulls
        await places.retryUnsent()
        #expect(await backend.pulls == pulls)
    }

    // A wrong password keeps the places waiting for signing in again; a
    // server without the book stops being asked until it opens.
    @Test(arguments: [(KOSyncError.unauthorized, 1), (KOSyncError.unknownDocument, 0)])
    func aRetryTheServerRefuses(error: KOSyncError, stillPending: Int) async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        await backend.set(pushError: error)
        let places = places(backend)
        _ = places.readerSync(for: Self.book)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)
        places.readerClosed()

        await places.retryUnsent()

        #expect(places.pendingCount(on: Self.book.source) == stillPending)
    }

    // Settings' "N books pending.", and Remove server forgetting them.
    @Test func countsAndForgetsAServersPendingPlaces() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        let places = places(backend)
        #expect(places.pendingCount(on: Self.book.source) == 0)
        _ = places.readerSync(for: Self.book)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)
        places.readerClosed()
        #expect(places.pendingCount(on: Self.book.source) == 1)
        #expect(places.pendingCount(on: LibrarySourceID(rawValue: "another")) == 0)

        places.forget(server: Self.book.source)
        #expect(places.pendingCount(on: Self.book.source) == 0)
        await places.retryUnsent()
        #expect(await backend.pushes.isEmpty, "a removed server's places go nowhere")
        #expect(store.progress(forBook: key)?.position == Self.iPhonePlace, "the place itself stays")
    }

    // KOReader's Sign out, or a catalog switched off: a place waiting to go
    // stays the iPhone's own, so the next account doesn't get it.
    @Test func stoppingSyncKeepsAPlaceFromTheNextAccount() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        let places = places(backend)
        _ = places.readerSync(for: Self.book)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)
        places.readerClosed()

        places.stopSending(to: Self.book.source)

        #expect(places.pendingCount(on: Self.book.source) == 0)
        #expect(store.progress(forBook: key)?.position == Self.iPhonePlace)
        #expect(store.progress(forBook: key)?.needsPush == false)
    }

    // The list of unsent places is kept on disk, so a relaunch still sends.
    @Test func aRelaunchStillSendsIt() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        _ = places(backend).readerSync(for: Self.book)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)

        await places(backend).retryUnsent()
        #expect(await backend.pushes == [Self.iPhonePlace])
    }

    // The book in the reader sends its own place (and may be offering the
    // server's instead).
    @Test func theOpenBookIsLeftToItsReader() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace, updatedAt: Self.longAgo))
        let places = places(backend)
        _ = places.readerSync(for: Self.book)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)

        await places.retryUnsent(except: key)
        #expect(await backend.pulls == 0)
        #expect(await backend.pushes.isEmpty)
    }

    // MARK: The reader's pull

    // Unfolding soon after the cover appeared opens at once: no second pull.
    @Test func theReaderReusesTheScreensRecentPull() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace))
        let places = places(backend)
        places.refresh(Self.book)
        #expect(await eventually { places.progress(of: Self.book) == 0.6 })

        let reader = try #require(places.readerSync(for: Self.book))
        #expect(try await reader.pull()?.position == Self.serverPlace)
        #expect(await backend.pulls == 1)

        clock.advance(by: BookPlaces.reuseAge + 1)
        await backend.set(remote: SyncedPosition(position: Self.iPhonePlace))
        #expect(try await reader.pull()?.position == Self.iPhonePlace)
        #expect(await backend.pulls == 2)
    }

    // An open reader coming back to the app asks the server again, however
    // recent the last pull (Adam, 2026-11-02).
    @Test func theReadersCheckNeverReusesAPull() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace))
        let places = places(backend)
        let reader = try #require(places.readerSync(for: Self.book))
        _ = try await reader.pull()

        await backend.set(remote: SyncedPosition(position: Self.iPhonePlace))
        #expect(try await reader.pullLatest()?.position == Self.iPhonePlace)
        #expect(await backend.pulls == 2)
        #expect(places.progress(of: Self.book) == Self.iPhonePlace.fraction)
    }

    @Test func aPullAlreadyRunningIsShared() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace))
        await backend.hold()
        let places = places(backend)
        places.refresh(Self.book)
        #expect(await eventuallyAwaiting { await backend.pulls == 1 })

        let reader = try #require(places.readerSync(for: Self.book))
        async let pulled = reader.pull()
        try await Task.sleep(for: .milliseconds(50))
        await backend.release()

        #expect(try await pulled?.position == Self.serverPlace)
        #expect(await backend.pulls == 1)
    }

    // A pull that started before the reader's push can't put the older
    // position back.
    @Test func aPullFromBeforeAPushDoesntUndoIt() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace))
        await backend.hold()
        let places = places(backend)
        places.refresh(Self.book)
        #expect(await eventuallyAwaiting { await backend.pulls == 1 })

        let reader = try #require(places.readerSync(for: Self.book))
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)
        try await reader.push(Self.iPhonePlace)
        try store.markPushed(Self.iPhonePlace, forBook: key, at: clock.now)
        await backend.release()
        try await Task.sleep(for: .milliseconds(50))

        #expect(places.opening(of: Self.book) == .remote(Self.iPhonePlace))
        #expect(places.status(of: Self.book) == .synced(clock.now))
    }

    // Another server's positions don't carry over, even a pull still running.
    @Test func anotherServerForgetsTheOldOnesPlaces() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace))
        let places = places(backend)
        places.refresh(Self.book)
        #expect(await eventually { places.progress(of: Self.book) == 0.6 })

        await backend.hold()
        places.refresh(Self.book)
        #expect(await eventuallyAwaiting { await backend.pulls == 2 })
        places.reset(Self.book.source)
        await backend.release()
        try await Task.sleep(for: .milliseconds(50))

        #expect(places.progress(of: Self.book) == 0.3)
    }

    // Home's and Search's rows fetch a started book's place, at most once a
    // minute, and leave books not started alone.
    @Test func rowsFetchStartedBooksAtMostOnceAMinute() async throws {
        let backend = FakeProgressSync(remote: SyncedPosition(position: Self.serverPlace))
        let places = places(backend)

        let notStarted = SourcedBook(source: Self.book.source, book: LibraryBook(id: LibraryBookID(rawValue: "3"), title: "Moby-Dick", files: [Self.file]))
        places.refreshRow(notStarted)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await backend.pulls == 0)

        places.refreshRow(Self.book)
        #expect(await eventually { places.progress(of: Self.book) == 0.6 })
        places.refreshRow(Self.book)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await backend.pulls == 1)

        // Coming back to the app fetches again.
        places.refreshRow(Self.book, again: true)
        #expect(await eventuallyAwaiting { await backend.pulls == 2 })

        clock.advance(by: BookPlaces.rowReuseAge + 1)
        places.refreshRow(Self.book)
        #expect(await eventuallyAwaiting { await backend.pulls == 3 })
    }

    // MARK: Which books sync

    @Test func onlyABookOrbitServerSetToSyncSyncs() {
        let client = BookOrbitClient(baseURL: URL(string: "http://localhost:3300")!)
        let id = LibrarySourceID(rawValue: "server")
        var server = LibraryServer(id: id, name: "BookOrbit", source: BookOrbitSource(client: client), syncsProgress: true)
        let book = SourcedBook(source: id, book: Self.book.book)
        // Debug builds wrap it, for the debug remote's `offline`.
        let sync = ShellModel.progressSync(for: book, on: server)
        let bookOrbit = (sync as? DebugProgressSync)?.wrapping ?? sync
        #expect(bookOrbit is BookOrbitProgressSync)
        #expect((bookOrbit as? BookOrbitProgressSync)?.fileID == 3)
        // Another library's book.
        #expect(ShellModel.progressSync(for: SourcedBook(source: .files, book: Self.book.book), on: server) == nil)
        // A book without a file the reader opens.
        #expect(ShellModel.progressSync(for: SourcedBook(source: id, book: LibraryBook(id: LibraryBookID(rawValue: "9"), title: "PDF")), on: server) == nil)

        server.syncsProgress = false
        #expect(ShellModel.progressSync(for: book, on: server) == nil)

        let opds = LibraryServer(id: id, name: "Calibre", source: StubLibrarySource(), syncsProgress: true)
        #expect(ShellModel.progressSync(for: book, on: opds) == nil)
    }

    /// EPUBs from Files, or a catalog switched on for it, on the iPhone, go
    /// to the KOReader account.
    @Test func catalogAndFilesEPUBsSyncWithKOReader() throws {
        let url = URL(string: "https://sync.test")!
        let account = KOReaderAccount(
            id: "koreader-test", address: url, username: "a",
            client: KOSyncClient(baseURL: url, key: KOSyncKey(username: "a", password: "b"), transport: ServerTransport(server: url)),
            places: KOSyncPlaces(file: URL.testDirectory.appending(path: "places-\(UUID().uuidString).json")), deviceID: "test"
        )
        let id = LibrarySourceID(rawValue: "catalog")
        var catalog = LibraryServer(
            id: id, name: "Calibre-Web", source: OPDSSource(catalogURL: URL(string: "http://nas.lan/opds")!, transport: ServerTransport(server: url)),
            syncsWithKOReader: true
        )
        let file = URL.testDirectory.appending(path: "book.epub")
        let book = SourcedBook(source: id, book: Self.book.book)
        func wrapped(_ sync: (any ProgressSync)?) -> (any ProgressSync)? { (sync as? DebugProgressSync)?.wrapping ?? sync }

        #expect(wrapped(ShellModel.koreaderSync(for: book, on: catalog, account: account, file: { file })) is KOSync)
        #expect(wrapped(ShellModel.koreaderSync(for: SourcedBook(source: .files, book: Self.book.book), on: nil, account: account, file: { file })) is KOSync)
        #expect(ShellModel.koreaderSync(for: book, on: catalog, account: account, file: { file })?.wantsXPointers == true)
        // No account, not downloaded, not an EPUB.
        #expect(ShellModel.koreaderSync(for: book, on: catalog, account: nil, file: { file }) == nil)
        #expect(ShellModel.koreaderSync(for: book, on: catalog, account: account, file: { nil }) == nil)
        #expect(ShellModel.koreaderSync(for: book, on: catalog, account: account, file: { URL.testDirectory.appending(path: "book.azw3") }) == nil)
        // The sample book, a BookOrbit book, and a book of another server.
        let sample = SourcedBook(source: .files, book: LibraryBook(id: .sample, title: "Pride and Prejudice"))
        #expect(ShellModel.koreaderSync(for: sample, on: nil, account: account, file: { file }) == nil)
        let bookOrbit = LibraryServer(id: id, name: "BookOrbit", source: BookOrbitSource(client: BookOrbitClient(baseURL: url)), syncsProgress: false)
        #expect(ShellModel.koreaderSync(for: book, on: bookOrbit, account: account, file: { file }) == nil)
        #expect(ShellModel.koreaderSync(for: SourcedBook(source: LibrarySourceID(rawValue: "other"), book: Self.book.book), on: catalog, account: account, file: { file }) == nil)
        // A catalog not switched on for it; Files books need only the account.
        catalog.syncsWithKOReader = false
        #expect(ShellModel.koreaderSync(for: book, on: catalog, account: account, file: { file }) == nil)
    }

    /// A KOReader server answers the same for a book nobody else has, so a
    /// pull that found nothing doesn't make the place "Synced".
    @Test func anEmptyPullIsntSynced() async throws {
        let backend = FakeProgressSync(remote: nil)
        let places = places(backend)
        try store.save(Self.iPhonePlace, forBook: key)

        places.refresh(Self.book)

        #expect(await eventuallyAwaiting { await backend.pulls == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(places.status(of: Self.book) == nil)
    }

    @Test func norIsOneBesideAKOReaderPlaceItHasntSeen() async throws {
        let theirs = ReadingPosition(fraction: 0.2, xpointer: "/body/DocFragment[2]/body/p[3].0")
        let backend = FakeProgressSync(remote: SyncedPosition(position: theirs, origin: .elsewhere(.first)))
        let places = places(backend)
        try store.save(Self.iPhonePlace, forBook: key)

        places.refresh(Self.book)

        #expect(await eventuallyAwaiting { await backend.pulls == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(places.status(of: Self.book) == nil)
        await backend.set(remote: SyncedPosition(position: theirs, origin: .elsewhere(.unchanged)))
        places.refresh(Self.book)
        #expect(await eventually { places.status(of: Self.book) == .synced(clock.now) })
    }

    /// The iPhone's place having gone earlier doesn't make it Synced.
    @Test func norAfterAnEarlierPush() async throws {
        let theirs = ReadingPosition(fraction: 0.2, xpointer: "/body/DocFragment[2]/body/p[3].0")
        let backend = FakeProgressSync(remote: SyncedPosition(position: theirs, origin: .elsewhere(.moved)))
        let places = places(backend)
        try store.save(Self.iPhonePlace, forBook: key, needsPush: true)
        try store.markPushed(Self.iPhonePlace, forBook: key, at: clock.now)

        places.refresh(Self.book)

        #expect(await eventuallyAwaiting { await backend.pulls == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(places.opening(of: Self.book) == .local(Self.iPhonePlace))
        #expect(places.status(of: Self.book) == nil)
    }

    // MARK: The sync line

    @Test(arguments: [
        (30, "Synced just now"),
        (5 * 60, "Synced 5 minutes ago"),
        (3 * 3600, "Synced 3 hours ago"),
        (18 * 3600, "Synced yesterday"),
        (6 * 86_400, "Synced Oct 27"),
    ] as [(TimeInterval, String)])
    func syncLine(ago: TimeInterval, expected: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_793_620_800)  // 2 Nov 2026, 12:00 UTC
        let text = BookPlaces.Status.synced(now.addingTimeInterval(-ago)).text(now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(text == expected)
    }

    @Test func notSyncedLine() {
        #expect(BookPlaces.Status.notSynced.text() == "Not synced yet, will retry")
    }
}

/// `eventually` for a condition that waits on an actor.
@MainActor
func eventuallyAwaiting(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while await !condition() {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_793_620_800)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

final class Flag: @unchecked Sendable {
    var isSet = false
}
