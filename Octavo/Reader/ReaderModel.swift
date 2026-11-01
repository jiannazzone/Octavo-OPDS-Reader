import Foundation
import OctavoKit
import Observation
import UIKit
import WebKit
import os

/// Drives one book in a foliate-js `WebPage`: loads the reader, opens the book
/// at its saved position, and keeps that position up to date as pages turn.
///
/// With a `ProgressSync`, the book opens where `OpeningPosition` says (pulled
/// from the backend before opening), and every move the reader makes after
/// that is pushed, debounced. Opening itself pushes nothing: the page we land
/// on starts at or before the backend's position, so pushing it back would
/// creep the position backwards a little on every open.
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
    private(set) var tocLabel: String?
    private(set) var location: ReaderMessage.Relocation.Location?
    /// Where the opening position came from (`cfi`, `fraction`, `start`).
    private(set) var restoredFrom: String?
    /// The last script error, for the debug overlay.
    private(set) var lastError: String?
    /// The latest relocation, both CFI shapes included.
    private(set) var relocation: ReaderMessage.Relocation?
    /// Counts relocations, including ones that repeat the same page (a fold
    /// re-lays out the page without moving the position).
    private(set) var relocationCount = 0

    // Layout, decided from the fold. See `ReaderLayout`.
    private(set) var posture: ReaderPosture = .noHinge
    /// The hinge angle in degrees, as last reported.
    private(set) var hingeAngle: Double?
    /// The SwiftUI view's geometry, with the page's own size once known.
    private(set) var geometry: ReaderGeometry?
    private(set) var layout: ReaderLayout = .automatic
    /// The page's size as the page reports it.
    @ObservationIgnored private var viewport: CGSize?

    // Folding: one re-layout per fold, under a cross-fade. See `FoldBatch`.
    /// Shown over the page while a fold settles (`ReaderFoldCoverView`).
    private(set) var foldCover: ReaderFoldCover?
    /// The last fold's timings, for the debug overlay.
    private(set) var lastFold: FoldReport?
    @ObservationIgnored var foldTiming = FoldBatch.Timing()
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

    @ObservationIgnored private let store: ReadingPositionStore
    @ObservationIgnored private let sync: (any ProgressSync)?
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
        cfiShape: ReaderMessage.CFIShape = .point,
        pushDelay: Duration = .seconds(2)
    ) {
        self.book = book
        self.store = store
        self.sync = sync
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
    func goTo(fraction: Double) { call("return await window.octavo.goToFraction(fraction)", arguments: ["fraction": fraction]) }

    /// The hinge changed. `angle` is in degrees. The system repeats
    /// unchanged values many times a second while the hinge settles.
    func hingeChanged(_ posture: ReaderPosture, angle: Double?) {
        if angle != hingeAngle { hingeAngle = angle }
        guard posture != self.posture else { return }
        log.debug("posture \(posture.rawValue, privacy: .public)")
        let old = self.posture
        self.posture = posture
        // `.noHinge` is only the first report, before the hinge is known.
        if old != .noHinge, old.isFolded != posture.isFolded { beginFold() }
        relayout()
    }

    /// The reader view's size or the fold's regions changed.
    func geometryChanged(_ geometry: ReaderGeometry) {
        var geometry = geometry
        if let viewport { geometry.size = viewport }
        guard geometry != self.geometry else { return }
        self.geometry = geometry
        relayout()
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
        apply(ReaderLayout(posture: posture, geometry: geometry))
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
    private func beginFold() {
        guard phase == .open else { return }
        let now = ContinuousClock.now
        if foldBatch != nil {
            foldBatch?.restart(at: now)
            scheduleFoldEnd()
            return
        }
        foldBatch = FoldBatch(startedAt: now)
        lastFold = FoldReport()
        call("return await window.octavo.hold()")
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
        let layout = ReaderLayout(posture: posture, geometry: geometry)
        self.layout = layout
        sentLayout = layout
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

    private func call(_ body: String, arguments: [String: Any] = [:]) {
        guard phase == .open else { return }
        Task {
            do {
                _ = try await page.callJavaScript(body, arguments: arguments)
            } catch {
                log.error("Reader call failed: \(error)")
            }
        }
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
            restoredFrom = opened.restoredFrom
            isRestoring = false
            phase = .open
            openedCFI = position?.cfi
            hasMoved = false
            didOpen()
            sendLayout()
        case .relocate(let relocation):
            log.debug("relocate \(relocation.fraction ?? -1) \(relocation.cfi ?? "nil", privacy: .public)")
            self.relocation = relocation
            relocationCount += 1
            position = relocation.position(cfiShape)
            tocLabel = relocation.tocLabel
            location = relocation.location
            if !isRestoring { moved(to: relocation) }
        case .tap:
            break
        case .viewport(let width, let height):
            viewport = CGSize(width: width, height: height)
            if foldBatch != nil {
                foldBatch?.pageResized(at: .now)
                if lastFold?.resized == nil, let startedAt = foldBatch?.startedAt {
                    lastFold?.resized = FoldReport.milliseconds(since: startedAt)
                }
                scheduleFoldEnd()
            }
            if let geometry { geometryChanged(geometry) }
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
            let saved = opening.position
            let options: [String: Any] = [
                "url": ReaderSchemeHandler.bookURL(fileName: book.fileName).absoluteString,
                "name": book.fileName,
                "cfi": saved?.cfi ?? NSNull(),
                "fraction": saved?.fraction ?? NSNull(),
                "layout": layout.scriptArguments,
            ]
            sentLayout = layout
            do {
                _ = try await page.callJavaScript("return await window.octavo.open(options)", arguments: ["options": options])
            } catch {
                phase = .failed(lastError ?? error.localizedDescription)
            }
        }
    }

    /// The local position, or the rule's pick between it and the backend's.
    /// If the pull fails or takes too long, the local position wins.
    private func chooseOpeningPosition() async -> OpeningPosition {
        let local = store.progress(forBook: book.id)
        let fallback = local.map { OpeningPosition.local($0.position) } ?? .start
        guard let sync else { return fallback }
        do {
            let remote = try await Self.withTimeout(Self.pullTimeout) { try await sync.pull() }
            let opening = OpeningPosition.choose(local: local, remote: remote)
            syncStatus = "pulled \(remote?.position.cfi ?? "nothing") → \(opening.label)"
            return opening
        } catch {
            syncStatus = "pull failed (\(error.localizedDescription)) → local"
            log.error("Couldn't pull progress: \(error)")
            return fallback
        }
    }

    private func didOpen() {
        guard let position else { return }
        let local = store.progress(forBook: book.id)
        switch openingPosition {
        case .local where local?.needsPush == true:
            // The device's unpushed position won; the backend should catch up.
            save(position, needsPush: true)
            Task { await pusher?.submit(position) }
        case .remote:
            // The backend already has this spot.
            save(position, needsPush: false)
        default:
            save(position, needsPush: local?.needsPush ?? false)
        }
    }

    private func moved(to relocation: ReaderMessage.Relocation) {
        // A blank page's CFI only names its section. Keep the last real page.
        guard relocation.blankPage != true else {
            log.notice("Blank page; position not saved")
            return
        }
        let position = relocation.position(cfiShape)
        if !hasMoved {
            guard position.cfi != openedCFI else { return }
            hasMoved = true
        }
        save(position, needsPush: sync != nil)
        if let pusher { Task { await pusher.submit(position) } }
    }

    private func save(_ position: ReadingPosition, needsPush: Bool) {
        do {
            try store.save(position, forBook: book.id, needsPush: needsPush)
        } catch {
            log.error("Couldn't save reading position: \(error)")
        }
    }

    private func didPush(_ position: ReadingPosition) {
        lastPushedCFI = position.cfi
        syncStatus = "pushed \(Date.now.formatted(date: .omitted, time: .standard))"
        try? store.markPushed(position, forBook: book.id)
    }

    private func pushFailed(_ error: any Error) {
        syncStatus = "push failed: \(error.localizedDescription)"
        log.error("Couldn't push progress: \(error)")
    }

    private nonisolated static func withTimeout<T: Sendable>(
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
