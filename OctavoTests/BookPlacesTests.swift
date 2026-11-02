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
        directory: URL.temporaryDirectory.appending(path: "places-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    let clock = TestClock()
    var key: String { Self.file.storageKey }

    func places(_ backend: FakeProgressSync?) -> BookPlaces {
        BookPlaces(store: store, now: { [clock] in clock.now }) { _ in backend }
    }

    // MARK: The place

    // Before a pull: the iPhone's place, else the list's percentage.
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
        places.reset()
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
        var server = LibraryServer(id: id, name: "BookOrbit", detail: "", source: BookOrbitSource(client: client), syncsProgress: true)
        let book = SourcedBook(source: id, book: Self.book.book)
        #expect(ShellModel.progressSync(for: book, on: server) is BookOrbitProgressSync)
        #expect((ShellModel.progressSync(for: book, on: server) as? BookOrbitProgressSync)?.fileID == 3)
        // Another library's book.
        #expect(ShellModel.progressSync(for: SourcedBook(source: .files, book: Self.book.book), on: server) == nil)
        // A book without a file the reader opens.
        #expect(ShellModel.progressSync(for: SourcedBook(source: id, book: LibraryBook(id: LibraryBookID(rawValue: "9"), title: "PDF")), on: server) == nil)

        server.syncsProgress = false
        #expect(ShellModel.progressSync(for: book, on: server) == nil)

        let opds = LibraryServer(id: id, name: "Calibre", detail: "", source: StubLibrarySource(), syncsProgress: true)
        #expect(ShellModel.progressSync(for: book, on: opds) == nil)
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
