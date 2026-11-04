import UIKit

/// A finger turning the page (decision 27), recognised in UIKit beside the
/// web view rather than in the page: once a turn starts under the finger,
/// WebKit stops passing that touch to the page (`docs/notes/page-turns.md`).
/// The pan sits on the web view's superview, where WebKit's own gestures
/// don't hold it back, and takes the touch from the page once it starts, so
/// the page sees a cancelled touch, not a tap.
///
/// A swipe starts once the finger has moved about 10 pt, mostly sideways,
/// before a press would select text, and not while text is selected (a
/// finger moving a selection's handle). Off with Page Turn set to None,
/// when foliate's paginator drags the page itself, except on fixed-layout
/// books, whose renderer doesn't.
final class ReaderSwipeRecognizer: NSObject, UIGestureRecognizerDelegate {
    /// A press held longer than this before moving is selecting text.
    static let pressDuration: TimeInterval = 0.3

    var onSwipe: ((ReaderTurnSwipe) -> Void)?
    /// Set from the page (`ReaderMessage.selection`).
    var pageHasSelection = false
    var isEnabled = false {
        didSet { pan.isEnabled = isEnabled }
    }

    private let pan = UIPanGestureRecognizer()
    private var touchStartedAt: TimeInterval?
    /// Where the finger landed. The pan's own translation starts from where
    /// it recognised, 10–20 pt on, so the page would lag the finger.
    private var touchStartX: Double = 0

    override init() {
        super.init()
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = isEnabled
        pan.delegate = self
        pan.addTarget(self, action: #selector(panned(_:)))
    }

    /// On the web view's superview, moving from any view it was on.
    func install(on view: UIView) {
        guard pan.view !== view else { return }
        pan.view?.removeGestureRecognizer(pan)
        view.addGestureRecognizer(pan)
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let dx = Double(pan.location(in: pan.view).x) - touchStartX
        #if DEBUG
        states.append("\(pan.state.rawValue):\(Int(dx))")
        if states.count > 40 { states.removeFirst() }
        #endif
        switch pan.state {
        case .began:
            onSwipe?(ReaderTurnSwipe(phase: .began, side: dx < 0 ? .right : .left, dx: dx))
            onSwipe?(ReaderTurnSwipe(phase: .changed, dx: dx))
        case .changed:
            onSwipe?(ReaderTurnSwipe(phase: .changed, dx: dx))
        case .ended:
            // Points per second to points per millisecond.
            let velocity = Double(pan.velocity(in: pan.view).x) / 1000
            onSwipe?(ReaderTurnSwipe(phase: .ended, dx: dx, velocity: velocity))
        case .cancelled, .failed:
            onSwipe?(ReaderTurnSwipe(phase: .cancelled, dx: dx))
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touchStartedAt = touch.timestamp
        touchStartX = Double(touch.location(in: gestureRecognizer.view).x)
        return true
    }

    #if DEBUG
    /// For `ReaderRemote`'s `turnState`.
    var debugState: String {
        "pan on \(pan.view.map { String(describing: type(of: $0)) } ?? "nothing"), enabled \(pan.isEnabled), state \(pan.state.rawValue), selection \(pageHasSelection), asked \(asked), states \(states.joined(separator: " "))"
    }
    private(set) var asked = ""
    private var states: [String] = []
    #endif

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let moved = pan.translation(in: pan.view)
        #if DEBUG
        asked = "moved \(moved), since \(touchStartedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? -1)"
        #endif
        guard !pageHasSelection else { return false }
        guard abs(moved.x) > abs(moved.y) else { return false }
        if let touchStartedAt, ProcessInfo.processInfo.systemUptime - touchStartedAt > Self.pressDuration { return false }
        return true
    }

    /// WebKit's own touch tracking carries on beside it until the pan takes
    /// the touch.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
