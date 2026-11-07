import SwiftUI

/// A tab's screens, drawn by Octavo rather than a `NavigationStack`'s pushes:
/// the deepest screen fills the spread, folded or unfolded, and a fold only
/// lays it out again (`docs/design/direction.md`).
///
/// - A pushed screen slides in from the trailing edge over the one before,
///   which stays as it was; Back, or a swipe from the leading edge, slides
///   it out. With Reduce Motion it fades instead, though a swipe still
///   follows the finger. A `List` at the screen's edge has to state its
///   leading margin, or its rows shrink at the end of the slide
///   (`SettingsPageList`).
/// - Back (or, at the root, Settings) sits in the side column: the
///   `NavigationStack` here never pushes and exists only so the system puts
///   those buttons there, as it does the reader's.
struct ScreenStack<Root: View>: View {
    let tab: ShellTab
    /// The root's title. `nil`: the root draws its own (`TitledScreen`).
    let title: String?
    /// Setup has no Settings to open.
    var showsSettings = true
    /// The Library's top screen has a + for Import from Files, above
    /// Settings (Adam, 2026-11-02).
    var importsBooks = false
    /// The tour's Add your books has Skip, at its root (decision 30).
    var skip: (() -> Void)?
    @ViewBuilder let root: () -> Root
    @Environment(ShellModel.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `nil` until the stack has been laid out once.
    @State private var measured: Spread?
    /// How far a screen slides: past the side column, which it runs under,
    /// and on a little further, so the slide's slow end happens off screen.
    @State private var travel: CGFloat = 1000
    /// How far a swipe from the leading edge has pulled the top screen.
    @State private var swipe: CGFloat?

    /// Quick out of the gate and settled at 0.32 s. Not a spring: across the
    /// spread's full width its tail crept for half a second more.
    private static var slide: Animation { .timingCurve(0.25, 0.8, 0.25, 1, duration: 0.32) }
    private static var fade: Animation { .easeOut(duration: 0.2) }

    /// Beyond the screen's edge, so the slide is still quick when a screen
    /// leaves sight.
    private static var overshoot: CGFloat { 80 }

    /// A swipe this far across, or flicked this fast, goes back.
    private static var swipeCommit: CGFloat { 0.35 }
    private static var edgeWidth: CGFloat { 24 }

    var body: some View {
        let path = shell[path: tab]
        let spread = measured ?? shell.lastSpread ?? .onePage
        NavigationStack {
            ZStack(alignment: .topLeading) {
                ForEach(visibleDepths(path), id: \.self) { id in
                    let isTop = id.depth == path.routes.count
                    screen(at: id, in: path)
                        // Whatever appears on a screen mid-slide (a cover
                        // that just loaded) moves with it, instead of
                        // appearing where it will end up.
                        .geometryGroup()
                        .zIndex(Double(id.depth))
                        .offset(x: isTop ? swipe ?? 0 : 0)
                        .allowsHitTesting(isTop)
                        .accessibilityHidden(!isTop)
                        .transition(reduceMotion ? .opacity : .offset(x: travel))
                }
                if !path.routes.isEmpty {
                    edge
                        .zIndex(Double(path.routes.count + 1))
                }
            }
            // A replaced path (a launch argument, closing the reader onto its
            // book) changes at once.
            .animation(path.lastMove == .replace ? nil : reduceMotion ? Self.fade : Self.slide, value: path)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: measured)
            .onSpreadChange { spreadChanged(to: $0) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width + $0.safeAreaInsets.trailing } action: {
                travel = $0 + Self.overshoot
            }
            .environment(\.spread, spread)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if path.routes.isEmpty {
                        if let skip {
                            TourSkipButton(action: skip)
                        }
                        if importsBooks {
                            Button("Import from Files", systemImage: "plus") { shell.showFilePicker() }
                        }
                        if showsSettings {
                            Button("Settings", systemImage: "gearshape") { shell.openSettings() }
                        }
                    } else {
                        Button("Back", systemImage: "chevron.backward") { back() }
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
        }
    }

    /// Only a fold (a new width) re-lays the screens out smoothly. At the
    /// same width the pages split the same way, so any other change is the
    /// hinge's region arriving a moment after a stack's first layout: that
    /// happens at once, from the spread the other tabs measured, since
    /// animated from one page to two a tab opening for the first time
    /// visibly rearranged itself.
    private func spreadChanged(to new: Spread) {
        // Narrower than a page: the layout before the stack's first real
        // one (0 pt), which would make the next reading look like a fold.
        guard new.width >= Spread.minimumPageWidth else { return }
        if let old = measured, old.width != new.width {
            measured = new
            keep(new)
            return
        }
        // Before the region arrives, a stack opening at the width the
        // other tabs have takes their split.
        let settled = if measured == nil, new.pages == nil, let known = shell.lastSpread, known.width == new.width { known } else { new }
        keep(settled)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { measured = settled }
    }

    /// The tab's spread for its navigation, and for a tab opening later if
    /// this one is showing (a tab out of sight measures without the hinge).
    private func keep(_ spread: Spread) {
        shell.spreads[tab] = spread
        if shell.isShowing(tab) { shell.lastSpread = spread }
    }

    /// Every screen in the stack, each under the next. A screen stays put
    /// (and keeps its scroll position) while others cover it: a pushed screen
    /// slides in over it, and Back or a swipe slides the top one off to
    /// uncover it. Only the top screen comes and goes, always the same way,
    /// so none leaves with a transition left over from the move before
    /// (SwiftUI animates a removal with the transition from the view's last
    /// update).
    private func visibleDepths(_ path: ShellPath) -> [ScreenID] {
        (0...path.routes.count).map { ScreenID(depth: $0, route: $0 == 0 ? nil : path.routes[$0 - 1]) }
    }

    private func screen(at id: ScreenID, in path: ShellPath) -> some View {
        ScreenFrame(title: id.route.map(\.title) ?? title) {
            if let route = id.route {
                ShellScreen(route: route)
            } else {
                root()
            }
        }
        // Unfolded, the screen above draws this one on its left page
        // (`ShellRoute.leftPage`), so this one's own screen stays out of
        // sight: a swipe back uncovers the one beneath both. It goes by the
        // posture Back does, so it's hidden exactly when Back leaves both.
        // With Reduce Motion it waits for a swipe, or the one beneath would
        // show through as the screen above fades in.
        .opacity(path.isDrawnByTheOneAbove(id.depth, twoPages: shell.isTwoPages(in: tab)) && (!reduceMotion || swipe != nil) ? 0 : 1)
    }

    private func back() {
        shell.back(tab)
    }

    /// The strip along the leading edge that a swipe back starts in.
    private var edge: some View {
        Color.clear
            .frame(width: Self.edgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        swipe = max(0, value.translation.width)
                    }
                    .onEnded { value in
                        let width = max((measured ?? .onePage).width, 1)
                        let goesBack = value.translation.width > width * Self.swipeCommit
                            || value.predictedEndTranslation.width > width * 0.6
                        if goesBack, reduceMotion {
                            // Fades from where the finger left it.
                            back()
                            swipe = nil
                        } else if goesBack {
                            withAnimation(.easeOut(duration: 0.2)) {
                                swipe = travel
                            } completion: {
                                var instant = Transaction()
                                instant.disablesAnimations = true
                                withTransaction(instant) {
                                    back()
                                    swipe = nil
                                }
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                swipe = 0
                            } completion: {
                                swipe = nil
                            }
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}

/// One screen in a stack: the tab's root at depth 0, then each route.
private struct ScreenID: Hashable {
    var depth: Int
    var route: ShellRoute?
}

/// A screen's title and content on an opaque page, so a pushed screen covers
/// the one beneath. The title sits on the left page. `nil`: the screen draws
/// its own (Settings on each page; Home and the Library, which decide theirs).
struct ScreenFrame<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        TitledScreen {
            if let title {
                ScreenTitle(title)
                    .onLeftPage()
            }
        } content: {
            content()
        }
        // The bar's height changes as Back comes and goes, which would move
        // the title; the Duo keeps the bar's buttons in the side column, so
        // the screen ignores it and places its title itself.
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(.systemBackground))
    }
}

/// A title over a screen's content, where every screen has its title: for a
/// screen that decides its own (Home has none unfolded beside your book; the
/// Library's is the servers' menu when there are several).
struct TitledScreen<Title: View, Content: View>: View {
    @ViewBuilder let title: () -> Title
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A screen's large title, where every screen has it: level with the one
/// the system drew folded. A screen without a route title (Settings) draws
/// one on each page with this.
struct ScreenTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.largeTitle.bold())
            .lineLimit(untilLargerText: 1)
            .padding(.horizontal, 20)
            .padding(.top, SpreadMetrics.titleTop)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
