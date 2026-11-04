import Foundation
import OctavoKit
import WebKit

/// Going back after a jump (decision 33). A jump doesn't move your place: the
/// page you land on stays a trip until you settle.
extension ReaderModel {
    func jump(to target: String) {
        runJump("return await window.octavo.goTo(target)", arguments: ["target": target])
    }

    func jump(toFraction fraction: Double) {
        runJump("return await window.octavo.goToFraction(fraction)", arguments: ["fraction": fraction])
    }

    func runJump(_ body: String, arguments: [String: Any]) {
        guard phase == .open else { return }
        beginJump()
        Task {
            _ = try? await page.callJavaScript(body, arguments: arguments)
            await endJump()
        }
    }

    /// Relocations from here on aren't saved. A trip under way keeps its way
    /// back; otherwise this page's place is the way back.
    func beginJump() {
        if jumpsUnderWay == 0 { jumpStartCount = relocationCount }
        jumpsUnderWay += 1
        guard trip == nil, tripToBe == nil, let place = savedPlace else { return }
        tripToBe = ReaderTrip(place: place, placePage: ReaderPlace(chapter: nil, location: location, fraction: shownFraction).first)
    }

    /// The jump has landed. Landing on your own page isn't a trip.
    func endJump() async {
        await relocationsSettled(since: jumpStartCount)
        jumpsUnderWay -= 1
        guard jumpsUnderWay == 0, var landed = trip ?? tripToBe else { return }
        tripToBe = nil
        if await isShowing(landed.place) {
            guard jumpsUnderWay == 0 else { return }
            trip = nil
            return
        }
        guard jumpsUnderWay == 0 else {
            tripToBe = landed
            return
        }
        landed.landed(on: position)
        trip = landed
        tripFraction = shownFraction
    }

    /// Back: to your place, by its CFI (by fraction, a fixed-layout page lands
    /// a page late). It's saved as it was, so nothing's sent.
    func goBack() {
        guard let trip else { return }
        self.trip = nil
        isGoingBack = true
        Task {
            let count = relocationCount
            if let cfi = trip.place.cfi {
                let went = try? await page.callJavaScript("return await window.octavo.goTo(cfi)", arguments: ["cfi": cfi]) as? Bool
                // A place that won't open (another edition's): the way back stays.
                guard went == true else {
                    isGoingBack = false
                    self.trip = trip
                    return
                }
            } else {
                _ = try? await page.callJavaScript("return await window.octavo.goToFraction(fraction)", arguments: ["fraction": trip.place.fraction])
            }
            await relocationsSettled(since: count)
            // A quick tap on the page may have turned on from it meanwhile.
            let isShowingPlace = await isShowing(trip.place)
            if trip.place.cfi == nil || isShowingPlace {
                wentBack()
            } else {
                wentBackAndTurned()
            }
        }
    }

    /// While away: where you are, and turning or scrubbing back onto your
    /// page ends the trip.
    func tripMoved(to page: ReadingPosition) {
        trip?.page = page
        guard let place = trip?.place else { return }
        let asked = relocationCount
        Task {
            guard await isShowing(place), asked == relocationCount, jumpsUnderWay == 0, trip?.place == place else { return }
            trip = nil
            wentBack()
        }
    }

    /// A page really turned (not a swipe that fell back). Away, enough turns
    /// forward are reading on.
    func pageTurned() {
        onPageTurned?()
        guard trip != nil, jumpsUnderWay == 0 else { return }
        let now = shownFraction
        trip?.turned(from: tripFraction, to: now)
        tripFraction = now
        if trip?.hasReadOn == true { settleTrip() }
    }

    /// Whether `place` is on the page showing, as foliate resolves it.
    private func isShowing(_ place: ReadingPosition) async -> Bool {
        guard let cfi = place.cfi else { return false }
        let flags = try? await page.callJavaScript("return await window.octavo.onPage(cfis)", arguments: ["cfis": [cfi]]) as? [Bool]
        return flags?.first == true
    }

    /// Relocations come after a call does, and a page settling on a spread
    /// can take a moment and report more than once. At most half a second.
    func relocationsSettled(since count: Int) async {
        var last = count
        var quiet = 0
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(20))
            quiet = relocationCount == last ? quiet + 1 : 0
            last = relocationCount
            if last != count, quiet >= 3 { break }
        }
    }
}
