import Foundation
import Testing
import WebKit
@testable import Octavo

struct ReaderSchemeHandlerTests {
    let root: URL
    let book: URL
    let handler: ReaderSchemeHandler

    init() throws {
        root = URL.temporaryDirectory.appending(path: "ReaderWeb-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "foliate-js"), withIntermediateDirectories: true)
        try Data("export const x = 1\n".utf8).write(to: root.appending(path: "foliate-js/view.js"))
        try Data("<!DOCTYPE html>".utf8).write(to: root.appending(path: "reader.html"))
        book = URL.temporaryDirectory.appending(path: "book-\(UUID().uuidString).epub")
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
    ])
    func rejectsRequestsOutsideTheWebRoot(url: String) {
        #expect(handler.fileURL(for: URL(string: url)!) == nil)
    }

    @Test(arguments: [
        ("js", "text/javascript"), ("mjs", "text/javascript"), ("html", "text/html"),
        ("css", "text/css"), ("epub", "application/epub+zip"), ("CBZ", "application/vnd.comicbook+zip"),
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

    private func fetch(_ url: String) async throws -> (HTTPURLResponse?, Data) {
        var response: HTTPURLResponse?
        var data = Data()
        for try await result in handler.reply(for: URLRequest(url: URL(string: url)!)) {
            switch result {
            case .response(let r): response = r as? HTTPURLResponse
            case .data(let chunk): data.append(chunk)
            @unknown default: break
            }
        }
        return (response, data)
    }
}
