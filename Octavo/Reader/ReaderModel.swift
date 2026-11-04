import Foundation
import OctavoKit
import Observation
import SwiftUI
import UIKit
import WebKit
import os

/// Drives one book in a foliate-js `WebPage`: loads the reader, opens the book
/// at its saved position, and keeps that position up to date as pages turn.
///
/// With a `ProgressSync`, the book opens where `OpeningPosition` says (pulled
/// from the backend before opening, or from `fallback` if the pull fails),
/// and every move the reader makes after that is pushed, debounced. Opening
/// itself pushes nothing: the page we land on starts at or before the
/// backend's position, so pushing it back would creep the position
/// backwards a little on every open.
@Observable
final class ReaderModel {
    enum Phase: Equatable {
        case loading
        case open
        case failed(String)
    }

    let book: ReaderBook
    let page: WebPage

    private(set) var phase: Phase = .loading
    private(set) var title: String?
    private(set) var position: ReadingPosition?
    /// The current chapter, as the book's contents name it. Saved with the
    /// position (`ReadingPositionStore.chapter`) for the cover strip and
    /// Home's place line.
    private(set) var tocLabel: String?
    var chapter: String? { tocLabel }
    private(set) var location: ReaderMessage.Relocation.Location?
    /// The contents with where each entry starts, for naming the chapter at
    /// any point of the progress bar.
    private(set) var toc: [ReaderMessage.TOCEntry] = []
    /// Where the opening position came from (`cfi`, `fraction`, `start`).
    private(set) var restoredFrom: String?
    /// The last script error, for the debug overlay.
    private(set) var lastError: String?
    /// The latest relocation, both CFI shapes included.
    private(set) var relocation: ReaderMessage.Relocation?
    /// Counts relocations, including ones that repeat the same page (a fold
    /// re-lays out the page without moving the position).
    private(set) var relocationCount = 0
    /// Where the page is as the reader shows it. `position` is what's saved.
    var shownFraction: Double { relocation?.shownFraction ?? 0 }

    // Layout, decided from the fold. See `ReaderLayout`.
    /// The hinge's posture and angle, and whether that's book mode.
    private(set) var hinge = ReaderHinge()
    var posture: ReaderPosture { hinge.posture }
    /// The hinge angle in degrees, as last reported.
    var hingeAngle: Double? { hinge.angle }
    /// Half open like a book with two pages (decision 9). Half open sideways,
    /// with one column across the fold, reads like flat.
    var isBookMode: Bool { hinge.isBookMode && layout.columns == 2 }
    /// The reader's geometry, with the page's own size once known and the
    /// safe area the text stays out of.
    private(set) var geometry: ReaderGeometry?
    private(set) var layout: ReaderLayout = .automatic
    /// The margins setting (decision 8).
    var margins = ReaderMargins.standard {
        didSet { if margins != oldValue { relayout() } }
    }
    /// Pre-paginated: pages drawn by the book, with no text to give margins.
    private(set) var isFixedLayout = false
    /// Narrow margins reach the page under the side column, which only suits
    /// margins that aren't drawn.
    private var layoutMargins: ReaderMargins { isFixedLayout ? .standard : margins }
    /// The controls cover the page, so a tap anywhere hides them.
    var coversPage = false {
        didSet { if coversPage != oldValue { sendTapMode() } }
    }
    /// The Text and theme choices, as the bridge applies them (decision 13).
    var appearance = ReaderAppearance().script(darkMode: false) {
        didSet { if appearance != oldValue { sendAppearance() } }
    }
    /// Page Turn (decision 27); Reduce Motion turns Automatic into a fade.
    var pageTurn = ReaderPageTurn.standard {
        didSet { if pageTurn != oldValue { sendTurnMode() } }
    }
    var reduceMotion = false
    /// The turn on screen, if any (`ReaderModel+Turns`).
    var turn: ReaderTurn?
    @ObservationIgnored let snapshots = ReaderPageSnapshots()
    /// A finger's turns, recognised beside the web view.
    @ObservationIgnored let swipes = ReaderSwipeRecognizer()
    @ObservationIgnored var turnRun: ReaderTurnRun?
    @ObservationIgnored var turnCount = 0
    /// Turns asked for while one was still being drawn, played after it.
    @ObservationIgnored var queuedTurns: [ReaderTurnSide] = []
    /// How long the last turn's new page took to draw, in ms, for debugging.
    @ObservationIgnored var lastTurnDrawnAfter: Int?
    @ObservationIgnored private var sentTurnMode: Bool?
    /// The page's size as the page reports it.
    @ObservationIgnored private var viewport: CGSize?
    /// The system's areas (the side column, or a band along the top when
    /// turned sideways), measured outside the reader's own toolbar so
    /// showing the controls never moves the text.
    @ObservationIgnored private var safeArea = ReaderInsets.zero
    @ObservationIgnored private var lastGeometry: ReaderGeometry?
    @ObservationIgnored private var sentTapMode: ReaderTapMode?
    @ObservationIgnored private var sentAppearance: ReaderAppearanceScript?

    /// A tap while the controls cover the page (`coversPage`): `"dismiss"`.
    /// Otherwise taps turn; the column's "…" button brings the controls up.
    @ObservationIgnored var onControlsTap: ((_ zone: String) -> Void)?

    // Folding: one re-layout per fold, under a cross-fade. See `FoldBatch`.
    /// Shown over the page while a fold settles (`ReaderFoldCoverView`).
    private(set) var foldCover: ReaderFoldCover?
    /// The last fold's timings, for the debug overlay.
    private(set) var lastFold: FoldReport?
    @ObservationIgnored private let foldTiming = FoldBatch.Timing()
    @ObservationIgnored private var foldBatch: FoldBatch?
    @ObservationIgnored private var foldTask: Task<Void, Never>?
    @ObservationIgnored private var coverTask: Task<Void, Never>?
    @ObservationIgnored private var coverCount = 0
    /// Snapshots up to this one arrived too late to be shown.
    @ObservationIgnored private var lastClosedCover = 0

    // Sync state, for the debug overlay.
    /// Where the book opened, decided from the local and pulled positions.
    private(set) var openingPosition: OpeningPosition?
    private(set) var syncStatus: String?
    private(set) var lastPushedCFI: String?
    /// The server's place, when another reader moved it on while this book
    /// was open (`checkServerPlace`), until it's taken or left.
    private(set) var serverPlace: ReaderServerPlace?

    /// The book's bookmarks (decisions 17–18).
    let bookmarks: ReaderBookmarks
    /// Search in book (decision 19).
    let search = ReaderSearch()

    @ObservationIgnored private let store: ReadingPositionStore
    @ObservationIgnored private let sync: (any ProgressSync)?
    /// The backend's position as the library list gave it (a percentage),
    /// for when there's no pull: the book's screen showed it, so the book
    /// opens there.
    @ObservationIgnored private let fallback: SyncedPosition?
    /// The pull succeeded, so opening at the backend's position means the
    /// iPhone and the backend agree.
    @ObservationIgnored private var pulled = false
    /// The CFI the server holds as far as this reader knows: pulled to open,
    /// pushed since, or seen by the last check. Only another is offered.
    @ObservationIgnored private var serverCFI: String?
    /// Counts pushes that landed, so a check overtaken by one is dropped.
    @ObservationIgnored private var pushCount = 0
    /// `goToServerPlace` is under way: the page it lands on is the server's.
    @ObservationIgnored private var isJumpingToServer = false
    /// This page's place went to the pusher while the server's was offered.
    @ObservationIgnored private var pushedSinceOffer = false
    @ObservationIgnored private var isCatchingUp = false
    /// A chapter button's tap is finding its place (`skipChapter`).
    @ObservationIgnored var isSkippingChapter = false

    // Going back after a jump (decision 33, `ReaderModel+Trip`).
    /// Away from your place. It stays saved as it was until you settle.
    var trip: ReaderTrip? {
        didSet { if trip != oldValue { store.saveTrip(trip, forBook: book.id) } }
    }
    /// The saved trip this book is reopening on.
    @ObservationIgnored private var tripToResume: ReaderTrip?
    /// A saved trip whose place the rule's position may or may not be.
    @ObservationIgnored private var tripToCheck: ReaderTrip?
    /// A jump under way, until it's landed somewhere other than your place.
    @ObservationIgnored var tripToBe: ReaderTrip?
    @ObservationIgnored var jumpsUnderWay = 0
    /// How many relocations there had been when the jump started.
    @ObservationIgnored var jumpStartCount = 0
    /// Back is under way: the page it lands on is your place, already saved.
    @ObservationIgnored var isGoingBack = false
    /// Where the page was at the last turn, to tell which way a turn went.
    @ObservationIgnored var tripFraction = 0.0
    @ObservationIgnored let cfiShape: ReaderMessage.CFIShape
    @ObservationIgnored private var pusher: DebouncedProgressPusher<ContinuousClock>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Positions reported while the book is still being restored are not saved,
    /// so a half-finished open can't overwrite the saved position.
    @ObservationIgnored private var isRestoring = true
    /// The CFI the book opened at. Relocations that repeat it (foliate reports
    /// a page several times as it settles) aren't the reader moving.
    @ObservationIgnored private var openedCFI: String?
    @ObservationIgnored private var hasMoved = false
    /// The layout the page has, or is about to get.
    @ObservationIgnored private var sentLayout: ReaderLayout?
    @ObservationIgnored private let log = Logger(subsystem: "com.ianazzone.ereader", category: "Reader")

    static let pullTimeout = Duration.seconds(5)

    init(
        book: ReaderBook,
        store: ReadingPositionStore = ReadingPositionStore(),
        sync: (any ProgressSync)? = nil,
        fallback: SyncedPosition? = nil,
        bookmarks: ReaderBookmarks? = nil,
        cfiShape: ReaderMessage.CFIShape = .point,
        pushDelay: Duration = .seconds(2)
    ) {
        self.book = book
        self.store = store
        self.sync = sync
        self.fallback = fallback
        self.bookmarks = bookmarks ?? ReaderBookmarks(bookID: book.id)
        self.cfiShape = cfiShape

        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme(ReaderSchemeHandler.scheme)!] = ReaderSchemeHandler(bookFile: book.fileURL)
        let relay = ScriptMessageRelay()
        configuration.userContentController.add(relay, name: ScriptMessageRelay.name)
        page = WebPage(configuration: configuration)
        #if DEBUG
        page.isInspectable = true
        #endif

        relay.onMessage = { [weak self] body in self?.receive(body) }
        swipes.onSwipe = { [weak self] swipe in self?.swiped(swipe) }
        if let sync {
            pusher = DebouncedProgressPusher(delay: pushDelay) { [weak self] position in
                do {
                    try await sync.push(position)
                } catch {
                    await self?.pushFailed(error)
                    throw error
                }
                await self?.didPush(position)
            }
        }
        log.debug("Opening reader for \(book.id, privacy: .public)")
        loadTask = Task { [page, log] in
            do {
                for try await _ in page.load(ReaderSchemeHandler.readerURL) {}
            } catch {
                log.error("Reader page failed to load: \(error)")
            }
        }
    }

    // MARK: Commands

    func next() { call("return await window.octavo.next()") }
    func previous() { call("return await window.octavo.prev()") }
    func goTo(cfi: String) { call("return await window.octavo.goTo(cfi)", arguments: ["cfi": cfi]) }
    /// A CFI or an href from the contents.
    func goTo(target: String) { call("return await window.octavo.goTo(target)", arguments: ["target": target]) }
    func goTo(fraction: Double) { call("return await window.octavo.goToFraction(fraction)", arguments: ["fraction": fraction]) }

    /// The hinge changed. `angle` is in degrees. The system repeats
    /// unchanged values many times a second while the hinge settles; those
    /// change nothing.
    func hingeChanged(_ posture: ReaderPosture, angle: Double?) {
        let old = hinge.posture
        let change = hinge.update(posture: posture, angle: angle)
        if change.contains(.bookMode) { bookModeMayHaveChanged() }
        guard change.contains(.posture) else { return }
        log.debug("posture \(posture.rawValue, privacy: .public)")
        // `.noHinge` is only the first report, before the hinge is known.
        if old != .noHinge, old.isFolded != posture.isFolded { beginFold(folded: posture.isFolded) }
        relayout()
    }

    /// A page really turned: not a swipe that fell back, or a tap at the
    /// book's first or last page (the tour's Turn the page).
    @ObservationIgnored var onPageTurned: (() -> Void)?

    /// Called when book mode starts or ends, so the controls can hide.
    @ObservationIgnored var onBookModeChange: ((Bool) -> Void)?
    @ObservationIgnored private var reportedBookMode = false

    /// Book mode follows the hinge's angle and the layout's two pages,
    /// which change at different moments.
    private func bookModeMayHaveChanged() {
        guard isBookMode != reportedBookMode else { return }
        reportedBookMode = isBookMode
        log.debug("book mode \(self.isBookMode)")
        onBookModeChange?(isBookMode)
    }

    /// A fold is settling (`FoldBatch`).
    var isFolding: Bool { foldBatch != nil }

    /// The reader view's size or the fold's regions changed.
    func geometryChanged(_ geometry: ReaderGeometry) {
        lastGeometry = geometry
        updateGeometry(geometry)
    }

    /// The system's areas changed (`ReaderInsets`, in the page's physical
    /// directions).
    func safeAreaChanged(_ insets: ReaderInsets) {
        guard insets != safeArea else { return }
        safeArea = insets
        if let lastGeometry { updateGeometry(lastGeometry) }
    }

    /// `geometry` with the page's own size, once the page has reported it,
    /// and the safe area.
    private func updateGeometry(_ geometry: ReaderGeometry) {
        var geometry = geometry
        if let viewport { geometry.size = viewport }
        geometry.safeArea = safeArea
        guard geometry != self.geometry else { return }
        self.geometry = geometry
        relayout()
    }

    /// Whether a tap hides the controls instead of turning.
    var tapMode: ReaderTapMode {
        ReaderTapMode(dismisses: coversPage)
    }

    /// While the book is opening, `open` takes it, and `.opened` sends any
    /// change since.
    private func sendAppearance() {
        let appearance = appearance
        guard phase == .open, appearance != sentAppearance else { return }
        sentAppearance = appearance
        call("return await window.octavo.setAppearance(appearance)", arguments: ["appearance": appearance.scriptArguments])
    }

    /// Whether Swift draws the turns; sent when Page Turn changes and once
    /// the book has opened.
    private func sendTurnMode() {
        let animated = pageTurn.isAnimated
        // Off with None, when foliate's paginator takes swipes itself. Its
        // fixed-layout renderer has none, so those stay here.
        swipes.isEnabled = animated || isFixedLayout
        guard phase == .open, animated != sentTurnMode else { return }
        sentTurnMode = animated
        call("return await window.octavo.setTurnMode(mode)", arguments: ["mode": ["animated": animated]])
    }

    /// Sent when `coversPage` changes, and once the book has opened (while
    /// it opens, `.opened` sends it instead). Posture and size don't affect it.
    private func sendTapMode() {
        let mode = tapMode
        guard phase == .open, mode != sentTapMode else { return }
        sentTapMode = mode
        call("return await window.octavo.setTapMode(mode)", arguments: ["mode": mode.scriptArguments])
    }

    /// For checking a layout by hand; the next posture or geometry change
    /// replaces it.
    func override(_ layout: ReaderLayout) {
        apply(layout)
    }

    private func relayout() {
        if foldBatch != nil {
            foldBatch?.input(at: .now)
            scheduleFoldEnd()
            return
        }
        apply(ReaderLayout(posture: posture, geometry: geometry, margins: layoutMargins))
    }

    // MARK: Folding

    /// The timings of one fold in milliseconds from the hinge, for the
    /// debug overlay.
    struct FoldReport: Equatable, Encodable {
        /// When the page resized, if it did.
        var resized: Int?
        /// When the new layout was sent.
        var laidOut: Int?
        /// When the snapshot was ready.
        var snapshot: Int?
        /// Whether the new layout re-rendered the page.
        var rendered: Bool?

        static func milliseconds(since start: ContinuousClock.Instant) -> Int {
            let elapsed = (ContinuousClock.now - start).components
            return Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
        }
    }

    /// The hinge moved between folded and unfolded: hold the page as it is,
    /// cover it with a snapshot, and lay out once the fold's inputs settle.
    private func beginFold(folded: Bool) {
        guard phase == .open else { return }
        // A turn under way ends where it was going, before the page holds.
        let endTurn = finishTurnForFold() ?? ""
        let now = ContinuousClock.now
        if foldBatch != nil {
            foldBatch?.hingeMoved(folded: folded, at: now)
            scheduleFoldEnd()
            return
        }
        foldBatch = FoldBatch(folded: folded, at: now)
        lastFold = FoldReport()
        call(endTurn + "return await window.octavo.hold()")
        captureCover(startedAt: now)
        scheduleFoldEnd()
    }

    /// (Re)starts the wait for the batch's deadline, which each input moves.
    private func scheduleFoldEnd() {
        guard let deadline = foldBatch?.deadline(foldTiming) else { return }
        foldTask?.cancel()
        foldTask = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                return
            }
            await self?.endFold()
        }
    }

    private func captureCover(startedAt: ContinuousClock.Instant) {
        coverCount += 1
        let id = coverCount
        let size = geometry?.size ?? .zero
        coverTask = Task { [page] in
            guard let data = try? await page.exported(as: .image(afterScreenUpdates: false)),
                  let image = UIImage(data: data) else { return }
            // The fold may have been laid out already.
            guard id > self.lastClosedCover else { return }
            self.lastFold?.snapshot = FoldReport.milliseconds(since: startedAt)
            self.foldCover = ReaderFoldCover(id: id, image: image, size: size)
        }
    }

    private func endFold() async {
        guard let startedAt = foldBatch?.startedAt else { return }
        // Nothing can move the deadline from here on.
        foldBatch = nil
        foldTask = nil
        let cover = coverCount
        // The snapshot normally arrived long ago; don't wait long for a slow one.
        if let coverTask {
            _ = try? await Self.withTimeout(.milliseconds(300)) { await coverTask.value }
        }
        lastClosedCover = max(lastClosedCover, cover)
        let layout = ReaderLayout(posture: posture, geometry: geometry, margins: layoutMargins)
        self.layout = layout
        sentLayout = layout
        bookModeMayHaveChanged()
        lastFold?.laidOut = FoldReport.milliseconds(since: startedAt)
        do {
            let rendered = try await page.callJavaScript(
                "return await window.octavo.setLayout(layout)", arguments: ["layout": layout.scriptArguments])
            lastFold?.rendered = rendered as? Bool
        } catch {
            log.error("Fold layout failed: \(error)")
        }
        // Folded back meanwhile: that fold fades the cover.
        guard foldBatch == nil else { return }
        fadeCover()
    }

    private func fadeCover() {
        guard let id = foldCover?.id else { return }
        foldCover?.isFading = true
        Task {
            try? await Task.sleep(for: .seconds(ReaderFoldCover.fadeDuration + 0.05))
            if foldCover?.id == id { foldCover = nil }
        }
    }

    private func apply(_ layout: ReaderLayout) {
        guard layout != self.layout else { return }
        self.layout = layout
        sendLayout()
        bookModeMayHaveChanged()
    }

    /// While the book is opening, `openBook` passes the layout along instead,
    /// and `.opened` catches up with any change made in the meantime.
    private func sendLayout() {
        guard phase == .open, sentLayout != layout else { return }
        sentLayout = layout
        call("return await window.octavo.setLayout(layout)", arguments: ["layout": layout.scriptArguments])
    }

    /// Where the visible text sits against the fold (see `bridge.js`
    /// `layoutReport`), for debugging.
    func layoutReport() async -> [String: Any]? {
        guard phase == .open else { return nil }
        return try? await page.callJavaScript("return await window.octavo.layoutReport()") as? [String: Any]
    }

    /// Whether the visible page contains `cfi`'s start (see `bridge.js`
    /// `locate`), for debugging.
    func locate(_ cfi: String) async -> [String: Any]? {
        guard phase == .open else { return nil }
        return try? await page.callJavaScript("return await window.octavo.locate(cfi)", arguments: ["cfi": cfi]) as? [String: Any]
    }

    /// The visible page's text, for debugging.
    func visibleText(limit: Int = 300) async -> String? {
        guard phase == .open else { return nil }
        return try? await page.callJavaScript("return await window.octavo.visibleText(limit)", arguments: ["limit": limit]) as? String
    }

    /// Pushes any position still waiting for the debounce. Call when the
    /// reader goes away.
    func close() async {
        await pusher?.flush()
    }

    /// Calls the bridge without waiting for its answer.
    func call(_ body: String, arguments: [String: Any] = [:]) {
        guard phase == .open else { return }
        Task {
            do {
                _ = try await page.callJavaScript(body, arguments: arguments)
            } catch {
                log.error("Reader call failed: \(error)")
            }
        }
    }

    /// The contents with each entry placed again (`bridge.js`
    /// `refineContents`).
    func contentsPlaced(_ entries: [ReaderMessage.TOCEntry]) {
        if entries != toc { toc = entries }
    }

    // MARK: Messages

    func receive(_ body: Any) {
        let message: ReaderMessage
        do {
            message = try ReaderMessage.decode(body)
        } catch {
            log.error("Undecodable reader message: \(error)")
            return
        }
        handle(message)
    }

    func handle(_ message: ReaderMessage) {
        switch message {
        case .ready:
            openBook()
        case .opened(let opened):
            log.debug("opened, restored from \(opened.restoredFrom, privacy: .public)")
            title = opened.title
            toc = opened.toc ?? []
            restoredFrom = opened.restoredFrom
            isRestoring = false
            phase = .open
            openedCFI = position?.cfi
            hasMoved = false
            if let tripToResume {
                trip = tripToResume
                tripFraction = shownFraction
                self.tripToResume = nil
            }
            didOpen()
            if let tripToCheck {
                self.tripToCheck = nil
                Task { await resumeIfStillYourPlace(tripToCheck) }
            }
            isFixedLayout = opened.isFixedLayout
            relayout()
            sendLayout()
            sendTapMode()
            sendTurnMode()
            sendAppearance()
            Task { await refreshBookmarks() }
        case .contents(let entries):
            contentsPlaced(entries)
        case .searchResults(let batch):
            search.receive(batch)
        case .relocate(let relocation):
            log.debug("relocate \(relocation.fraction ?? -1) \(relocation.cfi ?? "nil", privacy: .public)")
            let previous = self.relocation
            self.relocation = relocation
            relocationCount += 1
            position = relocation.position(cfiShape)
            tocLabel = relocation.tocLabel
            location = relocation.location
            // A repeat isn't a move (a fixed-layout page re-laid out reports
            // itself for the footer): saving it would mark it unsent, with a
            // new time that could beat another reader's newer place.
            if !isRestoring, relocation.position(cfiShape) != previous?.position(cfiShape) {
                // With None the page turns itself: its relocation is all
                // there is to go by.
                if !pageTurn.isAnimated, relocation.isPageTurn, foldBatch == nil, relocation.cfi != previous?.cfi { pageTurned() }
                moved(to: relocation)
            }
            // A turn's new page, measured again since its pictures came.
            if turnRun?.drawn == true, turn?.newPlace != nil {
                turn?.newPlace = ReaderPlace(chapter: relocation.tocLabel, location: relocation.location, fraction: relocation.shownFraction)
            }
            // Away, your place hasn't been left.
            if serverPlace != nil, trip == nil, tripToBe == nil { Task { await serverPlaceMayBeLeft() } }
            Task { await updateBookmarkedPage() }
        case .tap(let zone):
            onControlsTap?(zone)
        case .turn(let side):
            turnRequested(side)
        case .selection(let active):
            swipes.pageHasSelection = active
        case .viewport(let width, let height):
            log.debug("viewport \(width)×\(height)")
            viewport = CGSize(width: width, height: height)
            if foldBatch != nil {
                foldBatch?.pageResized(at: .now)
                if lastFold?.resized == nil, let startedAt = foldBatch?.startedAt {
                    lastFold?.resized = FoldReport.milliseconds(since: startedAt)
                }
                scheduleFoldEnd()
            }
            if let geometry { updateGeometry(geometry) }
        case .externalLink(let href):
            log.notice("Ignored external link \(href, privacy: .public)")
        case .error(let error):
            lastError = error.message
            log.error("Reader script error (\(error.phase ?? "?", privacy: .public)): \(error.message, privacy: .public)")
        case .log(let level, let message):
            log.notice("foliate \(level, privacy: .public): \(message, privacy: .public)")
        case .unknown(let type):
            log.notice("Unknown reader message type \(type, privacy: .public)")
        }
    }

    private func openBook() {
        isRestoring = true
        phase = .loading
        Task {
            let opening = await chooseOpeningPosition()
            openingPosition = opening
            // A trip reopens where you were looking, as long as the rule
            // still opens at your place. Spelled differently, only the page
            // can say (`resumeIfStillYourPlace`).
            let savedTrip = store.trip(forBook: book.id)
            tripToResume = savedTrip.flatMap { $0.page != nil && $0.place.cfi == opening.position?.cfi ? $0 : nil }
            tripToCheck = tripToResume == nil ? savedTrip : nil
            let saved = tripToResume?.page ?? opening.position
            var options: [String: Any] = [
                "url": ReaderSchemeHandler.bookURL(fileName: book.fileName).absoluteString,
                "name": book.fileName,
                "cfi": saved?.cfi ?? NSNull(),
                "fraction": saved?.fraction ?? NSNull(),
                "layout": layout.scriptArguments,
                "appearance": appearance.scriptArguments,
            ]
            #if DEBUG
            // The formats check's controls: the bridge's second layer off
            // (`docs/notes/formats-check.md`).
            if UserDefaults.standard.bool(forKey: "readerWithoutHarden") { options["harden"] = false }
            #endif
            sentLayout = layout
            sentAppearance = appearance
            do {
                _ = try await page.callJavaScript("return await window.octavo.open(options)", arguments: ["options": options])
            } catch {
                phase = .failed(lastError ?? error.localizedDescription)
            }
        }
    }

    /// The rule's pick between the local position and the backend's. If the
    /// pull fails or takes too long, the local position wins, else
    /// `fallback`'s percentage.
    private func chooseOpeningPosition() async -> OpeningPosition {
        let local = store.progress(forBook: book.id)
        let fallback = OpeningPosition.choose(local: local, remote: self.fallback)
        guard let sync else { return fallback }
        let started = ContinuousClock.now
        do {
            let remote = try await Self.withTimeout(Self.pullTimeout) { try await sync.pull() }
            let opening = OpeningPosition.choose(local: local, remote: remote)
            pulled = true
            serverCFI = remote?.position.cfi
            let waited = FoldReport.milliseconds(since: started)
            syncStatus = "pulled \(remote?.position.cfi ?? "nothing") in \(waited) ms → \(opening.label)"
            return opening
        } catch {
            syncStatus = "pull failed (\(error.localizedDescription)) → \(fallback.label)"
            log.error("Couldn't pull progress: \(error)")
            return fallback
        }
    }

    private func didOpen() {
        // Reopening on a trip, your place is what's saved, not this page.
        guard let position = trip?.place ?? position else { return }
        let local = store.progress(forBook: book.id)
        let chapter = trip != nil ? store.chapter(forBook: book.id) : nil
        switch openingPosition {
        case .local where local?.needsPush == true:
            // The device's unpushed position won; the backend should catch up.
            save(position, needsPush: true, chapter: chapter)
            Task { await pusher?.submit(position) }
        case .remote:
            // The backend already has this spot.
            save(position, needsPush: false, syncedAt: pulled ? .now : nil, chapter: chapter)
        default:
            save(position, needsPush: local?.needsPush ?? false, chapter: chapter)
        }
    }

    /// The saved trip's place wasn't what the rule opened at.
    func forgetSavedTrip() {
        store.saveTrip(nil, forBook: book.id)
    }

    private func moved(to relocation: ReaderMessage.Relocation) {
        // A blank page's CFI only names its section. Keep the last real page.
        guard relocation.blankPage != true else {
            log.notice("Blank page; position not saved")
            return
        }
        let position = relocation.position(cfiShape)
        // Your place stays as it is until you settle.
        if jumpsUnderWay > 0 || isGoingBack { return }
        if trip != nil {
            tripMoved(to: position)
            return
        }
        if isJumpingToServer {
            // As when opening: the server has this place, and pushing the
            // page's start would move it back a little.
            isJumpingToServer = false
            openedCFI = position.cfi
            hasMoved = false
            save(position, needsPush: false, syncedAt: .now)
            return
        }
        if !hasMoved {
            guard position.cfi != openedCFI else { return }
            hasMoved = true
        }
        saveAndSend(position)
    }

    private func saveAndSend(_ position: ReadingPosition) {
        save(position, needsPush: sync != nil)
        if let pusher {
            if serverPlace != nil { pushedSinceOffer = true }
            Task { await pusher.submit(position) }
        }
    }

    /// Where a jump leaves from: your saved place, the last real page if
    /// the page showing is blank.
    var savedPlace: ReadingPosition? {
        store.position(forBook: book.id) ?? position
    }

    /// ✕, or reading on: the page you're on is your place now, and syncs.
    func settleTrip() {
        guard trip != nil else { return }
        trip = nil
        // This place answers BookOrbit's capsule too, as reading on does.
        serverPlace = nil
        guard let position, relocation?.blankPage != true else { return }
        hasMoved = true
        saveAndSend(position)
    }

    /// Back has landed: this is your place, saved and sent as it was, so
    /// repeats of it aren't a move.
    func wentBack() {
        isGoingBack = false
        openedCFI = position?.cfi
        hasMoved = false
    }

    /// Back landed, and a page turn has already gone on from it.
    func wentBackAndTurned() {
        isGoingBack = false
        hasMoved = true
        guard let position, relocation?.blankPage != true else { return }
        saveAndSend(position)
    }

    private func save(_ position: ReadingPosition, needsPush: Bool, syncedAt: Date? = nil, chapter: String? = nil) {
        do {
            try store.save(position, forBook: book.id, needsPush: needsPush, chapter: chapter ?? tocLabel, syncedAt: syncedAt)
        } catch {
            log.error("Couldn't save reading position: \(error)")
        }
    }

    private func didPush(_ position: ReadingPosition) {
        lastPushedCFI = position.cfi
        serverCFI = position.cfi
        pushCount += 1
        syncStatus = "pushed \(Date.now.formatted(date: .omitted, time: .standard))"
        try? store.markPushed(position, forBook: book.id)
    }

    private func pushFailed(_ error: any Error) {
        syncStatus = "push failed: \(error.localizedDescription)"
        log.error("Couldn't push progress: \(error)")
    }

    // MARK: The server's place (Adam, 2026-11-02)

    /// The app came back with the book open: if another reader moved the
    /// server's place meanwhile, and it isn't on this page, offer it.
    func checkServerPlace() async {
        guard let sync, phase == .open, !isRestoring else { return }
        let pushes = pushCount
        let remote: SyncedPosition?
        do {
            remote = try await Self.withTimeout(Self.pullTimeout) { try await sync.pullLatest() }
        } catch {
            log.error("Couldn't check the server's place: \(error)")
            return
        }
        // A push that landed meanwhile may be newer than what the pull saw.
        guard pushes == pushCount, let remote, let cfi = remote.position.cfi, cfi != serverCFI,
              let pageStart = relocation?.startCFI ?? relocation?.cfi, phase == .open
        else { return }
        let asked = relocationCount
        let flags = try? await page.callJavaScript("return await window.octavo.onPage(cfis)", arguments: ["cfis": [cfi]]) as? [Bool]
        guard asked == relocationCount, pushes == pushCount, let flag = flags?.first else { return }
        // Away, the page showing isn't your place, so it says nothing.
        let onPage = trip == nil && flag
        serverCFI = cfi
        log.debug("server's place \(cfi, privacy: .public) \(onPage ? "is on this page" : "offered")")
        guard !onPage else { return }
        let place = await describe(cfi)
        guard asked == relocationCount else { return }
        await pusher?.backendMoved()
        pushedSinceOffer = false
        serverPlace = ReaderServerPlace(
            position: remote.position,
            fraction: remote.position.fraction > 0 ? remote.position.fraction : place?.fraction ?? 0,
            chapter: place?.chapter,
            offeredOn: trip?.place.cfi ?? pageStart
        )
    }

    /// The app came back, or the connection did: offer the server's place
    /// if another reader moved it, else send this page's if it didn't go.
    /// While the capsule shows, the page waits for Go, ✕ or a turn.
    func catchUp() async {
        // The app and the connection often come back together. A second
        // check could find the first one's place already known but not yet
        // offered, and send this page over it.
        guard !isCatchingUp else { return }
        isCatchingUp = true
        defer { isCatchingUp = false }
        await checkServerPlace()
        if serverPlace == nil { await pusher?.flush() }
    }

    /// Go: to the server's place, which the server keeps.
    func goToServerPlace() {
        guard let place = serverPlace, let cfi = place.position.cfi else { return }
        serverPlace = nil
        // The server's place is your place now, so a trip ends with this.
        let tripSoFar = trip
        trip = nil
        isJumpingToServer = true
        Task {
            // It may not open (another edition's place), and the next turn is
            // then this reader's own.
            let went = try? await page.callJavaScript("return await window.octavo.goTo(cfi)", arguments: ["cfi": cfi]) as? Bool
            if went != true {
                isJumpingToServer = false
                trip = tripSoFar
            }
        }
        // A fold or a text change since the offer re-laid out the page and
        // sent its place; the server's goes back.
        if pushedSinceOffer, let pusher { Task { await pusher.submit(place.position) } }
    }

    /// ✕: this page stays, and the server takes it.
    func keepThisPlace() {
        guard serverPlace != nil else { return }
        serverPlace = nil
        // Away, what stays is your place, not the page you're looking at.
        guard let kept = trip?.place ?? position, let pusher else { return }
        save(kept, needsPush: true, chapter: trip != nil ? store.chapter(forBook: book.id) : nil)
        Task { await pusher.submit(kept) }
    }

    /// Reading on from the page it was offered on leaves the server's place
    /// (the move sent this one). A fold or a text change keeps that page.
    private func serverPlaceMayBeLeft() async {
        guard let place = serverPlace else { return }
        let asked = relocationCount
        let flags = try? await page.callJavaScript("return await window.octavo.onPage(cfis)", arguments: ["cfis": [place.offeredOn]]) as? [Bool]
        guard asked == relocationCount, serverPlace == place, flags?.first == false else { return }
        serverPlace = nil
    }

    /// `operation`'s result, or `URLError(.timedOut)` after `timeout`, which
    /// cancels it.
    nonisolated static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

extension OpeningPosition {
    var label: String {
        switch self {
        case .remote: "server"
        case .local: "local"
        case .start: "start"
        }
    }
}

/// `WKUserContentController` retains its handlers, so this small relay sits
/// between it and the model to avoid a retain cycle.
///
/// Only `bridge.js` in the top-level reader page may talk to the app. Book
/// content lives in iframes, and anything posted from one is dropped, as a
/// second line of defense behind the CSP that blocks book scripts.
private final class ScriptMessageRelay: NSObject, WKScriptMessageHandler {
    static let name = "octavo"
    var onMessage: ((Any) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame,
              origin.protocol == ReaderSchemeHandler.scheme,
              origin.host == ReaderSchemeHandler.host else { return }
        onMessage?(message.body)
    }
}
