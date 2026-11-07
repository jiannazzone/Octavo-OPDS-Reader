import Foundation
import Testing
import WebKit
@testable import Octavo

@Suite(.temporaryFiles)
struct ReaderSchemeHandlerTests {
    let root: URL
    let book: URL
    let handler: ReaderSchemeHandler

    init() throws {
        root = URL.testDirectory.appending(path: "ReaderWeb-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "foliate-js"), withIntermediateDirectories: true)
        try Data("export const x = 1\n".utf8).write(to: root.appending(path: "foliate-js/view.js"))
        try Data("<!DOCTYPE html>".utf8).write(to: root.appending(path: "reader.html"))
        book = URL.testDirectory.appending(path: "book-\(UUID().uuidString).epub")
        try Data(repeating: 0x50, count: 3_000_000).write(to: book)
        handler = ReaderSchemeHandler(bookFile: book, webRoot: root)
    }

    @Test func mapsReaderPathsIntoTheWebRoot() {
        #expect(handler.fileURL(for: ReaderSchemeHandler.readerURL)?.lastPathComponent == "reader.html")
        #expect(handler.fileURL(for: URL(string: "octavo://app/foliate-js/view.js")!)?.path(percentEncoded: false)
            == root.appending(path: "foliate-js/view.js").standardizedFileURL.path(percentEncoded: false))
    }

    @Test func mapsBookPathsToTheBookFile() {
        #expect(handler.fileURL(for: ReaderSchemeHandler.bookURL(fileName: "Pride & Prejudice.epub")) == book)
    }

    @Test(arguments: [
        "octavo://app/../secret.txt",
        "octavo://app/foliate-js/../../secret.txt",
        "octavo://other/reader.html",
        "https://app/reader.html",
        "octavo://app/",
        // Encoded dot segments: the CSP's `fonts/` and `foliate-js/` paths
        // would take these as inside them.
        "octavo://app/fonts/..%2Freader.html",
        "octavo://app/fonts/%2e%2e%2Ffoliate-js%2Fview.js",
        "octavo://app/foliate-js/.%2Fview.js",
    ])
    func rejectsRequestsOutsideTheWebRoot(url: String) {
        #expect(handler.fileURL(for: URL(string: url)!) == nil)
    }

    @Test(arguments: [
        ("js", "text/javascript"), ("mjs", "text/javascript"), ("html", "text/html"),
        ("css", "text/css"), ("epub", "application/epub+zip"), ("CBZ", "application/vnd.comicbook+zip"),
        ("fb2", "application/x-fictionbook+xml"), ("fbz", "application/x-zip-compressed-fb2"),
        ("mobi", "application/x-mobipocket-ebook"), ("azw3", "application/x-mobipocket-ebook"),
        ("woff2", "font/woff2"),
    ])
    func pinsWebMIMETypes(ext: String, mimeType: String) {
        #expect(ReaderSchemeHandler.mimeType(forPathExtension: ext) == mimeType)
    }

    @Test func servesModulesWithAJavaScriptMIMEType() async throws {
        let (response, data) = try await fetch("octavo://app/foliate-js/view.js")
        #expect(response?.statusCode == 200)
        #expect(response?.value(forHTTPHeaderField: "Content-Type") == "text/javascript")
        #expect(data == Data("export const x = 1\n".utf8))
    }

    // foliate-js renders books in same-origin iframes that allow scripts; the
    // CSP these responses carry is what keeps a book's JavaScript from running.
    @Test func everyResponseCarriesAScriptBlockingCSP() async throws {
        for url in ["octavo://app/reader.html", "octavo://app/foliate-js/view.js", "octavo://app/missing.js"] {
            let (response, _) = try await fetch(url)
            let policy = try #require(response?.value(forHTTPHeaderField: "Content-Security-Policy"))
            let scriptSources = try #require(policy.split(separator: ";").first { $0.contains("script-src") })
            #expect(scriptSources.trimmingCharacters(in: .whitespaces)
                == "script-src octavo://app/bridge.js octavo://app/foliate-js/")
            #expect(!policy.contains("unsafe-eval"))
            #expect(!policy.contains("http"))
            #expect(response?.value(forHTTPHeaderField: "X-Content-Type-Options") == "nosniff")
        }
    }

    // Fonts come from the bundled `fonts/` or the book's own blobs, never
    // anywhere else on the origin (the book at `/book/`) or the network.
    // The whole policy, so loosening any directive shows up here.
    @Test func theReaderPolicyIsExactlyThis() {
        #expect(ReaderSchemeHandler.contentSecurityPolicy == """
            default-src 'self'; script-src octavo://app/bridge.js octavo://app/foliate-js/; \
            style-src 'self' 'unsafe-inline' blob: data:; img-src 'self' blob: data:; \
            font-src octavo://app/fonts/ blob: data:; media-src 'self' blob: data:; connect-src 'self' blob:; \
            frame-src blob:; object-src 'none'; base-uri 'none'; form-action 'none'
            """)
    }

    @Test func fontsLoadOnlyFromTheBundledFonts() throws {
        let policy = ReaderSchemeHandler.contentSecurityPolicy
        let fontSources = try #require(policy.split(separator: ";").first { $0.contains("font-src") })
        #expect(fontSources.trimmingCharacters(in: .whitespaces) == "font-src octavo://app/fonts/ blob: data:")
    }

    // Every face `ReaderFont` asks for is in the app's own `ReaderWeb/fonts/`
    // and served as a font, under the reader's CSP.
    @Test func servesEveryBundledFontAsWOFF2() async throws {
        let bundled = ReaderSchemeHandler(bookFile: book)
        let sources = ReaderFont.allCases.flatMap { $0.fontFaces.matches(of: #/url\("([^"]+)"\)/#).map { String($0.output.1) } }
        #expect(sources.count == 6)
        for source in sources {
            let (response, data) = try await fetch(source, from: bundled)
            #expect(response?.statusCode == 200, "\(source)")
            #expect(response?.value(forHTTPHeaderField: "Content-Type") == "font/woff2")
            #expect(response?.value(forHTTPHeaderField: "Content-Security-Policy") == ReaderSchemeHandler.contentSecurityPolicy)
            #expect(data.prefix(4) == Data("wOF2".utf8))
        }
    }

    // The book is same-origin, so it must never be usable as a script or a document.
    @Test func theBookIsServedLockedDown() async throws {
        let (response, _) = try await fetch(ReaderSchemeHandler.bookURL(fileName: "book.epub").absoluteString)
        #expect(response?.value(forHTTPHeaderField: "Content-Security-Policy") == "default-src 'none'; sandbox")
        #expect(response?.value(forHTTPHeaderField: "X-Content-Type-Options") == "nosniff")
    }

    @Test func streamsTheBookInChunks() async throws {
        let (response, data) = try await fetch(ReaderSchemeHandler.bookURL(fileName: "book.epub").absoluteString)
        #expect(response?.statusCode == 200)
        #expect(response?.value(forHTTPHeaderField: "Content-Length") == "3000000")
        #expect(data.count == 3_000_000)
    }

    @Test func answersMissingFilesWith404() async throws {
        let (response, data) = try await fetch("octavo://app/missing.js")
        #expect(response?.statusCode == 404)
        #expect(data.isEmpty)
    }

    private func fetch(_ url: String, from handler: ReaderSchemeHandler? = nil) async throws -> (HTTPURLResponse?, Data) {
        var response: HTTPURLResponse?
        var data = Data()
        for try await result in (handler ?? self.handler).reply(for: URLRequest(url: URL(string: url)!)) {
            switch result {
            case .response(let r): response = r as? HTTPURLResponse
            case .data(let chunk): data.append(chunk)
            @unknown default: break
            }
        }
        return (response, data)
    }
}
