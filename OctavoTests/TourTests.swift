import Foundation
import OctavoKit
import SwiftUI
import Testing
@testable import Octavo

// Step 17, the tour for a new install (decisions 29 and 30).

extension TourRecord {
    /// A record of its own, never the app's.
    static func temporary(state: State? = nil) -> TourRecord {
        let suite = "TourTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let record = TourRecord(defaults: defaults)
        if let state { record.set(state) }
        return record
    }
}

private extension TourFlow.ReaderState {
    static let hidden = Self(barVisible: false, buttonsVisible: false, textPanelOpen: false)
    static let controls = Self(barVisible: true, buttonsVisible: true, textPanelOpen: false)
    static let panel = Self(barVisible: false, buttonsVisible: true, textPanelOpen: true)
    static let otherPanel = Self(barVisible: false, buttonsVisible: true, textPanelOpen: false)
}

@MainActor
struct TourFlowTests {
    @Test func itStartsFromTheHinge() {
        #expect(TourFlow(fold: .open).step == .closeYourIPhone)
        #expect(TourFlow(fold: .closed).step == .cover)
        #expect(TourFlow(fold: nil).step == .turnThePage)
    }

    @Test func theWholeTourInOrder() {
        var flow = TourFlow(fold: .open)
        flow.handle(.folded)
        #expect(flow.step == .cover)
        #expect(flow.coverLine == "Open your iPhone to begin")
        flow.handle(.unfolded)
        #expect(flow.step == .turnThePage)
        #expect(flow.step == .turnThePage)
        flow.handle(.pageTurned)
        #expect(flow.step == .bringUpControls)
        flow.handle(.reader(.controls))
        #expect(flow.step == .tapAa)
        flow.handle(.reader(.panel))
        #expect(flow.step == .makeItYours)
        flow.handle(.done)
        #expect(flow.step == .addYourBooks)
    }

    @Test func continueWithoutClosingGoesStraightToTheBook() {
        var flow = TourFlow(fold: .open)
        flow.handle(.continueWithoutClosing)
        #expect(flow.step == .turnThePage)
    }

    // A step only moves on for what it asks for.
    @Test func stepsIgnoreWhatTheyDoNotAskFor() {
        var flow = TourFlow(fold: .open)
        flow.handle(.pageTurned)
        flow.handle(.done)
        #expect(flow.step == .closeYourIPhone)
        flow.handle(.continueWithoutClosing)
        flow.handle(.reader(.controls))
        flow.handle(.done)
        #expect(flow.step == .turnThePage)
        flow.handle(.pageTurned)
        flow.handle(.pageTurned)
        #expect(flow.step == .bringUpControls)
    }

    // A tap on the page hides the controls, and Aa with them.
    @Test func controlsHiddenOnMakeItYoursGoBackAStep() {
        var flow = TourFlow(fold: nil)
        flow.handle(.pageTurned)
        flow.handle(.reader(.controls))
        #expect(flow.step == .tapAa)
        flow.handle(.reader(.hidden))
        #expect(flow.step == .bringUpControls)
        flow.handle(.reader(.controls))
        #expect(flow.step == .tapAa)
    }

    @Test func anotherPanelLeavesAaToTap() {
        var flow = TourFlow(fold: nil)
        flow.handle(.pageTurned)
        flow.handle(.reader(.controls))
        flow.handle(.reader(.otherPanel))
        #expect(flow.step == .tapAa)
    }

    // With the panel already open from looking ahead, the step is done.
    @Test func aPanelOpenedEarlyCountsWhenItsStepComes() {
        var flow = TourFlow(fold: nil)
        flow.handle(.reader(.panel))
        #expect(flow.step == .turnThePage)
        flow.handle(.pageTurned)
        flow.handle(.reader(.controls))
        #expect(flow.step == .tapAa)
    }

    // Aa opened from Turn the page: the bar has gone with it, and the panel
    // is what Make it yours asks for.
    @Test func thePanelOpenWhenBringUpControlsComesCounts() {
        var flow = TourFlow(fold: nil)
        flow.handle(.reader(.panel))
        flow.handle(.pageTurned)
        #expect(flow.step == .bringUpControls)
        flow.handle(.reader(.panel))
        #expect(flow.step == .makeItYours)
    }

    // Another panel hides the bar too: closing it brings the bar back.
    @Test func anotherPanelWaitsAtBringUpControls() {
        var flow = TourFlow(fold: nil)
        flow.handle(.pageTurned)
        flow.handle(.reader(.otherPanel))
        #expect(flow.step == .bringUpControls)
        flow.handle(.reader(.controls))
        #expect(flow.step == .tapAa)
    }

    // Done is there as long as the card is, with or without the panel.
    @Test func closingThePanelKeepsTheCardWithDone() {
        var flow = TourFlow(fold: nil)
        flow.handle(.pageTurned)
        flow.handle(.reader(.controls))
        flow.handle(.reader(.panel))
        flow.handle(.reader(.hidden))
        #expect(flow.step == .makeItYours)
        flow.handle(.done)
        #expect(flow.step == .addYourBooks)
    }

    // Folding mid-tour closes the book; unfolding resumes at the same step.
    @Test(arguments: [TourFlow.Event.pageTurned, .reader(.controls), .reader(.panel), .done])
    func aFoldResumesAtTheSameStep(upTo last: TourFlow.Event) {
        var flow = TourFlow(fold: .closed)
        flow.handle(.unfolded)
        for event in [TourFlow.Event.pageTurned, .reader(.controls), .reader(.panel), .done] {
            flow.handle(event)
            if event == last { break }
        }
        let step = flow.step
        flow.handle(.folded)
        #expect(flow.step == .cover)
        #expect(flow.coverLine == "Open your iPhone to continue")
        // The repeats and a second report change nothing.
        flow.handle(.folded)
        #expect(flow.coverLine == "Open your iPhone to continue")
        flow.handle(.unfolded)
        #expect(flow.step == step)
    }

    @Test func foldingBeforeTheBookOpenedStillBegins() {
        var flow = TourFlow(fold: .open)
        flow.handle(.folded)
        flow.handle(.folded)
        #expect(flow.coverLine == "Open your iPhone to begin")
    }

    // The words are decision 29's, and what each step lights.
    @Test func cardsDotsAndRings() {
        typealias Step = TourFlow.Step
        #expect(Step.closeYourIPhone.card == nil)
        #expect(Step.cover.card == nil)
        #expect(Step.turnThePage.card?.title == "Turn the page")
        #expect(Step.turnThePage.card?.message == "Tap the right page, or swipe. Tap the left page to go back.")
        #expect(Step.bringUpControls.card?.message == "Tap ··· whenever you need them.")
        #expect(Step.tapAa.card?.title == "Make it yours")
        #expect(Step.tapAa.card?.message == "Tap Aa for themes, text size and fonts.")
        #expect(Step.makeItYours.card?.title == "The page changes as you go")
        #expect(Step.makeItYours.card?.message == "Come back to Aa any time.")
        #expect(Step.addYourBooks.card?.message == "From your server, or from Files.")
        // Four dots; Make it yours is one step.
        #expect(Step.dotCount == 4)
        #expect([Step.turnThePage, .bringUpControls, .tapAa, .makeItYours, .addYourBooks].map(\.dot) == [0, 1, 2, 2, 3])
        #expect(Step.bringUpControls.litButton == .showControls)
        #expect(Step.tapAa.litButton == .textAndTheme)
        #expect(Step.turnThePage.litButton == nil)
        #expect(Step.makeItYours.litButton == nil)
    }

    // The button a sentence names stands out; the words themselves don't change.
    @Test func theCardPicksOutTheButtonItNames() {
        for step in [TourFlow.Step.bringUpControls, .tapAa, .makeItYours] {
            let message = step.card?.message ?? ""
            let words = TourCardWords.emphasized(message)
            #expect(String(words.characters) == message)
            #expect(words.runs.count == 3)
        }
        let plain = TourFlow.Step.turnThePage.card?.message ?? ""
        #expect(TourCardWords.emphasized(plain).runs.count == 1)
    }

    // The page lifts as it would turn; with Reduce Motion, or a style with
    // nothing to lift, it holds still.
    @Test func thePageLiftsAsItTurnsOrHoldsStill() {
        #expect(ReaderPageTurn.automatic.hintMotion(spread: true, reduceMotion: false) == .flip)
        #expect(ReaderPageTurn.automatic.hintMotion(spread: false, reduceMotion: false) == .slide)
        #expect(ReaderPageTurn.slide.hintMotion(spread: true, reduceMotion: false) == .slide)
        #expect(ReaderPageTurn.flip.hintMotion(spread: true, reduceMotion: true) == nil)
        #expect(ReaderPageTurn.automatic.hintMotion(spread: true, reduceMotion: true) == nil)
        #expect(ReaderPageTurn.fade.hintMotion(spread: true, reduceMotion: false) == nil)
        #expect(ReaderPageTurn.none.hintMotion(spread: true, reduceMotion: false) == nil)
    }
}

@MainActor
struct TourRecordTests {
    @Test func aNewInstallPlaysItAndAFinishedOneNever() {
        let record = TourRecord.temporary()
        #expect(record.shouldPlay(hasEarlierData: false, protectedDataAvailable: true))
        record.set(.played)
        #expect(!record.shouldPlay(hasEarlierData: false, protectedDataAvailable: true))
    }

    // Left at step 1, or killed part way: it starts again, whatever the book
    // it installed left behind.
    @Test func anUnfinishedTourPlaysAgain() {
        let record = TourRecord.temporary(state: .playing)
        #expect(record.shouldPlay(hasEarlierData: true, protectedDataAvailable: true))
    }

    // A build from before the marker left a server, books or places:
    // Settings only.
    @Test func earlierDataSettlesAnExistingInstallOnce() {
        let record = TourRecord.temporary()
        #expect(!record.shouldPlay(hasEarlierData: true, protectedDataAvailable: true))
        #expect(record.state == .played)
        // Even with everything then removed.
        #expect(!record.shouldPlay(hasEarlierData: false, protectedDataAvailable: true))
    }

    // An earlier build's install with nothing in it still has the marker.
    @Test func theInstallMarkerSettlesAnExistingInstall() {
        let record = TourRecord.temporary()
        record.defaults.set(true, forKey: ServerCredentials.installedKey)
        record.settle()
        #expect(record.state == .played)
        #expect(!record.shouldPlay(hasEarlierData: false, protectedDataAvailable: true))
    }

    // iOS runs the app ahead of the first launch (prewarming): the app's init
    // says new and sets the marker, and nobody has seen a thing yet. The real
    // first launch still plays it.
    @Test func aRunBeforeTheFirstLaunchDoesNotUseItUp() {
        let record = TourRecord.temporary()
        record.settle()
        #expect(record.state == .new)
        record.defaults.set(true, forKey: ServerCredentials.installedKey)
        record.settle()
        #expect(record.state == .new)
        #expect(record.shouldPlay(hasEarlierData: false, protectedDataAvailable: true))
    }

    @Test func theMarkerDoesNotEndATourUnderWay() {
        let record = TourRecord.temporary(state: .playing)
        record.defaults.set(true, forKey: ServerCredentials.installedKey)
        record.settle()
        #expect(record.state == .playing)
    }

    // Before the first unlock nothing can be read: decide nothing.
    @Test func nothingIsDecidedBeforeTheFirstUnlock() {
        let record = TourRecord.temporary()
        #expect(!record.shouldPlay(hasEarlierData: false, protectedDataAvailable: false))
        #expect(record.state == nil)
        #expect(record.shouldPlay(hasEarlierData: false, protectedDataAvailable: true))
    }
}

@MainActor
@Suite(.temporaryFiles)
struct TourShellTests {
    let folder: URL
    let record: TourRecord

    init() throws {
        folder = try ImportFixtures.folder()
        record = .temporary()
    }

    private func shell(state: TourRecord.State? = nil) -> ShellModel {
        if let state { record.set(state) }
        return makeShell(tourRecord: record) { BookImporter(store: $0, inspect: ImportFixtures.inspect()) }
    }

    /// A new install on a Duo that opened with `fold`.
    private func started(fold: HingeTransition.Fold? = .closed) -> ShellModel {
        let model = shell()
        #expect(model.tourWaitsForHinge)
        #expect(!model.needsSetup)
        if let fold { model.hingeReported(fold) } else { model.hingeStayedSilent() }
        return model
    }

    /// `model` on the tour's last card, its book open.
    private func onTheLastCard(_ model: ShellModel) async -> ShellModel {
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        for event in [TourFlow.Event.pageTurned, .reader(.controls), .reader(.panel), .done] { model.tourEvent(event) }
        #expect(model.tour?.step == .addYourBooks)
        return model
    }

    @Test func aNewInstallStartsFromTheHinge() {
        let unfolded = TourShellTests.startedSeparately(.open)
        #expect(unfolded.tour?.step == .closeYourIPhone)
        #expect(unfolded.reading == nil)
        let folded = TourShellTests.startedSeparately(.closed)
        #expect(folded.tour?.step == .cover)
        #expect(folded.reading == nil)
    }

    private static func startedSeparately(_ fold: HingeTransition.Fold) -> ShellModel {
        let model = makeShell(tourRecord: .temporary())
        model.hingeReported(fold)
        return model
    }

    // Without a fold steps 1 and 2 drop out, and the book opens at once.
    @Test func withoutAFoldItStartsInTheBook() async {
        let model = started(fold: nil)
        #expect(model.tour?.step == .turnThePage)
        #expect(await eventually { model.reading?.book.id == .sample })
    }

    // Reports without a hinge say nothing until the wait is over.
    @Test func aReportWithoutAHingeDoesNotDecide() {
        let model = shell()
        model.hingeReported(nil)
        #expect(model.tourWaitsForHinge)
        #expect(model.tour == nil)
    }

    @Test func itPlaysOnceAndNotAfterAFinishedOne() async {
        let model = started()
        #expect(record.state == .playing)
        model.skipTour()
        #expect(record.state == .played)
        let next = makeShell(tourRecord: record)
        #expect(!next.tourWaitsForHinge)
        next.hingeReported(.closed)
        #expect(next.tour == nil)
    }

    // Killed part way: the next launch plays it again.
    @Test func anUnfinishedTourPlaysAgainNextLaunch() {
        _ = started()
        #expect(record.state == .playing)
        #expect(makeShell(tourRecord: record).tourWaitsForHinge)
    }

    @Test func unfoldingOnTheCoverOpensTheBookOnTheShelf() async {
        let model = started()
        #expect(model.onIPhoneBooks().map(\.book.id) == [.sample])
        model.hingeChanged(.unfold)
        #expect(model.tour?.step == .turnThePage)
        #expect(await eventually { model.reading?.book.id == .sample })
        #expect(model.library.continueReading.map(\.book.id) == [.sample])
        // The fold is the motion.
        #expect(model.coverMotion == nil)
    }

    // Folding mid-tour closes the book without opening its screen; unfolding
    // comes back to the same step.
    @Test func aFoldClosesTheBookAndAnUnfoldResumes() async {
        let model = started()
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        model.tourEvent(.pageTurned)
        model.hingeChanged(.fold)
        #expect(model.reading == nil)
        #expect(model.tour?.step == .cover)
        #expect(model.tour?.coverLine == "Open your iPhone to continue")
        #expect(model[path: .home].routes.isEmpty)
        model.hingeChanged(.unfold)
        #expect(model.tour?.step == .bringUpControls)
        #expect(await eventually { model.reading != nil })
    }

    // Opened or closed while the app was away, with no change reported: the
    // tour still follows the hinge.
    @Test func theTourFollowsAReportWithoutAChange() async {
        let model = started()
        model.hingeReported(.open)
        #expect(model.tour?.step == .turnThePage)
        #expect(await eventually { model.reading != nil })
        model.hingeReported(.closed)
        #expect(model.tour?.step == .cover)
        #expect(model.reading == nil)
        // The repeats change nothing.
        model.hingeReported(.closed)
        #expect(model.tour?.step == .cover)
        model.hingeReported(.open)
        model.hingeChanged(.unfold)
        #expect(model.tour?.step == .turnThePage)
        #expect(await eventually { model.reading != nil })
    }

    // A hinge that reports late, on a tour already started without one.
    @Test func aLateHingeStillClosesTheBook() async {
        let model = started(fold: nil)
        #expect(await eventually { model.reading != nil })
        model.hingeReported(.closed)
        #expect(model.reading == nil)
        #expect(model.tour?.step == .cover)
    }

    // A download finishing mid-tour stays a download: no reader, and the
    // tour carries on.
    @Test func aDownloadFinishingDuringATourDoesNotOpen() async throws {
        let files = try TemporaryBookFiles()
        let model = makeShell(opener: BookOpener(files: files.store), tourRecord: .temporary(state: .played))
        let source = StubLibrarySource()
        let book = SampleRoutes.book(1).book
        await model.library.connect(RemoveServerTests.bookOrbit(id: LibrarySourceID(rawValue: "tour-download"), account: "octavo"))
        model.hingeReported(.closed)
        model.showTour()
        let sourced = SourcedBook(source: LibrarySourceID(rawValue: "tour-download"), book: book)
        model.opener.open(sourced, from: source)
        #expect(await eventually { model.opener.status(of: sourced) == .downloaded })
        #expect(model.reading == nil)
        #expect(model.tour?.step == .cover)
    }

    @Test func closingAtStepOneGoesToTheCover() {
        let model = started(fold: .open)
        model.hingeChanged(.fold)
        #expect(model.tour?.step == .cover)
        #expect(model.tour?.coverLine == "Open your iPhone to begin")
    }

    // Skip from the very first screen: Home, with the book under Continue
    // reading though it never opened.
    @Test func skipLandsOnHomeWithTheSampleBook() {
        let model = started(fold: .open)
        model.skipTour()
        #expect(model.tour == nil)
        #expect(model.reading == nil)
        #expect(!model.needsSetup)
        #expect(!model.showsSetup)
        #expect(model.tab == .home)
        #expect(model.library.continueReading.map(\.book.id) == [.sample])
        #expect(model.onIPhoneBooks().map(\.book.id) == [.sample])
    }

    @Test func notNowClosesTheReaderOnHome() async {
        let model = await onTheLastCard(started())
        model.skipTour()
        #expect(model.reading == nil)
        #expect(model.tour == nil)
        #expect(model.tab == .home)
        #expect(model[path: .home].routes.isEmpty)
        #expect(model.library.continueReading.map(\.book.id) == [.sample])
        #expect(record.state == .played)
    }

    // Add books: setup's first screen with Skip; its steps go on top of it.
    @Test func addBooksOpensAddYourBooksAndSkipLeavesIt() async {
        let model = await onTheLastCard(started())
        model.tourAddBooks()
        #expect(model.reading == nil)
        #expect(model.tour == nil)
        #expect(model.showsSetup)
        #expect(model.addsBooksAfterTour)
        #expect(record.state == .played)
        model.setup.push(.opds)
        #expect(model[path: .setup].routes == [.setup(.opds)])
        model.setup.pop()
        model.skipAddingBooks()
        #expect(!model.showsSetup)
        #expect(model.tab == .home)
    }

    // Its steps end on Home, as they always do.
    @Test func addingAServerFromTheTourEndsOnHome() async {
        let model = await onTheLastCard(started())
        model.tourAddBooks()
        model.setup.finished(SavedServer(id: SavedServer.newID(), kind: .opds, address: "http://localhost:3320/feed.php", name: "COPS"))
        #expect(!model.showsSetup)
        #expect(model.tab == .home)
        #expect(model[path: .setup].routes.isEmpty)
    }

    @Test func aBookImportedFromAddYourBooksLandsOnTheLibrary() async throws {
        let model = await onTheLastCard(started())
        model.tourAddBooks()
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        #expect(!model.showsSetup)
        #expect(model.tab == .library)
        #expect(model.onIPhoneBooks().map(\.book.title).contains("Persuasion"))
    }

    @Test func aFailedImportStaysOnAddYourBooksWithTheReason() async throws {
        let model = await onTheLastCard(started())
        model.tourAddBooks()
        await model.importBooks([try ImportFixtures.drmMobi(in: folder)])
        #expect(model.showsSetup)
        #expect(model.setupImportFailures == [ImportFailure(fileName: "Kindred.mobi", reason: .drmProtected)])
    }

    // Open in Octavo on a new install: the file is what they came for.
    @Test func aSharedFileEndsTheTour() async throws {
        let model = started()
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        #expect(model.tour == nil)
        #expect(record.state == .played)
        #expect(model.tab == .library)
    }

    // Opened with a file before the hinge has even said how to start.
    @Test func aSharedFileBeforeTheTourStartsCancelsIt() async throws {
        let model = shell()
        #expect(model.tourWaitsForHinge)
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        #expect(!model.tourWaitsForHinge)
        #expect(record.state == .played)
        model.hingeReported(.closed)
        #expect(model.tour == nil)
        #expect(model.tab == .library)
    }

    // Opened with a file, the book's what they came for, whichever comes
    // first: the sample's on the shelf either way.
    @Test func aSharedFileBeforeTheTourStartsStillLeavesTheSampleBook() async throws {
        let model = shell()
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        #expect(model.onIPhoneBooks().map(\.book.id).contains(.sample))
        #expect(model.library.continueReading.map(\.book.id) == [.sample])
    }

    // Refused before the hinge reported: the tour starts once it does.
    @Test func aRefusedFileBeforeTheTourStartsLeavesItToStart() async throws {
        let model = shell()
        await model.importBooks([try ImportFixtures.drmMobi(in: folder)])
        #expect(model.tourWaitsForHinge)
        #expect(model.tour == nil)
        model.hingeReported(.closed)
        #expect(model.tour?.step == .cover)
        #expect(model.importFailures == [ImportFailure(fileName: "Kindred.mobi", reason: .drmProtected)])
    }

    // One that doesn't come in leaves the tour playing.
    @Test func aRefusedSharedFileLeavesTheTourPlaying() async throws {
        let model = started()
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        await model.importBooks([try ImportFixtures.drmMobi(in: folder)])
        #expect(model.tour?.step == .turnThePage)
        #expect(model.reading != nil)
        #expect(model.importFailures == [ImportFailure(fileName: "Kindred.mobi", reason: .drmProtected)])
    }

    // MARK: The sample book and setup

    // With the tour gone, the sample book is a book like any other: removing
    // the last one goes back to setup (decision 6).
    @Test func removingTheSampleBookWithNothingElseGoesBackToSetup() throws {
        let model = started(fold: .open)
        model.skipTour()
        let sample = try #require(model.onIPhoneBooks().first)
        #expect(model.library.hasBooks)
        model.removeImported(sample)
        #expect(!model.library.hasBooks)
        #expect(model.needsSetup)
        // And the tour stays played.
        #expect(!makeShell(tourRecord: record).tourWaitsForHinge)
    }

    // MARK: Show the tour

    /// The Settings a replay comes back to, in a shell that isn't new.
    private func settings(fold: HingeTransition.Fold?) -> ShellModel {
        let model = shell(state: .played)
        model.hingeReported(fold)
        model.openSettings()
        return model
    }

    @Test func aReplayStartsFromTheBeginningAndReturnsToSettings() {
        let model = settings(fold: .open)
        let routes = model[path: model.tab].routes
        model.showTour()
        #expect(model.tour?.step == .closeYourIPhone)
        #expect(model.tour?.isReplay == true)
        #expect(!model.needsSetup)
        model.skipTour()
        #expect(model.tour == nil)
        #expect(model[path: model.tab].routes == routes)
        #expect(model.tab == .home)
    }

    @Test func aReplayFoldedStartsOnTheCover() {
        let model = settings(fold: .closed)
        model.showTour()
        #expect(model.tour?.step == .cover)
        #expect(model.tour?.coverLine == "Open your iPhone to begin")
    }

    @Test func aReplayWithoutAFoldStartsInTheBook() async {
        let model = settings(fold: nil)
        model.showTour()
        #expect(model.tour?.step == .turnThePage)
        #expect(await eventually { model.reading?.book.id == .sample })
    }

    // A removed book stays removed, "cannot be recovered" stays true, and
    // it's not back on Home either.
    @Test func aReplayDoesNotPutARemovedBookBack() async {
        let model = settings(fold: .closed)
        model.showTour()
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        #expect(model.reading?.reader.fileURL == SampleBook.bundledFile)
        #expect(model.library.imported.all().isEmpty)
        #expect(model.onIPhoneBooks().isEmpty)
        #expect(model.library.continueReading.isEmpty)
        model.skipTour()
        #expect(model.library.imported.all().isEmpty)
        #expect(model.onIPhoneBooks().isEmpty)
        #expect(model.library.continueReading.isEmpty)
    }

    // A new install's book opens on Chapter I, and a place it already has stays.
    @Test func theSampleBookStartsOnChapterOneOnce() throws {
        let model = started()
        let key = try #require(SampleBook.book.primaryFile?.storageKey)
        #expect(model.places.store.position(forBook: key) == SampleBook.firstChapter)
        let later = ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.2)
        try model.places.store.save(later, forBook: key)
        model.installSampleBook()
        #expect(model.places.store.position(forBook: key) == later)
    }

    // A replay's reader has a place of its own, starting on Chapter I, that
    // goes with the tour.
    @Test func aReplayNeverSavesAPlace() async throws {
        let model = settings(fold: .closed)
        model.showTour()
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        let place = try #require(model.tourReplayPlace)
        let id = try #require(model.reading).reader.id
        #expect(place.positions.position(forBook: id) == SampleBook.firstChapter)
        let reader = ReaderModel(
            book: try #require(model.reading).reader, store: place.positions, bookmarks: ReaderBookmarks(bookID: id, store: place.bookmarks)
        )
        reader.handle(.opened(.init(restoredFrom: "start", sectionCount: 1, isFixedLayout: false)))
        reader.handle(.relocate(.init(cfi: "epubcfi(/6/4!/4/2/1:0)", fraction: 0.1)))
        #expect(place.positions.position(forBook: id) != nil)
        #expect(model.places.store.position(forBook: id) == nil)
        model.skipTour()
        #expect(model.tourReplayPlace == nil)
        #expect(!FileManager.default.fileExists(atPath: place.directory.path))
    }

    // Already on the shelf, a replay keeps its place and first spot alone.
    @Test func aReplayLeavesTheBookOnTheShelfAlone() async throws {
        let model = shell(state: .played)
        await model.importBooks([try ImportFixtures.epub(in: folder)])
        let sample = try #require(model.installSampleBook())
        try model.library.recents.record(try #require(model.onIPhoneBooks().last { $0.book.title == "Persuasion" }))
        model.library.mergeContinueReading()
        let reading = model.library.continueReading.map(\.book.id)
        model.hingeReported(.closed)
        model.showTour()
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading?.book.id == sample.book.id })
        model.skipTour()
        #expect(model.library.continueReading.map(\.book.id) == reading)
    }

    // On a replay with a server, Add books adds another (decision 36), over
    // the Settings it was replayed from.
    @Test func addBooksOnAReplayWithAServerOffersTheServerChoices() async throws {
        let model = shell(state: .played)
        await model.library.connect(RemoveServerTests.bookOrbit(id: LibrarySourceID(rawValue: "tour-server"), account: "octavo"))
        model.hingeReported(.closed)
        model.openSettings()
        let routes = model[path: model.tab].routes
        model.showTour()
        model.tourAddBooks()
        #expect(model.tour == nil)
        #expect(!model.showsSetup)
        #expect(!model.picksFiles)
        #expect(model[path: model.tab].routes == routes + [.setup(.choose)])
    }

    @Test func aReplayEndingOnAddYourBooksReturnsToSettingsOnSkip() {
        let model = settings(fold: .closed)
        model.installSampleBook()
        let routes = model[path: model.tab].routes
        model.showTour()
        model.tourAddBooks()
        #expect(model.showsSetup)
        model.skipAddingBooks()
        #expect(!model.showsSetup)
        #expect(model[path: model.tab].routes == routes)
    }

    @Test func aPlayedInstallShowsNoTour() {
        let model = shell(state: .played)
        model.hingeReported(.open)
        #expect(model.tour == nil)
        #expect(model.needsSetup)
    }

    // A fold while the cover is still opening the book leaves nothing behind.
    @Test func aFoldTakesAwayACoverStillOpening() async {
        let model = shell(state: .played)
        let sample = model.installSampleBook()!
        model.openBook(sample)
        #expect(await eventually { model.reading != nil })
        model.coverMotion = ReaderCoverMotion(
            cover: nil, title: "", author: "", coverFrame: CGRect(x: 0, y: 0, width: 10, height: 10), windowSize: CGSize(width: 20, height: 20),
            bookScreen: nil, spread: true, reduceMotion: false, paper: .white
        )
        model.hingeChanged(.fold)
        #expect(model.coverMotion == nil)
    }
}
