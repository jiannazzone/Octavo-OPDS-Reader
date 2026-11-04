import SwiftUI
import UIKit

/// A book opening like a cover (decision 28, provisional: Adam decides on
/// his Duo). From a book's screen, unfolded, the cover moves from the left
/// page onto the right one and swings over the spine, landing as the left
/// page of your place, the right page uncovered beneath it: the same motion
/// as a flip. Folded, the cover fills the screen and swings away to the
/// left, uncovering your page. With Reduce Motion the book's screen fades
/// into the page. The cover rests where it is until the reader has opened
/// your place, so the wait for the book is part of the motion.
///
/// Closing with Back onto the book's screen plays it backwards: your left
/// page swings back over the spine as the cover, which moves back into its
/// place; folded, the cover swings in from the left over your page. The
/// reader goes at once (a reader left on screen is rebuilt by an unfold,
/// which WebKit traps on; `AppShell`), so the motion draws your pages from
/// pictures taken as Back was tapped, over the book's screen.
///
/// Drawn by `ReaderCoverMotionView` over the whole window, above the
/// reader, which opens underneath it at once (`AppShell`). Unfolding on a
/// cover and folding while reading keep their own motion, the fold.
@Observable
final class ReaderCoverMotion {
    /// Seconds: the cover moving onto the right page, its swing (a flip's),
    /// and Reduce Motion's fade.
    static let slideDuration = 0.35
    static let swingDuration = ReaderTurnMotion.flip.duration
    static let fadeDuration = 0.3

    /// The cover's own picture, drawn as the book's screen draws it; a book
    /// without artwork shows its title.
    let cover: UIImage?
    let title: String
    let author: String
    /// Where the book's screen shows the cover, in the window's coordinates.
    let coverFrame: CGRect
    let windowSize: CGSize
    /// The book's screen as it was when the book opened, under the motion
    /// until the cover leaves it. Closing, the screen itself is underneath.
    let bookScreen: ReaderSnapshot?
    /// Played backwards, as the book closes.
    let closing: Bool
    /// Cover | Details: the cover moves onto the right page and swings over
    /// the spine. Otherwise it fills the screen and swings off it.
    let spread: Bool
    let reduceMotion: Bool
    /// The page's colour where the cover has left.
    var paper: Color
    /// How far the cover swings: over the spine, or folded only until it
    /// stands edge on at the screen's left edge (past that it's off the
    /// screen, and the page would sit still for half the swing).
    var swungOver: Double { spread ? 1 : 0.5 }
    /// Folded, the visible half of the swing at the flip's pace.
    var swingDuration: Double { Self.swingDuration * swungOver }
    /// The reader's pages once it has opened your place: the left page goes
    /// on the back of the cover.
    private(set) var pages: ReaderCoverPages?
    /// 0 with the cover where the book's screen has it, 1 over the right page.
    var slide = 0.0
    /// 0 with the cover flat, 1 swung over the spine (or off the screen).
    var swing = 0.0
    /// The book's screen still shows (until the cover starts to swing).
    var showsBookScreen = true
    /// Reduce Motion's fade, from the book's screen to the page.
    var fade = 0.0

    /// Called once the motion is over, to take it away.
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var slid = false
    @ObservationIgnored private var swinging = false

    /// Opening, from a picture of the book's screen; or closing, from
    /// pictures of your pages.
    init(cover: UIImage?, title: String, author: String, coverFrame: CGRect, windowSize: CGSize,
         bookScreen: ReaderSnapshot?, closing pages: ReaderCoverPages? = nil,
         spread: Bool, reduceMotion: Bool, paper: Color) {
        self.cover = cover
        self.title = title
        self.author = author
        self.coverFrame = coverFrame
        self.windowSize = windowSize
        self.bookScreen = bookScreen
        self.spread = spread
        self.reduceMotion = reduceMotion
        self.paper = pages?.paper ?? paper
        closing = pages != nil
        guard let pages else { return }
        // As the reader left it: your pages, the cover swung over the spine.
        self.pages = pages
        slide = spread ? 1 : 0
        swing = swungOver
        showsBookScreen = false
    }

    /// The middle of the reader's spread, once known; the window's middle
    /// (the hinge) till then.
    var spine: Double { pages?.spine ?? Double(windowSize.width) / 2 }

    /// The cover over the right page: its own frame mirrored about the
    /// spine, so the swing lands it back where the book's screen had it.
    var rightPage: CGRect {
        CGRect(x: 2 * spine - coverFrame.maxX, y: coverFrame.minY, width: coverFrame.width, height: coverFrame.height)
    }

    #if DEBUG
    /// For `ReaderRemote`'s `coverMotion`.
    var debugState: String {
        "slide \(slide) swing \(swing) fade \(fade) bookScreen \(showsBookScreen) slid \(slid) swinging \(swinging) pages \(pages != nil) spine \(spine) cover \(coverFrame) window \(windowSize) spread \(spread)"
    }
    #endif

    // MARK: Playing it

    /// The book is opening: unfolded, the cover moves onto the right page.
    /// Called once the motion is on screen and the reader has started, so
    /// the move is seen.
    func start() {
        guard !started else { return }
        started = true
        if closing { return close() }
        guard spread, !reduceMotion else {
            slid = true
            return
        }
        withAnimation(.easeInOut(duration: Self.slideDuration)) {
            slide = 1
        } completion: { [weak self] in
            self?.slid = true
            self?.swingIfReady()
        }
    }

    /// The reader has opened your place (`nil` if it couldn't): the cover
    /// swings once it's over the right page.
    func readerOpened(_ pages: ReaderCoverPages?) {
        guard self.pages == nil else { return }
        guard let pages else { return finish(fading: true) }
        self.pages = pages
        paper = pages.paper
        swingIfReady()
    }

    private func swingIfReady() {
        guard slid, pages != nil, !swinging else { return }
        swinging = true
        if reduceMotion { return finish(fading: true) }
        showsBookScreen = false
        withAnimation(spread ? .easeInOut(duration: swingDuration) : .easeIn(duration: swingDuration)) {
            swing = swungOver
        } completion: { [weak self] in
            self?.onFinished?()
        }
    }

    /// Backwards: the cover swings back over your page, then, unfolded,
    /// moves back to its place on the book's screen. With Reduce Motion your
    /// pages fade into the book's screen.
    private func close() {
        if reduceMotion { return finish(fading: true) }
        withAnimation(spread ? .easeInOut(duration: swingDuration) : .easeOut(duration: swingDuration)) {
            swing = 0
        } completion: { [weak self] in
            guard let self else { return }
            guard spread else {
                onFinished?()
                return
            }
            showsBookScreen = true
            withAnimation(.easeInOut(duration: Self.slideDuration)) {
                slide = 0
            } completion: { [weak self] in
                self?.onFinished?()
            }
        }
    }

    /// Reduce Motion, or a book that couldn't open: the book's screen fades
    /// away instead.
    private func finish(fading: Bool) {
        withAnimation(.easeOut(duration: Self.fadeDuration)) {
            fade = 1
        } completion: { [weak self] in
            self?.onFinished?()
        }
    }
}

/// The reader's pages for the cover's motion: pictures of each half of a
/// spread (or the one page) and where they meet.
struct ReaderCoverPages {
    var left: ReaderSnapshot?
    var right: ReaderSnapshot?
    var whole: ReaderSnapshot?
    var spine: Double?
    var paper: Color
}

/// Draws a `ReaderCoverMotion` over the window. Takes touches meanwhile, so
/// nothing under it is tapped half way. Its pictures are in the window's
/// coordinates, so it's moved to the window's corner from wherever the
/// shell lays it out (inside the safe area, folded 42 pt in and 17 down).
struct ReaderCoverMotionView: View {
    let motion: ReaderCoverMotion

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            content
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .offset(x: -origin.x, y: -origin.y)
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        let size = motion.windowSize
        return ZStack(alignment: .topLeading) {
            if motion.showsBookScreen {
                bookScreen
            } else {
                yourPages
            }
            if !motion.reduceMotion {
                // There from the start, so its swing animates: folded it
                // shows once the book's screen goes.
                ReaderCoverLeaf(motion: motion, slide: motion.slide, swing: motion.swing)
                    .opacity(motion.showsBookScreen && !motion.spread ? 0 : 1)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(1 - motion.fade)
        .contentShape(.rect)
        .accessibilityHidden(true)
        // Just after the reader's own start (it makes its web view, which
        // holds up the main thread long enough to swallow the move).
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            motion.start()
        }
    }

    /// The book's screen as it was (or, closing, the screen itself), its
    /// cover gone from its place while the cover moves.
    private var bookScreen: some View {
        ZStack(alignment: .topLeading) {
            if let screen = motion.bookScreen {
                ReaderSnapshotView(snapshot: screen)
                    .frame(width: screen.frame.width, height: screen.frame.height)
            }
            if motion.spread {
                motion.paper
                    .frame(width: motion.coverFrame.width, height: motion.coverFrame.height)
                    .offset(x: motion.coverFrame.minX, y: motion.coverFrame.minY)
            }
        }
    }
}

extension ReaderCoverMotionView {
    /// Under the swinging cover: your right page, the left page bare until
    /// the cover lands on it; folded, your page. The pictures, as the reader
    /// (gone when closing) drew them; with Reduce Motion, both pages.
    @ViewBuilder fileprivate var yourPages: some View {
        let size = motion.windowSize
        ZStack(alignment: .topLeading) {
            if motion.spread {
                motion.paper
                    .frame(width: motion.spine, height: size.height)
                if motion.reduceMotion, let left = motion.pages?.left {
                    picture(left)
                }
                if let right = motion.pages?.right {
                    picture(right)
                }
            } else if let whole = motion.pages?.whole {
                motion.paper
                    .frame(width: size.width, height: size.height)
                picture(whole)
            }
        }
    }

    private func picture(_ snapshot: ReaderSnapshot) -> some View {
        ReaderSnapshotView(snapshot: snapshot)
            .frame(width: snapshot.frame.width, height: snapshot.frame.height)
            .offset(x: snapshot.frame.minX, y: snapshot.frame.minY)
    }
}

/// The cover: moved onto the right page, then swung over its hinge (the
/// spine, or the screen's left edge folded), the left page of your place on
/// its back.
private struct ReaderCoverLeaf: View, Animatable {
    let motion: ReaderCoverMotion
    var slide: Double
    var swing: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(slide, swing) }
        set {
            slide = newValue.first
            swing = newValue.second
        }
    }

    var body: some View {
        let size = motion.windowSize
        let width = Double(size.width)
        let leaf = motion.spread ? motion.rightPage : motion.coverFrame
        let hinge = motion.spread ? motion.spine : Double(motion.coverFrame.minX)
        let anchor = UnitPoint(x: width > 0 ? hinge / width : 0, y: 0.5)
        // Unfolded it starts where the book's screen has the cover.
        let shift = motion.spread ? (1 - slide) * Double(motion.coverFrame.minX - leaf.minX) : 0
        let angle = swing * 180
        return ZStack(alignment: .topLeading) {
            if angle <= 90 {
                cover
                    .frame(width: leaf.width, height: leaf.height)
                    .clipped()
                    .offset(x: leaf.minX, y: leaf.minY)
            } else {
                back
                    .scaleEffect(x: -1, y: 1, anchor: anchor)
            }
            Color.black
                .opacity(0.18 * sin(angle * .pi / 180))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(ReaderTurnRegion(rect: leaf))
        .rotation3DEffect(.degrees(-angle), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.35)
        .offset(x: shift)
        .allowsHitTesting(false)
    }

    /// As the book's screen draws it, so it doesn't jump as it starts to move.
    @ViewBuilder private var cover: some View {
        if let image = motion.cover {
            FittedCover(image: image)
        } else {
            BookTitleCover(title: motion.title, author: motion.author)
        }
    }

    /// The left page of your place, on a spread; plain paper folded.
    @ViewBuilder private var back: some View {
        ZStack(alignment: .topLeading) {
            motion.paper
            if motion.spread, let left = motion.pages?.left {
                ReaderSnapshotView(snapshot: left)
                    .frame(width: left.frame.width, height: left.frame.height)
                    .offset(x: left.frame.minX, y: left.frame.minY)
            }
        }
        .frame(width: motion.windowSize.width, height: motion.windowSize.height, alignment: .topLeading)
    }
}
