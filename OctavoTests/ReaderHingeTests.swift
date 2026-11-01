import Foundation
import Testing
@testable import Octavo

/// Book mode from the hinge angle (decision 9), and repeated hinge reports.
struct ReaderHingeTests {
    /// A hinge after these reports, in order.
    static func hinge(_ path: [(ReaderPosture, Double)]) -> ReaderHinge {
        var hinge = ReaderHinge()
        for (posture, angle) in path { _ = hinge.update(posture: posture, angle: angle) }
        return hinge
    }

    static let flat = [(ReaderPosture.open, 180.0)]
    static let unfolding = [(ReaderPosture.closed, 0.0), (.halfOpen, 36.7)]

    // MARK: Entering

    @Test(arguments: [150.0, 146.7, 120, 90, 60])
    func closingFromFlatEntersBookModeInTheRange(angle: Double) {
        #expect(Self.hinge(Self.flat + [(.halfOpen, angle)]).isBookMode)
    }

    @Test(arguments: [176.7, 160, 153.3, 150.1])
    func closingFromFlatStaysFlatAboveTheRange(angle: Double) {
        #expect(!Self.hinge(Self.flat + [(.halfOpen, angle)]).isBookMode)
    }

    @Test(arguments: [36.7, 50, 59.9])
    func openingFromFoldedStaysFlatBelowTheRange(angle: Double) {
        #expect(!Self.hinge(Self.unfolding + [(.halfOpen, angle)]).isBookMode)
    }

    @Test(arguments: [60.0, 63.3, 90])
    func openingFromFoldedEntersBookModeInTheRange(angle: Double) {
        #expect(Self.hinge(Self.unfolding + [(.halfOpen, angle)]).isBookMode)
    }

    // MARK: Leaving

    @Test(arguments: [150.1, 153.3, 156.7, 159.9])
    func bookModeHoldsInTheBufferAboveTheRange(angle: Double) {
        #expect(Self.hinge(Self.flat + [(.halfOpen, 90), (.halfOpen, angle)]).isBookMode)
    }

    @Test(arguments: [(ReaderPosture.halfOpen, 160.0), (.halfOpen, 176.7), (.open, 180)])
    func openingFlatLeavesBookMode(posture: ReaderPosture, angle: Double) {
        #expect(!Self.hinge(Self.flat + [(.halfOpen, 90), (posture, angle)]).isBookMode)
    }

    @Test(arguments: [59.9, 50, 36.7])
    func bookModeHoldsWhileClosingTowardsTheFold(angle: Double) {
        #expect(Self.hinge(Self.flat + [(.halfOpen, 90), (.halfOpen, angle)]).isBookMode)
    }

    @Test func foldingLeavesBookMode() {
        #expect(!Self.hinge(Self.flat + [(.halfOpen, 90), (.closed, 33.3)]).isBookMode)
    }

    /// Flapping across the upper boundary doesn't flicker.
    @Test func noFlickerAtTheUpperBoundary() {
        var hinge = Self.hinge(Self.flat + [(.halfOpen, 146.7)])
        #expect(hinge.isBookMode)
        for angle in [153.3, 150, 156.7, 146.7, 153.3] {
            #expect(!hinge.update(posture: .halfOpen, angle: angle).contains(.bookMode))
            #expect(hinge.isBookMode)
        }
        #expect(hinge.update(posture: .halfOpen, angle: 160).contains(.bookMode))
        for angle in [156.7, 163.3, 153.3] {
            #expect(!hinge.update(posture: .halfOpen, angle: angle).contains(.bookMode))
            #expect(!hinge.isBookMode)
        }
    }

    @Test func noHingeIsNeverBookMode() {
        #expect(!Self.hinge([(.noHinge, 90)]).isBookMode)
        var hinge = ReaderHinge()
        #expect(!hinge.update(posture: .halfOpen, angle: nil).contains(.bookMode))
    }

    // MARK: Repeats

    @Test func repeatedReportsChangeNothing() {
        var hinge = ReaderHinge()
        #expect(hinge.update(posture: .halfOpen, angle: 90) == [.posture, .angle, .bookMode])
        for _ in 0..<15 {
            #expect(hinge.update(posture: .halfOpen, angle: 90).isEmpty)
        }
        #expect(hinge.isBookMode)
    }

    @Test func aNewAngleInTheSamePostureIsOnlyAnAngle() {
        var hinge = Self.hinge([(.halfOpen, 90)])
        #expect(hinge.update(posture: .halfOpen, angle: 93.3) == .angle)
        #expect(hinge.update(posture: .open, angle: 180) == [.posture, .angle, .bookMode])
    }

    @Test func thresholdsCanBeTuned() {
        var hinge = ReaderHinge()
        hinge.thresholds = BookModeThresholds(lowestEntry: 70, highestEntry: 140, flat: 170)
        _ = hinge.update(posture: .open, angle: 180)
        _ = hinge.update(posture: .halfOpen, angle: 145)
        #expect(!hinge.isBookMode)
        _ = hinge.update(posture: .halfOpen, angle: 140)
        #expect(hinge.isBookMode)
        _ = hinge.update(posture: .halfOpen, angle: 165)
        #expect(hinge.isBookMode)
    }

    // MARK: Tap mode

    @Test func tapModeArgumentsForTheBridge() {
        let mode = ReaderTapMode(isBook: true, columnStart: 867)
        #expect(mode.scriptArguments["book"] as? Bool == true)
        #expect(mode.scriptArguments["columnStart"] as? Double == 867)
        #expect(ReaderTapMode().scriptArguments["columnStart"] is NSNull)
    }
}
