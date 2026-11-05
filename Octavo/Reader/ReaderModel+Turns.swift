import OctavoKit
import SwiftUI
import WebKit

/// One turn behind `ReaderModel.turn`, which the views draw: where foliate
/// is with it, and where the pictures are going.
final class ReaderTurnRun {
    let id: Int
    let side: ReaderTurnSide
    let motion: ReaderTurnMotion
    /// A finger holds it; it plays on its own once let go.
    let interactive: Bool
    /// Whether foliate turned (not at the book's start or end), once it has.
    var moved: Bool?
    /// foliate has turned and drawn the new page, or found none.
    var drawn = false
    /// Where the pictures are going: 1 finishes the turn, 0 lets the page
    /// fall back. `nil` while a finger holds it.
    var target: Double?
    /// The way there, while it's playing.
    var ramp: ReaderTurnRamp?
    var animationDone = false
    let startedAt = ContinuousClock.now
    /// Milliseconds from the start until the new page's pictures were in.
    var drawnAfter: Int?

    init(id: Int, side: ReaderTurnSide, motion: ReaderTurnMotion, interactive: Bool) {
        self.id = id
        self.side = side
        self.motion = motion
        self.interactive = interactive
    }

    /// Done drawing and going forward: it can end early for the next one.
    var canEndEarly: Bool { drawn && target == 1 }
}

/// Page turns (decision 27). A turn snapshots the page (2–5 ms), lays the
/// pictures over it (`ReaderTurn`), and has foliate turn at once underneath
/// (`bridge.js` `turn`). The new page is drawn 20–70 ms later, and its
/// pictures follow; until then the page's colour shows where it will be.
/// Once the motion has played, the pictures go and the web view shows the
/// new page. The turn is foliate's own, so the position and its syncing
/// are as they were; a swipe's turn is held back until it's let go, and one
/// that falls back is turned back and never saved.
extension ReaderModel {
    /// A tap, a key or the trackpad asked for a turn: the whole turn plays.
    /// One asked for while the last is still being drawn waits for it; once
    /// that's drawn, it ends early so the next starts at once.
    func turnRequested(_ side: ReaderTurnSide) {
        // A tap that beat the page to hearing a note had opened: it only closes it.
        guard note == nil else { return closeNote("a tap elsewhere, early") }
        guard phase == .open, !isFolding else { return }
        guard let run = turnRun else { return startTurn(side, interactive: false) }
        if queuedTurns.count < 3 { queuedTurns.append(side) }
        if run.canEndEarly { endTurn() }
    }

    /// A finger turning the page.
    func swiped(_ swipe: ReaderTurnSwipe) {
        switch swipe.phase {
        case .began:
            closeNote("a swipe on the page")
            guard phase == .open, !isFolding, let side = swipe.side else { return }
            queuedTurns.removeAll()
            if let run = turnRun {
                // A turn still being drawn or falling back: this finger waits.
                guard run.canEndEarly else { return }
                endTurn()
            }
            startTurn(side, interactive: true)
        case .changed:
            guard let run = turnRun, run.interactive, run.target == nil, let turn, turn.id == run.id else { return }
            var progress = ReaderTurnDrag.progress(dx: swipe.dx, side: run.side, motion: run.motion, pageWidth: turn.pageWidth)
            // The book's first or last page: it barely gives.
            if run.moved == false { progress = min(progress, 0.06) }
            self.turn?.progress = progress
        case .ended, .cancelled:
            guard let run = turnRun, run.interactive, run.target == nil, let turn, turn.id == run.id else { return }
            let finishes = swipe.phase == .ended && run.moved != false
                && ReaderTurnDrag.finishes(progress: turn.progress, velocity: swipe.velocity, side: run.side)
            if finishes { call("return await window.octavo.endTurn(true)") }
            play(run, to: finishes ? 1 : 0)
        }
    }

    /// The hinge moved between folded and unfolded mid-turn: the turn ends
    /// where it was going (a finger's turn forward, unless it was already
    /// falling back) and its pictures go; the fold's own cover takes over.
    /// Returns the bridge call that ends a held turn, to run before `hold`.
    func finishTurnForFold() -> String? {
        queuedTurns.removeAll()
        guard let run = turnRun else {
            // A hint, if anything: it has nothing to end.
            turn = nil
            return nil
        }
        turnRun = nil
        turn = nil
        guard run.interactive, run.target != 1 else { return nil }
        return run.target == 0 ? "window.octavo.endTurn(false); " : "window.octavo.endTurn(true); "
    }

    // MARK: Playing a turn

    private func startTurn(_ side: ReaderTurnSide, interactive: Bool) {
        let motion = pageTurn.motion(spread: layout.columns == 2, reduceMotion: reduceMotion)
        guard motion != .none, let geometry else { return turnWithoutPictures(side) }
        let size = geometry.size
        let spine = motion == .flip && layout.columns == 2 ? spine(in: geometry) : nil
        let regions = ReaderTurn.regions(motion: motion, side: side, size: size, spine: spine)
        guard let old = pictures(regions.old, size: size, spine: spine, afterScreenUpdates: false) else {
            return turnWithoutPictures(side)
        }
        turnCount += 1
        let run = ReaderTurnRun(id: turnCount, side: side, motion: motion, interactive: interactive)
        turnRun = run
        turn = ReaderTurn(
            id: run.id, motion: motion, side: side, geometry: geometry, layout: layout, spine: spine,
            paper: Color(hex: appearance.background), old: old,
            oldPlace: ReaderPlace(chapter: chapter, location: location, fraction: shownFraction)
        )
        turn?.hidesChapter = trip != nil
        Task { await turnUnderPictures(run, regions: regions.new, size: size, spine: spine) }
        // A tap's turn waits for the new page, which is drawn about 50 ms
        // later (too soon to notice), so it moves in whole; one that takes
        // longer (a chapter loading) starts anyway, over the page's colour.
        // A fade always waits: the page shows through it at once.
        guard !interactive, motion != .fade else { return }
        Task {
            try? await Task.sleep(for: Self.longestWaitForPage)
            guard turnRun === run, run.target == nil else { return }
            play(run, to: 1)
        }
    }

    /// How long a tap's turn waits for the new page before it moves.
    static let longestWaitForPage = Duration.milliseconds(100)

    /// No pictures to draw (no web view to snapshot): foliate turns at once.
    private func turnWithoutPictures(_ side: ReaderTurnSide) {
        guard phase == .open else { return }
        Task {
            let answer = try? await page.callJavaScript("return await window.octavo.turn(side, false)", arguments: ["side": side.rawValue]) as? [String: Any]
            if answer?["moved"] as? Bool == true { pageTurned() }
        }
    }

    /// Has foliate turn under the pictures, then takes the new page's.
    private func turnUnderPictures(_ run: ReaderTurnRun, regions: ReaderTurn.Regions, size: CGSize, spine: Double?) async {
        let answer: [String: Any]?
        do {
            answer = try await page.callJavaScript(
                "return await window.octavo.turn(side, hold)", arguments: ["side": run.side.rawValue, "hold": run.interactive]
            ) as? [String: Any]
        } catch {
            answer = nil
        }
        guard turnRun === run else { return }
        let moved = answer?["moved"] as? Bool ?? false
        run.moved = moved
        if moved {
            let relocation = (answer?["relocation"] as? String).flatMap {
                try? JSONDecoder().decode(ReaderMessage.Relocation.self, from: Data($0.utf8))
            }
            let place = relocation.map { ReaderPlace(chapter: $0.tocLabel, location: $0.location, fraction: $0.shownFraction) }
            let new = pictures(regions, size: size, spine: spine, afterScreenUpdates: true) ?? ReaderTurn.Pictures()
            // Fades in only over the page's colour, if the turn is moving.
            let fadesIn = run.target != nil || (run.interactive && turn?.progress ?? 0 > 0)
            withAnimation(fadesIn ? .easeOut(duration: ReaderTurnMotion.fade.duration) : nil) {
                turn?.new = new
                turn?.newPlace = place
            }
        } else if !run.interactive {
            // The book's first or last page: nothing to turn to.
            play(run, to: 0)
        }
        run.drawn = true
        run.drawnAfter = FoldReport.milliseconds(since: run.startedAt)
        lastTurnDrawnAfter = run.drawnAfter
        if !run.interactive, run.target == nil, moved { play(run, to: 1) }
        if run.animationDone, run.target == 1 { return endTurn() }
        if !queuedTurns.isEmpty, run.canEndEarly { return endTurn() }
        // A snapshot taken as the page reached the screen can miss it by a
        // frame; a second look settles it.
        guard moved, !regions.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(100))
        guard turnRun === run, let fresh = pictures(regions, size: size, spine: spine, afterScreenUpdates: false) else { return }
        turn?.new = fresh
    }

    /// Plays the rest of `run` to `target`: a whole turn at its own pace, or
    /// the rest of a finger's turn.
    private func play(_ run: ReaderTurnRun, to target: Double) {
        guard let turn, turn.id == run.id else { return }
        run.target = target
        run.animationDone = false
        let whole = !run.interactive && target == 1
        run.ramp = ReaderTurnRamp(
            from: turn.progress,
            to: target,
            start: CACurrentMediaTime(),
            duration: whole ? run.motion.duration : ReaderTurnDrag.remainingDuration(from: turn.progress, to: target, motion: run.motion),
            curve: whole && run.motion == .flip ? .easeInOut : .easeOut
        )
    }

    /// While a turn is on screen, the page's display is asked for up to
    /// 120 Hz and `turnFrame` moves the pictures. A SwiftUI animation can't
    /// ask, and on the Duo it mostly ran at 60 (`docs/notes/page-turns.md`).
    func followTurnFrames(_ onScreen: Bool) {
        turnFrames?.isEnabled = false
        turnFrames = nil
        guard onScreen, let webView = snapshots.webView else { return }
        let link = UIUpdateLink(view: webView) { [weak self] _, info in
            self?.turnFrame(at: info.modelTime)
        }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        turnFrames = link
    }

    private func turnFrame(at time: Double) {
        guard let run = turnRun, let ramp = run.ramp else { return }
        turn?.progress = ramp.progress(at: time)
        guard time >= ramp.end else { return }
        run.ramp = nil
        played(run, to: ramp.to)
    }

    private func played(_ run: ReaderTurnRun, to target: Double) {
        guard turnRun === run, run.target == target else { return }
        run.animationDone = true
        if target == 0 {
            // Fallen back: a finger's turn is turned back under the old page
            // before the pictures go.
            Task {
                if run.interactive { _ = try? await page.callJavaScript("return await window.octavo.endTurn(false)") }
                guard turnRun === run else { return }
                endTurn()
            }
        } else if run.drawn {
            endTurn()
        }
        // Otherwise the turn ends once foliate has drawn the new page.
    }

    /// The pictures go, and the web view shows where the turn went. A turn
    /// asked for meanwhile starts.
    private func endTurn() {
        if let turnRun, turnRun.target == 1, turnRun.moved == true { pageTurned() }
        turnRun = nil
        turn = nil
        guard !queuedTurns.isEmpty else { return }
        startTurn(queuedTurns.removeFirst(), interactive: false)
    }

    // MARK: A hint

    /// The right page lifts a little and settles, showing that it turns (the
    /// tour's Turn the page). Pictures only: foliate doesn't move, so nothing
    /// is saved, and a real turn asked for meanwhile simply takes over.
    func playTurnHint() async {
        guard phase == .open, !isFolding, turnRun == nil, turn == nil, queuedTurns.isEmpty, let geometry,
              let motion = pageTurn.hintMotion(spread: layout.columns == 2, reduceMotion: reduceMotion)
        else { return }
        let size = geometry.size
        let spine = motion == .flip && layout.columns == 2 ? spine(in: geometry) : nil
        let regions = ReaderTurn.regions(motion: motion, side: .right, size: size, spine: spine)
        guard let old = pictures(regions.old, size: size, spine: spine, afterScreenUpdates: false) else { return }
        turnCount += 1
        let id = turnCount
        turn = ReaderTurn(
            id: id, motion: motion, side: .right, geometry: geometry, layout: layout, spine: spine,
            paper: Color(hex: appearance.background), old: old,
            oldPlace: ReaderPlace(chapter: chapter, location: location, fraction: shownFraction),
            isHint: true
        )
        for target in [Self.turnHintLift(motion), 0] {
            guard turn?.id == id, !Task.isCancelled else { break }
            withAnimation(.easeInOut(duration: Self.turnHintDuration)) {
                turn?.progress = target
            }
            try? await Task.sleep(for: .seconds(Self.turnHintDuration))
        }
        if turn?.id == id { turn = nil }
    }

    /// Seconds each way.
    static let turnHintDuration = 0.45

    /// How far a hint goes: about 45° of a flip, or a slide's 6%. Much less
    /// of a flip shows no edge: the page rises towards you, still covering its
    /// own place.
    static func turnHintLift(_ motion: ReaderTurnMotion) -> Double {
        motion == .flip ? 0.25 : 0.06
    }

    // MARK: Pictures

    /// The pages as they are now, for a cover's motion (decision 28): each
    /// half of a spread, or the one page.
    func coverPages() -> ReaderCoverPages {
        let paper = Color(hex: appearance.background)
        guard let geometry else { return ReaderCoverPages(paper: paper) }
        let size = geometry.size
        let spine = layout.columns == 2 ? spine(in: geometry) : nil
        let regions: ReaderTurn.Regions = spine == nil ? .whole : [.left, .right]
        let taken = pictures(regions, size: size, spine: spine, afterScreenUpdates: true)
        return ReaderCoverPages(left: taken?.left, right: taken?.right, whole: taken?.whole, spine: spine, paper: paper)
    }

    /// The middle of foliate's gap between the pages: over the fold.
    private func spine(in geometry: ReaderGeometry) -> Double {
        let width = Double(geometry.size.width)
        guard let gap = layout.gap(inReaderWidth: width) else { return width / 2 }
        return (gap.lowerBound + gap.upperBound) / 2
    }

    private func pictures(_ regions: ReaderTurn.Regions, size: CGSize, spine: Double?, afterScreenUpdates: Bool) -> ReaderTurn.Pictures? {
        var pictures = ReaderTurn.Pictures()
        var updates = afterScreenUpdates
        func take(_ rect: CGRect?) -> ReaderSnapshot? {
            defer { updates = false }
            return snapshots.snapshot(of: rect, afterScreenUpdates: updates)
        }
        if regions.contains(.whole) {
            guard let whole = take(nil) else { return nil }
            pictures.whole = whole
        }
        if let spine {
            if regions.contains(.left) {
                guard let left = take(ReaderTurn.half(.left, of: size, spine: spine)) else { return nil }
                pictures.left = left
            }
            if regions.contains(.right) {
                guard let right = take(ReaderTurn.half(.right, of: size, spine: spine)) else { return nil }
                pictures.right = right
            }
        }
        return pictures
    }
}
