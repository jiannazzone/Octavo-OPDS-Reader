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

    // No fold: two pages only in a room wide enough, held sideways (an iPad
    // in landscape), and only for a screen that asks; never an iPhone
    // turned sideways or a portrait iPad.
    @Test func withoutAFoldOnlyAWideRoomSplits() throws {
        let ipad = Spread(width: 1376, height: 1032, divisions: [])
        #expect(!ipad.isTwoPages, "shelves and lists run across")
        let pages = try #require(ipad.splitWhenWide.pages)
        #expect(pages.leftWidth == pages.rightWidth)
        #expect(pages.leftWidth + pages.hingeWidth + pages.rightWidth == 1376)
        #expect(!Spread(width: 1032, height: 1376, divisions: []).splitWhenWide.isTwoPages)
        #expect(!Spread(width: 956, height: 440, divisions: []).splitWhenWide.isTwoPages)
        #expect(!Spread(width: 1376, divisions: []).splitWhenWide.isTwoPages, "no height: a measurement without one stays one page")
    }

    // The Duo: a screen that splits when wide splits exactly as the fold
    // does, in every posture, and never down the middle of a room.
    @Test func onTheDuoTheFoldDecides() {
        let open = Spread(width: 867, height: 760, divisions: [Self.hinge])
        #expect(open.splitWhenWide == open)
        #expect(open.widePages == nil)
        let folded = Spread(width: 382, height: 760, divisions: [])
        #expect(folded.splitWhenWide == folded)
        let sideways = Spread(width: 1100, height: 700, divisions: [CGRect(x: 0, y: 330, width: 1100, height: 40)])
        #expect(!sideways.splitWhenWide.isTwoPages, "a fold across the room: one page, as before")
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
        let pages = PageFrames()
        let posture = Posture(spread: Spread(width: 867, pages: nil))
        let window = try host(HostedSpreadPages(frames: pages, posture: posture))
        defer { window.isHidden = true }
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

    /// A page shown folded is given the screen's width, and none before the
    /// spread has been measured (0 pt, `Spread.onePage`).
    @MainActor @Test func aFoldedPageIsGivenAWidthOnlyOnceMeasured() async throws {
        let pages = PageFrames()
        let posture = Posture(spread: .onePage)
        let window = try host(HostedSpreadPages(frames: pages, posture: posture))
        defer { window.isHidden = true }
        #expect(await eventually { pages.rightWidths.contains(nil) })
        posture.spread = .duoFolded
        #expect(await eventually { pages.rightWidths.last == 382 })
        #expect(!pages.rightWidths.contains(0))
    }

    /// Unfolded, a title or banner keeps to the left page; folded, the page.
    @MainActor @Test func onLeftPageKeepsToTheLeftPage() async throws {
        let frames = PageFrames()
        let posture = Posture(spread: .duoUnfolded)
        let window = try host(HostedLeftPage(frames: frames, posture: posture))
        defer { window.isHidden = true }
        #expect(await eventually { frames.left.last?.width == 455.5 })
        #expect(frames.left.last?.minX == 0)
        posture.spread = Spread(width: 867, pages: nil)
        #expect(await eventually { frames.left.last?.width == 867 })
    }

    /// `view` in a window of the Duo's tab width, with no safe areas.
    @MainActor private func host(_ view: some View) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 867, height: 669)
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        window.rootViewController = host
        window.isHidden = false
        return window
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
    /// What the right page's closure was given.
    var rightWidths: [CGFloat?] = []
}

private struct HostedLeftPage: View {
    let frames: PageFrames
    let posture: Posture

    var body: some View {
        Color.red
            .frame(height: 10)
            .onLeftPage()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.left.append($0) }
            .environment(\.spread, posture.spread)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
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
        } right: { width in
            Color.blue
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.right.append($0) }
                .onAppear {
                    frames.rightAppearances += 1
                    frames.rightWidths.append(width)
                }
                .onChange(of: width) { _, width in frames.rightWidths.append(width) }
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
        path.pop()
        #expect(path.top == Self.a)
    }

    @Test func poppingTheRootDoesNothing() {
        var path = ShellPath()
        path.pop()
        path.popToRoot()
        #expect(path.routes.isEmpty)
    }

    // The pick is the right column's first screen; what's pushed goes over it.
    @Test func aPickReplacesWhatTheRightColumnShowed() {
        var path = ShellPath()
        path.pick(Self.a)
        path.push(Self.b)
        #expect(path.pick == Self.a)
        #expect(path.pushed == [Self.b])
        path.pick(Self.b)
        #expect(path.routes == [Self.b])
        path.pick(nil)
        #expect(path.routes.isEmpty)
    }

    // Back or a swipe in the right column keeps the pick under it.
    @Test func theRightColumnsStackKeepsThePick() {
        var path = ShellPath()
        path.pick(Self.a)
        path.setPushed([Self.b, .cover(SampleRoutes.book(3))])
        #expect(path.routes == [Self.a, Self.b, .cover(SampleRoutes.book(3))])
        path.setPushed([])
        #expect(path.routes == [Self.a])
        var none = ShellPath()
        none.setPushed([Self.b])
        #expect(none.routes.isEmpty, "nothing pushes without a pick")
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
        #expect(await eventually { model.reader.reading != nil })
        #expect(model.reader.reading?.book.id == Self.book.book.id)
    }

    // Not under Settings' sheet.
    @Test func unfoldingUnderSettingsOpensNothing() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.opener.download(Self.book, from: StubLibrarySource())
        #expect(await eventually { model.opener.status(of: Self.book) == .downloaded })
        model.select(.library)
        model.pick(.cover(Self.book), in: .library)
        model.openSettings()
        model.hingeChanged(.unfold)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.reader.reading == nil)
    }

    // Nothing downloads until Download or Open is tapped.
    @Test func unfoldingOnABookNotOnTheIPhoneStaysOnItsScreen() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(model.reader.reading == nil)
        #expect(model.opener.status(of: Self.book) == .notDownloaded)
        #expect(model[path: .library].top == .cover(Self.book))
    }

    @Test func unfoldingElsewhereKeepsTheScreen() {
        let model = makeShell()
        model.select(.library)
        model[path: .library].replace([.cover(Self.book), SampleRoutes.collections])
        model.hingeChanged(.unfold)
        #expect(model.reader.reading == nil)
        #expect(model[path: .library].routes == [.cover(Self.book), SampleRoutes.collections])
    }

    @Test func unfoldingOnARootDoesNothing() {
        let model = makeShell()
        model.hingeChanged(.unfold)
        #expect(model.reader.reading == nil)
    }

    @Test func onlyTheSelectedTabCounts() {
        let model = makeShell()
        model[path: .library].replace([.cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(model.reader.reading == nil)
    }

    // Opened from Home, so its screen isn't on the stack yet.
    @Test func foldingWhileReadingClosesTheBookToItsScreen() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.reader.open(Self.book)
        #expect(await eventually { model.reader.reading != nil })
        model.hingeChanged(.fold)
        #expect(model.reader.reading == nil)
        #expect(model[path: .home].top == .cover(Self.book))
    }

    @Test func foldingWhileReadingFromItsScreenStaysThere() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.reader.open(Self.book)
        #expect(await eventually { model.reader.reading != nil })
        model.hingeChanged(.fold)
        #expect(model.reader.reading == nil)
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
        model.reader.open(Self.book)
        #expect(await eventually { model.reader.reading != nil })
        let open = model.reader.reading
        model.hingeChanged(.fold)
        #expect(model.reader.reading == open)
        #expect(model[path: .library].routes == [.cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(model.reader.reading == open)
        #expect(model.reader.coverMotion == nil)
    }

    // A cover still opening the book was laid out for the other display.
    @Test func foldingWithCloseBookOffTakesAwayACoverStillOpening() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store), defaults: .closingBookWhenFolded(false))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        model.reader.open(Self.book)
        #expect(await eventually { model.reader.reading != nil })
        model.reader.coverMotion = ReaderCoverMotion(
            cover: nil, title: "", author: "", coverFrame: CGRect(x: 0, y: 0, width: 10, height: 10), windowSize: CGSize(width: 20, height: 20),
            bookScreen: nil, spread: true, reduceMotion: false, paper: .white
        )
        model.hingeChanged(.fold)
        #expect(model.reader.reading != nil)
        #expect(model.reader.coverMotion == nil)
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
        model.reader.open(Self.book)
        #expect(await eventually { model.reader.reading != nil })
        model.reader.coverMotion = coverMotion(closing: false)
        model.hingeChanged(.unfold)
        #expect(model.reader.reading != nil)
        #expect(model.reader.coverMotion == nil)
    }

    @Test func foldingTakesAwayACoverStillClosing() {
        let model = makeShell()
        model.reader.coverMotion = coverMotion(closing: true)
        model.hingeChanged(.fold)
        #expect(model.reader.coverMotion == nil)
    }

    @Test func repeatedHingeReportsLeaveTheCover() {
        let model = makeShell()
        let motion = coverMotion(closing: true)
        model.reader.coverMotion = motion
        model.hingeChanged(.none)
        #expect(model.reader.coverMotion === motion)
    }

    // An import, say, while a cover is still opening the book.
    @Test func closingTheReaderTakesAwayACoverStillOpening() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.reader.open(Self.book)
        #expect(await eventually { model.reader.reading != nil })
        model.reader.coverMotion = coverMotion(closing: false)
        model.reader.close()
        #expect(model.reader.reading == nil)
        #expect(model.reader.coverMotion == nil)
    }

    // Back draws the closing cover, then the reader goes.
    @Test func closingTheReaderKeepsBacksCover() async throws {
        let files = try TemporaryBookFiles()
        let model = await connectedShell(files)
        model.reader.open(Self.book)
        #expect(await eventually { model.reader.reading != nil })
        let closing = coverMotion(closing: true)
        model.reader.coverMotion = closing
        model.reader.close()
        #expect(model.reader.reading == nil)
        #expect(model.reader.coverMotion === closing)
    }

    @Test func foldingWithoutABookDoesNothing() {
        let model = makeShell()
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.hingeChanged(.fold)
        model.hingeChanged(.none)
        #expect(model.reader.reading == nil)
        #expect(model[path: .library].routes == [.cover(Self.book)])
    }

    @Test func linksPushOntoTheCurrentTab() {
        let model = makeShell()
        model.select(.library)
        model.push(SampleRoutes.collections)
        model.push(SampleRoutes.classics)
        #expect(model[path: .library].routes == [SampleRoutes.collections, SampleRoutes.classics])
        model.back()
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

    @Test func settingsOpensOverTheCurrentTab() {
        let model = makeShell()
        model.select(.library)
        model.openSettings()
        #expect(model.showsSettings)
        #expect(model.tab == .library)
        #expect(model[path: .library].routes.isEmpty)
    }

    @Test func aBookJoinsContinueReadingOnceItOpens() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        #expect(model.library.continueReading.isEmpty)

        let alice = SampleRoutes.book(3)
        model.reader.open(alice)
        #expect(await eventually { model.reader.reading != nil })
        #expect(model.library.continueReading.map(\.id) == [alice.id])
    }

    // Recorded only once the reader has it: a failed download isn't a book
    // in progress.
    @Test func aBookThatDoesntOpenStaysOut() async {
        let model = makeShell()
        await model.library.connectSampleLibrary()
        let alice = SampleRoutes.book(3)
        model.reader.open(alice)
        #expect(await eventually {
            if case .failed = model.opener.status(of: alice) { true } else { false }
        })
        #expect(model.library.continueReading.map(\.book.title) == ["Moby-Dick", "Frankenstein"])
    }
}
