import Foundation
import Observation
import OctavoKit
import Testing
@testable import Octavo

/// What the cover's sheet shows (decision 20).
@MainActor
@Suite(.temporaryFiles)
struct BookPageTests {
    static let book = LibraryBook(id: LibraryBookID(rawValue: "3"), title: "Moby-Dick", authors: ["Herman Melville"], progress: 0.3)

    @Test func loadsTheDetails() async {
        let page = BookPage(book: Self.book)
        page.load(from: StubLibrarySource())
        #expect(await eventually { page.coverFinished })
        #expect(page.serverName == "Stub server")
        #expect(page.plainDescription == "Call me Ishmael.")
        #expect(page.seriesLine == "Sea Stories · 3")
        #expect(page.collectionsLine == "Classics · Spike")
        #expect(page.fileLine == "EPUB · 1.2 MB")
        #expect(page.addedLine != nil)
        #expect(page.cover == nil)
    }

    @Test func beforeTheDetailsLoad() {
        let page = BookPage(book: Self.book)
        #expect(page.plainDescription == nil)
        #expect(page.seriesLine == nil)
        #expect(page.collectionsLine == nil)
        #expect(page.fileLine == nil)
        #expect(page.authorLine == "Herman Melville")
    }

    @Test func emptyDescriptionsAreNone() async {
        var source = StubLibrarySource()
        source.description = "<p> </p>"
        let page = BookPage(book: Self.book)
        page.load(from: source)
        #expect(await eventually { page.details != nil })
        #expect(page.plainDescription == nil)
    }

    @Test(arguments: [
        (Double?.none, "Not started"),
        (0, "Not started"),
        (0.3, "30%"),
    ])
    func placeLine(progress: Double?, expected: String) {
        #expect(BookPage.placeLine(progress: progress) == expected)
    }

    // The folded sheet's second row (Adam, 2026-11-03): the place and when
    // it synced on one line.
    @Test func sheetPlaceLine() {
        let now = Date(timeIntervalSince1970: 1_793_700_000)
        let synced = BookPlace(progress: 0.48, problem: nil, status: .synced(now), finished: false)
        #expect(synced.line(now: now) == "48% · Synced just now")
        let unsent = BookPlace(progress: 0.48, problem: nil, status: .notSynced, finished: false)
        #expect(unsent.line(now: now) == "48% · Not synced yet, will retry")
        // Away from your place: where the book opens, in place of the sync.
        var trip = ReaderTrip(place: ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.48))
        trip.landed(on: ReadingPosition(cfi: "epubcfi(/6/30!/4/2)", fraction: 0.9), fraction: 0.9)
        #expect(BookPlace(progress: 0.48, problem: nil, status: .synced(now), trip: trip, finished: false).line(now: now) == "48% · Opens at 90%")
        #expect(BookPlace(progress: 0.48, problem: nil, status: .synced(now), trip: trip, finished: true).line(now: now) == "Finished")
        // An OPDS book doesn't sync: the place alone.
        #expect(BookPlace(progress: nil, problem: nil, status: nil, finished: false).line(now: now) == "Not started")
    }

    // Finished and problems leave out the sync, and finished fills the bar.
    @Test func sheetPlaceLineLeavesOutTheSync() {
        let now = Date(timeIntervalSince1970: 1_793_700_000)
        let finished = BookPlace(progress: 0.48, problem: nil, status: .synced(now), finished: true)
        #expect(finished.line(now: now) == "Finished")
        #expect(finished.progress == 1)
        let failed = BookPlace(progress: 0.48, problem: "Needs a connection to download.", status: .synced(now), finished: false)
        #expect(failed.line(now: now) == "Needs a connection to download.")
        #expect(failed.progress == 0.48)
    }

    @Test(arguments: [
        (BookOpenButton.State.failed(offline: true), false, String?("Needs a connection to download.")),
        (.failed(offline: false), false, "Couldn’t download. Check your connection."),
        (.protected, false, "This file is DRM-protected and cannot be opened."),
        (.open, true, "Couldn’t mark it finished. Check your connection."),
        (.downloading(fraction: 0.4), false, nil),
        (.open, false, nil),
    ])
    func sheetProblems(state: BookOpenButton.State, finishedFailed: Bool, expected: String?) {
        #expect(BookPlace.problem(state, finishedFailed: finishedFailed) == expected)
    }

    @Test func unnumberedSeries() {
        var book = Self.book
        book.series = LibrarySeriesPosition(name: "Sea Stories")
        #expect(BookPage(book: book).seriesLine == "Sea Stories")
        book.series = LibrarySeriesPosition(name: "Sea Stories", position: 2.5)
        #expect(BookPage(book: book).seriesLine == "Sea Stories · 2.5")
    }

    // MARK: Mark finished

    private static func finishedBooks() -> FinishedBooks {
        FinishedBooks(fileURL: URL.testDirectory.appending(path: "FinishedBooks-\(UUID().uuidString).json"))
    }

    private static let id = SourcedBook.ID(source: LibrarySourceID(rawValue: "server"), book: book.id)

    @Test func finishedStaysOnTheIPhoneWhenTheServerDoesntKeepIt() async {
        let books = Self.finishedBooks()
        let page = BookPage(book: Self.book)
        page.keepFinished(in: books, as: Self.id)
        #expect(!page.isFinished)

        await page.setFinished(true, from: StubLibrarySource())
        #expect(page.isFinished)
        let later = BookPage(book: Self.book)
        later.keepFinished(in: books, as: Self.id)
        #expect(later.isFinished)

        await later.setFinished(false, from: StubLibrarySource())
        #expect(!books.contains(Self.id))
    }

    @Test func finishedGoesToAServerThatKeepsIt() async {
        let books = Self.finishedBooks()
        let marks = FinishedMarks()
        let page = BookPage(book: Self.book)
        page.keepFinished(in: books, as: Self.id)

        await page.setFinished(true, from: StubLibrarySource(finishedMarks: marks))
        #expect(page.isFinished)
        #expect(marks.sent == [true])
        #expect(!books.contains(Self.id))
    }

    @Test func aMarkTheServerRefusesIsTakenBack() async {
        let marks = FinishedMarks()
        marks.refuses = true
        let page = BookPage(book: Self.book)

        await page.setFinished(true, from: StubLibrarySource(finishedMarks: marks))
        #expect(!page.isFinished)
        #expect(page.finishedFailed)
    }

    @Test func showsTheServersMark() {
        var book = Self.book
        book.isFinished = true
        #expect(BookPage(book: book).isFinished)
    }

    // Open is Download until the book is on the iPhone.
    @Test func openIsDownloadUntilTheBookIsOnTheIPhone() async throws {
        let files = try TemporaryBookFiles()
        let shell = makeShell(opener: BookOpener(files: files.store))
        let book = SampleRoutes.book(1).book
        #expect(BookOpenButton.state(of: .test(book), in: shell) == .download)
        shell.opener.download(.test(book), from: StubLibrarySource())
        #expect(await eventually { BookOpenButton.state(of: .test(book), in: shell) == .open })
    }

    @Test func pagesAreKeptAcrossRedraws() {
        let pages = BookPages(limit: 2)
        let first = pages.page(for: .test(Self.book))
        first.isExpanded = true
        #expect(pages.page(for: .test(Self.book)) === first)
    }

    @Test func oldPagesAreDropped() {
        let pages = BookPages(limit: 2)
        let first = pages.page(for: .test(Self.book))
        for id in ["a", "b"] {
            _ = pages.page(for: .test(LibraryBook(id: LibraryBookID(rawValue: id), title: id)))
        }
        #expect(pages.page(for: .test(Self.book)) !== first)
    }
}
