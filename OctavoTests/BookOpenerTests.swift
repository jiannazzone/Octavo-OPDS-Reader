import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Opening a book downloads it first (decision 3), with progress and
/// problems on the cover's strip (decision 22).
@MainActor
struct BookOpenerTests {
    /// As a list shows it: no files until the details load.
    static let book = LibraryBook(id: LibraryBookID(rawValue: "3"), title: "Moby-Dick", authors: ["Herman Melville"])

    let files: TemporaryBookFiles
    let opener: BookOpener
    var opened: [OpenedBook] { recorder.opened }
    private let recorder = Recorder()

    init() throws {
        files = try TemporaryBookFiles()
        opener = BookOpener(files: files.store)
        opener.onOpen = { [recorder] in recorder.opened.append($0) }
    }

    @Test func downloadsThenOpens() async {
        opener.open(Self.book, from: StubLibrarySource())
        #expect(opener.status(of: Self.book) == .downloading(fraction: 0, opensWhenDone: true))
        #expect(await eventually { !opened.isEmpty })
        let book = opened[0]
        #expect(book.book.files.count == 1)
        #expect(book.reader.id == book.file.storageKey)
        #expect(book.reader.fileURL.deletingLastPathComponent().standardizedFileURL == files.directory.standardizedFileURL)
        #expect(book.reader.fileURL.pathExtension == "epub")
        #expect(opener.status(of: book.book) == .downloaded)
    }

    @Test func opensAtOnceWhenOnTheIPhone() async throws {
        let source = StubLibrarySource()
        let book = try await source.details(for: Self.book).book
        let url = try #require(files.store.url(for: source.files[0]))
        try Data("epub".utf8).write(to: url)
        opener.open(book, from: source)
        #expect(opened.map(\.reader.fileURL) == [url])
    }

    @Test func downloadAloneDoesNotOpen() async throws {
        let source = StubLibrarySource()
        let book = try await source.details(for: Self.book).book
        opener.download(book, from: source)
        #expect(opener.status(of: book) == .downloading(fraction: 0, opensWhenDone: false))
        #expect(await eventually { opener.status(of: book) == .downloaded })
        #expect(opened.isEmpty)
    }

    @Test func removingADownloadTakesTheBookOffTheIPhone() async throws {
        let source = StubLibrarySource()
        let book = try await source.details(for: Self.book).book
        opener.download(book, from: source)
        #expect(await eventually { opener.status(of: book) == .downloaded })

        opener.removeDownload(book)
        #expect(opener.status(of: book) == .notDownloaded)
        #expect(files.store.localFile(for: source.files[0]) == nil)
    }

    // Open (or an unfold) during a plain download opens it when it's done.
    @Test func openingDuringADownloadOpensWhenDone() async {
        var source = StubLibrarySource()
        source.downloadTime = .milliseconds(200)
        opener.download(Self.book, from: source)
        opener.open(Self.book, from: source)
        #expect(opener.status(of: Self.book) == .downloading(fraction: 0, opensWhenDone: true))
        #expect(await eventually { opened.count == 1 })
    }

    @Test func offlineNeedsAConnection() async {
        var source = StubLibrarySource()
        source.downloadError = URLError(.notConnectedToInternet)
        opener.open(Self.book, from: source)
        #expect(await eventually { opener.status(of: Self.book) == .failed(offline: true, opensWhenDone: true) })
        #expect(opened.isEmpty)
    }

    @Test func otherErrorsCouldntDownload() async {
        var source = StubLibrarySource()
        source.downloadError = LibraryError.server(status: 500, message: nil)
        opener.open(Self.book, from: source)
        #expect(await eventually { opener.status(of: Self.book) == .failed(offline: false, opensWhenDone: true) })
    }

    @Test func tryAgainOpens() async {
        var failing = StubLibrarySource()
        failing.downloadError = URLError(.timedOut)
        opener.open(Self.book, from: failing)
        #expect(await eventually { opener.status(of: Self.book) == .failed(offline: false, opensWhenDone: true) })
        opener.retry(Self.book, from: StubLibrarySource())
        #expect(await eventually { opened.count == 1 })
    }

    @Test func cancelLeavesNothing() async throws {
        var source = StubLibrarySource()
        source.downloadTime = .seconds(30)
        opener.open(Self.book, from: source)
        opener.cancel(Self.book)
        #expect(opener.status(of: Self.book) == .notDownloaded)
        try await Task.sleep(for: .milliseconds(100))
        #expect(opener.status(of: Self.book) == .notDownloaded)
        #expect(opened.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).isEmpty)
    }

    @Test func formatsTheReaderCantOpenDoNothing() {
        var book = Self.book
        book.files = [LibraryFile(id: LibraryFileID(rawValue: "pdf"), format: "pdf", isPrimary: true)]
        #expect(!opener.canOpen(book))
        opener.open(book, from: StubLibrarySource())
        #expect(opener.status(of: book) == .notDownloaded)
    }

    // A book that lists no files yet might have a readable one.
    @Test func unknownFilesMightOpen() {
        #expect(opener.canOpen(Self.book))
    }

    @Test(arguments: [
        (["pdf*", "epub", "mobi"], "epub"),
        (["epub", "azw3*"], "azw3"),
        (["EPUB"], "EPUB"),
        (["pdf", "cbr"], nil),
    ])
    func picksTheReadableFile(formats: [String], expected: String?) {
        var book = Self.book
        book.files = formats.enumerated().map { index, format in
            LibraryFile(id: LibraryFileID(rawValue: "\(index)"), format: format.trimmingCharacters(in: ["*"]), isPrimary: format.hasSuffix("*"))
        }
        #expect(book.readableFile?.format == expected)
    }

    // OPDS file IDs are URLs; the key must be a plain file name.
    @Test func storageKeysAreSafeFileNames() {
        let file = LibraryFile(id: LibraryFileID(rawValue: "https://example.com/opds/book/12/../../file.epub?x=/y"), format: "epub")
        #expect(file.storageKey.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(file.storageKey == LibraryFile(id: file.id).storageKey)
        #expect(file.storageKey != LibraryFile(id: LibraryFileID(rawValue: "other")).storageKey)
    }

    @MainActor
    private final class Recorder {
        var opened: [OpenedBook] = []
    }
}

/// Where downloads live: kept until removed, out of the backup.
struct StoredBookFilesTests {
    static let file = LibraryFile(id: LibraryFileID(rawValue: "file-1"), format: "epub", isPrimary: true)

    @Test func downloadsStayOutOfTheBackup() async throws {
        let files = try TemporaryBookFiles()
        let store = StoredBookFiles(directory: files.directory.appending(path: "Books", directoryHint: .isDirectory))
        _ = try await store.download(Self.file, from: StubLibrarySource()) { _ in }
        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(store.localFile(for: Self.file) != nil)
    }

    // Books from before the move (Caches) come along; one already moved wins.
    @Test func booksMoveInFromCaches() throws {
        let files = try TemporaryBookFiles()
        let old = files.directory.appending(path: "Caches-Books", directoryHint: .isDirectory)
        let store = StoredBookFiles(directory: files.directory.appending(path: "Books", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: old.appending(path: "a.epub"))
        try Data("old".utf8).write(to: old.appending(path: "b.epub"))
        try Data("new".utf8).write(to: store.directory.appending(path: "b.epub"))

        store.moveBooks(from: old)

        #expect(try String(contentsOf: store.directory.appending(path: "a.epub"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: store.directory.appending(path: "b.epub"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }
}
