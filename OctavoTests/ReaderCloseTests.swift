import Foundation
import OctavoKit
import Testing
import WebKit
@testable import Octavo

/// A closed reader goes away, with its page and that page's web process
/// (`docs/notes/reader-release.md`). These pages are never shown, so they draw
/// no frames, like a closed reader's.
@MainActor
@Suite(.temporaryFiles)
struct ReaderCloseTests {
    private let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private let bookmarkStore = BookmarkStore(
        directory: URL.testDirectory.appending(path: "bookmarks-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private let bookID = "closing"

    private func reader(sync: (any ProgressSync)? = nil) throws -> ReaderModel {
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let book = ReaderBook(fileURL: directory.appending(path: "closing.epub"), id: bookID)
        try BookInspectorTests.epub(opf: "<dc:title>Closing</dc:title>").write(to: book.fileURL)
        return ReaderModel(book: book, store: store, sync: sync, bookmarks: ReaderBookmarks(bookID: book.id, store: bookmarkStore))
    }

    // A new layout waits for a frame. That call used to keep the model, the
    // page and the web process for good.
    @Test func goesAwayWithACallWaitingForAFrame() async throws {
        weak var closedModel: ReaderModel?
        weak var closedPage: WebPage?
        do {
            let model = try reader()
            closedModel = model
            closedPage = model.page
            #expect(await eventually(timeout: .seconds(30)) { model.phase == .open && model.relocation != nil })
            var layout = model.layout
            layout.rightInset += 10
            model.override(layout)
            await model.close()
        }
        #expect(await eventually(timeout: .seconds(10)) { closedModel == nil && closedPage == nil })
    }

    // Leaving the window gives the page another size for a moment, and a page
    // laid out for that isn't where the reader was.
    @Test func takesNothingMoreFromThePage() async throws {
        let model = try reader()
        model.handle(.opened(.init(restoredFrom: "start", sectionCount: 1, isFixedLayout: false)))
        model.handle(.relocate(.init(cfi: "epubcfi(/6/4!/4/2/1:0)", fraction: 0.1)))
        model.geometryChanged(ReaderGeometry(size: CGSize(width: 466, height: 678)))
        let position = model.position
        let geometry = model.geometry
        await model.close()

        model.handle(.viewport(width: 1024, height: 768))
        model.handle(.relocate(.init(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.4)))
        model.handle(.opened(.init(restoredFrom: "start", sectionCount: 1, isFixedLayout: false)))

        #expect(model.phase == .closed)
        #expect(model.geometry == geometry)
        #expect(model.position == position)
        #expect(store.position(forBook: bookID) == position)
    }

    @Test func opensNothingAfterClosingWhileAskingTheServer() async throws {
        let sync = FakeProgressSync()
        await sync.hold()
        let model = try reader(sync: sync)
        #expect(await eventuallyAwaiting(timeout: .seconds(30)) { await sync.pulls == 1 })
        await model.close()
        await sync.release()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.openingPosition == nil)
        #expect(model.phase == .closed)
    }
}
