import CoreGraphics
import OctavoKit
import Testing
@testable import Octavo

/// Home (`docs/design/direction.md`, Home).
@MainActor @Suite(.temporaryFiles) struct HomeTests {
    // Books in progress, or their shapes while they load: not an invitation.
    @Test func homeShowsBooksOnlyWithBooksInProgress() async {
        let nothing = makeShell().library
        #expect(!HomeState(nothing).showsBooks)
        await nothing.connectSampleLibrary(nothingInProgress: true)
        #expect(!HomeState(nothing).showsBooks)

        let reading = makeShell().library
        await reading.connectSampleLibrary()
        #expect(HomeState(reading).showsBooks)
    }

    // A shelf has covers while it loads, and once loaded only if it has
    // books.
    @Test func aShelfHasCoversWhileLoadingOrWithBooks() async throws {
        let source = SampleLibrarySource.id
        let feed = FeedModel(link: LibraryLink(rawValue: "recent"), source: source, library: SampleLibrarySource()) { _ in }
        #expect(LibraryShelf.hasCovers(feed, from: source))
        await feed.load()
        #expect(LibraryShelf.hasCovers(feed, from: source))
    }
}
