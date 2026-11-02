import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// The capsule offering the server's place (Adam, 2026-11-02).
struct ReaderServerPlaceTests {
    static func place(_ fraction: Double) -> ReaderServerPlace {
        ReaderServerPlace(position: ReadingPosition(cfi: "epubcfi(/6/8!/4/352)", fraction: fraction), fraction: fraction, chapter: "CHAPTER 54. The Town-Ho's Story.", offeredOn: "epubcfi(/6/6!/4/20/1:0)")
    }

    // Like the footer, so going there shows the same number.
    @Test func theLabelRoundsDownLikeTheFooter() {
        #expect(Self.place(0.629).label == "BookOrbit: 62%")
        #expect(Self.place(1).label == "BookOrbit: 100%")
    }
}
