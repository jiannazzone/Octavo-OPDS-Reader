import Foundation
import OctavoKit
import WebKit

/// What a book file says about itself: for a book imported from Files,
/// which has no server to describe it.
nonisolated struct BookFileDetails: Equatable, Sendable {
    /// The format by the file's own bytes. Keep the file under
    /// `format.fileExtension`: foliate tells FB2 and CBZ apart by name.
    var format: BookFileFormat
    /// `nil` if the file has none; show the file's name instead.
    var title: String?
    var subtitle: String?
    /// First name first, as the book has them.
    var authors: [String] = []
    var publisher: String?
    /// A language code, as the book says it: `"en"`, `"en-GB"`.
    var language: String?
    /// As the book says it: `"1813-01-28"`, `"1813"`.
    var published: String?
    /// Plain text: the book's markup is never rendered.
    var description: String?
    /// The cover's image bytes (JPEG, PNG, GIF…), `nil` without one.
    var cover: Data?
}

/// Why a file can't be imported.
nonisolated enum BookInspectionError: Error, Equatable, Sendable {
    /// DRM ties it to a store's own apps.
    case drmProtected
    /// Not a format the reader opens. `kind` names the format when it's a
    /// known one ("PDF", "KFX"), for the message.
    case unsupported(kind: String?)
    /// It claims a format the reader opens, but can't be read as one, or
    /// took too long to read.
    case damaged
}

/// Reads an imported book's details (step 15, `docs/notes/formats-check.md`):
/// first its bytes, which refuse DRM-protected and unsupported files before
/// anything parses them (`BookFileCheck`), then foliate, in a page of its
/// own that is never shown, with the reader's scheme handler and CSP. No
/// section is laid out, so none of the book's own content is ever rendered.
/// One parser for every format, and the same one the reader uses; FB2's
/// cover is read in Swift, as the CSP blocks foliate's own read.
///
/// Each call loads a fresh page, which goes once the details are in.
struct BookInspector {
    /// How long one book may take: the 69 MB *Treasure Island* FB2 opens in
    /// about 3 s on the simulator.
    var timeout: Duration = .seconds(30)
    var webRoot: URL = Bundle.main.url(forResource: "ReaderWeb", withExtension: nil)!
    /// Starts the bridge's `inspect` and posts its answer, as JSON, to the
    /// handler `name`. Tests swap in a script that never answers.
    var script = """
        const handler = window.webkit.messageHandlers[name]
        window.octavo.inspect(options).then(
            result => handler.postMessage(JSON.stringify({ result })),
            error => handler.postMessage(JSON.stringify({ error: String(error) })))
        """

    func inspect(_ file: URL) async throws(BookInspectionError) -> BookFileDetails {
        let format: BookFileFormat
        do {
            format = try await Self.check(file)
        } catch let refusal as BookFileRefusal {
            switch refusal {
            case .drmProtected: throw .drmProtected
            case .unsupported(let kind): throw .unsupported(kind: kind)
            case .notABook: throw .unsupported(kind: nil)
            }
        } catch {
            throw .damaged
        }
        let answer: String
        do {
            answer = try await HiddenReader(file: file, format: format, webRoot: webRoot, script: script).read(timeout: timeout)
        } catch {
            throw .damaged
        }
        guard let data = answer.data(using: .utf8),
              let read = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["result"] as? [String: Any]
        else { throw .damaged }
        // Encrypted content, not just obfuscated fonts (Kobo's DRM).
        if read["drm"] as? Bool == true { throw .drmProtected }
        // No section to show: an EPUB with an empty spine, say.
        guard (read["sectionCount"] as? Int ?? 0) > 0 else { throw .damaged }
        var details = Self.details(from: read, format: format)
        if format == .fb2 {
            details.cover = await Self.fb2Cover(file)
        }
        return details
    }

    /// The most of a description's markup that's read: far more than any
    /// blurb.
    static let descriptionLimit = 20_000

    /// The details foliate's answer carries, tidied.
    static func details(from read: [String: Any], format: BookFileFormat) -> BookFileDetails {
        func text(_ key: String) -> String? {
            (read[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        let cover = (read["cover"] as? [String: Any])?["data"] as? String
        return BookFileDetails(
            format: format,
            title: text("title"),
            subtitle: text("subtitle"),
            authors: (read["authors"] as? [String] ?? []).compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty },
            publisher: text("publisher"),
            language: text("language"),
            published: text("published").map(dateOnly),
            // A book can carry any amount of markup here, and this runs on
            // the main actor, where the timeout can't stop it.
            description: text("description").map { PlainText.fromHTML(String($0.prefix(descriptionLimit))) }.flatMap(\.nilIfEmpty),
            cover: cover.flatMap { Data(base64Encoded: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// MOBI's dates come as times ("2008-06-27T04:00:00+00:00", the hour
    /// a tool's time zone); the day is what an EPUB of the book says.
    private static func dateOnly(_ date: String) -> String {
        date.wholeMatch(of: /(\d{4}-\d{2}-\d{2})T[0-9:.]+(Z|[+-]\d{2}:?\d{2})?/).map { String($0.1) } ?? date
    }

    // Off the main actor: both read the file.
    @concurrent private nonisolated static func check(_ file: URL) async throws -> BookFileFormat {
        try BookFileCheck.check(file)
    }

    @concurrent private nonisolated static func fb2Cover(_ file: URL) async -> Data? {
        FB2Cover.read(from: file)?.data
    }
}

/// The reader page, never shown, asked for one file's details. A user script
/// starts the bridge's `inspect` as the page loads, and the answer comes back
/// as a message, so nothing in Swift is left waiting on the page: a call into
/// a page that a book keeps busy never returns, and holds the page (and its
/// web process) for good. Once the answer is in, or `timeout` has passed,
/// the page is dropped and freed at once.
///
/// A web process still busy in a script outlives its page: iOS 27.1's WebKit
/// keeps it running after the page closes, navigates away or loses its data
/// store (measured; `docs/notes/formats-check.md`), and no public API ends
/// it. No book is known to do that to foliate.
@MainActor
private final class HiddenReader {
    static let messageName = "octavoInspect"

    private var page: WebPage?
    /// The bridge's answer, as the JSON it posted: `{ result }` or
    /// `{ error }`.
    private var continuation: CheckedContinuation<String, any Error>?

    init(file: URL, format: BookFileFormat, webRoot: URL, script: String) {
        let name = "book.\(format.fileExtension)"
        let options = ["url": ReaderSchemeHandler.bookURL(fileName: name).absoluteString, "name": name]
        let relay = InspectRelay()
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme(ReaderSchemeHandler.scheme)!] = ReaderSchemeHandler(bookFile: file, webRoot: webRoot)
        configuration.userContentController.add(relay, name: Self.messageName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.starter(script, options: options), injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        page = WebPage(configuration: configuration)
        relay.onMessage = { [weak self] body in self?.received(body) }
    }

    /// `script` with its `options` and handler `name`, run once the bridge
    /// (a module, so it may finish after the document) is there.
    private static func starter(_ script: String, options: [String: String]) -> String {
        let json = { (value: Any) in
            String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("null".utf8), as: UTF8.self)
        }
        return """
            (() => {
                const options = \(json(options)), name = \(json(messageName))
                const run = () => { \(script) }
                const wait = tries => window.octavo?.inspect ? run() : tries > 0 && setTimeout(() => wait(tries - 1), 20)
                wait(250)
            })()
            """
    }

    func read(timeout: Duration) async throws -> String {
        defer { close() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            // Its events aren't followed: following them holds the page
            // until the load ends, which a busy page never reports.
            _ = page?.load(ReaderSchemeHandler.readerURL)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func received(_ body: Any) {
        finish(body is String ? .success(body as! String) : .failure(BookInspectionError.damaged))
    }

    private func finish(_ result: Result<String, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        close()
    }

    /// The last reference to the page goes, and WebKit closes it.
    private func close() {
        page = nil
    }
}

/// Only the hidden page itself may answer, as with the reader's relay.
private final class InspectRelay: NSObject, WKScriptMessageHandler {
    var onMessage: ((Any) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame,
              origin.protocol == ReaderSchemeHandler.scheme,
              origin.host == ReaderSchemeHandler.host else { return }
        onMessage?(message.body)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
