import CoreGraphics
import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// The shell's split at the hinge. Geometry from the iPhone Duo simulator
/// (iOS 27.1): a tab's content is 867 pt wide unfolded (382 folded) and the
/// division region is x 455.5–495.5, the full height of the screen.
struct PaneSplitTests {
    static let hinge = CGRect(x: 455.5, y: -82, width: 40, height: 669)

    @Test func unfoldedSplitsAtTheHinge() throws {
        let split = try #require(PaneSplit(width: 867, divisions: [Self.hinge]))
        #expect(split.leftWidth == 455.5)
        #expect(split.hingeWidth == 40)
        #expect(split.rightWidth == 371.5)
    }

    @Test func foldedIsOnePane() {
        #expect(PaneSplit(width: 382, divisions: []) == nil)
    }

    // Around a fold the region can report for the inner display while the
    // view still has the outer display's width.
    @Test func ignoresAHingePastTheView() {
        #expect(PaneSplit(width: 382, divisions: [Self.hinge]) == nil)
    }

    // ... or turned across the view (duo-spreads §1).
    @Test func ignoresAHingeAcross() {
        let across = CGRect(x: -42, y: 373.5, width: 669, height: 40)
        #expect(PaneSplit(width: 867, divisions: [across]) == nil)
    }

    @Test func needsRoomForAPaneEachSide() {
        let nearTheEdge = CGRect(x: 120, y: 0, width: 40, height: 669)
        #expect(PaneSplit(width: 867, divisions: [nearTheEdge]) == nil)
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
func makeShell(opener: BookOpener? = nil) -> ShellModel {
    let folder = URL.temporaryDirectory.appending(path: "ShellTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    return ShellModel(
        library: LibraryModel(recents: RecentBooks(fileURL: folder.appending(path: "RecentBooks.json"))),
        opener: opener ?? BookOpener(files: CachedBookFiles(directory: folder.appending(path: "Books")))
    )
}

struct ShellRouteTests {
    // A refreshed list or book still marks the same row.
    @Test func theSameScreenSurvivesNewDetails() {
        var entry = LibraryEntry(kind: .collection, title: "Classics", count: 5, link: LibraryLink(rawValue: "collections/classics"))
        let route = ShellRoute.feed(entry, from: SampleLibrarySource.id)
        entry.count = 6
        #expect(route.isSameScreen(as: .feed(entry, from: SampleLibrarySource.id)))
        #expect(!route.isSameScreen(as: .feed(entry, from: .files)))

        var book = SampleRoutes.book(0)
        let cover = ShellRoute.cover(book)
        book.book.progress = 0.9
        #expect(cover.isSameScreen(as: .cover(book)))
        #expect(!cover.isSameScreen(as: .cover(SampleRoutes.book(1))))
        #expect(!cover.isSameScreen(as: nil))
    }
}

struct PanePathTests {
    static let a = SampleRoutes.collections
    static let b = SampleRoutes.classics
    static let c = ShellRoute.cover(SampleRoutes.book(0))
    static let d = ShellRoute.cover(SampleRoutes.book(1))

    @Test func levelsCountFromTheRoot() {
        let path = PanePath(routes: [Self.a, Self.b])
        #expect(path.route(at: 0) == nil)
        #expect(path.route(at: 1) == Self.a)
        #expect(path.route(at: 2) == Self.b)
        #expect(path.route(at: 3) == nil)
    }

    @Test func openingFromTheLeftPaneReplacesTheRight() {
        var path = PanePath(routes: [Self.a, Self.b])
        path.open(Self.c, from: 1)
        #expect(path.routes == [Self.a, Self.c])
        #expect(path.pushedPairs == [PaneLevel(value: 1)])
    }

    @Test func openingFromTheRightPaneShiftsAlong() {
        var path = PanePath(routes: [Self.a, Self.b])
        path.open(Self.c, from: 2)
        #expect(path.routes == [Self.a, Self.b, Self.c])
        #expect(path.pushedPairs == [PaneLevel(value: 1), PaneLevel(value: 2)])
        #expect(path.rightOfPair(2) == Self.c)
    }

    @Test func openingFromTheRootStartsOver() {
        var path = PanePath(routes: [Self.a, Self.b, Self.c])
        path.open(Self.d, from: 0)
        #expect(path.routes == [Self.d])
        #expect(path.pushedPairs.isEmpty)
    }

    @Test func theCompanionShowsBesideTheRootUntilSomethingOpens() {
        var path = PanePath(companion: Self.c)
        #expect(path.rightOfPair(0) == Self.c)
        path.open(Self.a, from: 0)
        #expect(path.rightOfPair(0) == Self.a)
        #expect(path.rightOfPair(1) == nil)
    }

    @Test func openingFromTheCompanionKeepsIt() {
        var path = PanePath(companion: Self.c)
        path.open(Self.a, from: 1)
        #expect(path.routes == [Self.c, Self.a])
    }

    @Test func poppingAPairClosesTheDeepestScreen() {
        var path = PanePath(routes: [Self.a, Self.b, Self.c])
        path.pushedPairs = [PaneLevel(value: 1)]
        #expect(path.routes == [Self.a, Self.b])
        path.pushedPairs = []
        #expect(path.routes == [Self.a])
    }

    @Test func theStackCantPushPairs() {
        var path = PanePath(routes: [Self.a])
        path.pushedPairs = [PaneLevel(value: 1)]
        #expect(path.routes == [Self.a])
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
struct ShellModelTests {
    static let book = SampleRoutes.book(1)

    // The book isn't on the iPhone yet: it downloads, then opens (#14).
    @Test func unfoldingOnACoverOpensTheBook() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", detail: "", source: StubLibrarySource()))
        model.tab = .library
        model[path: .library].routes = [SampleRoutes.collections, .cover(Self.book)]
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        #expect(model.reading?.book.id == Self.book.book.id)
    }

    @Test func unfoldingElsewhereKeepsTheScreen() {
        let model = makeShell()
        model.tab = .library
        model[path: .library].routes = [.cover(Self.book), SampleRoutes.collections]
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
        #expect(model[path: .library].routes == [.cover(Self.book), SampleRoutes.collections])
    }

    // Home's companion is a cover, but it isn't on screen folded.
    @Test func unfoldingOnARootDoesNothing() {
        let model = makeShell()
        model.tab = .home
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
    }

    @Test func onlyTheSelectedTabCounts() {
        let model = makeShell()
        model.tab = .home
        model[path: .library].routes = [.cover(Self.book)]
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
    }

    @Test func foldingDoesNothing() {
        let model = makeShell()
        model.tab = .library
        model[path: .library].routes = [.cover(Self.book)]
        model.hingeChanged(.fold)
        model.hingeChanged(.none)
        #expect(model.reading == nil)
    }

    @Test func linksPushFoldedAndShiftUnfolded() {
        let model = makeShell()
        model.open(SampleRoutes.collections, from: PaneContext(tab: .library))
        model.open(SampleRoutes.classics, from: PaneContext(tab: .library))
        #expect(model[path: .library].routes == [SampleRoutes.collections, SampleRoutes.classics])
        model.open(.cover(Self.book), from: PaneContext(tab: .library, level: 1))
        #expect(model[path: .library].routes == [SampleRoutes.collections, .cover(Self.book)])
    }

    @Test func aBookJoinsContinueReadingOnceItOpens() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store))
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "Stub", detail: "", source: StubLibrarySource()))
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
