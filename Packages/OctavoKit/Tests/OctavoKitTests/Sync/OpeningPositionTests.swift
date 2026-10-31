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
