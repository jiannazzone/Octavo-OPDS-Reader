import Foundation
import ImageIO
import OctavoKit
import Testing
import UIKit
@testable import Octavo

private func png(width: Int = 90, height: Int = 120) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let png = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return png as Data
}

/// A new `CoverCache` on the same files is the next launch.
@MainActor
@Suite(.temporaryFiles)
struct CoverFilesTests {
    private let server = LibrarySourceID(rawValue: "server-one")
    private let cover = LibraryCover(rawValue: "books/7", version: "a")
    private let files = CoverFiles(directory: URL.testDirectory.appending(path: "Covers-\(UUID().uuidString)", directoryHint: .isDirectory))

    private func source(_ supply: CoverSupply) -> StubLibrarySource {
        var source = StubLibrarySource()
        source.coverSupply = supply
        return source
    }

    private func stored() -> [URL] {
        let all = FileManager.default.enumerator(at: files.directory, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return all.filter { !$0.hasDirectoryPath }
    }

    private func image(_ cover: LibraryCover, in server: LibrarySourceID, size: LibraryCoverSize = .thumbnail, from library: any LibrarySource) async -> UIImage? {
        await CoverCache(files: files).image(for: cover, in: server, size: size, from: library)
    }

    @Test func aCoverIsFetchedOnceAcrossLaunches() async throws {
        let supply = try CoverSupply(data: png())
        #expect(await image(cover, in: server, from: source(supply)) != nil)
        #expect(await image(cover, in: server, from: source(supply)) != nil)
        #expect(supply.fetches == 1)
    }

    @Test func aKeptCoverShowsWhenTheServerCantBeReached() async throws {
        #expect(try await image(cover, in: server, from: source(CoverSupply(data: png()))) != nil)
        #expect(await image(cover, in: server, from: StubLibrarySource()) != nil, "this source has no covers")
    }

    @Test func aChangedCoverIsFetchedAgain() async throws {
        let supply = try CoverSupply(data: png())
        _ = await image(cover, in: server, from: source(supply))
        _ = await image(LibraryCover(rawValue: "books/7", version: "b"), in: server, from: source(supply))
        #expect(supply.fetches == 2)
    }

    @Test func eachSizeAndServerKeepsItsOwn() async throws {
        let supply = try CoverSupply(data: png())
        _ = await image(cover, in: server, from: source(supply))
        _ = await image(cover, in: server, size: .full, from: source(supply))
        _ = await image(cover, in: LibrarySourceID(rawValue: "server-two"), from: source(supply))
        #expect(supply.fetches == 3)
        #expect(stored().count == 3)
    }

    @Test func importedCoversArentCopied() async throws {
        let library = LibrarySourceID.files
        let supply = try CoverSupply(data: png())
        _ = await image(cover, in: library, from: source(supply))
        _ = await image(cover, in: library, from: source(supply))
        #expect(supply.fetches == 2)
        #expect(stored().isEmpty)
    }

    @Test func aFileThatWontDecodeIsFetchedAgain() async throws {
        let data = try png()
        let supply = CoverSupply(data: data)
        _ = await image(cover, in: server, from: source(supply))
        let file = try #require(stored().first)
        try Data("not an image".utf8).write(to: file)
        #expect(await image(cover, in: server, from: source(supply)) != nil)
        #expect(supply.fetches == 2)
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func aFailedFetchKeepsNothing() async {
        #expect(await image(cover, in: server, from: StubLibrarySource()) == nil)
        #expect(await image(cover, in: server, from: source(CoverSupply(data: Data("not an image".utf8)))) == nil)
        #expect(stored().isEmpty)
    }

    // A catalog's address can hold its key (`OPDSURLSecret`).
    @Test func aFileNameHoldsNothingOfTheAddress() async throws {
        let address = LibraryCover(rawValue: "https://example.test/opds/s3cret/cover.jpg?apikey=s3cret")
        _ = try await image(address, in: server, from: source(CoverSupply(data: png())))
        let file = try #require(stored().first)
        #expect(!file.absoluteString.contains("s3cret"))
        #expect(!file.absoluteString.contains("cover.jpg"))
    }

    @Test func removingAServerRemovesOnlyItsCovers() async throws {
        let other = LibrarySourceID(rawValue: "server-two")
        let supply = try CoverSupply(data: png())
        let covers = CoverCache(files: files)
        _ = await covers.image(for: cover, in: server, size: .thumbnail, from: source(supply))
        _ = await covers.image(for: cover, in: other, size: .thumbnail, from: source(supply))
        await covers.removeFiles(of: server)
        #expect(stored().count == 1)
        #expect(FileManager.default.fileExists(atPath: files.folder(of: other).path))
        #expect(!FileManager.default.fileExists(atPath: files.folder(of: server).path))
    }

    @Test func aFetchStartedBeforeItsServerWentKeepsNothing() async throws {
        let covers = CoverCache(files: files)
        let library = try source(CoverSupply(data: png(), time: .milliseconds(100)))
        let fetch = Task { await covers.image(for: cover, in: server, size: .thumbnail, from: library) }
        try await Task.sleep(for: .milliseconds(20))
        await covers.removeFiles(of: server)
        _ = await fetch.value
        #expect(stored().isEmpty)
    }

    @Test func theLibraryRemovesARemovedServersCovers() async throws {
        let covers = CoverCache(files: files)
        let model = LibraryModel(
            recents: RecentBooks(fileURL: files.directory.appending(path: "RecentBooks.json")),
            finished: FinishedBooks(fileURL: files.directory.appending(path: "FinishedBooks.json")),
            onIPhone: BooksOnIPhone(fileURL: files.directory.appending(path: "BooksOnIPhone.json")),
            imported: .temporary(), covers: covers
        )
        let library = try source(CoverSupply(data: png()))
        await model.connect(LibraryServer(id: server, name: "BookOrbit", source: library))
        _ = await covers.image(for: cover, in: server, size: .thumbnail, from: library)
        #expect(FileManager.default.fileExists(atPath: files.folder(of: server).path))
        model.remove(server)
        #expect(await eventually { !FileManager.default.fileExists(atPath: files.folder(of: server).path) })
    }

    private func age(_ file: URL, by seconds: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-seconds)], ofItemAtPath: file.path)
    }

    @Test func anUnversionedCoverIsFetchedAgainAfterADay() async throws {
        let unversioned = LibraryCover(rawValue: "books/7")
        let old = try png(width: 90)
        let new = try png(width: 60)
        _ = await image(unversioned, in: server, from: source(CoverSupply(data: old)))
        let file = try #require(stored().first)
        try age(file, by: CoverFiles.refreshAge + 60)
        let supply = CoverSupply(data: new)
        // Kept for the background fetch, as the library keeps its cache.
        let covers = CoverCache(files: files)
        let shown = await covers.image(for: unversioned, in: server, size: .thumbnail, from: source(supply))
        #expect(shown?.size.width == 90, "the kept one shows at once")
        #expect(await eventually { (try? Data(contentsOf: file)) == new })
        #expect(supply.fetches == 1)
        #expect(await eventually { covers.cachedImage(for: unversioned, in: server, size: .thumbnail)?.size.width == 60 })
    }

    @Test func anUnversionedCoverIsntFetchedAgainWithinADay() async throws {
        let unversioned = LibraryCover(rawValue: "books/7")
        let supply = try CoverSupply(data: png())
        _ = await image(unversioned, in: server, from: source(supply))
        _ = await image(unversioned, in: server, from: source(supply))
        try await Task.sleep(for: .milliseconds(50))
        #expect(supply.fetches == 1)
    }

    @Test func aVersionedCoverIsntFetchedAgainHoweverOld() async throws {
        let supply = try CoverSupply(data: png())
        _ = await image(cover, in: server, from: source(supply))
        try age(try #require(stored().first), by: 365 * CoverFiles.refreshAge)
        _ = await image(cover, in: server, from: source(supply))
        try await Task.sleep(for: .milliseconds(50))
        #expect(supply.fetches == 1)
    }

    @Test func aFailedRefreshKeepsTheCover() async throws {
        let unversioned = LibraryCover(rawValue: "books/7")
        let data = try png()
        _ = await image(unversioned, in: server, from: source(CoverSupply(data: data)))
        let file = try #require(stored().first)
        try age(file, by: CoverFiles.refreshAge + 60)
        let covers = CoverCache(files: files)
        #expect(await covers.image(for: unversioned, in: server, size: .thumbnail, from: StubLibrarySource()) != nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func trimmingRemovesWhatWasWrittenLongestAgo() async throws {
        let data = Data(repeating: 1, count: 100)
        for (index, key) in ["oldest", "middle", "newest"].enumerated() {
            await files.write(data, as: key, in: server)
            try age(files.url(for: key, in: server), by: TimeInterval(3 - index) * 60)
        }
        await files.trim(to: 300)
        #expect(stored().count == 3, "within the limit")
        await files.trim(to: 250)
        #expect(await files.read("oldest", in: server) == nil)
        #expect(await files.read("middle", in: server) == data)
        #expect(await files.read("newest", in: server) == data)
    }
}

struct CoverDecodingTests {
    @Test func aThumbnailIsAtMost600PixelsASide() async throws {
        let image = try #require(await CoverCache.decoded(try png(width: 1200, height: 1800), size: .thumbnail))
        #expect(image.size == CGSize(width: 400, height: 600))
    }

    @Test func aFullCoverIsAtMost2400PixelsASide() async throws {
        let large = try #require(await CoverCache.decoded(try png(width: 3000, height: 4800), size: .full))
        #expect(large.size == CGSize(width: 1500, height: 2400))
        let small = try #require(await CoverCache.decoded(try png(width: 1200, height: 1800), size: .full))
        #expect(small.size == CGSize(width: 1200, height: 1800))
    }

    @Test func aSmallCoverStaysItsSize() async throws {
        let image = try #require(await CoverCache.decoded(try png(width: 90, height: 120), size: .thumbnail))
        #expect(image.size == CGSize(width: 90, height: 120))
    }

    @Test func whatWontDecodeIsNothing() async {
        #expect(await CoverCache.decoded(Data("not an image".utf8), size: .thumbnail) == nil)
        #expect(await CoverCache.decoded(Data(), size: .full) == nil)
    }
}
