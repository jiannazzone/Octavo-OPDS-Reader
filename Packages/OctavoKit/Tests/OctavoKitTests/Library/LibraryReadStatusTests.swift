import Foundation
import OctavoKit
import Testing

// Measured against BookOrbit v3.6.0 (`docs/notes/book-status.md`).
struct LibraryReadStatusTests {
    @Test func continueReadingKeepsBooksStillOnTheGo() {
        let stays = LibraryReadStatus.allCases.filter(\.staysInContinueReading)
        #expect(stays == [.wantToRead, .reading, .onHold, .rereading])
    }

    @Test func startingMovesOnlyUnreadAndWantToRead() {
        #expect(LibraryReadStatus.allCases.filter { $0.whenStarted != nil } == [.unread, .wantToRead])
        #expect(LibraryReadStatus.wantToRead.whenStarted == .reading)
    }

    /// (status, progress, the filter that shows it)
    static let shelves: [(LibraryReadStatus?, Double?, LibraryFilter?)] = [
        (nil, nil, .unread),
        (nil, 0.3, nil),
        (.wantToRead, 0, .unread),
        (.wantToRead, 0.3, .reading),
        (.onHold, 0.3, .reading),
        (.onHold, 0, nil),
        (.onHold, 1, nil),
        (.reading, 0, .reading),
        (.rereading, 1, .reading),
        (.read, 0.4, .finished),
        (.skimmed, 0.3, nil),
        (.abandoned, 0, nil),
    ]

    @Test(arguments: shelves)
    func showsUnderTheFilterBookOrbitDoes(status: LibraryReadStatus?, progress: Double?, filter: LibraryFilter?) {
        #expect(LibraryFilter.showing(status, progress: progress) == filter)
    }
}
