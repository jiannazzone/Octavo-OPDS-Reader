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
        (BookOpenButton.State.unsupported(format: "pdf"), false, String?("Octavo can’t open PDF files.")),
        (BookOpenButton.State.unsupported(format: "DJVU"), false, String?("Octavo can’t open DJVU files.")),
        (BookOpenButton.State.unsupported(format: nil), false, String?("Octavo can’t open this book’s files.")),
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

    // MARK: Read status (#120)

    @Test func aStatusGoesToTheServer() async {
        let marks = FinishedMarks()
        var book = Self.book
        book.readStatus = .read
        book.isFinished = true
        let page = BookPage(book: book)

        await page.setStatus(.onHold, from: StubLibrarySource(finishedMarks: marks, keepsStatus: true))
        #expect(marks.statuses == [.onHold])
        #expect(page.readStatus == .onHold)
        #expect(!page.isFinished)
    }

    @Test func aStatusTheServerRefusesIsTakenBack() async {
        let marks = FinishedMarks()
        marks.refuses = true
        var book = Self.book
        book.readStatus = .reading
        let page = BookPage(book: book)

        await page.setStatus(.abandoned, from: StubLibrarySource(finishedMarks: marks, keepsStatus: true))
        #expect(page.readStatus == .reading)
        #expect(page.statusFailed)
        #expect(BookPlace.problem(.download, finishedFailed: false, statusFailed: true) == "Couldn’t change the status. Check your connection.")
    }

    // BookOrbit's not finished is `reading`.
    @Test func markingFinishedSetsTheStatusToo() async {
        let marks = FinishedMarks()
        var book = Self.book
        book.readStatus = .onHold
        let page = BookPage(book: book)
        let source = StubLibrarySource(finishedMarks: marks, keepsStatus: true)

        await page.setFinished(true, from: source)
        #expect(page.readStatus == .read)
        await page.setFinished(false, from: source)
        #expect(page.readStatus == .reading)
        #expect(marks.sent == [true, false])
    }

    /// (status, progress, the place line)
    nonisolated static let placeLines: [(LibraryReadStatus?, Double?, String)] = [
        (nil, 0.3, "30%"),
        (.reading, 0.3, "30%"),
        (.unread, nil, "Not started"),
        (.wantToRead, nil, "Want to read"),
        (.wantToRead, 0.12, "Want to read · 12%"),
        (.onHold, 0.5, "On hold · 50%"),
        (.onHold, 0, "On hold"),
        (.skimmed, 0.5, "Skimmed · 50%"),
        (.abandoned, 0.5, "Abandoned · 50%"),
    ]

    @Test(arguments: placeLines)
    func thePlaceLineNamesAStatusThePlaceWouldMisstate(status: LibraryReadStatus?, progress: Double?, line: String) {
        #expect(BookPlace(progress: progress, problem: nil, status: nil, finished: false, readStatus: status).text == line)
    }

    // Folded, a status takes the sync's room (Adam, 2026-11-13).
    @Test func theFoldedLineDropsTheSyncForAStatus() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let synced = BookPlaces.Status.synced(now)
        #expect(BookPlace(progress: 0.5, problem: nil, status: synced, finished: false, readStatus: .onHold).line(now: now) == "On hold · 50%")
        #expect(BookPlace(progress: 0.5, problem: nil, status: synced, finished: false, readStatus: .reading).line(now: now) == "50% · Synced just now")
        #expect(BookPlace(progress: 0.5, problem: nil, status: .notSynced, finished: false, readStatus: .onHold).line(now: now) == "On hold · 50% · Not synced yet, will retry")
    }

    @Test func moreTicksTheStatusAsTheMenuNamesIt() {
        #expect(LibraryReadStatus.ticked(nil) == .unread)
        #expect(LibraryReadStatus.ticked(.rereading) == .reading)
        #expect(LibraryReadStatus.ticked(.read) == nil)
        #expect(LibraryReadStatus.menu.map(\.title) == ["Reading", "Want to read", "On hold", "Skimmed", "Abandoned", "Unread"])
    }

    // MARK: Rating (#120)

    /// A page on a server that keeps ratings, its details in, so "Rate it"
    /// can ask.
    private func ratingPage(rating: Int? = nil, marks: FinishedMarks, keepsRating: Bool = true) async -> (BookPage, StubLibrarySource) {
        var book = Self.book
        book.rating = rating
        let source = StubLibrarySource(finishedMarks: marks, keepsStatus: true, keepsRating: keepsRating)
        let page = BookPage(book: book)
        page.load(from: source)
        _ = await eventually { page.details != nil }
        return (page, source)
    }

    @Test func aRatingGoesToTheServer() async {
        let marks = FinishedMarks()
        let (page, source) = await ratingPage(marks: marks)

        await page.setRating(4, from: source)
        #expect(marks.ratings == [4])
        #expect(page.rating == 4)
        await page.setRating(nil, from: source)
        #expect(marks.ratings == [4, nil])
        #expect(page.rating == nil)
    }

    @Test func aRatingTheServerRefusesIsTakenBack() async {
        let marks = FinishedMarks()
        let (page, source) = await ratingPage(rating: 2, marks: marks)
        marks.refuses = true

        await page.setRating(5, from: source)
        #expect(page.rating == 2)
        #expect(page.ratingFailed)
        #expect(BookPlace.problem(.download, finishedFailed: false, ratingFailed: true) == "Couldn’t change the rating. Check your connection.")
    }

    @Test func anotherChangeClearsARatingProblem() async {
        let marks = FinishedMarks()
        let (page, source) = await ratingPage(marks: marks)
        marks.refuses = true
        await page.setRating(5, from: source)
        marks.refuses = false

        await page.setStatus(.onHold, from: source)
        #expect(!page.ratingFailed)
    }

    // Tap 5, then 3: the server took 3, and 5 being refused afterwards
    // doesn't put the book back to unrated.
    @Test func onlyTheLatestRatingPutsThingsBack() async {
        let marks = FinishedMarks()
        let (page, source) = await ratingPage(marks: marks)
        marks.holdsRatings = true

        let five = Task { await page.setRating(5, from: source) }
        #expect(await eventually { marks.isHolding(5) })
        let three = Task { await page.setRating(3, from: source) }
        #expect(await eventually { marks.isHolding(3) })
        marks.release(3, refusing: false)
        await three.value
        marks.release(5, refusing: true)
        await five.value

        #expect(page.rating == 3)
        #expect(!page.ratingFailed)
    }

    // Tap 5, then 3: 3 is refused, then 5 lands, so the server has 5.
    @Test func anEarlierRatingThatLandsLaterShows() async {
        let marks = FinishedMarks()
        let (page, source) = await ratingPage(marks: marks)
        marks.holdsRatings = true

        let five = Task { await page.setRating(5, from: source) }
        #expect(await eventually { marks.isHolding(5) })
        let three = Task { await page.setRating(3, from: source) }
        #expect(await eventually { marks.isHolding(3) })
        marks.release(3, refusing: true)
        await three.value
        #expect(page.rating == nil)
        marks.release(5, refusing: false)
        await five.value

        #expect(page.rating == 5)
        #expect(page.ratingFailed)
    }

    /// (the status set, whether "Rate it" asks)
    nonisolated static let asksAfter: [(LibraryReadStatus, Bool)] = [
        (.read, true), (.skimmed, true), (.abandoned, true),
        (.reading, false), (.onHold, false), (.wantToRead, false), (.unread, false),
    ]

    @Test(arguments: asksAfter)
    func rateItAsksWhenAReadingEnds(status: LibraryReadStatus, asks: Bool) async {
        let (page, source) = await ratingPage(marks: FinishedMarks())
        await page.setStatus(status, from: source)
        #expect(page.asksRating == asks)
    }

    @Test func markingFinishedAsksAndAStarAnswers() async {
        let (page, source) = await ratingPage(marks: FinishedMarks())

        await page.setFinished(true, from: source)
        #expect(page.asksRating)
        await page.setRating(4, from: source)
        #expect(!page.asksRating)
        #expect(page.rating == 4)
    }

    @Test func takingFinishedBackStopsAsking() async {
        let (page, source) = await ratingPage(marks: FinishedMarks())
        await page.setFinished(true, from: source)
        await page.setFinished(false, from: source)
        #expect(!page.asksRating)
    }

    @Test func notNowStopsAsking() async {
        let (page, source) = await ratingPage(marks: FinishedMarks())
        await page.setFinished(true, from: source)
        page.dismissRatingPrompt()
        #expect(!page.asksRating)
    }

    @Test func aRefusedAnswerAsksAgain() async {
        let marks = FinishedMarks()
        let (page, source) = await ratingPage(marks: marks)
        await page.setFinished(true, from: source)
        marks.refuses = true

        await page.setRating(4, from: source)
        #expect(page.asksRating)
        #expect(page.ratingFailed)
    }

    @Test func rateItDoesntAskForARatedBook() async {
        let (page, source) = await ratingPage(rating: 3, marks: FinishedMarks())
        await page.setFinished(true, from: source)
        #expect(!page.asksRating)
    }

    // The list's rating can be older than the server's.
    @Test func rateItWaitsForTheDetails() async {
        let page = BookPage(book: Self.book)
        await page.setFinished(true, from: StubLibrarySource(finishedMarks: FinishedMarks(), keepsStatus: true, keepsRating: true))
        #expect(!page.asksRating)
    }

    @Test func rateItAsksOnlyWhereRatingsAreKept() async {
        let (page, source) = await ratingPage(marks: FinishedMarks(), keepsRating: false)
        await page.setFinished(true, from: source)
        #expect(!page.asksRating)
    }

    @Test func starsAreSpokenAsCounts() {
        #expect(BookRateButton.choices == [5, 4, 3, 2, 1])
        #expect(BookRateButton.stars(4) == "★★★★")
        #expect(BookRateButton.spoken(1) == "1 star")
        #expect(BookRateButton.spoken(4) == "4 stars")
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
