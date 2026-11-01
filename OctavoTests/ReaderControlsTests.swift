import Foundation
import Testing
@testable import Octavo

/// The controls (decision 7) and the place they show: each page's footer
/// and the progress bar.
struct ReaderControlsTests {
    // MARK: Controls

    @Test func aTapShowsTheButtonsAndTheBarAndTheNextHidesThem() {
        var controls = ReaderControls()
        #expect(!controls.buttonsVisible)
        controls.toggle()
        #expect(controls.buttonsVisible)
        #expect(controls.showsBar)
        #expect(controls.coversPage)
        controls.hide()
        #expect(!controls.buttonsVisible)
        #expect(!controls.coversPage)
    }

    // The buttons sit in the column and never cover text; the bar does, so
    // it never stays.
    @Test func alwaysShowControlsKeepsTheButtonsAndTogglesTheBar() {
        var controls = ReaderControls(alwaysShowsButtons: true)
        #expect(controls.buttonsVisible)
        #expect(!controls.coversPage)
        controls.toggle()
        #expect(controls.showsBar)
        controls.hide()
        #expect(controls.buttonsVisible)
        #expect(!controls.showsBar)
        controls.toggle()
        controls.toggle()
        #expect(!controls.showsBar)
    }

    @Test func turningTheSettingOffHidesButtonsThatOnlyItKeptUp() {
        var controls = ReaderControls(alwaysShowsButtons: true)
        controls.alwaysShowsButtons = false
        #expect(!controls.buttonsVisible)
    }

    // MARK: Place

    static let location = ReaderMessage.Relocation.Location(current: 290, next: 291, total: 974)

    @Test func footerAndBarCountFromOne() {
        let place = ReaderPlace(chapter: "CHAPTER 36. The Quarter-Deck.", location: Self.location, fraction: 0.3005)
        #expect(place.first == 291)
        #expect(place.last == 292)
        #expect(place.footer(spread: false) == "291 of 974 · 30%")
        #expect(place.barLine(spread: false) == "Page 291 of 974 · 30%")
    }

    @Test func aSpreadShowsTheLocationsItCovers() {
        let place = ReaderPlace(chapter: nil, location: Self.location, fraction: 0.3)
        #expect(place.footer(spread: true) == "291–292 of 974 · 30%")
        #expect(place.barLine(spread: true) == "Pages 291–292 of 974 · 30%")
        let one = ReaderPlace(chapter: nil, location: .init(current: 290, next: 290, total: 974), fraction: 0.3)
        #expect(one.barLine(spread: true) == "Page 291 of 974 · 30%")
    }

    // 100% only at the very end.
    @Test func percentRoundsDown() {
        #expect(ReaderPlace(chapter: nil, location: nil, fraction: 0.999).percent == "99%")
        #expect(ReaderPlace(chapter: nil, location: nil, fraction: 1).percent == "100%")
        #expect(ReaderPlace(chapter: nil, location: nil, fraction: 0).percent == "0%")
    }

    @Test func withoutLocationsOnlyThePercentage() {
        let place = ReaderPlace(chapter: nil, location: .init(current: nil, total: nil), fraction: 0.42)
        #expect(place.footer(spread: false) == "42%")
        #expect(place.barLine(spread: true) == "42%")
    }

    @Test func theLastLocationNeverPassesTheTotal() {
        let place = ReaderPlace(chapter: nil, location: .init(current: 973, next: 974, total: 974), fraction: 1)
        #expect(place.first == 974)
        #expect(place.last == 974)
    }

    static let toc: [ReaderMessage.TOCEntry] = [
        .init(label: "Title", fraction: 0),
        .init(label: "CHAPTER 1. Loomings.", fraction: 0.01),
        .init(label: "CHAPTER 36. The Quarter-Deck.", fraction: 0.3),
        .init(label: "Broken link", fraction: nil),
        .init(label: "CHAPTER 37. Sunset.", fraction: 0.31),
    ]

    @Test func theScrubberNamesTheChapterUnderIt() {
        #expect(ReaderPlace.chapterName(at: 0.305, in: Self.toc) == "CHAPTER 36. The Quarter-Deck.")
        #expect(ReaderPlace.chapterName(at: 0.3, in: Self.toc) == "CHAPTER 36. The Quarter-Deck.")
        #expect(ReaderPlace.chapterName(at: 0.5, in: Self.toc) == "CHAPTER 37. Sunset.")
        #expect(ReaderPlace.chapterName(at: 0, in: Self.toc) == "Title")
        #expect(ReaderPlace.chapterName(at: 0.5, in: []) == nil)
    }

    @Test func aScrubberPointHasALocation() {
        let place = ReaderPlace(fraction: 0.5, toc: Self.toc, total: 974)
        #expect(place.chapter == "CHAPTER 37. Sunset.")
        #expect(place.barLine(spread: false) == "Page 488 of 974 · 50%")
        #expect(ReaderPlace(fraction: 1, toc: [], total: 974).first == 974)
    }

    // MARK: Bridge messages

    @Test func openedCarriesTheContents() throws {
        let json = #"{"type":"opened","restoredFrom":"cfi","title":"Moby Dick","sectionCount":20,"isFixedLayout":false,"toc":[{"label":"CHAPTER 1. Loomings.","fraction":0.01},{"label":"Etymology","fraction":null}]}"#
        guard case .opened(let opened) = try ReaderMessage.decode(json) else {
            Issue.record("not opened")
            return
        }
        #expect(opened.toc == [.init(label: "CHAPTER 1. Loomings.", fraction: 0.01), .init(label: "Etymology", fraction: nil)])
    }

    @Test func anOlderBridgeSendsNoContents() throws {
        let json = #"{"type":"opened","restoredFrom":"start","title":null,"sectionCount":1,"isFixedLayout":false}"#
        guard case .opened(let opened) = try ReaderMessage.decode(json) else {
            Issue.record("not opened")
            return
        }
        #expect(opened.toc == nil)
    }

    @Test func relocateCarriesTheLocationAtThePagesEnd() throws {
        let json = #"{"type":"relocate","cfi":null,"fraction":0.3,"location":{"current":290,"next":291,"total":974}}"#
        guard case .relocate(let relocation) = try ReaderMessage.decode(json) else {
            Issue.record("not relocate")
            return
        }
        #expect(relocation.location == Self.location)
    }

    @Test func dismissIsATap() throws {
        #expect(try ReaderMessage.decode(#"{"type":"tap","zone":"dismiss"}"#) == .tap(zone: "dismiss"))
    }
}
