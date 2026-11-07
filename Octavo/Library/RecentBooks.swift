import Foundation
import OctavoKit

/// The books opened on this iPhone, newest first: Home's half of Continue
/// reading that doesn't come from the server. One small JSON file, written
/// atomically.
nonisolated struct RecentBooks: Sendable {
    struct Record: Codable, Hashable, Sendable {
        var book: SourcedBook
        var openedAt: Date
    }

    let fileURL: URL
    /// Older records drop off.
    static let limit = 20

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "RecentBooks.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
    }

    func records() -> [Record] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    /// Forgets `book`, such as one marked finished.
    func remove(_ book: SourcedBook.ID) throws {
        let kept = records().filter { $0.book.id != book }
        guard kept.count != records().count else { return }
        try JSONEncoder().encode(kept).write(to: fileURL, options: .atomic)
    }

    /// Forgets every book from `source` (Remove server).
    func remove(source: LibrarySourceID) throws {
        let kept = records().filter { $0.book.source != source }
        guard kept.count != records().count else { return }
        try JSONEncoder().encode(kept).write(to: fileURL, options: .atomic)
    }

    /// Brings the records in `marks` up to date, so a cover shows them after
    /// the next launch too.
    func update(finished marks: [SourcedBook.ID: Bool]) throws {
        let records = records()
        let updated = records.map { Record(book: $0.book.withFinished(from: marks), openedAt: $0.openedAt) }
        guard updated != records else { return }
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
    }

    /// Puts `book` first, replacing an older record of it.
    func record(_ book: SourcedBook, at date: Date = .now) throws {
        let kept = records().filter { $0.book.id != book.id }
        let records = [Record(book: book, openedAt: date)] + kept.prefix(Self.limit - 1)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
    }
}

/// Home's Continue reading: the server's list and the iPhone's, one row per
/// book, most recently read first.
nonisolated enum ContinueReading {
    /// Up to `limit` books. A book in both lists takes the server's details
    /// (its progress is newer) and the later of the two dates; books without
    /// a date keep their order, after the dated ones.
    static func merge(server: [SourcedBook], iPhone: [RecentBooks.Record], limit: Int = 5) -> [SourcedBook] {
        var rows: [SourcedBook.ID: (book: SourcedBook, date: Date?, order: Int)] = [:]
        for (order, book) in server.enumerated() where rows[book.id] == nil {
            rows[book.id] = (book, book.book.lastReadAt, order)
        }
        for (offset, record) in iPhone.enumerated() {
            let id = record.book.id
            if let row = rows[id] {
                rows[id]?.date = max(row.date ?? .distantPast, record.openedAt)
            } else {
                rows[id] = (record.book, record.openedAt, server.count + offset)
            }
        }
        return rows.values
            .sorted { a, b in
                let (dateA, dateB) = (a.date ?? .distantPast, b.date ?? .distantPast)
                return dateA != dateB ? dateA > dateB : a.order < b.order
            }
            .prefix(limit)
            .map(\.book)
    }
}
