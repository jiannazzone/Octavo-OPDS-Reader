import SwiftUI
import UIKit

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
    /// The pages between turns (clear, or the page as it is once a turn
    /// starts), and the pages coming in each way, in the order UIKit asks
    /// for them. Made once per controller and reused turn after turn.
    private var waiting: [UIViewController] = []
    private var coming: [ReaderTurnSide: [UIViewController]] = [:]
    /// The turn under way: a tap's, or a finger's once the curl has started.
    private(set) var turning: Turning?
    /// UIKit is curling (a tap's curl, or one under a finger). Its pages
    /// can't be set meanwhile; the curl's end sets them.
    private var transitioning = false {
        didSet { if transitioning { transitionStarted = CACurrentMediaTime() } }
    }
    private var transitionStarted = 0.0
    /// Whether foliate turned for the tap's curl under way.
    var tapMoved = false

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
        // Remade mid-curl (the spine moved without a fold, say): that curl
        // goes with the old controller.
        endCurlGone()
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
        turning = nil
        transitioning = false
        tapMoved = false
        pages.turn = nil
        waiting = views(new: false)
        // Forward, the back of the page that turns is the next left page;
        // back, it's the right page before.
        coming = [.right: views(new: true), .left: views(new: true).reversed()]
        controller.setViewControllers(waiting, direction: .forward, animated: false)
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

    /// Ends UIKit's pan, so the page it's curling falls back: just after
    /// UIKit's own pan handler, which is asking.
    private func cancelPan() {
        DispatchQueue.main.async { [weak self] in
            guard let pan = self?.pan else { return }
            pan.isEnabled = false
            pan.isEnabled = true
        }
    }

    /// A curl under way when its controller goes (remade, or gone): the
    /// model ends it once SwiftUI's update, which this is in, is over.
    func endCurlGone() {
        guard model?.isCurling == true else { return }
        let ended = turning
        let moved = tapMoved
        DispatchQueue.main.async { [weak model] in
            model?.curlGone(ended, tapMoved: moved)
        }
    }

    /// Whether UIKit is curling. One it hasn't reported the end of in 2 s (a
    /// curl cancelled as it began, say) is taken as over.
    private var isTransitioning: Bool {
        transitioning && CACurrentMediaTime() - transitionStarted < 2
    }

    /// The waiting pages back on the controller, if a curl's end didn't put
    /// them back.
    func showWaiting() {
        guard turning == nil, !isTransitioning, let controller,
              controller.viewControllers?.first !== waiting.first
        else { return }
        transitioning = false
        controller.setViewControllers(waiting, direction: .forward, animated: false)
    }

    /// UIKit's pan is turning a page: from now on it must be given pages.
    private var panIsTurning: Bool {
        pan?.state == .began || pan?.state == .changed
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
        showWaiting()
        turning = .tap(id: turn.id)
        curlTrace("tap \(turn.id): plays \(turn.side.rawValue), new page \(self.pages.turn?.new == nil ? "not drawn" : "drawn")")
        // In the spread's order, left then right.
        let next = turn.side == .right ? coming[.right] ?? [] : (coming[.left] ?? []).reversed()
        let id = turn.id
        // UIKit copies the back of a page that curls on one page as it
        // starts, so the pages coming in are drawn first, and a picture that
        // came before the curl doesn't fade in.
        next.forEach {
            $0.view.setNeedsLayout()
            $0.view.layoutIfNeeded()
        }
        pages.isCurling = true
        transitioning = true
        controller.setViewControllers(next, direction: turn.side == .right ? .forward : .reverse, animated: true) { [weak self, weak controller] _ in
            // A controller since replaced (a fold) has nothing to say.
            guard let self, controller === self.controller else { return }
            transitioning = false
            // A fold or a close cleared the turn meanwhile: back to waiting.
            guard turning == .tap(id: id) else { return reset() }
            landed(id: id, completed: true)
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
        curlTrace("reset, was \(self.turning.map { "\($0)" } ?? "idle")\(self.transitioning ? ", mid-curl" : "")")
        turning = nil
        tapMoved = false
        pages.turn = nil
        pages.isCurling = false
        // Mid-curl, UIKit's pages can't be set; the curl's end resets them.
        guard !isTransitioning else { return }
        controller?.setViewControllers(waiting, direction: .forward, animated: false)
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
        controller === self.controller ? next(after: page, side: .right) : nil
    }

    func pageViewController(_ controller: UIPageViewController, viewControllerBefore page: UIViewController) -> UIViewController? {
        controller === self.controller ? next(after: page, side: .left) : nil
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
        // Before the pan begins, no page stops it. Once it has begun, UIKit
        // crashes on a spread without one ("The number of view controllers
        // provided (0)…", a finger reversing on a book's first page), so it
        // gets the pages, and `willTransitionTo` lets them fall back.
        guard (canStartWithFinger && model?.canTurn(side) == true) || panIsTurning else { return nil }
        return coming[side]?.first
    }

    // MARK: Delegate

    func pageViewController(_ controller: UIPageViewController, willTransitionTo pending: [UIViewController]) {
        guard controller === self.controller else { return }
        transitioning = true
        let side = coming.first(where: { $0.value.contains { $0 === pending.first } })?.key
        curlTrace("will turn \(side?.rawValue ?? "an unknown way") to \(pending.count) pages, turning \(self.turning.map { "\($0)" } ?? "nil")")
        guard turning == nil, let model, let side, model.canTurn(side),
              let turn = model.startCurl(side, finger: true)
        else {
            // Nothing to turn to, a turn that can't start now, or a finger
            // turning back the other way mid-curl: the page falls back.
            cancelPan()
            return
        }
        turning = .finger(id: turn.id)
        pages.isCurling = true
    }

    func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        // A controller since replaced (a fold) has nothing to say.
        guard controller === self.controller else { return }
        curlTrace("finished, \(completed ? "landed" : "fell back"), turning \(self.turning.map { "\($0)" } ?? "nil")")
        transitioning = false
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
    /// UIKit is curling them: a new page that comes now fades in.
    var isCurling = false
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
        curl.endCurlGone()
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
                .animation(fadeIn, value: turn.new != nil)
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
            .animation(fadeIn, value: turn.new != nil)
        }
    }

    /// A new page fades in if it comes while the page curls (a chapter
    /// loading); before, it's there as the curl starts.
    private var fadeIn: Animation? {
        pages.isCurling ? .easeOut(duration: ReaderTurnMotion.fade.duration) : nil
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
        curl.showWaiting()
        let sides = Self.sides(from: touchStart, to: location, spreadWidth: curl.spread ? curl.controller?.view.bounds.width : nil)
        guard sides.allSatisfy({ model.canTurn($0) }) else {
            curlTrace("pan: no page \(sides.map(\.rawValue).sorted().joined(separator: " and "))")
            return false
        }
        let begins = uikit?.gestureRecognizerShouldBegin?(recognizer) ?? true
        curlTrace("pan: UIKit says \(begins ? "begin" : "don't begin") at \(Int(location.x)),\(Int(location.y)), from \(Int(self.touchStart.x)),\(Int(self.touchStart.y))")
        return begins
    }

    /// The sides a finger from `start` to `point` may ask UIKit for: the way
    /// it moves and, on a spread `spreadWidth` wide, the side it's touching.
    nonisolated static func sides(from start: CGPoint, to point: CGPoint, spreadWidth: CGFloat?) -> Set<ReaderTurnSide> {
        var sides: Set<ReaderTurnSide> = [point.x > start.x ? .left : .right]
        if let spreadWidth { sides.insert(start.x < spreadWidth / 2 ? .left : .right) }
        return sides
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
