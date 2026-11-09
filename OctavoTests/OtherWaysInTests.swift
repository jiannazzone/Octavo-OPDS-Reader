import Foundation
import ImageIO
import OctavoKit
import SwiftUI
import Testing
@testable import Octavo

// Step 15, Other ways in: Import from Files, the sample book and On iPhone
// (`docs/notes/other-ways-in.md`).

/// Book files to import: the bundled sample book (a real EPUB), a Kindle
/// file with its DRM field set, and text that only says it's an EPUB.
nonisolated enum ImportFixtures {
    static func folder() throws -> URL {
        let folder = URL.testDirectory.appending(path: "ImportFixtures-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func epub(named name: String = "Some Book.epub", in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        try FileManager.default.copyItem(at: #require(SampleBook.bundledFile), to: url)
        return url
    }

    /// A PalmDB `BOOKMOBI` whose record 0 says it's encrypted.
    static func drmMobi(named name: String = "Kindred.mobi", in folder: URL) throws -> URL {
        var bytes = [UInt8](repeating: 0, count: 78 + 8 + 40)
        bytes.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        bytes[77] = 1 // one record
        bytes[81] = 86 // at 86
        bytes[86 + 13] = 2 // encryption type 2
        bytes.replaceSubrange((86 + 16)..<(86 + 20), with: Array("MOBI".utf8))
        let url = folder.appending(path: name)
        try Data(bytes).write(to: url)
        return url
    }

    static func notABook(named name: String = "Notes.epub", in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        try Data("just some notes".utf8).write(to: url)
        return url
    }

    /// Details as foliate would read them, without a web page.
    static func inspect(title: String? = "Persuasion") -> (URL) async throws -> BookFileDetails {
        let cover = SampleBook.bundledCover.flatMap { try? Data(contentsOf: $0) }
        return { _ in BookFileDetails(format: .epub, title: title, authors: ["Jane Austen"], description: "A novel.", cover: cover) }
    }
}

@MainActor
@Suite(.temporaryFiles)
struct BookImporterTests {
    let folder: URL
    let store: ImportedBooks

    init() throws {
        folder = try ImportFixtures.folder()
        store = .temporary()
    }

    @Test func importsABookWithItsDetailsAndCover() async throws {
        let importer = BookImporter(store: store, inspect: ImportFixtures.inspect())
        let book = try await importer.importFile(at: ImportFixtures.epub(in: folder)).get()
        #expect(book.title == "Persuasion")
        #expect(book.authors == ["Jane Austen"])
        #expect(book.id.rawValue.hasPrefix("import-"))
        #expect(book.primaryFile?.format == "epub")
        #expect(book.primaryFile?.filename == "Some Book.epub")
        let file = try #require(book.primaryFile)
        #expect(store.localFile(for: file) != nil)
        #expect(store.details(for: book.id)?.description == "A novel.")
        #expect(book.cover != nil)
        #expect(UIImage(data: try Data(contentsOf: store.coverURL(for: book.id))) != nil)
        // The original stays where it was; nothing is left on the way in.
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Some Book.epub").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.incomingDirectory().path).isEmpty)
    }

    // The same bytes are the same book: it moves first, not in twice.
    @Test func theSameFileTwiceIsOneBook() async throws {
        let importer = BookImporter(store: store, inspect: ImportFixtures.inspect())
        let first = try await importer.importFile(at: ImportFixtures.epub(named: "A.epub", in: folder)).get()
        _ = try await importer.importFile(at: ImportFixtures.epub(named: "B.epub", in: folder)).get()
        #expect(store.all().count == 1)
        let again = try await importer.importFile(at: folder.appending(path: "A.epub")).get()
        #expect(again.id == first.id)
        #expect(store.all().map(\.book.id) == [first.id])
    }

    @Test func aBookWithoutATitleGoesByItsFileName() async throws {
        let importer = BookImporter(store: store, inspect: ImportFixtures.inspect(title: nil))
        let book = try await importer.importFile(at: ImportFixtures.epub(named: "Kindred.fb2.zip.epub", in: folder)).get()
        #expect(book.title == "Kindred")
        #expect(BookImporter.title(fromFileName: "Notes.fb2.zip") == "Notes")
        #expect(BookImporter.title(fromFileName: ".epub") == ".epub")
    }

    @Test func aKindleFileWithDRMIsRefused() async throws {
        let importer = BookImporter(store: store, inspect: ImportFixtures.inspect())
        let result = try await importer.importFile(at: ImportFixtures.drmMobi(in: folder))
        #expect(result == .failure(ImportFailure(fileName: "Kindred.mobi", reason: .drmProtected)))
        #expect(store.all().isEmpty)
    }

    @Test func aFileThatIsntABookIsRefused() async throws {
        let importer = BookImporter(store: store, inspect: ImportFixtures.inspect())
        let result = try await importer.importFile(at: ImportFixtures.notABook(in: folder))
        #expect(result == .failure(ImportFailure(fileName: "Notes.epub", reason: .notABook)))
    }

    // foliate couldn't read it: damaged, and nothing is kept.
    @Test func aBookFoliateCantReadIsDamaged() async throws {
        let importer = BookImporter(store: store) { _ in throw BookInspectionError.damaged }
        let result = try await importer.importFile(at: ImportFixtures.epub(in: folder))
        #expect(result == .failure(ImportFailure(fileName: "Some Book.epub", reason: .damaged)))
        #expect(store.all().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.incomingDirectory().path).isEmpty)
    }

    // No answer in time reads the same to the person importing, for now.
    @Test func aReadThatTimesOutSaysDamaged() async throws {
        let importer = BookImporter(store: store) { _ in throw BookInspectionError.timedOut }
        let result = try await importer.importFile(at: ImportFixtures.epub(in: folder))
        #expect(result == .failure(ImportFailure(fileName: "Some Book.epub", reason: .damaged)))
        #expect(store.all().isEmpty)
    }

    @Test func failuresSayWhy() {
        let drm = ImportFailure(fileName: "Kindred.azw3", reason: .drmProtected)
        let pdf = ImportFailure(fileName: "Taxes 2025.pdf", reason: .notABook)
        #expect(drm.message == "“Kindred.azw3” is protected with DRM, which Octavo can’t open.")
        #expect(ImportFailure.summary([drm]) == drm.message)
        #expect(ImportFailure.summary([drm, pdf]) == "2 files weren’t imported. \(drm.message) \(pdf.message)")
        #expect(ImportFailure.summary([]) == nil)
    }
}

/// From the security review of the import path (2026-11-02).
@MainActor
@Suite(.temporaryFiles)
struct ImportHardeningTests {
    // A title can't put line breaks or direction overrides into the
    // removal question.
    @Test func bookTextIsOneSafeLine() {
        #expect(ImportText.line("X\u{201D} from this iPhone?\nYour book stays.\u{202E}evomeR", limit: 300) == "X\u{201D} from this iPhone? Your book stays.evomeR")
        #expect(ImportText.line("  \u{0007}\t ", limit: 10) == nil)
        #expect(ImportText.line(String(repeating: "a", count: 400), limit: 300)?.count == 300)
        #expect(ImportText.paragraphs("One\n\n\n\u{202D}Two\u{0000}\n", limit: 100) == "One\n\nTwo")
    }

    @Test func detailsAreCleanedAndCapped() {
        let details = BookImporter.cleaned(BookFileDetails(
            format: .epub, title: "A\nB", authors: Array(repeating: "Ann", count: 30) + ["\u{202E}"],
            description: String(repeating: "word ", count: 10_000)
        ))
        #expect(details.title == "A B")
        #expect(details.authors.count == 20)
        #expect((details.description?.count ?? 0) <= 20_000)
    }

    // A cover is stored at most 1,600 pixels a side; one that won't decode
    // is dropped.
    @Test func coversAreDownsampled() async throws {
        let context = try #require(CGContext(
            data: nil, width: 4000, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4000, height: 100))
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let cover = try #require(await BookImporter.coverImage(png as Data))
        let image = try #require(UIImage(data: cover))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= 1600)
        #expect(await BookImporter.coverImage(Data("not an image".utf8)) == nil)
    }

    @Test func aLinkIsntImported() async throws {
        let folder = try ImportFixtures.folder()
        let book = try ImportFixtures.epub(in: folder)
        let link = folder.appending(path: "Link.epub")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: book)
        let importer = BookImporter(store: .temporary(), inspect: ImportFixtures.inspect())
        #expect(await importer.importFile(at: link) == .failure(ImportFailure(fileName: "Link.epub", reason: .notABook)))
    }

    // A comic slipped in after the first check is refused by its copy's format.
    @Test func onlyV1FormatsComeIn() async throws {
        let folder = try ImportFixtures.folder()
        let importer = BookImporter(store: .temporary()) { _ in BookFileDetails(format: .cbz, title: "Comic") }
        #expect(await importer.importFile(at: try ImportFixtures.epub(in: folder)) == .failure(ImportFailure(fileName: "Some Book.epub", reason: .notABook)))
    }

    // An unreadable list is never replaced by one with only the new book.
    @Test func anUnreadableListIsntOverwritten() async throws {
        let store = ImportedBooks.temporary()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let list = store.directory.appending(path: "Books.json")
        try Data("not json".utf8).write(to: list)
        let importer = BookImporter(store: store, inspect: ImportFixtures.inspect())
        let result = await importer.importFile(at: try ImportFixtures.epub(in: try ImportFixtures.folder()))
        #expect(result == .failure(ImportFailure(fileName: "Some Book.epub", reason: .damaged)))
        #expect(try Data(contentsOf: list) == Data("not json".utf8))
    }

    // On a device the inbox is `/var/…` or `/private/var/…`; only a file
    // directly in an inbox is deleted after its import.
    @Test func inboxFilesAreRecognisedWithLinksResolved() throws {
        let root = try ImportFixtures.folder()
        let inbox = root.appending(path: "Inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let alias = root.appending(path: "alias", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        #expect(ShellModel.isInInbox(inbox.appending(path: "a.epub"), inboxes: [inbox]))
        #expect(ShellModel.isInInbox(alias.appending(path: "Inbox/a.epub"), inboxes: [inbox]))
        #expect(!ShellModel.isInInbox(root.appending(path: "a.epub"), inboxes: [inbox]))
        #expect(!ShellModel.isInInbox(inbox.appending(path: "sub/a.epub"), inboxes: [inbox]))
        #expect(!ShellModel.isInInbox(inbox.appending(path: "../a.epub"), inboxes: [inbox]))
    }

    @Test func oldInboxCopiesGoAtLaunch() throws {
        let inbox = try ImportFixtures.folder()
        let old = inbox.appending(path: "old.epub"), new = inbox.appending(path: "new.epub")
        for file in [old, new] { try Data("x".utf8).write(to: file) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: old.path)
        ShellModel.clearOldInboxFiles(inboxes: [inbox])
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: new.path))
    }
}

@MainActor
@Suite(.temporaryFiles)
struct ImportedBooksTests {
    @Test func removingABookTakesItsFileAndCoverOnly() throws {
        let store = ImportedBooks.temporary()
        let folder = try ImportFixtures.folder()
        for id in ["import-a", "import-b"] {
            let file = LibraryFile(id: LibraryFileID(rawValue: id), format: "epub", isPrimary: true)
            let book = LibraryBook(id: LibraryBookID(rawValue: id), title: id, files: [file])
            let incoming = folder.appending(path: "\(id).epub")
            try Data("epub".utf8).write(to: incoming)
            try store.add(LibraryBookDetails(book: book), file: incoming, cover: Data([1]))
        }
        #expect(store.all().map(\.book.id.rawValue) == ["import-b", "import-a"])
        try store.moveFirst(LibraryBookID(rawValue: "import-a"))
        #expect(store.all().map(\.book.id.rawValue) == ["import-a", "import-b"])
        try store.remove(LibraryBookID(rawValue: "import-a"))
        #expect(store.all().map(\.book.id.rawValue) == ["import-b"])
        let gone = LibraryFile(id: LibraryFileID(rawValue: "import-a"), format: "epub")
        #expect(store.localFile(for: gone) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.coverURL(for: LibraryBookID(rawValue: "import-a")).path))
        #expect(store.localFile(for: LibraryFile(id: LibraryFileID(rawValue: "import-b"), format: "epub")) != nil)
    }

    // The reader opens an imported book from its own folder, but only the
    // store removes it: never Remove download or Remove all downloads.
    @Test func downloadsDontTouchImportedBooks() throws {
        let files = try TemporaryBookFiles()
        let folder = try ImportFixtures.folder()
        let file = LibraryFile(id: LibraryFileID(rawValue: "import-c"), format: "epub", isPrimary: true)
        let incoming = folder.appending(path: "c.epub")
        try Data("epub".utf8).write(to: incoming)
        try files.store.imported.add(LibraryBookDetails(book: LibraryBook(id: LibraryBookID(rawValue: "import-c"), title: "C", files: [file])), file: incoming, cover: nil)
        #expect(files.store.localFile(for: file, in: .files) != nil)
        try files.store.remove(file, in: .files)
        try files.store.removeAll(keeping: [])
        #expect(files.store.localFile(for: file, in: .files) != nil)
    }
}

@MainActor
@Suite(.temporaryFiles)
struct OtherWaysInShellTests {
    let folder: URL

    init() throws {
        folder = try ImportFixtures.folder()
    }

    private func shell() -> ShellModel {
        makeShell { BookImporter(store: $0, inspect: ImportFixtures.inspect()) }
    }

    // No server: the Library is the iPhone's books, so it opens at its top.
    @Test func anImportLeavesSetupForTheLibrary() async throws {
        let model = shell()
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        #expect(!model.needsSetup)
        #expect(model.tab == .library)
        #expect(model[path: .library].routes.isEmpty)
        #expect(model.onIPhoneBooks().map(\.book.title) == ["Persuasion"])
        #expect(model.importFailures.isEmpty)
        #expect(model.library.continueReading.isEmpty)
    }

    // Nothing came in on the first screen: setup says why under its choices.
    @Test func nothingImportedStaysOnSetupWithTheReason() async throws {
        let model = shell()
        await model.importBooks([try ImportFixtures.drmMobi(in: folder)])
        #expect(model.needsSetup)
        #expect(model.setupImportFailures == [ImportFailure(fileName: "Kindred.mobi", reason: .drmProtected)])
        #expect(model.importFailures.isEmpty)
    }

    // With a server, an import lands on On iPhone over the Library, newest
    // first, with a banner for what didn't come in.
    @Test func withAServerAnImportLandsOnOnIPhone() async throws {
        let model = shell()
        await model.library.connect(RemoveServerTests.bookOrbit(id: LibrarySourceID(rawValue: "import-server"), account: "octavo"))
        await model.importBooks([try ImportFixtures.epub(in: folder), try ImportFixtures.notABook(in: folder)])
        #expect(model.tab == .library)
        #expect(model[path: .library].routes == [.onIPhone])
        #expect(model.importFailures == [ImportFailure(fileName: "Notes.epub", reason: .notABook)])
        #expect(model.onIPhoneBooks().first?.book.title == "Persuasion")
    }

    // Nothing came in: no move to On iPhone; the Library's top screen
    // shows why (Adam, 2026-11-02).
    @Test func aFailedImportStaysOnTheLibrary() async throws {
        let model = shell()
        await model.library.connect(RemoveServerTests.bookOrbit(id: LibrarySourceID(rawValue: "fail-server"), account: "octavo"))
        model.select(.home)
        await model.importBooks([try ImportFixtures.drmMobi(in: folder)])
        #expect(model.tab == .library)
        #expect(model[path: .library].routes.isEmpty)
        #expect(model.importFailures == [ImportFailure(fileName: "Kindred.mobi", reason: .drmProtected)])
    }

    @Test func removingTheLastImportedBookGoesBackToSetup() async throws {
        let model = shell()
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        let book = try #require(model.onIPhoneBooks().first)
        model.push(.cover(book))
        try model.library.recents.record(book)
        model.removeImported(book)
        #expect(model.library.imported.all().isEmpty)
        #expect(model.onIPhoneBooks().isEmpty)
        #expect(model.library.recents.records().isEmpty)
        #expect(model.needsSetup)
        #expect(!model[path: .library].routes.contains(.cover(book)))
    }

    // Settings' Add a server goes into Settings, and so do the steps after
    // it.
    @Test func addingAServerLaterStaysInSettings() async throws {
        let model = shell()
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        model.openSettings()
        model.pick(.setup(.choose), in: .settings)
        model.setup.push(.bookOrbit)
        #expect(model[path: .settings].routes == [.setup(.choose), .setup(.bookOrbit)])
        #expect(model[path: .setup].routes.isEmpty)
        #expect(model[path: .library].routes.isEmpty)
        model.setup.pop()
        #expect(model[path: .settings].routes == [.setup(.choose)])
    }

    // Remove all downloads and Remove server leave imported books and the
    // sample book (decision 24).
    @Test func removingDownloadsOrTheServerKeepsImportedBooks() async throws {
        let model = shell()
        await model.library.connect(RemoveServerTests.bookOrbit(id: LibrarySourceID(rawValue: "keep-server"), account: "octavo"))
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        model.installSampleBook()
        model.opener.removeAllDownloads()
        #expect(Set(model.onIPhoneBooks().map(\.book.title)) == ["Persuasion", "Pride and Prejudice"])
        await model.serverActions.remove(LibrarySourceID(rawValue: "keep-server"), removingBooks: true)
        #expect(Set(model.onIPhoneBooks().map(\.book.title)) == ["Persuasion", "Pride and Prejudice"])
        #expect(model.downloads(on: LibrarySourceID(rawValue: "keep-server")).isEmpty)
        // Books are still on the iPhone: the Library, not setup.
        #expect(!model.needsSetup)
    }

    @Test func importedBooksSearchWithoutAServer() async throws {
        let model = shell()
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        #expect(model.library.iPhoneBooks().map(\.book.title) == ["Persuasion"])
        let found = try await model.library.importedSource.search("persua")
        #expect(found.books.books.map(\.title) == ["Persuasion"])
    }
}

@MainActor
struct SpreadGridTests {
    struct Item: Identifiable, Equatable { let id: Int }

    // Across a fold the rows can be asked for with the other spread's
    // indices: what isn't there is nothing, not a trap.
    @Test func goneIndicesAreNoItems() {
        let rows = [[Item(id: 1), Item(id: 2), Item(id: 3)], [Item(id: 4)]]
        #expect(SpreadGrid<Item, EmptyView>.items(in: rows, row: 0, page: 0, counts: [3]) == rows[0])
        #expect(SpreadGrid<Item, EmptyView>.items(in: rows, row: 2, page: 0, counts: [3]).isEmpty)
        #expect(SpreadGrid<Item, EmptyView>.items(in: rows, row: 0, page: 1, counts: [3]).isEmpty)
        #expect(SpreadGrid<Item, EmptyView>.items(in: rows, row: 0, page: 1, counts: [2, 2]) == [Item(id: 3)])
    }
}
