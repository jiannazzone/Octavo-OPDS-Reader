import OctavoKit
import SwiftUI
import WebKit

/// The curl's turns (`ReaderCurl`). Like the other turns, a curl pictures the
/// page as it is and foliate turns at once underneath (`bridge.js` `turn`);
/// the new page's pictures follow once it's drawn. UIKit plays the curl: a
/// tap's whole, a finger's under the finger. A finger's turn is held until
/// the curl lands or falls back, so one that falls back is never saved.
extension ReaderModel {
    /// Whether a curl may start: the book open, nothing turning or folding.
    var canStartCurl: Bool {
        phase == .open && !isFolding && !isCurling && turnRun == nil && turn == nil
    }

    /// Whether there's a page to `side`: not at the book's start or end.
    /// Unknown counts as yes, and foliate finds out (`bridge.js` `turn`).
    func canTurn(_ side: ReaderTurnSide) -> Bool {
        relocation?.turns(side) ?? true
    }

    /// A tap, a key or the trackpad asked for a turn. One asked for while a
    /// tap's curl plays waits for it to land (UIKit's can't end early); one
    /// while a finger curls is dropped.
    func curlRequested(_ side: ReaderTurnSide) {
        if isCurling {
            if case .finger = curl.turning { return }
            if queuedTurns.count < 3 { queuedTurns.append(side) }
            return
        }
        guard let turn = startCurl(side, finger: false) else { return turnWithoutPictures(side) }
        // The new page is usually drawn about 50 ms later, so the curl waits
        // for it; one that takes longer (a chapter loading) curls anyway,
        // over the page's colour.
        Task {
            try? await Task.sleep(for: Self.longestWaitForPage)
            playCurl(turn)
        }
    }

    /// Pictures the page as it is on the curl's pages and has foliate turn
    /// underneath, held if a finger turns it. `nil` if it can't start.
    func startCurl(_ side: ReaderTurnSide, finger: Bool) -> ReaderTurn? {
        guard canStartCurl, curl.controller != nil, let geometry else {
            curlTrace("can't start a curl: phase \(String(describing: self.phase)), folding \(self.isFolding), curling \(self.isCurling), turn \(self.turnRun != nil || self.turn != nil)")
            return nil
        }
        closeNote(finger ? "a curl on the page" : "a tap elsewhere")
        if finger { queuedTurns.removeAll() }
        let size = geometry.size
        // UIKit's curl splits a spread in the middle.
        let spine: Double? = layout.columns == 2 ? Double(size.width) / 2 : nil
        let regions = ReaderTurn.regions(motion: .curl, side: side, size: size, spine: spine)
        guard let old = pictures(regions.old, size: size, spine: spine, afterScreenUpdates: false) else {
            curlTrace("can't start a curl: no pictures")
            return nil
        }
        turnCount += 1
        var turn = ReaderTurn(
            id: turnCount, motion: .curl, side: side, geometry: geometry, layout: layout, spine: spine,
            paper: Color(hex: appearance.background), old: old,
            oldPlace: ReaderPlace(chapter: chapter, location: location, fraction: shownFraction)
        )
        turn.hidesChapter = trip != nil
        isCurling = true
        curlTrace("\(finger ? "finger" : "tap") \(turn.id): starts \(side.rawValue)")
        curl.show(turn)
        Task { await turnUnderCurl(turn, held: finger, regions: regions.new) }
        return turn
    }

    /// Has foliate turn under the curl, then puts the new page's pictures on
    /// the pages coming in.
    private func turnUnderCurl(_ turn: ReaderTurn, held: Bool, regions: ReaderTurn.Regions) async {
        let started = ContinuousClock.now
        let answer = try? await page.callJavaScript(
            "return await window.octavo.turn(side, hold)", arguments: ["side": turn.side.rawValue, "hold": held]
        ) as? [String: Any]
        guard curl.pages.turn?.id == turn.id else { return }
        let moved = answer?["moved"] as? Bool == true
        curlTrace("\(held ? "finger" : "tap") \(turn.id): foliate \(moved ? "turned" : "didn't turn") after \(FoldReport.milliseconds(since: started)) ms")
        if !held { curlTapMoved = moved }
        guard moved else {
            // The book's first or last page: a tap's curl doesn't play.
            if !held, curl.turning == nil { curlEnded(id: turn.id, completed: false, finger: false) }
            return
        }
        let place = Self.place(turnedTo: answer)
        // Taken before the pages change: taking them updates the screen,
        // which reads the pages.
        let new = pictures(regions, size: turn.size, spine: turn.spine, afterScreenUpdates: true) ?? ReaderTurn.Pictures()
        guard curl.pages.turn?.id == turn.id else { return }
        curl.pages.turn?.newPlace = place
        curl.pages.turn?.new = new
        lastTurnDrawnAfter = FoldReport.milliseconds(since: started)
        if !held { playCurl(turn) }
        // A snapshot taken as the page reached the screen can miss it by a
        // frame; a second look settles it.
        guard !regions.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(100))
        guard curl.pages.turn?.id == turn.id, let fresh = pictures(regions, size: turn.size, spine: turn.spine, afterScreenUpdates: false) else { return }
        curl.pages.turn?.new = fresh
    }

    /// A tap's curl plays, once.
    private func playCurl(_ turn: ReaderTurn) {
        guard curl.pages.turn?.id == turn.id, curl.turning == nil else { return }
        curl.play(turn)
    }

    /// The curl landed (`completed`) or fell back. A finger's held turn is
    /// kept or turned back; then the pages clear over the live page and a
    /// turn asked for meanwhile starts.
    func curlEnded(id: Int, completed: Bool, finger: Bool) {
        curlTrace("\(finger ? "finger" : "tap") \(id): \(completed ? "landed" : "fell back")")
        guard curl.pages.turn?.id == id else { return }
        Task {
            // Whether foliate turned: a tap's answer, or the held turn's end.
            var moved = curlTapMoved
            if finger {
                let ended = try? await page.callJavaScript("return await window.octavo.endTurn(keep)", arguments: ["keep": completed])
                moved = ended as? Bool == true
            }
            guard curl.pages.turn?.id == id else { return }
            curlTapMoved = false
            if completed, moved { pageTurned() }
            isCurling = false
            curl.reset()
            if !queuedTurns.isEmpty { curlRequested(queuedTurns.removeFirst()) }
        }
    }

    /// The hinge moved mid-curl: the curl goes with the controller, which is
    /// remade for the new spine. A finger's turn ends where it was going,
    /// forward, as a finger's other turns do. Returns the bridge call that
    /// ends a held turn, to run before `hold`.
    func finishCurlForFold() -> String? {
        let finger = if case .finger = curl.turning { true } else { false }
        isCurling = false
        curl.reset()
        return finger ? "window.octavo.endTurn(true); " : nil
    }

    /// The curl's controller left the page (Page Turn changed, or the reader
    /// closed) with a curl under way.
    func curlGone() {
        guard isCurling else { return }
        let finger = if case .finger = curl.turning { true } else { false }
        isCurling = false
        curl.reset()
        if finger { call("return await window.octavo.endTurn(true)") }
    }
}
