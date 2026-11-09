import SwiftUI

/// A tab as the system's push stack, its screens laid out as spreads (Adam,
/// 2026-11-08: keep the spreads): the tab's top screen, then each screen
/// pushed over it, with the system's Back and swipe in every posture. Each
/// screen lays itself out by its room (`measuresSpread`): two pages across
/// the hinge open, one folded and on an iPhone. The tab's state is its
/// `ShellPath`.
struct TabStack<Root: View, Buttons: ToolbarContent>: View {
    let tab: ShellTab
    @ViewBuilder let root: () -> Root
    /// On the top screen: the side column's buttons on the Duo, the bar's
    /// elsewhere.
    @ToolbarContentBuilder let buttons: () -> Buttons
    @Environment(ShellModel.self) private var shell

    var body: some View {
        NavigationStack(path: routes) {
            root()
                .measuresSpread()
                .toolbar { buttons() }
                .navigationDestination(for: ShellRoute.self) { route in
                    ShellScreen(route: route)
                        .measuresSpread()
                        .routeTitle(route.title)
                }
        }
    }

    /// The tab's screens, which Back and the swipe change.
    private var routes: Binding<[ShellRoute]> {
        Binding { shell[path: tab].routes } set: { shell[path: tab].replace($0) }
    }
}
