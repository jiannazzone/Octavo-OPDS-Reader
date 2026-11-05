import CoreGraphics
import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// iOS lays a backgrounded app out again for its snapshots, turned sideways and
/// back, and the page mustn't follow (`docs/notes/reader-background.md`). The sizes
/// are the ones measured on the unfolded Duo. The book file is missing, so
/// nothing opens under the tests.
@MainActor
@Suite(.temporaryFiles)
struct ReaderBackgroundTests {
    private let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private let bookID = "away"

    private static let upright = ReaderGeometry(
        size: CGSize(width: 951, height: 669),
        divisions: [.init(frame: CGRect(x: 455.5, y: 0, width: 40, height: 669), isActive: false)]
    )
    private static let sideways = ReaderGeometry(
        size: CGSize(width: 951, height: 669),
        divisions: [.init(frame: CGRect(x: 0, y: 455.5, width: 669, height: 40), isActive: false)]
    )
    private static let column = ReaderInsets(bottom: 34, right: 84)
    private static let band = ReaderInsets(top: 82, bottom: 34)

    private func reader() -> ReaderModel {
        let missing = URL.testDirectory.appending(path: "\(UUID().uuidString).epub")
        let bookmarks = BookmarkStore(directory: URL.testDirectory.appending(path: "bookmarks-\(UUID().uuidString)", directoryHint: .isDirectory))
        let model = ReaderModel(book: ReaderBook(fileURL: missing, id: bookID), store: store, bookmarks: ReaderBookmarks(bookID: bookID, store: bookmarks))
        model.handle(.opened(.init(restoredFrom: "start", sectionCount: 1, isFixedLayout: false)))
        model.hingeChanged(.open, angle: 180)
        model.geometryChanged(Self.upright)
        model.safeAreaChanged(Self.column)
        return model
    }

    @Test func aSnapshotsSizesDontReachThePage() {
        let model = reader()
        let layout = model.layout
        let geometry = model.geometry
        #expect(layout.columns == 2)

        model.isInBackground = true
        model.safeAreaChanged(Self.band)
        model.geometryChanged(Self.sideways)
        #expect(model.layout == layout)
        #expect(model.geometry == geometry)

        model.safeAreaChanged(Self.column)
        model.geometryChanged(Self.upright)
        model.isInBackground = false
        #expect(model.layout == layout)
        #expect(model.geometry == geometry)
    }

    @Test func aRealRotationWhileAwayIsLaidOutOnReturn() {
        let model = reader()
        let layout = model.layout
        model.isInBackground = true
        model.safeAreaChanged(Self.band)
        model.geometryChanged(Self.sideways)
        #expect(model.layout == layout)

        model.isInBackground = false
        #expect(model.layout != layout)
        #expect(model.geometry?.safeArea == Self.band)
    }

    // The fold's cover and batch are for a fold you can see.
    @Test func aRealFoldWhileAwayIsLaidOutOnReturn() async {
        let model = reader()
        model.hingeChanged(.closed, angle: 0)
        #expect(await eventually { !model.isFolding })
        let layout = model.layout

        model.isInBackground = true
        model.hingeChanged(.open, angle: 180)
        #expect(!model.isFolding)
        #expect(model.posture == .open)
        #expect(model.layout == layout)

        model.isInBackground = false
        #expect(!model.isFolding)
        #expect(model.layout != layout)
    }

    // A page still loading as you left is a real move.
    @Test func aMoveThatLandsWhileAwayIsStillSaved() {
        let model = reader()
        model.handle(.relocate(.init(cfi: "epubcfi(/6/4!/4/2/1:0)", fraction: 0.1)))
        model.isInBackground = true
        model.handle(.relocate(.init(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.4)))
        #expect(store.position(forBook: bookID)?.cfi == "epubcfi(/6/8!/4/2/1:0)")
    }
}
