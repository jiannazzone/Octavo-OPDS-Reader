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
/// - Open, with nothing picked, the right column shows the tab's
///   `ShellModel.defaultPick` (Home's current book), or says nothing is.
struct TabSplit<Menu: View, Buttons: ToolbarContent>: View {
    let tab: ShellTab
    /// The buttons stay on the list in both postures: Settings' close.
    var buttonsOnList = false
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
                    if buttonsOnList || sizeClass == .compact { buttons() }
                }
        } detail: {
            NavigationStack(path: pushed) {
                Group {
                    if let pick = shell[path: tab].pick ?? shell.defaultPick(tab) {
                        // Another pick is another screen, not this one with
                        // the last one's state (Home's default book, then
                        // one picked).
                        screen(pick)
                            .id(pick)
                    } else {
                        ContentUnavailableView("No Book Selected", systemImage: "books.vertical")
                            .toolbar {
                                if !buttonsOnList, sizeClass != .compact { buttons() }
                            }
                    }
                }
                .navigationDestination(for: ShellRoute.self) { screen($0) }
            }
        }
        .onChange(of: sizeClass, initial: true) {
            if sizeClass == .compact {
                shell.expandedSplits.remove(tab)
            } else {
                shell.expandedSplits.insert(tab)
            }
        }
    }

    private func screen(_ route: ShellRoute) -> some View {
        ShellScreen(route: route)
            .measuresSpread()
            .routeTitle(route.title)
            .toolbar {
                if !buttonsOnList, sizeClass != .compact { buttons() }
            }
    }

    /// The right column's stack over the pick, which Back and the swipe
    /// there change.
    private var pushed: Binding<[ShellRoute]> {
        Binding { shell[path: tab].pushed } set: { shell[path: tab].setPushed($0) }
    }
}

extension View {
    /// A route's large title; a screen without one (a book's, a page of
    /// Settings) names itself, or has none.
    func routeTitle(_ title: String?) -> some View {
        modifier(RouteTitle(title: title))
    }
}

private struct RouteTitle: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.large)
        } else {
            content
                .toolbarTitleDisplayMode(.inline)
        }
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
