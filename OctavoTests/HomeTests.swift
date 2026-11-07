import OctavoKit
import Testing
@testable import Octavo

/// Home unfolded (`docs/design/direction.md`, Home).
@MainActor struct HomeTests {
    // About what the right page has for rows on the Duo.
    private let room: CGFloat = 560

    @Test func rowsGrowToFillThePage() {
        let seven = AlsoReadingPage.coverHeight(rows: 7, gap: 10, room: room)
        let three = AlsoReadingPage.coverHeight(rows: 3, gap: 16, room: room)
        #expect(seven == ContinueReadingRow.standardCoverHeight)
        #expect(three > seven)
        #expect(3 * (three + 16) <= room)
    }

    @Test func rowsStopAtTheirTallest() {
        #expect(AlsoReadingPage.coverHeight(rows: 1, gap: 16, room: room) == ContinueReadingRow.tallestCoverHeight)
    }

    // Larger text can leave less room than the rows need: the page scrolls.
    @Test func rowsKeepTheirSmallestSizeWithoutRoom() {
        #expect(AlsoReadingPage.coverHeight(rows: 7, gap: 10, room: 100) == ContinueReadingRow.standardCoverHeight)
    }

    // Unfolded, the book has the left page, so Home has a title only over an
    // invitation.
    @Test func homeShowsBooksOnlyWithBooksInProgress() async {
        let nothing = makeShell().library
        #expect(!nothing.homeShowsBooks)
        await nothing.connectSampleLibrary(nothingInProgress: true)
        #expect(!nothing.homeShowsBooks)

        let reading = makeShell().library
        await reading.connectSampleLibrary()
        #expect(reading.homeShowsBooks)
    }

    // The shelf beside your books leaves them out, and with nothing else to
    // show the page says so instead.
    @Test func aShelfHasNoCoversOnceItsBooksAreHidden() async throws {
        let source = SampleLibrarySource.id
        let feed = FeedModel(link: LibraryLink(rawValue: "recent"), source: source, library: SampleLibrarySource()) { _ in }
        #expect(LibraryShelf.hasCovers(feed, from: source))
        await feed.load()
        let books = feed.books.map { SourcedBook(source: source, book: $0) }
        #expect(LibraryShelf.hasCovers(feed, from: source))
        #expect(LibraryShelf.hasCovers(feed, from: source, hiding: Set(books.dropFirst().map(\.id))))
        #expect(!LibraryShelf.hasCovers(feed, from: source, hiding: Set(books.map(\.id))))
    }
}
