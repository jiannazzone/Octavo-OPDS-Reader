import SwiftUI

/// A tab as the system's split (Adam, 2026-11-08): the tab's list on the
/// left, and what's picked from it on the right, where further screens push.
/// Folded, and on an iPhone, it collapses to one stack with the system's
/// Back and swipe. The tab's state is its `ShellPath`: the pick, then what's
/// pushed over it.
///
/// - The list is a `List` whose selection is the pick
///   (`ShellModel.pickBinding`): that's what gives the folded stack its Back.
///   A list in a plain scroll view collapses with none.
/// - Open, the Duo's side column holds the right column's buttons; folded,
///   the list's. So the tab's own buttons (`buttons`) go with whichever
///   column is the one on screen.
/// - Each column lays its screens out by its own room (`measuresSpread`):
///   one page, or two across the hinge with the list hidden.
struct TabSplit<Menu: View, Buttons: ToolbarContent>: View {
    let tab: ShellTab
    @ViewBuilder let menu: () -> Menu
    @ToolbarContentBuilder let buttons: () -> Buttons
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            menu()
                .environment(\.menuColumn, tab)
                .measuresSpread()
                .toolbar {
                    if sizeClass == .compact { buttons() }
                }
        } detail: {
            NavigationStack(path: pushed) {
                Group {
                    if let pick = shell[path: tab].pick {
                        screen(pick)
                    } else {
                        ContentUnavailableView("No Book Selected", systemImage: "books.vertical")
                            .toolbar {
                                if sizeClass != .compact { buttons() }
                            }
                    }
                }
                .navigationDestination(for: ShellRoute.self) { screen($0) }
            }
        }
    }

    private func screen(_ route: ShellRoute) -> some View {
        ShellScreen(route: route)
            .measuresSpread()
            .navigationTitle(route.title ?? "")
            .toolbarTitleDisplayMode(route.title == nil ? .inline : .large)
            .toolbar {
                if sizeClass != .compact { buttons() }
            }
    }

    /// The right column's stack over the pick, which Back and the swipe
    /// there change.
    private var pushed: Binding<[ShellRoute]> {
        Binding { shell[path: tab].pushed } set: { shell[path: tab].setPushed($0) }
    }
}

extension ShellModel {
    /// What a split's `List` selects: `tab`'s pick.
    func pickBinding(_ tab: ShellTab) -> Binding<ShellRoute?> {
        Binding { self[path: tab].pick } set: { self.pick($0, in: tab) }
    }
}

extension EnvironmentValues {
    /// The tab whose split list the view is in: what it opens becomes the
    /// pick (`ShellModel.open(_:inMenuOf:)`). `nil` elsewhere, where it
    /// pushes.
    @Entry var menuColumn: ShellTab?
}

extension View {
    /// Lays the view out by the room it has (`Spread`), for a column of a
    /// split: one page, or two when it spans the hinge.
    func measuresSpread() -> some View {
        modifier(MeasuresSpread())
    }
}

private struct MeasuresSpread: ViewModifier {
    @State private var spread: Spread?

    func body(content: Content) -> some View {
        content
            .environment(\.spread, spread ?? .onePage)
            .onSpreadChange { new in
                // Narrower than a page: the layout before the first real one.
                guard new.width >= Spread.minimumPageWidth, new != spread else { return }
                spread = new
            }
    }
}
