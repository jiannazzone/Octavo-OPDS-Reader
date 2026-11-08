import Foundation
import Observation
import OctavoKit

/// Where each book opens, as its screen, Home, Search and the reader all see
/// it, and whether that place has reached the server (step 13).
///
/// - A book's screen pulls the server's position when it appears
///   (`refresh`), and so do Home's and Search's rows for books with a place
///   (`refreshRow`). The reader reuses a recent pull (`SharedProgressSync`),
///   so unfolding on the cover opens the book at once.
/// - Every place line shows where the book opens: `OpeningPosition.choose`
///   with the iPhone's record and the server's position, the rule the
///   reader opens with. Until a pull lands (or if it fails) the server's
///   position is the library list's percentage, which the reader also falls
///   back to.
/// - A position the reader couldn't push goes again when its screen shows,
///   and with every other unsent place at launch, when the app comes back
///   and when the connection does (`retryUnsent`, Adam 2026-11-02).
///
/// Keyed by the book's `storageKey`, like `ReadingPositionStore`.
@Observable
final class BookPlaces {
    /// The server's position for one book, as last pulled or pushed.
    nonisolated struct Remote: Equatable {
        /// `nil`: the server has none.
        var position: SyncedPosition?
        /// When the iPhone learnt it.
        var at: Date
    }

    /// The sync line beside a place (decision 22).
    nonisolated enum Status: Equatable {
        case synced(Date)
        /// The iPhone's place is newer than the server's and not sent yet.
        case notSynced
    }

    /// A pull this recent is used instead of pulling again: unfolding soon
    /// after the cover appeared opens at once.
    nonisolated static let reuseAge: TimeInterval = 5 * 60
    /// A pull this recent is used for a row on Home or in Search, so going
    /// back and forth between tabs doesn't fetch again.
    nonisolated static let rowReuseAge: TimeInterval = 60

    private var remotes: [String: Remote] = [:]
    /// Changes when a saved position changes on disk, which isn't observed.
    private var revision = 0
    @ObservationIgnored private var pulls: [String: Task<SyncedPosition?, any Error>] = [:]
    /// Moves with each push, so a pull that started before it can't put an
    /// older position back.
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored let store: ReadingPositionStore
    /// Books whose place may still need sending (`UnsentPlaces`).
    @ObservationIgnored private var unsent: [String: SourcedBook]
    @ObservationIgnored private let unsentFile: UnsentPlaces
    @ObservationIgnored private var isRetrying = false
    @ObservationIgnored private let backend: (SourcedBook) -> (any ProgressSync)?
    @ObservationIgnored private let now: () -> Date

    /// `backend`: where a book's place syncs, if it does.
    init(
        store: ReadingPositionStore = ReadingPositionStore(),
        now: @escaping () -> Date = Date.init,
        backend: @escaping (SourcedBook) -> (any ProgressSync)?
    ) {
        self.store = store
        self.now = now
        self.backend = backend
        unsentFile = UnsentPlaces(directory: store.directory)
        unsent = unsentFile.load()
    }

    // MARK: What screens show

    /// Where `book` opens.
    func opening(of book: SourcedBook) -> OpeningPosition {
        _ = revision
        let listed = Self.listed(book.book)
        guard let key = book.storageKey else { return OpeningPosition.choose(local: nil, remote: listed) }
        let remote: SyncedPosition? = remotes[key].map(\.position) ?? listed
        return OpeningPosition.choose(local: store.progress(forBook: key), remote: remote)
    }

    /// The place line's progress, 0...1: where `book` opens. `nil` before
    /// it's started.
    func progress(of book: SourcedBook) -> Double? {
        opening(of: book).position?.fraction
    }

    /// The trip `book` reopens on (decision 33), while its place is still
    /// where the rule opens. Another reader moving it ends the trip when the
    /// book opens; here the place line just shows the new place.
    func trip(of book: SourcedBook) -> ReaderTrip? {
        _ = revision
        guard let key = book.storageKey, let trip = store.trip(forBook: key),
              trip.isPlace(opening(of: book).position)
        else { return nil }
        return trip
    }

    /// The sync line, for a book whose place syncs and has a place.
    /// "Synced" only when a push landed or the server's place came back and
    /// agrees: not after a pull that found nothing (a KOReader server can't
    /// say whether anyone else has the book), and not while another
    /// reader's place this iPhone hasn't seen is there.
    func status(of book: SourcedBook) -> Status? {
        _ = revision
        guard backend(book) != nil, let key = book.storageKey else { return nil }
        let opening = opening(of: book)
        guard opening != .start else { return nil }
        let local = store.progress(forBook: key)
        if let local, local.needsPush, opening == .local(local.position) { return .notSynced }
        let remote = remotes[key]
        if let position = remote?.position, case .elsewhere(let change) = position.origin, change != .unchanged,
           opening != .remote(position.position) { return nil }
        let agreed = remote.flatMap { $0.position == nil ? nil : $0.at }
        return [local?.syncedAt, agreed].compactMap(\.self).max().map(Status.synced)
    }

    /// Settings' "N books pending.": the books on `server` whose place the
    /// iPhone hasn't sent yet.
    func pendingCount(on server: LibrarySourceID) -> Int {
        _ = revision
        return unsent.filter { key, book in book.source == server && store.progress(forBook: key)?.needsPush == true }.count
    }

    /// The server's place as the library list gives it: a percentage
    /// without a position.
    static func listed(_ book: LibraryBook) -> SyncedPosition? {
        guard let progress = book.progress, progress > 0 else { return nil }
        return SyncedPosition(position: ReadingPosition(fraction: progress))
    }

    // MARK: Syncing

    /// The book's screen appeared, or the app came back to it: pull the
    /// server's position (unless one younger than `age` is known), then send
    /// the iPhone's if it's newer and unsent.
    func refresh(_ book: SourcedBook, reusingWithin age: TimeInterval = 0) {
        guard let backend = backend(book), let key = book.storageKey else { return }
        Task { await sync(key, with: backend, reusingWithin: age) }
    }

    /// Sends every place that didn't reach the server, as each book's
    /// screen would: pulled first, sent if it wins. At launch, when the app
    /// comes back and when the connection does (Adam, 2026-11-02: while the
    /// app is open, not in the background). `open` is the book in the
    /// reader, whose own pusher sends its place.
    func retryUnsent(except open: String? = nil) async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        forgetSent()
        for (key, book) in unsent where key != open {
            guard let backend = backend(book) else { continue }
            await sync(key, with: backend, reusingWithin: 0)
        }
        forgetSent()
    }

    private func sync(_ key: String, with backend: any ProgressSync, reusingWithin age: TimeInterval) async {
        let remote: SyncedPosition?
        do {
            remote = try await pull(key, from: backend, reusingWithin: age)
        } catch {
            return
        }
        await pushUnsent(key, to: backend, over: remote)
    }

    /// Drops the books whose place has gone (or isn't kept any more).
    private func forgetSent() {
        let sent = unsent.keys.filter { store.progress(forBook: $0)?.needsPush != true }
        guard !sent.isEmpty else { return }
        for key in sent { unsent[key] = nil }
        unsentFile.save(unsent)
    }

    /// A row on Home or in Search shows `book`: `refresh`, for a book with a
    /// place to show (one not started anywhere has nothing to fetch), and
    /// reusing a pull from the last minute unless `again`.
    func refreshRow(_ book: SourcedBook, again: Bool = false) {
        guard progress(of: book) != nil else { return }
        refresh(book, reusingWithin: again ? 0 : Self.rowReuseAge)
    }

    /// The reader's sync for `book`, through here: it reuses a recent pull
    /// and reports its pushes.
    func readerSync(for book: SourcedBook) -> (any ProgressSync)? {
        guard let backend = backend(book), let key = book.storageKey else { return nil }
        // Reading may leave a place unsent; remember where it goes.
        if unsent[key] != book {
            unsent[key] = book
            unsentFile.save(unsent)
        }
        return SharedProgressSync(key: key, backend: backend, places: self)
    }

    /// The server's position: from a pull younger than `age`, else from the
    /// pull already running, else a new one. A pull gives up after
    /// `ReaderModel.pullTimeout`, so nothing waiting on it waits longer.
    func pull(_ key: String, from backend: any ProgressSync, reusingWithin age: TimeInterval) async throws -> SyncedPosition? {
        if let remote = remotes[key], now().timeIntervalSince(remote.at) < age { return remote.position }
        if let running = pulls[key] { return try await running.value }
        let generation = generations[key, default: 0]
        let task = Task { try await ReaderModel.withTimeout(ReaderModel.pullTimeout) { try await backend.pull() } }
        pulls[key] = task
        defer { if pulls[key] == task { pulls[key] = nil } }
        let position = try await task.value
        if generations[key, default: 0] == generation {
            remotes[key] = Remote(position: position, at: now())
        }
        return position
    }

    /// A push reached the server, which now holds `position`.
    func pushed(_ position: ReadingPosition, key: String) {
        let date = now()
        generations[key, default: 0] += 1
        remotes[key] = Remote(position: SyncedPosition(position: position, updatedAt: date), at: date)
        revision += 1
    }

    /// The reader closed, having saved (and maybe pushed) its position.
    func readerClosed() {
        revision += 1
    }

    /// Remove server: its books' places no longer go anywhere. The places
    /// themselves stay on the iPhone, so a book opens where it was if the
    /// server is added again.
    func forget(server: LibrarySourceID) {
        let gone = unsent.filter { $0.value.source == server }.keys
        guard !gone.isEmpty else { return }
        for key in gone { unsent[key] = nil }
        unsentFile.save(unsent)
        revision += 1
    }

    /// KOReader sync stopped for `library` (Sign out, or its switch off):
    /// the places waiting to go stay this iPhone's own, so the next account
    /// doesn't get them, as Sign in again keeps one account's places from
    /// another (decision 36). What the account said no longer shows.
    func stopSending(to library: LibrarySourceID) {
        for (key, book) in unsent where book.source == library {
            guard var progress = store.progress(forBook: key), progress.needsPush else { continue }
            progress.needsPush = false
            try? store.save(progress, forBook: key)
        }
        forget(server: library)
        reset(library)
    }

    /// `library` went: what it said no longer applies.
    func reset(_ library: LibrarySourceID) {
        let prefix = StoredBookKeys.prefix(of: library)
        // Pulls still running land in the old generation.
        for key in Set(generations.keys).union(pulls.keys) where key.hasPrefix(prefix) { generations[key, default: 0] += 1 }
        remotes = remotes.filter { !$0.key.hasPrefix(prefix) }
        pulls = pulls.filter { !$0.key.hasPrefix(prefix) }
        revision += 1
    }

    /// Sends the iPhone's position if it's unsent and wins over `remote`,
    /// as it would when the book opens. Not over another reader's place
    /// this iPhone hasn't seen (`OpeningPosition.mayPush`): the reader offers
    /// that first. A failure leaves it for next time.
    private func pushUnsent(_ key: String, to backend: any ProgressSync, over remote: SyncedPosition?) async {
        guard let local = store.progress(forBook: key), OpeningPosition.mayPush(local, over: remote) else { return }
        do {
            try await backend.push(local.position)
        } catch {
            // A server that won't take this book (it doesn't have the file)
            // stops the retries. It goes again when the book opens. A wrong
            // password stays for next time: signing in again fixes them all.
            if let error = error as? KOSyncError, error.isAboutTheBook {
                unsent[key] = nil
                unsentFile.save(unsent)
            }
            return
        }
        try? store.markPushed(local.position, forBook: key, at: now())
        pushed(local.position, key: key)
    }
}

/// One book's `ProgressSync` for the reader: pulls through `BookPlaces`, so
/// a pull from the book's screen moments ago is used at once, and tells it
/// about pushes.
nonisolated struct SharedProgressSync: ProgressSync {
    let key: String
    let backend: any ProgressSync
    let places: BookPlaces

    func pull() async throws -> SyncedPosition? {
        try await places.pull(key, from: backend, reusingWithin: BookPlaces.reuseAge)
    }

    func pullLatest() async throws -> SyncedPosition? {
        try await places.pull(key, from: backend, reusingWithin: 0)
    }

    var wantsXPointers: Bool { backend.wantsXPointers }

    func adopted(_ remote: SyncedPosition) async {
        await backend.adopted(remote)
    }

    func push(_ position: ReadingPosition) async throws {
        try await backend.push(position)
        await places.pushed(position, key: key)
    }
}

extension BookPlaces.Status {
    /// "Synced just now", "Synced 5 minutes ago", "Synced yesterday",
    /// "Synced 28 Oct", or "Not synced yet, will retry".
    func text(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch self {
        case .notSynced:
            return "Not synced yet, will retry"
        case .synced(let date):
            if now.timeIntervalSince(date) < 60 { return "Synced just now" }
            if calendar.isDate(date, inSameDayAs: now) {
                let relative = RelativeDateTimeFormatter()
                relative.locale = locale
                relative.calendar = calendar
                relative.unitsStyle = .full
                relative.dateTimeStyle = .numeric
                return "Synced " + relative.localizedString(for: min(date, now), relativeTo: now)
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
                return "Synced yesterday"
            }
            var style = Date.FormatStyle(locale: locale, calendar: calendar).day().month(.abbreviated)
            style.timeZone = calendar.timeZone
            return "Synced " + date.formatted(style)
        }
    }
}
