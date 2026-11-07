import SwiftUI
import UIKit

/// A book opening like a cover (decision 28, provisional: Adam decides on
/// his Duo). From a book's screen, unfolded, the cover moves from the left
/// page onto the right one and swings over the spine, landing as the left
/// page of your place, the right page uncovered beneath it: the same motion
/// as a flip. Folded, the cover on its blur fills the screen and swings away
/// to the left, uncovering your page. With Reduce Motion the book's screen fades
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
/// From Home unfolded (Adam, 2026-11-07), the cover moves from Home's left
/// page to where the book's screen would have it on the right page, growing
/// on the way, while the left page turns to paper; from there it's the same.
/// Back onto Home brings it back to its spot.
///
/// Past page 1 leaves go over too (`ReaderLeaves`), with your page on the last
/// one instead of on the cover. Unfolding on a cover has no cover to swing, so
/// it's the leaves alone: there from the moment the inner display is, the last
/// waiting for your page if it isn't ready.
///
/// Drawn by `ReaderCoverMotionView` over the whole window, above the
/// reader, which opens underneath it at once (`AppShell`). Folding or
/// unfolding takes it away, opening or closing: it's drawn for the display it
/// started on, and the fold is the motion then (`ShellModel.hingeChanged`).
@Observable
final class ReaderCoverMotion {
    /// Seconds: the cover moving onto the right page, its swing, and Reduce
    /// Motion's fade. The swing is a third quicker than a page's flip (Adam,
    /// 2026-11-04); it was 0.5, and the slide 0.35.
    static let slideDuration = 0.23
    static let swingDuration = 0.33
    static let fadeDuration = 0.3
    /// The longest an opening cover waits for the reader before it fades
    /// anyway, onto the reader's own loading page and its Back. It takes
    /// every touch while it's up, so a reader that never opened would
    /// otherwise leave nothing to tap.
    static let longestWait: Duration = .seconds(8)

    /// The cover's own picture, drawn as the book's screen draws it; a book
    /// without artwork shows its title.
    let cover: UIImage?
    let title: String
    let author: String
    /// Where the book's screen shows the cover, in the window's coordinates.
    let coverFrame: CGRect
    /// Opened from Home, where it has the cover instead.
    let home: HomeCoverSpot?
    private(set) var windowSize: CGSize
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
    /// Folded, the visible half of the swing, at the same pace.
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
    /// Unfolding on a cover: no cover, just the leaves.
    let leavesOnly: Bool
    /// The leaves going over on the way to your place, if any.
    private(set) var leaves: ReaderLeaves?
    /// Their lines, in a few versions.
    private(set) var leafLines: [Path] = []
    /// Seconds since the cover began to swing or, without one, the leaves began.
    private(set) var clock = 0.0
    /// The last leaf has waited a while for your page.
    private(set) var showsWaiting = false

    /// Called once the motion is over, to take it away.
    @ObservationIgnored var onFinished: (() -> Void)?
    /// `longestWait`, which tests shorten.
    @ObservationIgnored var longestWait = ReaderCoverMotion.longestWait
    @ObservationIgnored private var started = false
    /// Ended, fading away or taken away (`cancel`): nothing more plays.
    @ObservationIgnored private var isOver = false
    /// The cover has reached the right page, opening.
    private(set) var slid = false
    @ObservationIgnored private var swinging = false
    @ObservationIgnored private let pageTurn: ReaderPageTurn
    @ObservationIgnored private let leafStyle: ReaderLeafStyle
    /// Where the hinge's middle is, unfolding, until the reader says.
    @ObservationIgnored private var hingeMiddle: Double?
    /// Where the system's areas are, unfolding, for where the lines go.
    @ObservationIgnored var safeArea = ReaderInsets.zero
    /// While the leaves play, the display is asked for up to 120 Hz, as for a
    /// page turn (`ReaderModel.followTurnFrames`).
    @ObservationIgnored private var frames: UIUpdateLink?
    @ObservationIgnored private var lastFrame: Double?

    /// Opening, from a picture of the book's screen; or closing, from
    /// pictures of your pages.
    init(cover: UIImage?, title: String, author: String, coverFrame: CGRect, home: HomeCoverSpot? = nil, windowSize: CGSize,
         bookScreen: ReaderSnapshot?, closing pages: ReaderCoverPages? = nil,
         spread: Bool, reduceMotion: Bool, paper: Color,
         pageTurn: ReaderPageTurn = .standard, leafStyle: ReaderLeafStyle = ReaderLeafStyle()) {
        self.cover = cover
        self.title = title
        self.author = author
        self.coverFrame = coverFrame
        self.home = home
        self.windowSize = windowSize
        self.bookScreen = bookScreen
        self.spread = spread
        self.reduceMotion = reduceMotion
        self.paper = pages?.paper ?? paper
        self.pageTurn = pageTurn
        self.leafStyle = leafStyle
        leavesOnly = false
        closing = pages != nil
        guard let pages else { return }
        // As the reader left it: your pages, the cover swung over the spine.
        self.pages = pages
        slide = spread ? 1 : 0
        swing = swungOver
        showsBookScreen = false
    }

    /// Unfolding on a cover, `progress` through the book as its screen said.
    init(unfoldingAt progress: Double, windowSize: CGSize, paper: Color, leafStyle: ReaderLeafStyle) {
        cover = nil
        title = ""
        author = ""
        coverFrame = .zero
        home = nil
        self.windowSize = windowSize
        bookScreen = nil
        closing = false
        spread = true
        reduceMotion = false
        self.paper = paper
        pageTurn = .standard
        self.leafStyle = leafStyle
        leavesOnly = true
        leaves = ReaderLeaves(count: ReaderLeaves.count(progress: progress), spread: true, followsCover: false)
        showsBookScreen = false
    }

    /// The middle of the reader's spread, once known; the hinge or the
    /// window's middle till then.
    var spine: Double { pages?.spine ?? hingeMiddle ?? Double(windowSize.width) / 2 }

    /// A leaf where it starts: the right half of a spread, or the whole page.
    var leafFrame: CGRect {
        spread
            ? CGRect(x: spine, y: 0, width: Double(windowSize.width) - spine, height: Double(windowSize.height))
            : CGRect(origin: .zero, size: windowSize)
    }

    /// The cover over the right page: its own frame mirrored about the
    /// spine, so the swing lands it back where the book's screen had it.
    var rightPage: CGRect {
        CGRect(x: 2 * spine - coverFrame.maxX, y: coverFrame.minY, width: coverFrame.width, height: coverFrame.height)
    }

    /// The cover `slide` of the way to the right page: unfolded from where
    /// it was (the book's screen or Home), folded where it is.
    func frame(slide: Double) -> CGRect {
        guard spread else { return coverFrame }
        let from = home?.cover ?? coverFrame
        let to = rightPage
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * slide }
        return CGRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY), width: mix(from.width, to.width), height: mix(from.height, to.height))
    }

    #if DEBUG
    /// For `ReaderRemote`'s `coverMotion`.
    var debugState: String {
        "slide \(slide) swing \(swing) fade \(fade) bookScreen \(showsBookScreen) slid \(slid) swinging \(swinging) pages \(pages != nil) spine \(spine) cover \(coverFrame) home \(home.map { "\($0.cover)" } ?? "none") window \(windowSize) spread \(spread) leaves \(leaves?.count ?? 0) clock \(clock)"
    }
    #endif

    // MARK: Playing it

    /// The book is opening: unfolded, the cover moves onto the right page.
    /// Called once the motion is on screen and the reader has started, so
    /// the move is seen.
    func start() {
        guard !started, !isOver else { return }
        started = true
        if closing { return close() }
        waitForTheReader()
        // No cover to move: the leaves wait for the inner display.
        if leavesOnly { return }
        guard spread, !reduceMotion else {
            slid = true
            // The reader may have opened already.
            return swingIfReady()
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
        guard self.pages == nil, !isOver else { return }
        guard let pages else { return finish(fading: true) }
        if leavesOnly { return unfoldedPages(pages) }
        self.pages = pages
        paper = pages.paper
        if !closing, ReaderLeaves.play(fraction: pages.fraction, pageTurn: pageTurn, reduceMotion: reduceMotion),
           let layout = pages.layout, (pages.spine != nil) == spread, spread || pages.whole != nil {
            leaves = ReaderLeaves(count: ReaderLeaves.count(progress: pages.fraction), spread: spread, followsCover: true)
            drawLines(layout)
        }
        swingIfReady()
    }

    /// Unfolding on a cover: the window has moved to the inner display once
    /// the hinge's region shows in it, and the leaves start.
    func windowChanged(_ window: UnfoldedWindow) {
        guard leavesOnly, !isOver, frames == nil, pages == nil, let hinge = window.hinge, let size = ShellModel.keyWindow?.bounds.size else { return }
        windowSize = size
        hingeMiddle = Double(hinge.midX)
        let geometry = ReaderGeometry(size: size, safeArea: safeArea)
        drawLines(.spread(in: geometry, fold: hinge, margins: leafStyle.margins))
        playLeaves()
    }

    /// Your pages, for the last leaf to carry. One page (the Duo turned on its
    /// side, or a reader quicker than the scene) has no spine to leaf over.
    private func unfoldedPages(_ pages: ReaderCoverPages) {
        guard pages.spine != nil, let layout = pages.layout else { return end() }
        self.pages = pages
        paper = pages.paper
        showsWaiting = false
        guard frames == nil else { return }
        if let size = ShellModel.keyWindow?.bounds.size { windowSize = size }
        drawLines(layout)
        playLeaves()
    }

    private func drawLines(_ layout: ReaderLayout) {
        leafLines = (0..<2).map { ReaderLeafLines.path(layout: layout, size: windowSize, pitch: leafStyle.pitch, seed: $0) }
    }

    private func swingIfReady() {
        guard slid, pages != nil, !swinging, !isOver else { return }
        swinging = true
        if reduceMotion { return finish(fading: true) }
        showsBookScreen = false
        if leaves != nil { return playLeaves() }
        withAnimation(spread ? .easeInOut(duration: swingDuration) : .easeIn(duration: swingDuration)) {
            swing = swungOver
        } completion: { [weak self] in
            self?.end()
        }
    }

    // MARK: The leaves

    /// A frame that took longer than this counts as this long, so a leaf
    /// doesn't jump when the main thread stalls (the scene moving, the reader's
    /// web view): it just runs late.
    private static let longestFrame = 0.05
    /// How long the last leaf waits for your page before a spinner shows.
    private static let waitBeforeSpinner = 0.75

    private func playLeaves() {
        guard let window = ShellModel.keyWindow else { return end() }
        let link = UIUpdateLink(view: window) { [weak self] link, info in
            guard let self else {
                link.isEnabled = false
                return
            }
            let last = lastFrame ?? info.modelTime
            lastFrame = info.modelTime
            advance(by: min(info.modelTime - last, Self.longestFrame))
        }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        frames = link
    }

    /// One frame of the swing and the leaves. Unfolding, your page may not be
    /// ready when the last leaf is due: the others land, and it rests.
    func advance(by seconds: Double) {
        guard var leaves else { return }
        clock += seconds
        let last = leaves.count - 1
        if pages == nil, clock > leaves.start(of: last) {
            leaves.lastLeafWait += clock - leaves.start(of: last)
            self.leaves = leaves
            if leaves.lastLeafWait > Self.waitBeforeSpinner, !showsWaiting { showsWaiting = true }
        }
        if !leavesOnly {
            let curve: UnitCurve = spread ? .easeInOut : .easeIn
            swing = swungOver * curve.value(at: min(clock / swingDuration, 1))
        }
        guard clock >= leaves.end else { return }
        end()
    }

    private func stopFrames() {
        frames?.isEnabled = false
        frames = nil
    }

    /// Backwards: the cover swings back over your page, then, unfolded,
    /// moves back to its place on the book's screen. With Reduce Motion your
    /// pages fade into the book's screen.
    private func close() {
        if reduceMotion { return finish(fading: true) }
        withAnimation(spread ? .easeInOut(duration: swingDuration) : .easeOut(duration: swingDuration)) {
            swing = 0
        } completion: { [weak self] in
            // Taken away meanwhile: no slide back.
            guard let self, !isOver else { return }
            guard spread else { return end() }
            showsBookScreen = true
            withAnimation(.easeInOut(duration: Self.slideDuration)) {
                slide = 0
            } completion: { [weak self] in
                self?.end()
            }
        }
    }

    /// Opening, the cover rests until the reader has your place, but not for
    /// good (`longestWait`).
    private func waitForTheReader() {
        Task { [weak self, longestWait] in
            try? await Task.sleep(for: longestWait)
            guard let self, pages == nil, !isOver else { return }
            finish(fading: true)
        }
    }

    /// Taken away before it's over (a fold, the reader closing): whatever the
    /// reader says later plays nothing, and the leaves stop.
    func cancel() {
        isOver = true
        stopFrames()
    }

    /// Played through, or with nothing left to play: it's taken away, and
    /// nothing later (the reader, the time limit, an animation's completion)
    /// plays it again.
    private func end() {
        guard !isOver else { return }
        isOver = true
        stopFrames()
        onFinished?()
    }

    /// Reduce Motion, a book that couldn't open, or one that took too long:
    /// the book's screen fades away instead.
    private func finish(fading: Bool) {
        guard !isOver else { return }
        isOver = true
        stopFrames()
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
    /// How far through the book they are, for the leaves.
    var fraction = 0.0
    var layout: ReaderLayout?
}

/// What `ReaderCoverMotionView` watches while unfolding on a cover: the hinge,
/// in the window's coordinates.
nonisolated struct UnfoldedWindow: Equatable, Sendable {
    var hinge: CGRect?

    init(_ proxy: GeometryProxy) {
        let origin = proxy.frame(in: .global).origin
        let hinge = proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
            .map(\.frame)
            .first { $0.height > $0.width }
        self.hinge = hinge?.offsetBy(dx: origin.x, dy: origin.y)
    }
}

/// Draws a `ReaderCoverMotion` over the window. Takes touches meanwhile, so
/// nothing under it is tapped half way. Its pictures are in the window's
/// coordinates, so it's moved to the window's corner from wherever the
/// shell lays it out (inside the safe area, folded 42 pt in and 17 down).
struct ReaderCoverMotionView: View {
    let motion: ReaderCoverMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack {
            // Unfolding, the window changes size under the leaves.
            if motion.leavesOnly {
                motion.paper
                    .ignoresSafeArea()
            }
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                content
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .onGeometryChange(for: UnfoldedWindow.self) { UnfoldedWindow($0) } action: { motion.windowChanged($0) }
                    .offset(x: -origin.x, y: -origin.y)
            }
            .ignoresSafeArea()
        }
        .onGeometryChange(for: ReaderInsets.self) { [layoutDirection] proxy in
            ReaderInsets(proxy.safeAreaInsets, layoutDirection: layoutDirection)
        } action: { motion.safeArea = $0 }
    }

    private var content: some View {
        let size = motion.windowSize
        return ZStack(alignment: .topLeading) {
            Group {
                if motion.showsBookScreen {
                    bookScreen
                } else {
                    yourPages
                }
            }
            .zIndex(-2)
            if let leaves = motion.leaves, !motion.showsBookScreen {
                ReaderLeavesView(motion: motion, leaves: leaves)
            }
            if !motion.reduceMotion, !motion.leavesOnly {
                // There from the start, so its swing animates: folded it
                // shows once the book's screen goes. Over the leaves until
                // it's past the spine, where they land on it.
                ReaderCoverLeaf(motion: motion, slide: motion.slide, swing: motion.swing)
                    .opacity(motion.showsBookScreen && !motion.spread ? 0 : 1)
                    .zIndex(motion.swing > 0.5 ? -1 : 1)
            }
            if motion.showsWaiting {
                ProgressView()
                    .position(x: motion.spine + (Double(size.width) - motion.spine) / 2, y: size.height / 2)
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
            // With Reduce Motion the cover stays where it is and fades.
            if motion.spread, !motion.reduceMotion, let home = motion.home {
                homePage(home)
            } else if motion.spread, !motion.reduceMotion {
                motion.paper
                    .frame(width: motion.coverFrame.width, height: motion.coverFrame.height)
                    .offset(x: motion.coverFrame.minX, y: motion.coverFrame.minY)
                // The gutter's paper, along the cover's trailing edge: off the
                // screen to start with, so the gutter stays the book screen's
                // until the cover has passed. Without it a dark screen's gutter
                // stays black between the paper and the cover.
                let gutter = max(motion.rightPage.minX - motion.coverFrame.maxX, 0)
                motion.paper
                    .frame(width: gutter, height: motion.windowSize.height)
                    .offset(x: motion.coverFrame.minX - gutter + motion.slide * (motion.rightPage.minX - motion.coverFrame.minX))
            }
        }
    }

    /// Home's left page without its cover: its blur again over the cover's
    /// spot, down to the strip, and the page and the gutter turning to paper
    /// as the cover moves, so it ends as the book's screen's does. Closing,
    /// Home itself is underneath, its cover hidden the same way.
    @ViewBuilder private func homePage(_ home: HomeCoverSpot) -> some View {
        // Under the paper once the cover's over the right page.
        if !motion.slid {
            homeBackdrop(home)
        }
        motion.paper
            .frame(width: max(motion.rightPage.minX - motion.coverFrame.minX, 0), height: motion.windowSize.height)
            .offset(x: motion.coverFrame.minX)
            .opacity(motion.slide)
    }

    private func homeBackdrop(_ home: HomeCoverSpot) -> some View {
        let page = home.page
        return Group {
            if let image = motion.cover {
                FittedCover(image: image)
            } else {
                home.standIn
            }
        }
        .frame(width: page.width, height: page.height)
        .clipped()
        .pageBlur(width: page.width)
        .frame(width: page.width, height: max(home.stripTop - page.minY, 0), alignment: .top)
        .clipped()
        .offset(x: page.minX, y: page.minY)
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
                if motion.leavesOnly {
                    // What the first leaf lands on: there's no cover before it.
                    ReaderLeafFace(motion: motion, variant: 0)
                        .clipShape(ReaderTurnRegion(rect: CGRect(x: 0, y: 0, width: motion.spine, height: size.height)))
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
        // Unfolded it starts where the book's screen (or Home) has the cover,
        // and swings once it's over the right page.
        let leaf = motion.frame(slide: slide)
        let hinge = motion.spread ? motion.spine : Double(motion.coverFrame.minX)
        let anchor = UnitPoint(x: width > 0 ? hinge / width : 0, y: 0.5)
        let angle = swing * 180
        return ZStack(alignment: .topLeading) {
            if angle <= 90 {
                front(leaf)
                    .offset(x: leaf.minX, y: leaf.minY)
            } else {
                back
                    .scaleEffect(x: -1, y: 1, anchor: anchor)
                    .clipShape(ReaderTurnRegion(rect: leaf))
            }
            Color.black
                .opacity(0.18 * sin(angle * .pi / 180))
                .clipShape(ReaderTurnRegion(rect: leaf))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .rotation3DEffect(.degrees(-angle), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.35)
        .allowsHitTesting(false)
    }

    /// The cover in `frame`. From Home it starts as Home draws it, rounded,
    /// with its shadow and marks, and loses them as it moves: none of them is
    /// drawn once it's over the right page.
    @ViewBuilder private func front(_ frame: CGRect) -> some View {
        let face = cover.frame(width: frame.width, height: frame.height)
        if let home = motion.home, slide < 1 {
            let homeLook = 1 - slide
            face
                .clipShape(.rect(cornerRadius: HomeCoverSpot.cornerRadius * homeLook))
                .overlay(alignment: .bottomTrailing) {
                    if let book = home.book {
                        CoverBadge(book: book, size: HomeCoverSpot.badgeSize)
                            .opacity(homeLook)
                    }
                }
                .shadow(color: .black.opacity(HomeCoverSpot.shadowOpacity * homeLook), radius: HomeCoverSpot.shadowRadius, y: HomeCoverSpot.shadowY)
        } else {
            face.clipped()
        }
    }

    /// As the book's screen draws it, so it doesn't jump as it starts to move.
    /// From Home, a book without artwork starts as Home's stand-in.
    @ViewBuilder private var cover: some View {
        if let image = motion.cover {
            FittedCover(image: image)
        } else {
            ZStack {
                BookTitleCover(title: motion.title, author: motion.author)
                motion.home?.standIn
                    .opacity(1 - slide)
            }
        }
    }

    /// The left page of your place, on a spread; plain paper folded.
    @ViewBuilder private var back: some View {
        ZStack(alignment: .topLeading) {
            motion.paper
            if motion.leaves != nil {
                // Your page is on the last leaf instead.
                ReaderLeafFace(motion: motion, variant: 0)
            } else if motion.spread, let left = motion.pages?.left {
                ReaderSnapshotView(snapshot: left)
                    .frame(width: left.frame.width, height: left.frame.height)
                    .offset(x: left.frame.minX, y: left.frame.minY)
            }
        }
        .frame(width: motion.windowSize.width, height: motion.windowSize.height, alignment: .topLeading)
    }
}
