import Foundation
import SwiftUI
import Testing
@testable import Octavo

/// Margins as a slider's five steps (decision 8): what's saved, what
/// VoiceOver reads, and that a setting saved before the slider still loads.
/// Where each step puts the text is in `ReaderLayoutTests`.
@MainActor
@Suite(.temporaryFiles)
struct ReaderMarginsTests {
    private func stored(in defaults: UserDefaults) -> ReaderMargins {
        AppStorage(wrappedValue: ReaderMargins.standard, ReaderMargins.key, store: defaults).wrappedValue
    }

    @Test func savedByName() {
        #expect(ReaderMargins.key == "reader.margins")
        #expect(ReaderMargins.allCases.map(\.rawValue) == ["narrow", "mediumNarrow", "medium", "mediumWide", "wide"])
    }

    @Test func voiceOverNames() {
        #expect(ReaderMargins.allCases.map(\.name) == ["Narrow", "Fairly Narrow", "Medium", "Fairly Wide", "Wide"])
    }

    // Saved by the segmented picker: its three load as the slider's ends and
    // middle.
    @Test(arguments: [("narrow", ReaderMargins.narrow, 0), ("medium", .medium, 2), ("wide", .wide, 4)])
    func savedBeforeTheSliderStillLoads(saved: String, margins: ReaderMargins, step: Int) {
        let defaults = UserDefaults.testSuite("margins")
        defaults.set(saved, forKey: ReaderMargins.key)
        #expect(stored(in: defaults) == margins)
        #expect(margins.step == step)
        #expect(ReaderMargins(step: step) == margins)
    }

    @Test func mediumUntilAnotherIsSaved() {
        let defaults = UserDefaults.testSuite("margins")
        #expect(stored(in: defaults) == .medium)
        defaults.set("mediumWide", forKey: ReaderMargins.key)
        #expect(stored(in: defaults) == .mediumWide)
        defaults.set("extraWide", forKey: ReaderMargins.key)
        #expect(stored(in: defaults) == .medium)
    }

    @Test func stepsRunNarrowToWide() {
        #expect(ReaderMargins.allCases.map(\.step) == [0, 1, 2, 3, 4])
        #expect((0...4).map(ReaderMargins.init(step:)) == ReaderMargins.allCases)
        // Out of range lands on the ends.
        #expect(ReaderMargins(step: -1) == .narrow)
        #expect(ReaderMargins(step: 9) == .wide)
    }
}
