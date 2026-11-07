import Foundation
import OctavoKit
import SwiftUI
import Testing
import UIKit
@testable import Octavo

/// Leafing through to your place: how many leaves, when they move, when they
/// play at all, and that none of it touches the reader's place.
struct ReaderLeavesTimingTests {
    // MARK: How many

    @Test(arguments: [
        (0.0, 2), (0.1, 2), (0.16, 2), (0.17, 3), (0.49, 3), (0.5, 4), (0.83, 4), (0.84, 5), (1.0, 5),
    ])
    func moreLeavesTheFurtherIn(progress: Double, count: Int) {
        #expect(ReaderLeaves.count(progress: progress) == count)
    }

    @Test func aProgressOutOfRangeStaysInRange() {
        #expect(ReaderLeaves.count(progress: -1) == 2)
        #expect(ReaderLeaves.count(progress: 2) == 5)
    }

    // MARK: When they play

    @Test func onlyPastPageOne() {
        #expect(!ReaderLeaves.play(fraction: 0, pageTurn: .automatic, reduceMotion: false))
        #expect(ReaderLeaves.play(fraction: 0.001, pageTurn: .automatic, reduceMotion: false))
    }

    @Test(arguments: [ReaderPageTurn.automatic, .slide, .flip, .fade, .none])
    func neverWithReduceMotion(pageTurn: ReaderPageTurn) {
        #expect(!ReaderLeaves.play(fraction: 0.5, pageTurn: pageTurn, reduceMotion: true))
    }

    @Test func notWithPageTurnOnFadeOrNone() {
        #expect(!ReaderLeaves.play(fraction: 0.5, pageTurn: .fade, reduceMotion: false))
        #expect(!ReaderLeaves.play(fraction: 0.5, pageTurn: .none, reduceMotion: false))
        for pageTurn in [ReaderPageTurn.automatic, .slide, .flip] {
            #expect(ReaderLeaves.play(fraction: 0.5, pageTurn: pageTurn, reduceMotion: false))
        }
    }

    // MARK: When they move

    @Test func openTheyFollowTheCoversSwing() {
        let two = ReaderLeaves(count: 2, spread: true, followsCover: true)
        let five = ReaderLeaves(count: 5, spread: true, followsCover: true)
        #expect(abs(two.start(of: 0) - 0.2) < 0.001)
        #expect(abs(two.start(of: 1) - 0.27) < 0.001)
        #expect(abs(two.end - 0.57) < 0.001)
        #expect(abs(five.end - 0.78) < 0.001)
    }

    @Test func foldedTheySwingOffTheEdge() {
        let leaves = ReaderLeaves(count: 3, spread: false, followsCover: true)
        #expect(abs(leaves.start(of: 0) - 0.1) < 0.001)
        #expect(abs(leaves.start(of: 2) - 0.24) < 0.001)
        #expect(abs(leaves.end - 0.39) < 0.001)
        #expect(leaves.angle(of: 0, at: 0.1) == 0)
        #expect(leaves.angle(of: 0, at: 0.25) == 90)
        // Ease-in: slower than the clock to begin with.
        #expect(leaves.angle(of: 0, at: 0.175) < 45)
    }

    @Test func aFlipIsEdgeOnHalfWay() {
        let leaves = ReaderLeaves(count: 2, spread: true, followsCover: true)
        #expect(leaves.angle(of: 0, at: 0.2) == 0)
        #expect(abs(leaves.angle(of: 0, at: 0.35) - 90) < 0.5)
        #expect(leaves.angle(of: 0, at: 0.5) == 180)
        // Ease-in-out: still slow a quarter of the way in.
        #expect(leaves.angle(of: 0, at: 0.275) < 45)
    }

    @Test func aloneTheyStartAtOnce() {
        let leaves = ReaderLeaves(count: 3, spread: true, followsCover: false)
        #expect(leaves.start(of: 0) == 0)
        #expect(abs(leaves.end - 0.44) < 0.001)
    }

    @Test func onlyWhatCanBeSeenIsDrawn() {
        let open = ReaderLeaves(count: 3, spread: true, followsCover: true)
        #expect(open.shown(at: 0) == 0..<1)
        #expect(open.shown(at: 0.28) == 0..<3)
        #expect(open.shown(at: 0.8) == 2..<3)
        let folded = ReaderLeaves(count: 3, spread: false, followsCover: true)
        #expect(folded.shown(at: 0) == 0..<1)
        #expect(folded.shown(at: 0.5).isEmpty)
    }

    // MARK: The lines

    @Test func theLinesStayInTheTextsPlace() throws {
        let size = CGSize(width: 951, height: 669)
        let hinge = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let layout = ReaderLayout.spread(in: ReaderGeometry(size: size, safeArea: ReaderInsets(top: 0, left: 0, bottom: 21, right: 84)), fold: hinge, margins: .medium)
        let columns = try #require(layout.textColumns(inReaderWidth: 951))
        let lines = ReaderLeafLines.path(layout: layout, size: size, pitch: 20, seed: 0)
        let box = lines.boundingRect
        #expect(box.minX >= columns[0].lowerBound)
        #expect(box.maxX <= columns[1].upperBound + 0.001)
        #expect(box.minY >= ReaderLayout.verticalMargin)
        #expect(box.maxY <= 669 - 21 - ReaderLayout.verticalMargin)
        // Nothing on the hinge.
        #expect(!lines.contains(CGPoint(x: hinge.midX, y: 300)))
        #expect(lines != ReaderLeafLines.path(layout: layout, size: size, pitch: 20, seed: 1))
    }
}

@MainActor
struct ReaderLeavesMotionTests {
    private static let window = CGSize(width: 951, height: 669)
    private static let layout = ReaderLayout.spread(in: ReaderGeometry(size: window), fold: CGRect(x: 455.5, y: 0, width: 40, height: 669), margins: .medium)

    private func opening(spread: Bool = true, reduceMotion: Bool = false, pageTurn: ReaderPageTurn = .automatic) -> ReaderCoverMotion {
        ReaderCoverMotion(
            cover: nil, title: "", author: "", coverFrame: CGRect(x: 0, y: 0, width: 455, height: 669), windowSize: Self.window,
            bookScreen: nil, spread: spread, reduceMotion: reduceMotion, paper: .white, pageTurn: pageTurn
        )
    }

    private func pages(fraction: Double, spread: Bool = true) -> ReaderCoverPages {
        let picture = ReaderSnapshot(view: UIView(), frame: .zero)
        return ReaderCoverPages(
            left: spread ? picture : nil, right: spread ? picture : nil, whole: spread ? nil : picture,
            spine: spread ? 475.5 : nil, paper: .white, fraction: fraction, layout: Self.layout
        )
    }

    @Test func aBookPastPageOneLeavesThrough() {
        let motion = opening()
        motion.readerOpened(pages(fraction: 0.5))
        #expect(motion.leaves?.count == 4)
        #expect(motion.leaves?.followsCover == true)
        #expect(motion.leaves?.spread == true)
    }

    @Test func aBookOnPageOneDoesnt() {
        let motion = opening()
        motion.readerOpened(pages(fraction: 0))
        #expect(motion.leaves == nil)
    }

    @Test func noLeavesWithReduceMotion() {
        let motion = opening(reduceMotion: true)
        motion.readerOpened(pages(fraction: 0.5))
        #expect(motion.leaves == nil)
    }

    @Test(arguments: [ReaderPageTurn.fade, .none])
    func noLeavesWithThesePageTurns(pageTurn: ReaderPageTurn) {
        let motion = opening(pageTurn: pageTurn)
        motion.readerOpened(pages(fraction: 0.5))
        #expect(motion.leaves == nil)
    }

    @Test func noLeavesOnClosing() {
        let motion = ReaderCoverMotion(
            cover: nil, title: "", author: "", coverFrame: CGRect(x: 0, y: 0, width: 455, height: 669), windowSize: Self.window,
            bookScreen: nil, closing: pages(fraction: 0.5), spread: true, reduceMotion: false, paper: .white
        )
        motion.readerOpened(pages(fraction: 0.5))
        #expect(motion.leaves == nil)
    }

    @Test func foldedTheCoverStillSwingsAtItsOwnPace() {
        let motion = opening(spread: false)
        motion.readerOpened(pages(fraction: 0.5, spread: false))
        #expect(motion.leaves?.spread == false)
        motion.advance(by: motion.swingDuration)
        #expect(abs(motion.swing - motion.swungOver) < 0.001)
    }

    // A reader with one page where the book's screen has two has no spine to
    // leaf over.
    @Test func noLeavesWithoutASpine() {
        let motion = opening()
        motion.readerOpened(pages(fraction: 0.5, spread: false))
        #expect(motion.leaves == nil)
    }

    @Test func itEndsWhenTheLastLeafHasLanded() {
        let motion = opening(spread: false)
        var finished = false
        motion.onFinished = { finished = true }
        motion.readerOpened(pages(fraction: 0.5, spread: false))
        let end = motion.leaves?.end ?? 0
        finished = false
        motion.advance(by: end - 0.01)
        #expect(!finished)
        motion.advance(by: 0.02)
        #expect(finished)
    }

    // MARK: Waiting for the reader

    // Folded the cover has no slide to finish first, so a reader that opened
    // before the motion started still has it swing.
    @Test func foldedItSwingsWhenTheReaderWasFirst() {
        let motion = opening(spread: false)
        motion.readerOpened(pages(fraction: 0, spread: false))
        motion.start()
        #expect(motion.swing == motion.swungOver)
        #expect(!motion.showsBookScreen)
    }

    @Test func withReduceMotionItFadesWhenTheReaderWasFirst() {
        let motion = opening(reduceMotion: true)
        motion.readerOpened(pages(fraction: 0))
        motion.start()
        #expect(motion.fade == 1)
    }

    // It takes every touch, so it can't wait for good.
    @Test func itFadesIfTheReaderNeverOpens() async {
        let motion = opening()
        motion.longestWait = .milliseconds(20)
        motion.start()
        #expect(await eventually { motion.fade == 1 })
    }

    @Test func aReaderThatOpenedIsntCutShort() async throws {
        let motion = opening()
        motion.longestWait = .milliseconds(20)
        motion.readerOpened(pages(fraction: 0.5))
        motion.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(motion.fade == 0)
    }

    @Test func takenAwayItIgnoresTheReader() {
        let motion = opening()
        motion.cancel()
        motion.readerOpened(pages(fraction: 0.5))
        motion.start()
        #expect(motion.leaves == nil)
        #expect(motion.slide == 0)
        #expect(motion.fade == 0)
    }

    // MARK: Unfolding on a cover

    private func unfolding(progress: Double = 0.5) -> ReaderCoverMotion {
        ReaderCoverMotion(unfoldingAt: progress, windowSize: Self.window, paper: .white, leafStyle: ReaderLeafStyle())
    }

    @Test func unfoldingItsTheLeavesAlone() {
        let motion = unfolding()
        #expect(motion.leavesOnly)
        #expect(motion.leaves?.count == 4)
        #expect(motion.leaves?.followsCover == false)
        #expect(motion.leaves?.start(of: 0) == 0)
    }

    // The others land; the last rests until there's a page for its back.
    @Test func theLastLeafWaitsForYourPage() throws {
        let motion = unfolding()
        var finished = false
        motion.onFinished = { finished = true }
        for _ in 0..<120 { motion.advance(by: 1.0 / 60) }
        #expect(!finished)
        let leaves = try #require(motion.leaves)
        #expect(leaves.angle(of: 0, at: motion.clock) == 180)
        #expect(leaves.angle(of: 2, at: motion.clock) == 180)
        #expect(leaves.angle(of: 3, at: motion.clock) == 0)
        #expect(motion.showsWaiting)

        motion.readerOpened(pages(fraction: 0.5))
        #expect(!motion.showsWaiting)
        motion.advance(by: 0.1)
        #expect(!finished)
        #expect(try #require(motion.leaves).angle(of: 3, at: motion.clock) > 0)
        motion.advance(by: 0.21)
        #expect(finished)
    }

    @Test func aQuickPageWaitsForNothing() throws {
        let motion = unfolding()
        motion.readerOpened(pages(fraction: 0.5))
        motion.advance(by: 0.1)
        #expect(motion.leaves?.lastLeafWait == 0)
        #expect(!motion.showsWaiting)
    }

    // There's no cover to move, and starting one would have the leaves play
    // twice at once.
    @Test func startingItLeavesTheLeavesToTheWindow() {
        let motion = unfolding()
        motion.start()
        #expect(motion.slide == 0)
        #expect(motion.clock == 0)
    }

    // Turned on its side, the Duo unfolds onto one page.
    @Test func onePageEndsItAtOnce() {
        let motion = unfolding()
        var finished = false
        motion.onFinished = { finished = true }
        motion.readerOpened(pages(fraction: 0.5, spread: false))
        #expect(finished)
    }
}

@MainActor
@Suite(.temporaryFiles)
struct ReaderLeavesShellTests {
    // A book with no place on the server's list.
    private static let book = SampleRoutes.book(3)
    private static var key: String { book.book.readableFile?.storageKey(in: book.source) ?? "" }

    private func unfoldedShell(place: ReadingPosition?, pageTurn: ReaderPageTurn = .automatic) async throws -> ShellModel {
        let files = try TemporaryBookFiles()
        let defaults = UserDefaults.closingBookWhenFolded(true)
        defaults.set(pageTurn.rawValue, forKey: ReaderPageTurn.key)
        let model = makeShell(opener: BookOpener(files: files.store), defaults: defaults)
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        model.opener.download(Self.book, from: StubLibrarySource())
        #expect(await eventually { model.opener.status(of: Self.book) == .downloaded })
        if let place { try model.places.store.save(place, forBook: Self.key) }
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        return model
    }

    @Test func unfoldingPastPageOnePlaysTheLeaves() async throws {
        let model = try await unfoldedShell(place: ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.5))
        #expect(model.coverMotion?.leavesOnly == true)
        #expect(model.coverMotion?.leaves?.count == 4)
    }

    @Test func unfoldingOnANewBookHasNone() async throws {
        let model = try await unfoldedShell(place: nil)
        #expect(model.coverMotion == nil)
    }

    @Test func unfoldingOnPageOneHasNone() async throws {
        let model = try await unfoldedShell(place: ReadingPosition(cfi: "epubcfi(/6/2!/4/2)", fraction: 0))
        #expect(model.coverMotion == nil)
    }

    @Test(arguments: [ReaderPageTurn.fade, .none])
    func unfoldingWithThesePageTurnsHasNone(pageTurn: ReaderPageTurn) async throws {
        let model = try await unfoldedShell(place: ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.5), pageTurn: pageTurn)
        #expect(model.coverMotion == nil)
    }

    // The book never closed, so there's nothing to leaf through to.
    @Test func foldingAndUnfoldingWithCloseBookOffPlaysNone() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store), defaults: .closingBookWhenFolded(false))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", source: StubLibrarySource()))
        try model.places.store.save(ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.5), forBook: Self.key)
        model.select(.library)
        model[path: .library].replace([.cover(Self.book)])
        model.openBook(Self.book)
        #expect(await eventually { model.reading != nil })
        model.coverMotion = nil
        model.hingeChanged(.fold)
        model.hingeChanged(.unfold)
        #expect(model.reading != nil)
        #expect(model.coverMotion == nil)
    }
}

/// The motion is pictures, so the reader's place doesn't move: no relocations,
/// nothing saved and nothing pushed. A real page and a real store, with the
/// motion played through.
@MainActor
@Suite(.temporaryFiles)
struct ReaderLeavesPlaceTests {
    private let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private let bookmarks = BookmarkStore(
        directory: URL.testDirectory.appending(path: "bookmarks-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private let bookID = "leaves"

    private func reader(sync: any ProgressSync) throws -> ReaderModel {
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let book = ReaderBook(fileURL: directory.appending(path: "leaves.epub"), id: bookID)
        try BookInspectorTests.epub(opf: "<dc:title>Leaves</dc:title>").write(to: book.fileURL)
        return ReaderModel(book: book, store: store, sync: sync, bookmarks: ReaderBookmarks(bookID: book.id, store: bookmarks), pushDelay: .milliseconds(50))
    }

    private struct Place: Equatable {
        var relocations: Int
        var moves: Int
        var position: ReadingPosition?
        var saved: LocalReadingProgress?
        var pushes: [ReadingPosition]
    }

    private func place(_ model: ReaderModel, _ sync: FakeProgressSync) async -> Place {
        await Place(
            relocations: model.relocationCount, moves: model.moveCount, position: model.position,
            saved: store.progress(forBook: bookID), pushes: sync.pushes
        )
    }

    private func settled(_ model: ReaderModel) async throws {
        #expect(await eventually(timeout: .seconds(30)) { model.phase == .open && model.relocation != nil })
        try await Task.sleep(for: .milliseconds(300))
    }

    private func picturesAt(_ fraction: Double, of model: ReaderModel, spread: Bool) -> ReaderCoverPages {
        // Taken as the reader takes them. It isn't on screen, so they're blank.
        var pages = model.coverPages()
        let picture = ReaderSnapshot(view: UIView(), frame: .zero)
        pages.fraction = fraction
        pages.layout = model.layout
        pages.left = spread ? picture : nil
        pages.right = spread ? picture : nil
        pages.whole = spread ? nil : picture
        pages.spine = spread ? 475.5 : nil
        return pages
    }

    @Test(arguments: [false, true])
    func openingFromItsScreenMovesNothing(spread: Bool) async throws {
        let sync = FakeProgressSync()
        let model = try reader(sync: sync)
        try await settled(model)
        let before = await place(model, sync)

        let motion = ReaderCoverMotion(
            cover: nil, title: "", author: "", coverFrame: CGRect(x: 0, y: 0, width: 455, height: 669), windowSize: CGSize(width: 951, height: 669),
            bookScreen: nil, spread: spread, reduceMotion: false, paper: .white
        )
        motion.readerOpened(picturesAt(0.5, of: model, spread: spread))
        let leaves = try #require(motion.leaves)
        for _ in 0...Int(leaves.end * 60) + 1 { motion.advance(by: 1.0 / 60) }

        // Past the 50 ms before a push.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await place(model, sync) == before)
    }

    @Test func unfoldingMovesNothing() async throws {
        let sync = FakeProgressSync()
        let model = try reader(sync: sync)
        try await settled(model)
        let before = await place(model, sync)

        let motion = ReaderCoverMotion(unfoldingAt: 0.5, windowSize: CGSize(width: 951, height: 669), paper: .white, leafStyle: ReaderLeafStyle())
        for _ in 0..<30 { motion.advance(by: 1.0 / 60) }
        motion.readerOpened(picturesAt(0.5, of: model, spread: true))
        for _ in 0..<60 { motion.advance(by: 1.0 / 60) }

        try await Task.sleep(for: .milliseconds(300))
        #expect(await place(model, sync) == before)
    }
}
