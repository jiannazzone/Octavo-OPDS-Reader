import CoreGraphics
import Foundation
import OctavoKit
import SwiftUI
import Testing
@testable import Octavo

/// The spread's split at the hinge. Geometry from the iPhone Duo simulator
/// (iOS 27.1): a tab's content is 867 pt wide unfolded (382 folded) and the
/// division region is x 455.5–495.5, the full height of the screen.
struct SpreadTests {
    static let hinge = CGRect(x: 455.5, y: -82, width: 40, height: 669)

    @Test func unfoldedIsTwoPagesSplitAtTheHinge() throws {
        let pages = try #require(Spread(width: 867, divisions: [Self.hinge]).pages)
        #expect(pages.leftWidth == 455.5)
        #expect(pages.hingeWidth == 40)
        #expect(pages.rightWidth == 371.5)
    }

    @Test func foldedIsOnePage() {
        #expect(!Spread(width: 382, divisions: []).isTwoPages)
    }

    // Around a fold the region can report for the inner display while the
    // view still has the outer display's width.
    @Test func ignoresAHingePastTheView() {
        #expect(!Spread(width: 382, divisions: [Self.hinge]).isTwoPages)
    }

    // ... or turned across the view (duo-spreads §1).
    @Test func ignoresAHingeAcross() {
        let across = CGRect(x: -42, y: 373.5, width: 669, height: 40)
        #expect(!Spread(width: 867, divisions: [across]).isTwoPages)
    }

    @Test func needsRoomForAPageEachSide() {
        let nearTheEdge = CGRect(x: 120, y: 0, width: 40, height: 669)
        #expect(!Spread(width: 867, divisions: [nearTheEdge]).isTwoPages)
    }

    // Three covers folded; four on the left page and three on the right.
    @MainActor @Test func gridColumnsPerPage() {
        #expect(SpreadMetrics.columns(382) == 3)
        #expect(SpreadMetrics.columns(455.5) == 4)
        #expect(SpreadMetrics.columns(371.5) == 3)
    }

    @MainActor @Test func aListFlowsFromTheLeftPageOntoTheRight() {
        struct Item: Identifiable { var id: Int }
        let items = (1...5).map { Item(id: $0) }
        #expect(SpreadList<Item, EmptyView>.split(items, into: 2).map { $0.map(\.id) } == [[1, 2, 3], [4, 5]])
        #expect(SpreadList<Item, EmptyView>.split(items, into: 1).map { $0.map(\.id) } == [[1, 2, 3, 4, 5]])
    }
}

/// Routes into the sample library.
enum SampleRoutes {
    static func book(_ index: Int) -> SourcedBook {
        SourcedBook(source: SampleLibrarySource.id, book: SampleLibrarySource.books[index])
    }

    static func feed(_ title: String, _ link: String) -> ShellRoute {
        .feed(LibraryEntry(kind: .collection, title: title, link: LibraryLink(rawValue: link)), from: SampleLibrarySource.id)
    }

    static let collections = feed("Collections", "collections")
    static let classics = feed("Classics", "collections/classics")
}

/// A shell whose library and downloads keep their files in a temporary
/// folder, not the app's.
@MainActor
func makeShell(
    opener: BookOpener? = nil, imported: ImportedBooks? = nil,
    // Not a new install, unless a test says it is.
    tourRecord: TourRecord = .temporary(state: .played),
    importer: ((ImportedBooks) -> BookImporter)? = nil
) -> ShellModel {
    let folder = URL.testDirectory.appending(path: "ShellTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    // Never the app's own imported books.
    let imported = imported ?? ImportedBooks(directory: folder.appending(path: "Imported"))
    return ShellModel(
        library: LibraryModel(
            recents: RecentBooks(fileURL: folder.appending(path: "RecentBooks.json")),
            finished: FinishedBooks(fileURL: folder.appending(path: "FinishedBooks.json")),
            onIPhone: BooksOnIPhone(fileURL: folder.appending(path: "BooksOnIPhone.json")),
            imported: imported
        ),
        opener: opener ?? BookOpener(files: StoredBookFiles(directory: folder.appending(path: "Books"), imported: imported)),
        servers: ServerStore(fileURL: folder.appending(path: "Server.json")),
        positions: ReadingPositionStore(directory: folder.appending(path: "ReadingPositions")),
        bookmarks: BookmarkStore(directory: folder.appending(path: "Bookmarks")),
        removedServers: RemovedServerStore(fileURL: folder.appending(path: "RemovedServer.json")),
        importer: importer?(imported),
        tourRecord: tourRecord
    )
}

struct ShellPathTests {
    static let a = SampleRoutes.collections
    static let b = SampleRoutes.classics

    @Test func pushingAndPoppingMoveTheTop() {
        var path = ShellPath()
        #expect(path.top == nil)
        path.push(Self.a)
        path.push(Self.b)
        #expect(path.routes == [Self.a, Self.b])
        #expect(path.lastMove == .push)
        path.pop()
        #expect(path.top == Self.a)
        #expect(path.lastMove == .pop)
    }

    @Test func poppingTheRootDoesNothing() {
        var path = ShellPath()
        path.pop()
        path.popToRoot()
        #expect(path.routes.isEmpty)
        #expect(path.lastMove == .replace)
    }

    @Test func replacingDoesntAnimate() {
        var path = ShellPath()
        path.push(Self.a)
        path.replace([Self.b])
        #expect(path.routes == [Self.b])
        #expect(path.lastMove == .replace)
    }
}

struct HingeTransitionTests {
    @Test func closedToOpenIsAnUnfold() {
        #expect(HingeTransition(from: .closed, to: .open) == .unfold)
    }

    @Test func openToClosedIsAFold() {
        #expect(HingeTransition(from: .open, to: .closed) == .fold)
    }

    // The first callback comes from no hinge; the repeats while the hinge
    // settles don't change the status.
    @Test(arguments: [
        (HingeTransition.Fold?.none, HingeTransition.Fold?.some(.open)),
        (nil, .closed),
        (.open, .open),
        (.closed, .closed),
        (.closed, nil),
    ])
    func appearingAndRepeatsAreNothing(old: HingeTransition.Fold?, new: HingeTransition.Fold?) {
        #expect(HingeTransition(from: old, to: new) == .none)
    }
}

@MainActor
@Suite(.temporaryFiles)
struct ShellModelTests {
    static let book = SampleRoutes.book(1)

    /// A shell connected to a stub library whose downloads work.
    private func connectedShell(_ files: TemporaryBookFiles) async -> ShellModel {
        let model = makeShell(opener: BookOpener(files: files.store))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        return model
    }

    @Test func unfoldingOnADownloadedBooksScreenOpensIt() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.opener.download(Self.book.book, from: StubLibrarySource())
        #expect(await eventually { model.opener.status(of: Self.book.book) == .downloaded })
        model.select(.library)
        model[path: .library].replace([SampleRoutes.collections, .cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        #expect(model.reading?.book.id == Self.book.book.id)
    }

    // Nothing downloads until Download or Open is tapped.
    @Test func unfoldingOnABookNotOnTheIPhoneStaysOnItsScreen() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
        #expect(model.opener.status(of: Self.book.book) == .notDownloaded)
        #expect(model[path: .library].top == .cover(Self.book))
    }

    @Test func unfoldingElsewhereKeepsTheScreen() {
        let model = makeShell()
        model.select(.library)
        model[path: .library].replace([.cover(Self.book), SampleRoutes.collections])
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
        #expect(model[path: .library].routes == [.cover(Self.book), SampleRoutes.collections])
    }

    @Test func unfoldingOnARootDoesNothing() {
        let model = makeShell()
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
    }

    @Test func onlyTheSelectedTabCounts() {
        let model = makeShell()
        model[path: .library].replace([.cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
    }

    // Opened from Home, so its screen isn't on the stack yet.
    @Test func foldingWhileReadingClosesTheBookToItsScreen() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        model.hingeChanged(.fold)
        #expect(model.reading == nil)
        #expect(model[path: .home].top == .cover(Self.book))
    }

    @Test func foldingWhileReadingFromItsScreenStaysThere() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        model.hingeChanged(.fold)
        #expect(model.reading == nil)
        #expect(model[path: .library].routes == [.cover(Self.book)])
    }

    @Test func foldingWithoutABookDoesNothing() {
        let model = makeShell()
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.hingeChanged(.fold)
        model.hingeChanged(.none)
        #expect(model.reading == nil)
        #expect(model[path: .library].routes == [.cover(Self.book)])
    }

    @Test func linksPushOntoTheCurrentTab() {
        let model = makeShell()
        model.select(.library)
        model.push(SampleRoutes.collections)
        model.push(SampleRoutes.classics)
        #expect(model[path: .library].routes == [SampleRoutes.collections, SampleRoutes.classics])
        model.pop(.library)
        #expect(model[path: .library].routes == [SampleRoutes.collections])
        #expect(model[path: .home].routes.isEmpty)
    }

    @Test func choosingTheShowingTabGoesBackToItsRoot() {
        let model = makeShell()
        model.select(.library)
        model.push(SampleRoutes.collections)
        model.select(.home)
        #expect(model[path: .library].routes == [SampleRoutes.collections])
        model.select(.library)
        model.select(.library)
        #expect(model[path: .library].routes.isEmpty)
    }

    @Test func settingsOpensOnTheCurrentTab() {
        let model = makeShell()
        model.select(.library)
        model.openSettings()
        #expect(model[path: .library].top == .settings)
    }

    @Test func aBookJoinsContinueReadingOnceItOpens() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        #expect(model.library.continueReading.isEmpty)

        let alice = SampleRoutes.book(3)
        model.openBook(alice)
        #expect(await eventually { model.reading != nil })
        #expect(model.library.continueReading.map(\.id) == [alice.id])
    }

    // Recorded only once the reader has it: a failed download isn't a book
    // in progress.
    @Test func aBookThatDoesntOpenStaysOut() async {
        let model = makeShell()
        await model.library.connectSampleLibrary()
        let alice = SampleRoutes.book(3)
        model.openBook(alice)
        #expect(await eventually {
            if case .failed = model.opener.status(of: alice.book) { true } else { false }
        })
        #expect(model.library.continueReading.map(\.book.title) == ["Moby-Dick", "Frankenstein"])
    }
}
