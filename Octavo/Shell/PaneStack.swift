import SwiftUI

/// A tab's navigation, laid out for the fold.
///
/// - Folded: an ordinary `NavigationStack`, one screen at a time.
/// - Unfolded or half open: the same path, but each screen on the stack is a
///   pair of panes split at the hinge, with nothing on it (decisions 9, 23).
///   Both panes' toolbar buttons and the system Back button then sit in the
///   side column, and Back pops a pair, which shifts the panes back one
///   level (`docs/notes/duo-tabbar.md` §5).
///
/// The path lives in `ShellModel`, so folding or unfolding keeps the same
/// screens (decision 10). The views themselves are rebuilt when the layout
/// changes: state that must survive a fold belongs in a model.
struct PaneStack<Root: View>: View {
    let tab: ShellTab
    let title: String
    @Binding var path: PanePath
    /// Behind both panes and the hinge between them, unfolded: white for
    /// plain screens, grouped grey for inset lists.
    var background = Color(.systemGroupedBackground)
    @ViewBuilder let root: () -> Root
    @State private var split: PaneSplit?

    var body: some View {
        Group {
            if let split {
                pairs(split)
            } else {
                stack
            }
        }
        .onGeometryChange(for: PaneSplit?.self) { proxy in
            PaneSplit(proxy)
        } action: { split = $0 }
    }

    private var stack: some View {
        NavigationStack(path: $path.routes) {
            root()
                .navigationTitle(title)
                .navigationDestination(for: ShellRoute.self) { route in
                    ShellScreen(route: route)
                        .navigationTitle(route.title ?? "")
                }
        }
        .environment(\.pane, PaneContext(tab: tab))
    }

    private func pairs(_ split: PaneSplit) -> some View {
        NavigationStack(path: $path.pushedPairs) {
            pair(0, split)
                .navigationDestination(for: PaneLevel.self) { level in
                    pair(level.value, split)
                }
        }
    }

    private func pair(_ level: Int, _ split: PaneSplit) -> some View {
        let left = path.route(at: level)
        let right = path.rightOfPair(level)
        return HStack(spacing: 0) {
            pane(level, title: level == 0 ? title : left?.title, opened: right) {
                if let left {
                    ShellScreen(route: left)
                } else if level == 0 {
                    root()
                }
            }
            .frame(width: split.leftWidth)
            Color.clear
                .frame(width: split.hingeWidth)
            pane(level + 1, title: right?.title, opened: nil) {
                if let right {
                    ShellScreen(route: right)
                }
            }
            .frame(width: split.rightWidth)
        }
        // The bar's height changes once Back appears, which would move the
        // panes; the Duo keeps the bar's buttons in the side column, so the
        // panes ignore it and place their titles themselves.
        .ignoresSafeArea(.container, edges: .top)
        .background(background)
        .toolbarTitleDisplayMode(.inline)
    }

    /// Where a pane's title starts: level with the large title the system
    /// draws folded, so a title doesn't jump when the Duo unfolds. Measured
    /// on the simulator (#13): the folded title's ink starts at 37.3 pt, and
    /// 28 left the pane's 2 pt higher.
    private static var titleTop: CGFloat { 30 }

    /// The navigation bar holds one title, so each pane draws its own.
    private func pane<Content: View>(
        _ level: Int, title: String?, opened: ShellRoute?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.top, Self.titleTop)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.pane, PaneContext(tab: tab, level: level, opened: opened))
    }
}

/// Which pane a screen is in, for `ShellLink`.
nonisolated struct PaneContext: Hashable, Sendable {
    var tab: ShellTab
    /// The pane's level (0 is the tab's root). `nil` folded, where links
    /// push onto the top of the stack.
    var level: Int?
    /// Unfolded: what the pane to the right shows, so a link to it can
    /// look selected.
    var opened: ShellRoute?
}

extension EnvironmentValues {
    @Entry var pane = PaneContext(tab: .home)
}

/// The shell's `NavigationLink`: opens a screen in the current tab, pushed
/// folded, beside this pane or shifted along unfolded (`PanePath`).
struct ShellLink<Label: View>: View {
    let route: ShellRoute
    @ViewBuilder let label: () -> Label
    @Environment(ShellModel.self) private var shell
    @Environment(\.pane) private var pane

    init(_ route: ShellRoute, @ViewBuilder label: @escaping () -> Label) {
        self.route = route
        self.label = label
    }

    var body: some View {
        Button {
            shell.open(route, from: pane)
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
        .listRowBackground(route.isSameScreen(as: pane.opened) ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityAddTraits(route.isSameScreen(as: pane.opened) ? .isSelected : [])
    }
}
