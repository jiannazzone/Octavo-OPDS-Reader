import Foundation
import OctavoKit
import Testing

struct OpeningPositionTests {
    let earlier = Date(timeIntervalSince1970: 1_800_000_000)
    let later = Date(timeIntervalSince1970: 1_800_000_600)

    let serverCFI = ReadingPosition(cfi: "epubcfi(/6/14!/4/2/10/1:120)", fraction: 0.375)
    let deviceCFI = ReadingPosition(cfi: "epubcfi(/6/12!/4/2,/6/1:0,/8/1:40)", fraction: 0.31)

    private func local(needsPush: Bool, at date: Date) -> LocalReadingProgress {
        LocalReadingProgress(position: deviceCFI, modifiedAt: date, needsPush: needsPush)
    }

    // Records saved before sync times existed read back as never synced.
    @Test func aRecordWithoutASyncTimeDecodes() throws {
        let json = #"{"position":{"cfi":"epubcfi(/6/4!/4)","fraction":0.1},"modifiedAt":0,"needsPush":false}"#
        let record = try JSONDecoder().decode(LocalReadingProgress.self, from: Data(json.utf8))
        #expect(record.syncedAt == nil)
        #expect(record.position.fraction == 0.1)
    }

    @Test func serverCFIWinsWhenTheDeviceHasNothingUnpushed() {
        let remote = SyncedPosition(position: serverCFI, updatedAt: earlier)
        // Even if the device's clock says it moved later: it already pushed that.
        #expect(OpeningPosition.choose(local: local(needsPush: false, at: later), remote: remote) == .remote(serverCFI))
        #expect(OpeningPosition.choose(local: nil, remote: remote) == .remote(serverCFI))
    }

    @Test func laterTimestampWinsWhenBothMoved() {
        let olderRemote = SyncedPosition(position: serverCFI, updatedAt: earlier)
        #expect(OpeningPosition.choose(local: local(needsPush: true, at: later), remote: olderRemote) == .local(deviceCFI))

        let newerRemote = SyncedPosition(position: serverCFI, updatedAt: later)
        #expect(OpeningPosition.choose(local: local(needsPush: true, at: earlier), remote: newerRemote) == .remote(serverCFI))
    }

    @Test func serverWinsTiesAndUndatedPositions() {
        let tie = SyncedPosition(position: serverCFI, updatedAt: later)
        #expect(OpeningPosition.choose(local: local(needsPush: true, at: later), remote: tie) == .remote(serverCFI))

        let undated = SyncedPosition(position: serverCFI, updatedAt: nil)
        #expect(OpeningPosition.choose(local: local(needsPush: true, at: later), remote: undated) == .remote(serverCFI))
    }

    @Test func localWinsWhenTheServerHasNoCFI() {
        let percentageOnly = SyncedPosition(position: ReadingPosition(fraction: 0.9), updatedAt: later)
        #expect(OpeningPosition.choose(local: local(needsPush: false, at: earlier), remote: percentageOnly) == .local(deviceCFI))
        #expect(OpeningPosition.choose(local: local(needsPush: false, at: earlier), remote: nil) == .local(deviceCFI))
    }

    @Test func fallsBackToTheServerFractionThenTheStart() {
        let percentageOnly = SyncedPosition(position: ReadingPosition(fraction: 0.9), updatedAt: later)
        #expect(OpeningPosition.choose(local: nil, remote: percentageOnly) == .remote(ReadingPosition(fraction: 0.9)))

        let zero = SyncedPosition(position: ReadingPosition(fraction: 0), updatedAt: later)
        #expect(OpeningPosition.choose(local: nil, remote: zero) == .start)
        #expect(OpeningPosition.choose(local: nil, remote: nil) == .start)
        #expect(OpeningPosition.start.position == nil)
    }
}

/// Another reader's place (KOReader's): it moves you only forward, only once
/// it changed, and never over a place this iPhone hasn't sent.
struct OpeningPositionElsewhereTests {
    /// Spine item 6 (DocFragment[7]), 41%.
    let ours = ReadingPosition(cfi: "epubcfi(/6/14!/4/2/2)", fraction: 0.41, xpointer: "/body/DocFragment[7]/body/div/p[3].0")

    private func local(needsPush: Bool = false) -> LocalReadingProgress {
        LocalReadingProgress(position: ours, modifiedAt: .now, needsPush: needsPush)
    }

    private func theirs(_ fragment: Int, _ fraction: Double, _ change: SyncedPosition.Change) -> SyncedPosition {
        SyncedPosition(position: ReadingPosition(fraction: fraction, xpointer: "/body/DocFragment[\(fragment)]/body/p.0"), origin: .elsewhere(change))
    }

    @Test func withNothingOnTheIPhoneItOpensThere() {
        let remote = theirs(3, 0.12, .first)
        #expect(OpeningPosition.choose(local: nil, remote: remote) == .remote(remote.position))
        let start = SyncedPosition(position: ReadingPosition(fraction: 0), origin: .elsewhere(.first))
        #expect(OpeningPosition.choose(local: nil, remote: start) == .start)
    }

    @Test(arguments: [SyncedPosition.Change.first, .unchanged])
    func aPlaceItHasntSeenMoveKeepsTheLocalPlace(change: SyncedPosition.Change) {
        #expect(OpeningPosition.choose(local: local(), remote: theirs(9, 0.6, change)) == .local(ours))
    }

    @Test func aMoveAheadIsFollowed() {
        let laterSection = theirs(9, 0.6, .moved)
        #expect(OpeningPosition.choose(local: local(), remote: laterSection) == .remote(laterSection.position))
        // A later section counts, whatever its percentage.
        let laterButLower = theirs(8, 0.39, .moved)
        #expect(OpeningPosition.choose(local: local(), remote: laterButLower) == .remote(laterButLower.position))
        let furtherInTheSame = theirs(7, 0.43, .moved)
        #expect(OpeningPosition.choose(local: local(), remote: furtherInTheSame) == .remote(furtherInTheSame.position))
    }

    @Test func aMoveBackOrTooCloseToTellIsnt() {
        #expect(OpeningPosition.choose(local: local(), remote: theirs(5, 0.3, .moved)) == .local(ours))
        #expect(OpeningPosition.choose(local: local(), remote: theirs(6, 0.45, .moved)) == .local(ours))
        // Within the engines' difference in the same section.
        #expect(OpeningPosition.choose(local: local(), remote: theirs(7, 0.415, .moved)) == .local(ours))
    }

    @Test func neverOverAPlaceTheIPhoneHasntSent() {
        #expect(OpeningPosition.choose(local: local(needsPush: true), remote: theirs(9, 0.6, .moved)) == .local(ours))
    }

    @Test func theBooksScreenSendsOnlyOverAPlaceItHasSeen() {
        #expect(OpeningPosition.mayPush(local(needsPush: true), over: theirs(5, 0.3, .unchanged)))
        #expect(!OpeningPosition.mayPush(local(needsPush: true), over: theirs(5, 0.3, .first)))
        #expect(!OpeningPosition.mayPush(local(needsPush: true), over: theirs(5, 0.3, .moved)))
        #expect(OpeningPosition.mayPush(local(needsPush: true), over: nil))
        #expect(!OpeningPosition.mayPush(local(needsPush: false), over: nil))
        // BookOrbit's, as before: only if the iPhone's place wins.
        let older = SyncedPosition(position: ReadingPosition(cfi: "epubcfi(/6/4!/4)", fraction: 0.1), updatedAt: .distantPast)
        #expect(OpeningPosition.mayPush(local(needsPush: true), over: older))
    }

    @Test func readsTheSpineItemFromEitherForm() {
        #expect(ReadingPosition(cfi: "epubcfi(/6/14!/4/2/2)", fraction: 0).spineIndex == 6)
        #expect(ReadingPosition(cfi: "epubcfi(/6/2!/4)", fraction: 0).spineIndex == 0)
        #expect(ReadingPosition(fraction: 0, xpointer: "/body/DocFragment[7].0").spineIndex == 6)
        #expect(ReadingPosition(fraction: 0, xpointer: "/body/DocFragment[0].0").spineIndex == nil)
        #expect(ReadingPosition(fraction: 0, xpointer: "12").spineIndex == nil)
        #expect(ReadingPosition(cfi: "epubcfi(/6/13!/4)", fraction: 0).spineIndex == nil)
    }
}
