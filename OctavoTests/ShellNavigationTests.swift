import CoreGraphics
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

struct PanePathTests {
    static let a = ShellRoute.collections
    static let b = ShellRoute.collection("Classics")
    static let c = ShellRoute.cover(PlaceholderBook.samples[0])
    static let d = ShellRoute.cover(PlaceholderBook.samples[1])

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
    static let book = PlaceholderBook.samples[1]

    @Test func unfoldingOnACoverOpensTheBook() {
        let model = ShellModel()
        model.tab = .library
        model[path: .library].routes = [.collections, .cover(Self.book)]
        model.hingeChanged(.unfold)
        #expect(model.reading == Self.book)
    }

    @Test func unfoldingElsewhereKeepsTheScreen() {
        let model = ShellModel()
        model.tab = .library
        model[path: .library].routes = [.cover(Self.book), .collections]
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
        #expect(model[path: .library].routes == [.cover(Self.book), .collections])
    }

    // Home's companion is a cover, but it isn't on screen folded.
    @Test func unfoldingOnARootDoesNothing() {
        let model = ShellModel()
        model.tab = .home
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
    }

    @Test func onlyTheSelectedTabCounts() {
        let model = ShellModel()
        model.tab = .home
        model[path: .library].routes = [.cover(Self.book)]
        model.hingeChanged(.unfold)
        #expect(model.reading == nil)
    }

    @Test func foldingDoesNothing() {
        let model = ShellModel()
        model.tab = .library
        model[path: .library].routes = [.cover(Self.book)]
        model.hingeChanged(.fold)
        model.hingeChanged(.none)
        #expect(model.reading == nil)
    }

    @Test func linksPushFoldedAndShiftUnfolded() {
        let model = ShellModel()
        model.open(.collections, from: PaneContext(tab: .library))
        model.open(.collection("Classics"), from: PaneContext(tab: .library))
        #expect(model[path: .library].routes == [.collections, .collection("Classics")])
        model.open(.cover(Self.book), from: PaneContext(tab: .library, level: 1))
        #expect(model[path: .library].routes == [.collections, .cover(Self.book)])
    }

    @Test func anEmptyHomeHasNoCompanion() {
        let model = ShellModel()
        model.homeIsEmpty = true
        #expect(model[path: .home].companion == nil)
        model.homeIsEmpty = false
        #expect(model[path: .home].companion == .cover(PlaceholderBook.samples[0]))
    }
}
