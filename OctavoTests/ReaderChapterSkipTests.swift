import Testing
@testable import Octavo

/// The chapter buttons (decision 35).
struct ReaderChapterSkipTests {
    /// Back tries this chapter's start first, then the ones before it.
    @Test func backStartsWithThisChapter() {
        let skip = ReaderChapterSkip(count: 10, current: 5, isOnFirstEntry: false)
        #expect(skip.targets(.back) == [5, 4, 3])
    }

    @Test func forwardStartsWithTheNextChapter() {
        let skip = ReaderChapterSkip(count: 10, current: 5, isOnFirstEntry: false)
        #expect(skip.targets(.forward) == [6, 7, 8])
    }

    @Test func backStopsAtTheFirstChapter() {
        let skip = ReaderChapterSkip(count: 10, current: 1, isOnFirstEntry: false)
        #expect(skip.targets(.back) == [1, 0])
    }

    @Test func forwardStopsAtTheLastChapter() {
        let skip = ReaderChapterSkip(count: 10, current: 8, isOnFirstEntry: false)
        #expect(skip.targets(.forward) == [9])
    }

    /// In the front matter, before the first entry.
    @Test func beforeTheFirstChapterOnlyForwardGoesAnywhere() {
        let skip = ReaderChapterSkip(count: 10, current: nil, isOnFirstEntry: false)
        #expect(!skip.canGoBack)
        #expect(skip.targets(.back).isEmpty)
        #expect(skip.canGoForward)
        #expect(skip.targets(.forward) == [0, 1, 2])
    }

    @Test func partwayThroughTheFirstChapterBackGoesToItsStart() {
        let skip = ReaderChapterSkip(count: 10, current: 0, isOnFirstEntry: false)
        #expect(skip.canGoBack)
        #expect(skip.targets(.back) == [0])
    }

    @Test func onTheFirstChaptersStartBackDims() {
        let skip = ReaderChapterSkip(count: 10, current: 0, isOnFirstEntry: true)
        #expect(!skip.canGoBack)
    }

    @Test func inTheLastChapterForwardDims() {
        let skip = ReaderChapterSkip(count: 10, current: 9, isOnFirstEntry: false)
        #expect(!skip.canGoForward)
        #expect(skip.targets(.forward).isEmpty)
    }

    @Test func aBookWithNoContentsHasNoButtons() {
        let skip = ReaderChapterSkip(count: 0, current: nil, isOnFirstEntry: false)
        #expect(!skip.isAvailable)
        #expect(!skip.canGoBack)
        #expect(!skip.canGoForward)
    }
}
