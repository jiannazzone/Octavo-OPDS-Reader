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
                let order = BookOrder.title(a.book.book).localizedStandardCompare(BookOrder.title(b.book.book))
                if order != .orderedSame { return order == .orderedAscending }
            case .author:
                let order = BookOrder.author(a.book.book).localizedStandardCompare(BookOrder.author(b.book.book))
                if order != .orderedSame { return order == .orderedAscending }
            case .downloaded:
                if a.downloadedAt != b.downloadedAt { return a.downloadedAt > b.downloadedAt }
            }
            return a.book.book.title.localizedStandardCompare(b.book.book.title) == .orderedAscending
        }
    }
}

/// Title and author order for books sorted on the iPhone: Books on iPhone's
/// and On iPhone's, and an OPDS list's (#131).
nonisolated enum BookOrder {
    static func title(_ book: LibraryBook) -> String {
        book.title
    }

    /// Filed by last name, as the Authors list is.
    static func author(_ book: LibraryBook) -> String {
        book.authors.first.map(AuthorIndex.sortKey(name:)) ?? ""
    }

    /// `books` by title, or by author then title. Any other sort leaves them
    /// in the list's order.
    static func sorted(_ books: [LibraryBook], by sort: LibrarySort) -> [LibraryBook] {
        let key: (LibraryBook) -> String
        switch sort {
        case .title: key = title
        case .author: key = author
        case .listOrder, .readingOrder, .recentlyAdded: return books
        }
        // Each key once: 2,000 books compare about 22,000 times.
        return books.map { (key: key($0), title: $0.title, book: $0) }
            .sorted { a, b in
                let order = a.key.localizedStandardCompare(b.key)
                return order == .orderedSame ? a.title.localizedStandardCompare(b.title) == .orderedAscending : order == .orderedAscending
            }
            .map(\.book)
    }
}

extension BookOpener {
    /// The books with a file on the iPhone, from `library`'s records: each
    /// one the iPhone downloaded, or opened before it kept that list, once.
    func downloads(listedIn library: LibraryModel) -> [DownloadedBook] {
        var seen = Set<String>()
        let records = library.onIPhone.books() + library.recents.records().map(\.book)
        return records.compactMap { record in
            guard let url = localFile(for: record),
                  seen.insert(url.lastPathComponent).inserted
            else { return nil }
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .creationDateKey])
            let size = values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
            return DownloadedBook(book: record, url: url, size: Int64(size), downloadedAt: values?.creationDate ?? .distantPast)
        }
    }

    /// What Remove server counts as `server`'s downloads.
    func downloads(on server: LibrarySourceID, listedIn library: LibraryModel) -> [DownloadedBook] {
        downloads(listedIn: library).filter { $0.book.source == server }
    }
}

extension ShellModel {
    /// The books with a file on the iPhone (`BookOpener.downloads(listedIn:)`).
    func downloads() -> [DownloadedBook] {
        opener.downloads(listedIn: library)
    }

    /// What Remove server counts as `server`'s downloads.
    func downloads(on server: LibrarySourceID) -> [DownloadedBook] {
        opener.downloads(on: server, listedIn: library)
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
