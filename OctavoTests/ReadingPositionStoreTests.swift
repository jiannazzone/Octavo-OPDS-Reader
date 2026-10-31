import Foundation
import OctavoKit
import Testing
@testable import Octavo

struct ReadingPositionStoreTests {
    let store = ReadingPositionStore(
        directory: URL.temporaryDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )

    @Test func roundTripsAPosition() throws {
        let position = ReadingPositionFixture.prideAndPrejudice
        try store.save(position, forBook: "pride-and-prejudice.epub")
        #expect(store.position(forBook: "pride-and-prejudice.epub") == position)
        #expect(store.position(forBook: "moby-dick.epub") == nil)
    }

    @Test func keepsIDsWithPathCharactersInsideTheDirectory() throws {
        try store.save(ReadingPositionFixture.prideAndPrejudice, forBook: "../books/42")
        #expect(store.fileURL(forBook: "../books/42").deletingLastPathComponent() == store.directory)
        #expect(store.position(forBook: "../books/42") != nil)
    }

    @Test func removesAPosition() throws {
        try store.save(ReadingPositionFixture.prideAndPrejudice, forBook: "a.epub")
        store.removePosition(forBook: "a.epub")
        #expect(store.position(forBook: "a.epub") == nil)
    }
}

private enum ReadingPositionFixture {
    static let prideAndPrejudice = ReadingPosition(cfi: "epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)", fraction: 0.0111)
}
