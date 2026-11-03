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
        #expect(TourFlow(fold: nil).step == .welcome)
    }

    @Test func theWholeTourInOrder() {
        var flow = TourFlow(fold: .open)
        flow.handle(.folded)
        #expect(flow.step == .cover)
        #expect(flow.coverLine == "Open your iPhone to begin")
        flow.handle(.unfolded)
        #expect(flow.step == .welcome)
        flow.handle(.start)
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

    @Test func continueWithoutClosingGoesStraightToWelcome() {
        var flow = TourFlow(fold: .open)
        flow.handle(.continueWithoutClosing)
        #expect(flow.step == .welcome)
    }

    // A step only moves on for what it asks for.
    @Test func stepsIgnoreWhatTheyDoNotAskFor() {
        var flow = TourFlow(fold: .open)
        flow.handle(.start)
        flow.handle(.pageTurned)
        #expect(flow.step == .closeYourIPhone)
        flow.handle(.continueWithoutClosing)
        flow.handle(.pageTurned)
        flow.handle(.done)
        flow.handle(.reader(.controls))
        #expect(flow.step == .welcome)
        flow.handle(.start)
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
        flow.handle(.start)
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
        flow.handle(.start)
        flow.handle(.pageTurned)
        flow.handle(.reader(.controls))
        flow.handle(.reader(.otherPanel))
        #expect(flow.step == .tapAa)
    }

    // With the panel already open from looking ahead, the step is done.
    @Test func aPanelOpenedEarlyCountsWhenItsStepComes() {
        var flow = TourFlow(fold: nil)
        flow.handle(.start)
        flow.handle(.reader(.panel))
        #expect(flow.step == .turnThePage)
        flow.handle(.pageTurned)
        flow.handle(.reader(.controls))
        #expect(flow.step == .tapAa)
    }

    // Done is there as long as the card is, with or without the panel.
    @Test func closingThePanelKeepsTheCardWithDone() {
        var flow = TourFlow(fold: nil)
        flow.handle(.start)
        flow.handle(.pageTurned)
        flow.handle(.reader(.controls))
        flow.handle(.reader(.panel))
        flow.handle(.reader(.hidden))
        #expect(flow.step == .makeItYours)
        flow.handle(.done)
        #expect(flow.step == .addYourBooks)
    }

    // Folding mid-tour closes the book; unfolding resumes at the same step.
    @Test(arguments: [TourFlow.Event.start, .pageTurned, .reader(.controls), .reader(.panel), .done])
    func aFoldResumesAtTheSameStep(upTo last: TourFlow.Event) {
        var flow = TourFlow(fold: .closed)
        flow.handle(.unfolded)
        for event in [TourFlow.Event.start, .pageTurned, .reader(.controls), .reader(.panel), .done] {
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

    // The words are decision 29's, and what each step marks.
    @Test func cardsDotsAndRings() {
        typealias Step = TourFlow.Step
        #expect(Step.closeYourIPhone.card == nil)
        #expect(Step.cover.card == nil)
        #expect(Step.welcome.card?.title == "Welcome to Octavo")
        #expect(Step.welcome.card?.message == "Try things out on this book. It’s yours to keep.")
        #expect(Step.turnThePage.card?.message == "Tap the right page, or swipe. Tap the left page to go back.")
        #expect(Step.bringUpControls.card?.message == "Tap ··· whenever you need them.")
        #expect(Step.tapAa.card?.title == "Make it yours")
        #expect(Step.tapAa.card?.message == "Tap Aa for themes, text size and fonts.")
        #expect(Step.makeItYours.card?.title == "The page changes as you go")
        #expect(Step.makeItYours.card?.message == "Come back to Aa any time.")
        #expect(Step.addYourBooks.card?.message == "From your server, or from Files.")
        // Five dots; Make it yours is one step.
        #expect([Step.welcome, .turnThePage, .bringUpControls, .tapAa, .makeItYours, .addYourBooks].map(\.dot) == [0, 1, 2, 3, 3, 4])
        #expect(Step.turnThePage.ring == .rightPage)
        #expect(Step.bringUpControls.ring == .columnButton(ReaderColumnButton.showControls))
        #expect(Step.tapAa.ring == .columnButton(ReaderColumnButton.textAndTheme))
        #expect(Step.welcome.ring == nil)
        #expect(Step.makeItYours.ring == nil)
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

    // An older build's install has its server, books or places: Settings only.
    @Test func anExistingInstallIsSettledOnce() {
        let record = TourRecord.temporary()
        #expect(!record.shouldPlay(hasEarlierData: true, protectedDataAvailable: true))
        #expect(record.state == .played)
        // Even with everything then removed.
        #expect(!record.shouldPlay(hasEarlierData: false, protectedDataAvailable: true))
    }

    // An older build's install with nothing in it still has the marker.
    @Test func theInstallMarkerSettlesAnExistingInstall() {
        let record = TourRecord.temporary()
        record.settleEarlierInstall()
        #expect(record.state == nil)
        record.defaults.set(true, forKey: ServerCredentials.installedKey)
        record.settleEarlierInstall()
        #expect(record.state == .played)
    }

    @Test func theMarkerDoesNotEndATourUnderWay() {
        let record = TourRecord.temporary(state: .playing)
        record.defaults.set(true, forKey: ServerCredentials.installedKey)
        record.settleEarlierInstall()
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
        for event in [TourFlow.Event.start, .pageTurned, .reader(.controls), .reader(.panel), .done] { model.tourEvent(event) }
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
        #expect(model.tour?.step == .welcome)
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
        #expect(model.tour?.step == .welcome)
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
        model.tourEvent(.start)
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

    // One that doesn't come in leaves the tour playing.
    @Test func aRefusedSharedFileLeavesTheTourPlaying() async throws {
        let model = started()
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        await model.importBooks([try ImportFixtures.drmMobi(in: folder)])
        #expect(model.tour?.step == .welcome)
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
        #expect(model.tour?.step == .welcome)
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

    // A replay's reader has a place of its own, starting empty, that goes with
    // the tour.
    @Test func aReplayNeverSavesAPlace() async throws {
        let model = settings(fold: .closed)
        model.showTour()
        model.hingeChanged(.unfold)
        #expect(await eventually { model.reading != nil })
        let place = try #require(model.tourReplayPlace)
        let id = try #require(model.reading).reader.id
        #expect(place.positions.position(forBook: id) == nil)
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

    // On a replay with a server there's no second one to add: Add books is
    // the Files picker, and no setup screen.
    @Test func addBooksOnAReplayWithAServerOffersFiles() async throws {
        let model = shell(state: .played)
        await model.library.connect(RemoveServerTests.bookOrbit(id: LibrarySourceID(rawValue: "tour-server"), account: "octavo"))
        model.hingeReported(.closed)
        model.openSettings()
        let routes = model[path: model.tab].routes
        model.showTour()
        model.tourAddBooks()
        #expect(model.tour == nil)
        #expect(!model.showsSetup)
        #expect(model.picksFiles)
        #expect(model[path: model.tab].routes == routes)
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
