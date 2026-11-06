import Foundation
import OctavoKit
import SwiftUI
import Testing
@testable import Octavo

/// Keep screen on (decision 24): what's saved, what the menu says, how long each
/// choice lasts, and that only a real move starts the time again. The book file
/// is missing, so nothing opens under the tests.
@MainActor
@Suite(.temporaryFiles)
struct ReaderScreenOnTests {
    private func stored(in defaults: UserDefaults) -> ReaderScreenOn {
        AppStorage(wrappedValue: ReaderScreenOn.standard, ReaderScreenOn.key, store: defaults).wrappedValue
    }

    @Test func isSavedInMinutes() {
        #expect(ReaderScreenOn.key == "reader.keepScreenOn")
        #expect(ReaderScreenOn.allCases.map(\.rawValue) == [0, 5, 10, 15, 30])
    }

    @Test func menuNames() {
        #expect(ReaderScreenOn.allCases.map(\.name) == ["Off", "5 minutes", "10 minutes", "15 minutes", "30 minutes"])
    }

    @Test func times() {
        #expect(ReaderScreenOn.allCases.map(\.time) == [nil, .seconds(300), .seconds(600), .seconds(900), .seconds(1800)])
    }

    @Test func tenMinutesUntilAnotherChoiceIsSaved() {
        let defaults = UserDefaults.testSuite("keep-screen-on")
        #expect(stored(in: defaults) == .tenMinutes)
        defaults.set(30, forKey: ReaderScreenOn.key)
        #expect(stored(in: defaults) == .thirtyMinutes)
        defaults.set(0, forKey: ReaderScreenOn.key)
        #expect(stored(in: defaults) == .off)
    }

    @Test func aTimeNoLongerOfferedIsTheDefault() {
        let defaults = UserDefaults.testSuite("keep-screen-on")
        defaults.set(20, forKey: ReaderScreenOn.key)
        #expect(stored(in: defaults) == .tenMinutes)
    }

    // A repeat of the same page reports itself but starts no new time.
    @Test func onlyAMoveCounts() {
        let bookID = "awake"
        let missing = URL.testDirectory.appending(path: "\(UUID().uuidString).epub")
        let store = ReadingPositionStore(directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory))
        let bookmarks = BookmarkStore(directory: URL.testDirectory.appending(path: "bookmarks-\(UUID().uuidString)", directoryHint: .isDirectory))
        let model = ReaderModel(book: ReaderBook(fileURL: missing, id: bookID), store: store, bookmarks: ReaderBookmarks(bookID: bookID, store: bookmarks))
        model.handle(.opened(.init(restoredFrom: "start", sectionCount: 1, isFixedLayout: false)))

        model.handle(.relocate(.init(cfi: "epubcfi(/6/4!/4/2/1:0)", fraction: 0.1)))
        #expect(model.moveCount == 1)
        model.handle(.relocate(.init(cfi: "epubcfi(/6/4!/4/2/1:0)", fraction: 0.1)))
        #expect(model.moveCount == 1)
        #expect(model.relocationCount == 2)
        model.handle(.relocate(.init(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.4)))
        #expect(model.moveCount == 2)
    }
}
