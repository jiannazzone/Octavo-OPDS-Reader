import Foundation
import OctavoKit

/// A book whose file is on the iPhone: a row in Storage's Books on iPhone,
/// and what Remove server counts.
nonisolated struct DownloadedBook: Identifiable, Equatable, Sendable {
    var book: SourcedBook
    var url: URL
    /// Bytes on disk.
    var size: Int64
    var downloadedAt: Date

    /// The file's `storageKey`: one row per file, whichever record named it.
    var id: String { url.deletingPathExtension().lastPathComponent }
}

/// How Books on iPhone lists its books (Adam, 2026-11-02: the reader picks,
/// largest first to start with). Remembered on the iPhone.
nonisolated enum DownloadOrder: String, CaseIterable, Identifiable, Sendable {
    case size, title, author, downloaded

    static let key = "settings.booksOnIPhone.order"

    var id: Self { self }

    var title: String {
        switch self {
        case .size: "Size"
        case .title: "Title"
        case .author: "Author"
        case .downloaded: "Recently downloaded"
        }
    }

    func sorted(_ books: [DownloadedBook]) -> [DownloadedBook] {
        books.sorted { a, b in
            switch self {
            case .size:
                if a.size != b.size { return a.size > b.size }
            case .title:
                let order = a.book.book.title.localizedStandardCompare(b.book.book.title)
                if order != .orderedSame { return order == .orderedAscending }
            case .author:
                let order = Self.authorKey(a).localizedStandardCompare(Self.authorKey(b))
                if order != .orderedSame { return order == .orderedAscending }
            case .downloaded:
                if a.downloadedAt != b.downloadedAt { return a.downloadedAt > b.downloadedAt }
            }
            return a.book.book.title.localizedStandardCompare(b.book.book.title) == .orderedAscending
        }
    }

    /// Filed by last name, as the Authors list is.
    private static func authorKey(_ book: DownloadedBook) -> String {
        book.book.book.authors.first.map(AuthorIndex.sortKey(name:)) ?? ""
    }
}

extension ShellModel {
    /// The books with a file on the iPhone: each one the iPhone downloaded,
    /// or opened before it kept that list, once.
    func downloads() -> [DownloadedBook] {
        var seen = Set<String>()
        let records = library.onIPhone.books() + library.recents.records().map(\.book)
        return records.compactMap { record in
            guard let url = opener.localFile(for: record),
                  seen.insert(url.lastPathComponent).inserted
            else { return nil }
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .creationDateKey])
            let size = values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
            return DownloadedBook(book: record, url: url, size: Int64(size), downloadedAt: values?.creationDate ?? .distantPast)
        }
    }

    /// What Remove server counts as `server`'s downloads.
    func downloads(on server: LibrarySourceID) -> [DownloadedBook] {
        downloads().filter { $0.book.source == server }
    }
}

nonisolated extension [DownloadedBook] {
    /// "12 · 48 MB", or "5 books · 4.4 MB" with `books`; "None" without any.
    func summary(books: Bool = false) -> String {
        guard !isEmpty else { return "None" }
        let size = ByteCountFormatter.string(fromByteCount: reduce(0) { $0 + $1.size }, countStyle: .file)
        let number = books ? (count == 1 ? "1 book" : "\(count) books") : "\(count)"
        return "\(number) · \(size)"
    }
}
