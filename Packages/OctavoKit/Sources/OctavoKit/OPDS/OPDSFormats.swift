import Foundation

/// Turns an acquisition link into a `LibraryFile.format`, and orders a
/// book's files the way Adam chose (2026-11-01): EPUB, then AZW3, MOBI, FB2
/// and FBZ, then everything else in the server's order.
enum OPDSFormats {
    /// Most wanted first; the first one the reader opens is what Open
    /// downloads.
    static let preference = ["epub", "azw3", "mobi", "azw", "fb2", "fbz"]

    /// The format of the file behind `link`, lowercase (`"epub"`), or `nil`
    /// if neither its type nor its name says.
    ///
    /// The link's title or file extension wins when it names a known
    /// format, because servers mislabel: Calibre-Web sends AZW3 and MOBI as
    /// the same `application/x-mobipocket-ebook`, and plain FB2 as
    /// `application/fb2+zip`.
    static func format(of link: OPDSLink) -> String? {
        if let hint = hint(link) { return hint }
        guard let type = link.mediaType else { return nil }
        return byType[type]
    }

    /// `files` sorted by `preference`; the rest keep their order.
    static func sorted<T>(_ files: [T], format: (T) -> String?) -> [T] {
        files.enumerated().sorted { a, b in
            let rankA = format(a.element).flatMap { preference.firstIndex(of: $0) } ?? preference.count
            let rankB = format(b.element).flatMap { preference.firstIndex(of: $0) } ?? preference.count
            return rankA != rankB ? rankA < rankB : a.offset < b.offset
        }.map(\.element)
    }

    private static let byType: [String: String] = [
        "application/epub+zip": "epub",
        // Kindle: foliate tells MOBI 6 from KF8 by the file itself, so the
        // extension only has to be one it opens.
        "application/x-mobipocket-ebook": "mobi",
        "application/x-mobi8-ebook": "azw3",
        "application/vnd.amazon.ebook": "azw3",
        "application/vnd.amazon.mobi8-ebook": "azw3",
        "application/x-fictionbook+xml": "fb2",
        "application/x-fictionbook": "fb2",
        "text/fb2+xml": "fb2",
        "application/fb2": "fb2",
        "application/x-zip-compressed-fb2": "fbz",
        "application/fb2+zip": "fbz",
        "application/pdf": "pdf",
        "application/vnd.comicbook+zip": "cbz",
        "application/x-cbz": "cbz",
        "application/vnd.comicbook-rar": "cbr",
        "application/x-cbr": "cbr",
        "application/x-cb7": "cb7",
        "text/plain": "txt",
        "application/rtf": "rtf",
        "text/rtf": "rtf",
        "application/vnd.oasis.opendocument.text": "odt",
        "application/x-mobipocket": "mobi",
        "application/vnd.ms-htmlhelp": "chm",
        "application/x-djvu": "djvu",
        "image/vnd.djvu": "djvu",
    ]

    /// Names a server may use, in a title or as an extension.
    private static let known: Set<String> = [
        "epub", "azw3", "azw", "mobi", "fb2", "fbz", "pdf", "cbz", "cbr", "cb7", "txt", "rtf", "odt", "chm", "djvu", "kepub", "docx",
    ]

    private static func hint(_ link: OPDSLink) -> String? {
        if let title = link.title?.trimmingCharacters(in: .whitespaces).lowercased(), known.contains(title) {
            return title
        }
        guard let path = link.url?.path.lowercased() else { return nil }
        if path.hasSuffix(".fb2.zip") { return "fbz" }
        if path.hasSuffix(".kepub.epub") { return "epub" }
        // `/download/6/azw3/` (Calibre-Web) or `book.azw3` (COPS, Kavita).
        let components = path.split(separator: "/")
        if let last = components.last {
            if let dot = last.lastIndex(of: ".") {
                let ext = String(last[last.index(after: dot)...])
                if known.contains(ext) { return ext }
            } else if known.contains(String(last)) {
                return String(last)
            }
        }
        return nil
    }
}
