import Foundation
import OctavoKit
import Observation
import WebKit
import os

/// Drives one book in a foliate-js `WebPage`: loads the reader, opens the book
/// at its saved position, and keeps that position up to date as pages turn.
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

    @ObservationIgnored private let store: ReadingPositionStore
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Positions reported while the book is still being restored are not saved,
    /// so a half-finished open can't overwrite the saved position.
    @ObservationIgnored private var isRestoring = true
    @ObservationIgnored private let log = Logger(subsystem: "com.ianazzone.ereader", category: "Reader")

    init(book: ReaderBook, store: ReadingPositionStore = ReadingPositionStore()) {
        self.book = book
        self.store = store

        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme(ReaderSchemeHandler.scheme)!] = ReaderSchemeHandler(bookFile: book.fileURL)
        let relay = ScriptMessageRelay()
        configuration.userContentController.add(relay, name: ScriptMessageRelay.name)
        page = WebPage(configuration: configuration)
        #if DEBUG
        page.isInspectable = true
        #endif

        relay.onMessage = { [weak self] body in self?.receive(body) }
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
            if let position { save(position) }
        case .relocate(let relocation):
            log.debug("relocate \(relocation.fraction ?? -1) \(relocation.cfi ?? "nil", privacy: .public)")
            position = relocation.position
            tocLabel = relocation.tocLabel
            location = relocation.location
            if !isRestoring { save(relocation.position) }
        case .tap:
            break
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
        let saved = store.position(forBook: book.id)
        let options: [String: Any] = [
            "url": ReaderSchemeHandler.bookURL(fileName: book.fileName).absoluteString,
            "name": book.fileName,
            "cfi": saved?.cfi ?? NSNull(),
            "fraction": saved?.fraction ?? NSNull(),
        ]
        isRestoring = true
        phase = .loading
        Task {
            do {
                _ = try await page.callJavaScript("return await window.octavo.open(options)", arguments: ["options": options])
            } catch {
                phase = .failed(lastError ?? error.localizedDescription)
            }
        }
    }

    private func save(_ position: ReadingPosition) {
        do {
            try store.save(position, forBook: book.id)
        } catch {
            log.error("Couldn't save reading position: \(error)")
        }
    }
}

/// `WKUserContentController` retains its handlers, so this small relay sits
/// between it and the model to avoid a retain cycle.
private final class ScriptMessageRelay: NSObject, WKScriptMessageHandler {
    static let name = "octavo"
    var onMessage: ((Any) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage?(message.body)
    }
}
