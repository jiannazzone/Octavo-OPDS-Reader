import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the web reader and the open book to the `WebView` over one custom
/// scheme, so everything shares a single origin. That keeps ES-module imports
/// and the bridge's `fetch` of the book same-origin.
///
/// - `octavo://app/<path>` → `<path>` inside the bundled `ReaderWeb/` folder.
/// - `octavo://app/book/<name>` → the book file this handler was made for.
nonisolated struct ReaderSchemeHandler: URLSchemeHandler {
    static let scheme = "octavo"
    static let host = "app"
    static let readerURL = URL(string: "\(scheme)://\(host)/reader.html")!

    /// Sent with every reader response. foliate-js renders book content in
    /// same-origin `blob:` iframes that must allow scripts (WebKit bug
    /// 218086), so this policy, which those iframes inherit, is the only thing
    /// stopping a book's own JavaScript. Only our bundled scripts may run (by
    /// path, so the book at `/book/` is never a script source, even though it
    /// is same-origin), and nothing may load from the network.
    static let contentSecurityPolicy = [
        "default-src 'self'",
        "script-src \(scheme)://\(host)/bridge.js \(scheme)://\(host)/foliate-js/",
        "style-src 'self' 'unsafe-inline' blob: data:",
        "img-src 'self' blob: data:",
        "font-src 'self' blob: data:",
        "media-src 'self' blob: data:",
        "connect-src 'self' blob:",
        "frame-src blob:",
        "object-src 'none'",
        "base-uri 'none'",
        "form-action 'none'",
    ].joined(separator: "; ")

    /// The book is only ever fetched as bytes. If anything tries to use it as
    /// a document, it gets nothing.
    static let bookContentSecurityPolicy = "default-src 'none'; sandbox"

    /// URL the bridge fetches the book from. The last path component is the
    /// file name, which foliate uses to tell CBZ/FB2 apart from EPUB.
    static func bookURL(fileName: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/book/" + fileName
        return components.url!
    }

    let webRoot: URL
    let bookFile: URL

    init(bookFile: URL, webRoot: URL = Bundle.main.url(forResource: "ReaderWeb", withExtension: nil)!) {
        self.webRoot = webRoot.standardizedFileURL
        self.bookFile = bookFile
    }

    /// The file a request maps to, or `nil` for anything outside `ReaderWeb/`
    /// and the book.
    func fileURL(for url: URL) -> URL? {
        guard url.scheme == Self.scheme, url.host == Self.host else { return nil }
        let path = url.path(percentEncoded: false)
        if path.hasPrefix("/book/") { return bookFile }
        let relative = path.drop(while: { $0 == "/" })
        guard !relative.isEmpty else { return nil }
        let file = webRoot.appending(path: String(relative)).standardizedFileURL
        // Reject `..` escapes.
        let root = webRoot.path(percentEncoded: false)
        guard file.path(percentEncoded: false).hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return nil }
        return file
    }

    /// WebKit only runs ES modules served with a JavaScript MIME type, so the
    /// common web types are pinned rather than left to `UTType`.
    static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": "text/html"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "json": "application/json"
        case "svg": "image/svg+xml"
        case "txt", "md": "text/plain"
        case "epub": "application/epub+zip"
        case "cbz": "application/vnd.comicbook+zip"
        case "fb2": "application/x-fictionbook+xml"
        // foliate tells a zipped FB2 from an EPUB by this type or by the name.
        case "fbz": "application/x-zip-compressed-fb2"
        // foliate detects MOBI/KF8 by its header, not by type.
        case "mobi", "azw", "azw3": "application/x-mobipocket-ebook"
        default: UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { continuation in
            guard let url = request.url else {
                continuation.finish(throwing: URLError(.badURL))
                return
            }
            guard let file = fileURL(for: url),
                  let handle = try? FileHandle(forReadingFrom: file) else {
                continuation.yield(.response(Self.response(url: url, status: 404, mimeType: "text/plain", length: 0)))
                continuation.finish()
                return
            }
            let task = Task {
                defer { try? handle.close() }
                do {
                    let length = try handle.seekToEnd()
                    try handle.seek(toOffset: 0)
                    let mimeType = Self.mimeType(forPathExtension: file.pathExtension)
                    let policy = file == bookFile ? Self.bookContentSecurityPolicy : Self.contentSecurityPolicy
                    continuation.yield(.response(Self.response(url: url, status: 200, mimeType: mimeType, length: length, policy: policy)))
                    // Stream in chunks so a large book isn't held twice in memory.
                    while !Task.isCancelled, let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                        continuation.yield(.data(chunk))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `nosniff` makes WebKit refuse to run anything as a script or stylesheet
    /// unless its MIME type says it is one, so a book file crafted to also
    /// parse as JavaScript can't be executed.
    private static func response(url: URL, status: Int, mimeType: String, length: UInt64, policy: String = contentSecurityPolicy) -> URLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": String(length),
                "Cache-Control": "no-store",
                "Content-Security-Policy": policy,
                "X-Content-Type-Options": "nosniff",
            ]
        )!
    }
}
