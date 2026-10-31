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

    @Test func readsAPositionSavedBeforeSyncAsPushed() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(ReadingPositionFixture.prideAndPrejudice).write(to: store.fileURL(forBook: "old.epub"))

        let progress = try #require(store.progress(forBook: "old.epub"))
        #expect(progress.position == ReadingPositionFixture.prideAndPrejudice)
        #expect(progress.needsPush == false)
    }

    @Test func clearsNeedsPushOnlyForTheSavedPosition() throws {
        let first = ReadingPositionFixture.prideAndPrejudice
        let second = ReadingPosition(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.05)
        try store.save(first, forBook: "a.epub", needsPush: true)
        try store.save(second, forBook: "a.epub", needsPush: true)

        // A push of the older position finishing late doesn't clear the newer one.
        try store.markPushed(first, forBook: "a.epub")
        #expect(store.progress(forBook: "a.epub")?.needsPush == true)

        try store.markPushed(second, forBook: "a.epub")
        #expect(store.progress(forBook: "a.epub")?.needsPush == false)
        #expect(store.position(forBook: "a.epub") == second)
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
