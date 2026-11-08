import SwiftUI
import UIKit

/// The curl's steps, for chasing what only the Duo does: printed in DEBUG
/// when Octavo is launched with `OCTAVO_CURL_TRACE` set, which a device's
/// console shows (`docs/notes/curl.md`).
func curlTrace(_ message: @autoclosure () -> String) {
    #if DEBUG
    guard tracesCurl else { return }
    print("[curl \(String(format: "%.3f", CACurrentMediaTime()))] \(message())")
    // A pipe buffers, and a crash would lose the last lines.
    fflush(stdout)
    #endif
}

#if DEBUG
private let tracesCurl = ProcessInfo.processInfo.environment["OCTAVO_CURL_TRACE"] != nil
#endif

/// The curl (decision 27, Adam, 2026-11-07): UIKit's own page curl, a
/// `UIPageViewController` with `.pageCurl`, as Apple Books has, over the same
/// snapshot pictures the other turns draw (`docs/notes/curl.md`).
///
/// While a page curls, the controller waits over the page, its pages clear
/// so the live page shows through. A turn fills them with pictures of the
/// page as it is and curls to pictures of the next, which fill in once
/// foliate has drawn it. One page curls about its left edge (`spineLocation
/// .min`); a spread over its spine (`.mid`, double sided, the next page on
/// the back of the one that turns).
///
/// - A tap's turn: the model has foliate turn, then plays the curl
///   (`play(_:)`), as the other turns do.
/// - A finger's turn: UIKit's own pan, moved to the web view's superview
///   (where `ReaderSwipeRecognizer` sits for the other turns) and
///   recognising beside WebKit, follows the finger. UIKit asks for the
///   next page as a finger lands, to see whether there is one, so the turn
///   starts only when the curl does (`willTransitionTo`), held; landing
///   keeps it, falling back turns foliate back and nothing is saved.
final class ReaderCurl: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    weak var model: ReaderModel?
    /// What the pages show.
    let pages = ReaderCurlPages()
    private(set) weak var controller: UIPageViewController?
    private(set) var spread = false
    private weak var pan: UIPanGestureRecognizer?
    private let panDelegate = ReaderCurlPanDelegate()
    /// The pages UIKit was given each way, in the order it asks for them.
    private var coming: [ReaderTurnSide: [UIViewController]] = [:]
    /// The turn under way: a tap's, or a finger's once the curl has started.
    private(set) var turning: Turning?

    enum Turning: Equatable {
        case tap(id: Int)
        case finger(id: Int)
    }

    override init() {
        super.init()
        panDelegate.curl = self
    }

    /// A new controller for one page or a spread (the spine can't change).
    func makeController(spread: Bool) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: (spread ? UIPageViewController.SpineLocation.mid : .min).rawValue)]
        )
        controller.isDoubleSided = spread
        controller.view.backgroundColor = .clear
        // Touches reach the page; only the pan, moved, follows them.
        controller.view.isUserInteractionEnabled = false
        controller.dataSource = self
        controller.delegate = self
        // A tap's turn is the bridge's.
        controller.gestureRecognizers.filter { !($0 is UIPanGestureRecognizer) }.forEach { $0.isEnabled = false }
        self.controller = controller
        self.spread = spread
        coming = [:]
        turning = nil
        pages.turn = nil
        controller.setViewControllers(views(new: false), direction: .forward, animated: false)
        curlTrace("made a controller, \(spread ? "spread" : "one page")")
        return controller
    }

    // MARK: The pan

    /// Moves UIKit's pan to the web view's superview, behind a delegate that
    /// lets it recognise beside WebKit.
    func installPan() {
        guard let controller, let host = model?.snapshots.webView?.superview,
              let found = controller.gestureRecognizers.lazy.compactMap({ $0 as? UIPanGestureRecognizer }).first,
              found.view !== host
        else { return }
        removePan()
        host.addGestureRecognizer(found)
        found.addTarget(self, action: #selector(panned(_:)))
        panDelegate.uikit = found.delegate
        found.delegate = panDelegate
        pan = found
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: pan.view)
        curlTrace("pan state \(pan.state.rawValue) at \(Int(point.x)),\(Int(point.y)), velocity \(Int(pan.velocity(in: pan.view).x))")
    }

    func removePan() {
        guard let pan else { return }
        pan.view?.removeGestureRecognizer(pan)
        self.pan = nil
    }

    /// Whether a finger may start a curl now.
    var canStartWithFinger: Bool {
        guard turning == nil, let model else { return false }
        return model.canStartCurl && !model.swipes.pageHasSelection
    }

    // MARK: A tap's turn

    /// Curls to the next pages; `ReaderModel.curlEnded` once it has landed.
    func play(_ turn: ReaderTurn) {
        guard let controller, pages.turn?.id == turn.id else { return }
        turning = .tap(id: turn.id)
        curlTrace("tap \(turn.id): plays \(turn.side.rawValue), new page \(turn.new == nil ? "not drawn" : "drawn")")
        let next = views(new: true)
        let id = turn.id
        controller.setViewControllers(next, direction: turn.side == .right ? .forward : .reverse, animated: true) { [weak self] _ in
            self?.landed(id: id, completed: true)
        }
    }

    // MARK: Pages

    /// Shows `turn`'s old pictures on the pages UIKit is about to curl, at
    /// once (a hosting view would otherwise draw them a frame late).
    func show(_ turn: ReaderTurn) {
        pages.turn = turn
        controller?.viewControllers?.forEach {
            $0.view.setNeedsLayout()
            $0.view.layoutIfNeeded()
        }
    }

    /// Clear pages over the live page, ready for the next turn.
    func reset() {
        curlTrace("reset, was \(self.turning.map { "\($0)" } ?? "idle")")
        coming = [:]
        turning = nil
        pages.turn = nil
        controller?.setViewControllers(views(new: false), direction: .forward, animated: false)
    }

    /// One page, or a spread's two halves.
    private func views(new: Bool) -> [UIViewController] {
        let halves: [ReaderTurnSide?] = spread ? [.left, .right] : [nil]
        return halves.map { half in
            let view = UIHostingController(rootView: ReaderCurlPage(pages: pages, isNew: new, half: half))
            view.safeAreaRegions = []
            view.view.backgroundColor = .clear
            return view
        }
    }

    // MARK: Data source

    func pageViewController(_ controller: UIPageViewController, viewControllerAfter page: UIViewController) -> UIViewController? {
        next(after: page, side: .right)
    }

    func pageViewController(_ controller: UIPageViewController, viewControllerBefore page: UIViewController) -> UIViewController? {
        next(after: page, side: .left)
    }

    /// Asking commits nothing: UIKit asks as a finger lands.
    private func next(after page: UIViewController, side: ReaderTurnSide) -> UIViewController? {
        let isCurrent = controller?.viewControllers?.contains { $0 === page } == true
        // A spread's second page: the other one coming in.
        if let pair = coming.values.first(where: { $0.contains { $0 === page } }) {
            let other = pair.first { $0 !== page }
            curlTrace("asked \(side == .right ? "after" : "before") a page coming in (current \(isCurrent)): \(other == nil ? "nil" : "its pair")")
            return other
        }
        let relocation = model?.relocation
        curlTrace("asked \(side == .right ? "after" : "before") \(isCurrent ? "a current page" : "an unknown page"): can start \(self.canStartWithFinger), turning \(self.turning.map { "\($0)" } ?? "nil"), curling \(self.model?.isCurling == true), turns left \(relocation?.turnsLeft.map { "\($0)" } ?? "nil") right \(relocation?.turnsRight.map { "\($0)" } ?? "nil"), blank \(relocation?.blankPage == true), location \(relocation?.location?.current ?? -1)")
        guard canStartWithFinger, model?.canTurn(side) == true else { return nil }
        if coming[side] == nil {
            // Forward, the back of the page that turns is the next left page;
            // back, it's the right page before.
            let next = views(new: true)
            coming[side] = side == .right ? next : next.reversed()
        }
        return coming[side]?.first
    }

    // MARK: Delegate

    func pageViewController(_ controller: UIPageViewController, willTransitionTo pending: [UIViewController]) {
        let side = coming.first(where: { $0.value.contains { $0 === pending.first } })?.key
        curlTrace("will turn \(side?.rawValue ?? "an unknown way") to \(pending.count) pages, turning \(self.turning.map { "\($0)" } ?? "nil")")
        guard turning == nil, let model,
              let side = coming.first(where: { $0.value.contains { $0 === pending.first } })?.key,
              let turn = model.startCurl(side, finger: true)
        else { return }
        turning = .finger(id: turn.id)
    }

    func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        curlTrace("finished, \(completed ? "landed" : "fell back"), turning \(self.turning.map { "\($0)" } ?? "nil")")
        guard case .finger(let id) = turning else { return reset() }
        landed(id: id, completed: completed)
    }

    private func landed(id: Int, completed: Bool) {
        guard let turning, turning == .tap(id: id) || turning == .finger(id: id) else { return }
        let finger = turning == .finger(id: id)
        model?.curlEnded(id: id, completed: completed, finger: finger)
    }

    #if DEBUG
    var debugState: String {
        "curl \(controller == nil ? "none" : spread ? "spread" : "one page"), pan on \(pan?.view.map { "\(type(of: $0))" } ?? "nothing"), turning \(turning.map { "\($0)" } ?? "nothing")"
    }
    #endif
}

/// What the curl's pages show: nothing (clear over the live page) until a
/// turn starts.
@Observable final class ReaderCurlPages {
    var turn: ReaderTurn?
    /// For the book-mode spine shadow, drawn on the pages so it turns with
    /// them; set by `ReaderCurlView`.
    @ObservationIgnored weak var model: ReaderModel?
    var theme: ReaderTheme?
    var showsSpineShadow = false
}

/// The curl's controller over the page, whenever pages curl. Remade when
/// the spine moves (one page or a spread).
struct ReaderCurlView: UIViewControllerRepresentable {
    let curl: ReaderCurl
    let spread: Bool
    let theme: ReaderTheme
    let showsSpineShadow: Bool

    func makeCoordinator() -> ReaderCurl { curl }

    func makeUIViewController(context: Context) -> UIPageViewController {
        curl.makeController(spread: spread)
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        curl.pages.model = curl.model
        if curl.pages.theme != theme { curl.pages.theme = theme }
        if curl.pages.showsSpineShadow != showsSpineShadow { curl.pages.showsSpineShadow = showsSpineShadow }
        curl.installPan()
    }

    static func dismantleUIViewController(_ controller: UIPageViewController, coordinator curl: ReaderCurl) {
        guard curl.controller === controller || curl.controller == nil else { return }
        curl.removePan()
        curl.model?.curlGone()
    }
}

/// One page of the curl: the old or new page, whole or half of a spread,
/// cut from the page-sized `ReaderTurnPage`, or clear between turns.
private struct ReaderCurlPage: View {
    let pages: ReaderCurlPages
    let isNew: Bool
    let half: ReaderTurnSide?

    /// Whether the new page is a picture on this page of the curl.
    static func isPictured(_ half: ReaderTurnSide?, in turn: ReaderTurn) -> Bool {
        let new = ReaderTurn.regions(motion: .curl, side: turn.side, size: turn.size, spine: turn.spine).new
        return switch half {
        case nil: new.contains(.whole)
        case .left: new.contains(.left)
        case .right: new.contains(.right)
        }
    }

    var body: some View {
        if let turn = pages.turn {
            let rect = half.map { ReaderTurn.half($0, of: turn.size, spine: turn.spine ?? 0) } ?? CGRect(origin: .zero, size: turn.size)
            page(turn)
                .overlay(alignment: .topLeading) {
                    if pages.showsSpineShadow, let model = pages.model, let theme = pages.theme {
                        ReaderSpineShadow(model: model, theme: theme)
                    }
                }
                .offset(x: -rect.minX)
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .clipped()
                .ignoresSafeArea()
        } else {
            Color.clear
        }
    }

    @ViewBuilder private func page(_ turn: ReaderTurn) -> some View {
        if !isNew {
            ReaderTurnPage(turn: turn, picture: turn.old[half], place: turn.oldPlace)
        } else if !Self.isPictured(half, in: turn) {
            // A page the curl uncovers: clear over the web view, which shows
            // it, with its footer.
            ReaderTurnUncovered(turn: turn)
                .animation(.easeOut(duration: ReaderTurnMotion.fade.duration), value: turn.new != nil)
        } else {
            // The page's colour until foliate has drawn the new page, which
            // fades in if the curl is already moving (a chapter loading).
            ZStack(alignment: .topLeading) {
                turn.paper
                if let new = turn.new, let place = turn.newPlace {
                    ReaderTurnPage(turn: turn, picture: new[half], place: place)
                        .transition(.opacity)
                }
            }
            .frame(width: turn.size.width, height: turn.size.height, alignment: .topLeading)
            .animation(.easeOut(duration: ReaderTurnMotion.fade.duration), value: turn.new != nil)
        }
    }
}

/// Stands in as the delegate of UIKit's curl pan: it may begin only when a
/// finger could turn the page, and recognises beside WebKit. UIKit says no
/// to recognising with any of WebKit's recognizers, which already hold the
/// touch, and with that the pan never begins. The rest is UIKit's.
final class ReaderCurlPanDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var curl: ReaderCurl?
    weak var uikit: UIGestureRecognizerDelegate?
    private var touchStartedAt: TimeInterval?
    private var touchStart = CGPoint.zero

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touchStartedAt = touch.timestamp
        touchStart = touch.location(in: recognizer.view)
        curlTrace("touch at \(Int(self.touchStart.x)),\(Int(self.touchStart.y)) of \(Int(recognizer.view?.bounds.width ?? 0))")
        return uikit?.gestureRecognizer?(recognizer, shouldReceive: touch) ?? true
    }

    /// As `ReaderSwipeRecognizer`: mostly sideways, before a press would
    /// select text, and not while text is selected (a finger moving a
    /// selection's handle).
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard curl?.canStartWithFinger == true else {
            curlTrace("pan: not now")
            return false
        }
        let location = recognizer.location(in: recognizer.view)
        guard abs(location.x - touchStart.x) > abs(location.y - touchStart.y) else { return false }
        if let touchStartedAt, ProcessInfo.processInfo.systemUptime - touchStartedAt > ReaderSwipeRecognizer.pressDuration { return false }
        // UIKit asks for the next page only once its pan has begun, and on a
        // spread it crashes if there's none ("The number of view controllers
        // provided (0) doesn't match the number required (2)", the book's
        // first page on the Duo). So there has to be a page the way the
        // finger moves and, on a spread, on the side it's touching.
        guard let curl, let model = curl.model else { return false }
        var sides: Set<ReaderTurnSide> = [location.x > touchStart.x ? .left : .right]
        if curl.spread, let width = curl.controller?.view.bounds.width {
            sides.insert(touchStart.x < width / 2 ? .left : .right)
        }
        guard sides.allSatisfy({ model.canTurn($0) }) else {
            curlTrace("pan: no page \(sides.map(\.rawValue).sorted().joined(separator: " and "))")
            return false
        }
        let begins = uikit?.gestureRecognizerShouldBegin?(recognizer) ?? true
        curlTrace("pan: UIKit says \(begins ? "begin" : "don't begin") at \(Int(location.x)),\(Int(location.y)), from \(Int(self.touchStart.x)),\(Int(self.touchStart.y))")
        return begins
    }


    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        uikit?.gestureRecognizer?(recognizer, shouldRequireFailureOf: other) ?? false
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        uikit?.gestureRecognizer?(recognizer, shouldBeRequiredToFailBy: other) ?? false
    }
}
