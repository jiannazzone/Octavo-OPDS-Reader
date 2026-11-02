import SwiftUI

/// A tab's screens, drawn by Octavo rather than a `NavigationStack`'s pushes:
/// the deepest screen fills the spread, folded or unfolded, and a fold only
/// lays it out again (`docs/design/direction.md`).
///
/// - A pushed screen slides in from the trailing edge; Back, or a swipe from
///   the leading edge, slides it out.
/// - Back (or, at the root, Settings) sits in the side column: the
///   `NavigationStack` here never pushes and exists only so the system puts
///   those buttons there, as it does the reader's.
struct ScreenStack<Root: View>: View {
    let tab: ShellTab
    let title: String
    /// Whether the tab's root has its two-page layout yet.
    var rootFillsSpread = false
    @ViewBuilder let root: () -> Root
    @Environment(ShellModel.self) private var shell
    @State private var spread = Spread.onePage
    /// How far a swipe from the leading edge has pulled the top screen.
    @State private var swipe: CGFloat?

    /// A swipe this far across, or flicked this fast, goes back.
    private static var swipeCommit: CGFloat { 0.35 }
    private static var edgeWidth: CGFloat { 24 }

    var body: some View {
        let path = shell[path: tab]
        NavigationStack {
            ZStack(alignment: .topLeading) {
                ForEach(visibleDepths(path), id: \.self) { id in
                    screen(at: id, in: path)
                        .zIndex(Double(id.depth))
                        .offset(x: id.depth == path.routes.count ? swipe ?? 0 : 0)
                        .transition(Self.transition(path.lastMove))
                }
                if !path.routes.isEmpty {
                    edge
                        .zIndex(Double(path.routes.count + 1))
                }
            }
            .animation(.smooth(duration: 0.35), value: path)
            .animation(.easeInOut(duration: 0.3), value: spread)
            .onGeometryChange(for: Spread.self) { Spread($0) } action: { spread = $0 }
            .environment(\.spread, spread)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if path.routes.isEmpty {
                        Button("Settings", systemImage: "gearshape") { shell.openSettings() }
                    } else {
                        Button("Back", systemImage: "chevron.backward") { shell.pop(tab) }
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
        }
    }

    /// The top screen, and while a swipe is under way the one it uncovers.
    private func visibleDepths(_ path: ShellPath) -> [ScreenID] {
        let top = path.routes.count
        let depths = swipe != nil && top > 0 ? [top - 1, top] : [top]
        return depths.map { ScreenID(depth: $0, route: $0 == 0 ? nil : path.routes[$0 - 1]) }
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

    private static func transition(_ move: ShellPath.Move) -> AnyTransition {
        switch move {
        case .push: .asymmetric(insertion: .move(edge: .trailing), removal: .opacity)
        case .pop: .asymmetric(insertion: .identity, removal: .move(edge: .trailing))
        case .replace: .identity
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
                        let width = max(spread.width, 1)
                        let goesBack = value.translation.width > width * Self.swipeCommit
                            || value.predictedEndTranslation.width > width * 0.6
                        if goesBack {
                            withAnimation(.easeOut(duration: 0.2)) {
                                swipe = width
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

    /// Where a title starts: level with the large title the system drew
    /// folded, so it doesn't jump when the Duo unfolds (measured in #13).
    static var titleTop: CGFloat { 30 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.top, Self.titleTop)
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
    @ViewBuilder let label: () -> Label
    @Environment(ShellModel.self) private var shell

    init(_ route: ShellRoute, @ViewBuilder label: @escaping () -> Label) {
        self.route = route
        self.label = label
    }

    var body: some View {
        Button {
            shell.push(route)
        } label: {
            HStack {
                label()
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
    }
}
