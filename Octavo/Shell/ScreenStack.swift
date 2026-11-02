import SwiftUI

/// A tab's screens, drawn by Octavo rather than a `NavigationStack`'s pushes:
/// the deepest screen fills the spread, folded or unfolded, and a fold only
/// lays it out again (`docs/design/direction.md`).
///
/// - A pushed screen slides in from the trailing edge over the one before,
///   which stays as it was; Back, or a swipe from the leading edge, slides
///   it out.
/// - Back (or, at the root, Settings) sits in the side column: the
///   `NavigationStack` here never pushes and exists only so the system puts
///   those buttons there, as it does the reader's.
struct ScreenStack<Root: View>: View {
    let tab: ShellTab
    let title: String
    /// Whether the tab's root has its two-page layout yet.
    var rootFillsSpread = false
    /// Setup has no Settings to open.
    var showsSettings = true
    @ViewBuilder let root: () -> Root
    @Environment(ShellModel.self) private var shell
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
                        .transition(.offset(x: travel))
                }
                if !path.routes.isEmpty {
                    edge
                        .zIndex(Double(path.routes.count + 1))
                }
            }
            // A replaced path (a launch argument, closing the reader onto its
            // book) changes at once.
            .animation(path.lastMove == .replace ? nil : Self.slide, value: path)
            .animation(.easeInOut(duration: 0.3), value: measured)
            .onGeometryChange(for: Spread.self) { Spread($0) } action: { new in
                spreadChanged(to: new)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width + $0.safeAreaInsets.trailing } action: {
                travel = $0 + Self.overshoot
            }
            .environment(\.spread, spread)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if path.routes.isEmpty {
                        if showsSettings {
                            Button("Settings", systemImage: "gearshape") { shell.openSettings() }
                        }
                    } else {
                        Button("Back", systemImage: "chevron.backward") { shell.pop(tab) }
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
        if let old = measured, old.width != new.width {
            measured = new
            shell.lastSpread = new
            return
        }
        // Before the region arrives, a stack opening at the width the
        // other tabs have takes their split.
        let settled = if measured == nil, new.pages == nil, let known = shell.lastSpread, known.width == new.width { known } else { new }
        shell.lastSpread = settled
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { measured = settled }
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
        ScreenFrame(title: id.route.map(\.title) ?? title, fillsSpread: id.route?.fillsSpread ?? rootFillsSpread) {
            if let route = id.route {
                ShellScreen(route: route)
            } else {
                root()
            }
        }
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
                        if goesBack {
                            withAnimation(.easeOut(duration: 0.2)) {
                                swipe = travel
                            } completion: {
                                var instant = Transaction()
                                instant.disablesAnimations = true
                                withTransaction(instant) {
                                    shell.pop(tab)
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
/// the one beneath.
///
/// The title sits on the left page. Unfolded, a screen that hasn't got its
/// two-page layout yet keeps to the left page altogether; a book's screen
/// and Home take the whole spread as they're redone.
struct ScreenFrame<Content: View>: View {
    let title: String?
    var fillsSpread = false
    @ViewBuilder let content: () -> Content
    @Environment(\.spread) private var spread

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.top, SpreadMetrics.titleTop)
                    .padding(.bottom, 8)
                    .frame(width: spread.pages?.leftWidth, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: fillsSpread ? nil : spread.pages?.leftWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The bar's height changes as Back comes and goes, which would move
        // the title; the Duo keeps the bar's buttons in the side column, so
        // the screen ignores it and places its title itself.
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(.systemBackground))
    }
}

/// A list row that opens a screen in the current tab: pushed, folded or
/// unfolded.
struct ShellLink<Label: View>: View {
    let route: ShellRoute
    /// Off for the Library's lists: unfolded, a row's chevron would sit
    /// mid-screen at the left page's edge.
    var showsChevron = true
    @ViewBuilder let label: () -> Label
    @Environment(ShellModel.self) private var shell

    init(_ route: ShellRoute, showsChevron: Bool = true, @ViewBuilder label: @escaping () -> Label) {
        self.route = route
        self.showsChevron = showsChevron
        self.label = label
    }

    var body: some View {
        Button {
            shell.push(route)
        } label: {
            HStack {
                label()
                Spacer(minLength: 8)
                if showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
    }
}
