import Foundation
import Observation
import OctavoKit
import Testing
@testable import Octavo

/// What the cover's sheet shows (decision 20).
@MainActor
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

    // The iPhone's own position wins over the server's list progress until
    // #11 reconciles them.
    @Test func progressPrefersTheSavedPosition() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BookPageTests-\(UUID().uuidString)")
        let positions = ReadingPositionStore(directory: directory)
        let page = BookPage(book: Self.book)
        #expect(page.progress(positions: positions) == 0.3)
        page.load(from: StubLibrarySource())
        #expect(await eventually { page.details != nil })
        let file = try #require(page.current.readableFile)
        try positions.save(ReadingPosition(fraction: 0.5), forBook: file.storageKey)
        #expect(page.progress(positions: positions) == 0.5)
    }

    // The strip reads the saved position again once the reader closes.
    @Test func closingTheReaderRefreshesTheProgress() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BookPageTests-\(UUID().uuidString)")
        let positions = ReadingPositionStore(directory: directory)
        let page = BookPage(book: Self.book)
        page.load(from: StubLibrarySource())
        #expect(await eventually { page.details != nil })
        let file = try #require(page.current.readableFile)
        let changed = Flag()
        withObservationTracking { _ = page.progress(positions: positions) } onChange: { changed.isSet = true }
        try positions.save(ReadingPosition(fraction: 0.5), forBook: file.storageKey)
        page.readerClosed()
        #expect(changed.isSet)
    }

    @Test func unnumberedSeries() {
        var book = Self.book
        book.series = LibrarySeriesPosition(name: "Sea Stories")
        #expect(BookPage(book: book).seriesLine == "Sea Stories")
        book.series = LibrarySeriesPosition(name: "Sea Stories", position: 2.5)
        #expect(BookPage(book: book).seriesLine == "Sea Stories · 2.5")
    }

    @Test func pagesAreKeptAcrossRedraws() {
        let pages = BookPages(limit: 2)
        let first = pages.page(for: Self.book)
        first.isExpanded = true
        #expect(pages.page(for: Self.book) === first)
    }

    @Test func oldPagesAreDropped() {
        let pages = BookPages(limit: 2)
        let first = pages.page(for: Self.book)
        for id in ["a", "b"] {
            _ = pages.page(for: LibraryBook(id: LibraryBookID(rawValue: id), title: id))
        }
        #expect(pages.page(for: Self.book) !== first)
    }
}

private final class Flag: @unchecked Sendable {
    var isSet = false
}
