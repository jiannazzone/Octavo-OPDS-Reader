import CoreGraphics
import Foundation
import OctavoKit
import SwiftUI
import Testing
import UIKit
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

    /// Pages as wide as the last reading, which was wider than the room
    /// (the inner display's full width, before the side column arrived):
    /// the next reading is of the room, so the pages shrink to fit it
    /// instead of holding the view at their width (duo-tabbar §7).
    @MainActor @Test func readsTheRoomNotItsPages() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let readings = SpreadReadings()
        let host = UIHostingController(rootView: PagesAsWideAsTheirReading(readings: readings))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.isHidden = false
        #expect(await eventually { readings.widths.last == 300 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(readings.widths.last == 300)
        #expect(!readings.widths.contains(500))
    }

    /// Each page at its width either side of the hinge, and a page shown
    /// folded is the same view unfolded: it isn't made again (a half-typed
    /// name would go).
    @MainActor @Test func spreadPagesSplitAtTheHingeAndKeepTheFoldedPage() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }
        window.frame = CGRect(x: 0, y: 0, width: 867, height: 669)
        let pages = PageFrames()
        let posture = Posture(spread: Spread(width: 867, pages: nil))
        let host = UIHostingController(rootView: HostedSpreadPages(frames: pages, posture: posture))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.isHidden = false
        #expect(await eventually { pages.right.last?.width == 867 })
        #expect(pages.left.isEmpty)
        #expect(pages.rightAppearances == 1)

        posture.spread = .duoUnfolded
        #expect(await eventually { pages.right.last?.minX == 495.5 })
        #expect(pages.right.last?.width == 371.5)
        #expect(pages.left.last?.minX == 0)
        #expect(pages.left.last?.width == 455.5)
        #expect(pages.rightAppearances == 1)
    }
}

@MainActor
private final class SpreadReadings {
    var widths: [CGFloat] = []
}

@MainActor
private final class PageFrames {
    var left: [CGRect] = []
    var right: [CGRect] = []
    var rightAppearances = 0
}

@MainActor @Observable
private final class Posture {
    var spread: Spread

    init(spread: Spread) {
        self.spread = spread
    }
}

private struct HostedSpreadPages: View {
    let frames: PageFrames
    let posture: Posture

    var body: some View {
        SpreadPages(alignment: .top, folded: .right) { _ in
            Color.red
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.left.append($0) }
        } right: { _ in
            Color.blue
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.right.append($0) }
                .onAppear { frames.rightAppearances += 1 }
        }
        .environment(\.spread, posture.spread)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PagesAsWideAsTheirReading: View {
    let readings: SpreadReadings
    @State private var width: CGFloat = 500

    var body: some View {
        Color.clear
            .frame(width: width, height: 10)
            .onSpreadChange { spread in
                readings.widths.append(spread.width)
                width = spread.width
            }
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
    importer: ((ImportedBooks) -> BookImporter)? = nil,
    // Never the simulator's own setting.
    defaults: UserDefaults = .closingBookWhenFolded(true)
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
        servers: ServerStore(fileURL: folder.appending(path: "Servers.json")),
        positions: ReadingPositionStore(directory: folder.appending(path: "ReadingPositions")),
        bookmarks: BookmarkStore(directory: folder.appending(path: "Bookmarks")),
        removedServers: RemovedServerStore(fileURL: folder.appending(path: "RemovedServers.json")),
        importer: importer?(imported),
        tourRecord: tourRecord,
        defaults: defaults
    )
}

extension UserDefaults {
    /// Reading settings of its own, never the app's.
    static func closingBookWhenFolded(_ closes: Bool) -> UserDefaults {
        let suite = "ShellTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(closes, forKey: ReaderSettings.closeBookWhenFoldedKey)
        return defaults
    }
}

extension Spread {
    /// The Duo's tabs, measured in the simulator (`SpreadTests`).
    static let duoUnfolded = Spread(width: 867, divisions: [SpreadTests.hinge])
    static let duoFolded = Spread(width: 382, divisions: [])
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

    // Only a route with a left page pairs up; any other is pushed, folded
    // or not, and Back takes one step.
    @Test(arguments: [false, true])
    func otherRoutesArePushed(twoPages: Bool) {
        var path = ShellPath()
        path.open(Self.a, twoPages: twoPages)
        path.open(Self.b, twoPages: twoPages)
        #expect(path.routes == [Self.a, Self.b])
        #expect(path.lastMove == .push)
        path.back(twoPages: twoPages)
        #expect(path.routes == [Self.a])
    }

    // Unfolded, the list under its page is drawn by the page, and only then.
    @Test func aLeftPageIsHiddenUnderItsPageUnfolded() {
        var path = ShellPath()
        path.push(Self.a)
        path.push(.settings)
        path.push(.settingsPage(.storage))
        // Depth 2 is the list, under its page at depth 3.
        #expect(path.isDrawnByTheOneAbove(2, twoPages: true))
        #expect(!path.isDrawnByTheOneAbove(2, twoPages: false))
        #expect(!path.isDrawnByTheOneAbove(1, twoPages: true))
        #expect(!path.isDrawnByTheOneAbove(3, twoPages: true))
        #expect(!path.isDrawnByTheOneAbove(0, twoPages: true))
        path.push(.signInAgain(SampleLibrarySource.id))
        #expect(path.isDrawnByTheOneAbove(2, twoPages: true), "a screen over the page leaves the pair as it was")
        #expect(!path.isDrawnByTheOneAbove(3, twoPages: true))
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
        model.opener.download(Self.book, from: StubLibrarySource())
        #expect(await eventually { model.opener.status(of: Self.book) == .downloaded })
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
        #expect(model.opener.status(of: Self.book) == .notDownloaded)
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

    @Test func closeBookWhenFoldedIsOnByDefault() {
        let suite = "ShellTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(ReaderSettings.closesBookWhenFolded(in: defaults))
        defaults.set(false, forKey: ReaderSettings.closeBookWhenFoldedKey)
        #expect(!ReaderSettings.closesBookWhenFolded(in: defaults))
    }

    // Close book when folded off: the book stays open at your place, on the
    // same screens, and unfolding has nothing to open.
    @Test func foldingWithCloseBookOffKeepsTheBookOpen() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store), defaults: .closingBookWhenFolded(false))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        let open = model.reading
        model.hingeChanged(.fold)
        #expect(model.reading == open)
        #expect(model[path: .library].routes == [.cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(model.reading == open)
        #expect(model.coverMotion == nil)
    }

    // A cover still opening the book was laid out for the other display.
    @Test func foldingWithCloseBookOffTakesAwayACoverStillOpening() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store), defaults: .closingBookWhenFolded(false))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        model.coverMotion = ReaderCoverMotion(
            cover: nil, title: "", author: "", coverFrame: CGRect(x: 0, y: 0, width: 10, height: 10), windowSize: CGSize(width: 20, height: 20),
            bookScreen: nil, spread: true, reduceMotion: false, paper: .white
        )
        model.hingeChanged(.fold)
        #expect(model.reading != nil)
        #expect(model.coverMotion == nil)
    }

    private func coverMotion(closing: Bool) -> ReaderCoverMotion {
        ReaderCoverMotion(
            cover: nil, title: "", author: "", coverFrame: CGRect(x: 0, y: 0, width: 10, height: 10), windowSize: CGSize(width: 20, height: 20),
            bookScreen: nil, closing: closing ? ReaderCoverPages(paper: .white) : nil, spread: true, reduceMotion: false, paper: .white
        )
    }

    // Open tapped folded, then unfolded before the cover had gone: it was
    // laid out for the outer display.
    @Test func unfoldingTakesAwayACoverStillOpening() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        model.coverMotion = coverMotion(closing: false)
        model.hingeChanged(.unfold)
        #expect(model.reading != nil)
        #expect(model.coverMotion == nil)
    }

    @Test func foldingTakesAwayACoverStillClosing() {
        let model = makeShell()
        model.coverMotion = coverMotion(closing: true)
        model.hingeChanged(.fold)
        #expect(model.coverMotion == nil)
    }

    @Test func repeatedHingeReportsLeaveTheCover() {
        let model = makeShell()
        let motion = coverMotion(closing: true)
        model.coverMotion = motion
        model.hingeChanged(.none)
        #expect(model.coverMotion === motion)
    }

    // An import, say, while a cover is still opening the book.
    @Test func closingTheReaderTakesAwayACoverStillOpening() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        model.coverMotion = coverMotion(closing: false)
        model.closeReader()
        #expect(model.reading == nil)
        #expect(model.coverMotion == nil)
    }

    // Back draws the closing cover, then the reader goes.
    @Test func closingTheReaderKeepsBacksCover() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        let closing = coverMotion(closing: true)
        model.coverMotion = closing
        model.closeReader()
        #expect(model.reading == nil)
        #expect(model.coverMotion === closing)
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
            if case .failed = model.opener.status(of: alice) { true } else { false }
        })
        #expect(model.library.continueReading.map(\.book.title) == ["Moby-Dick", "Frankenstein"])
    }
}
