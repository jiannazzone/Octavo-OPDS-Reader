import Foundation
import OctavoKit
import Observation
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
        case .relocate(let relocation):
            log.debug("relocate \(relocation.fraction ?? -1) \(relocation.cfi ?? "nil", privacy: .public)")
            self.relocation = relocation
            position = relocation.position(cfiShape)
            tocLabel = relocation.tocLabel
            location = relocation.location
            if !isRestoring { moved(to: relocation) }
        case .tap:
            break
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
            ]
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
