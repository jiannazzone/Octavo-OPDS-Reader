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

extension View {
    /// A route's large title; a screen without one (a book's, a page of
    /// Settings) names itself, or has none.
    func routeTitle(_ title: String?) -> some View {
        modifier(RouteTitle(title: title))
    }

    /// Lays the view out by the room it has (`Spread`): two pages across the
    /// hinge, or one.
    func measuresSpread() -> some View {
        modifier(MeasuresSpread())
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

/// A screen's spread, as it measures its room. Only a fold (a new width)
/// re-lays it out smoothly, over 0.3 s (at once with Reduce Motion); its
/// first reading, and the hinge's region arriving at the same width, are
/// taken at once, or a screen showing for the first time would visibly
/// rearrange itself (`docs/notes/duo-tabbar.md` §7).
private struct MeasuresSpread: ViewModifier {
    @State private var spread: Spread?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.spread, spread ?? .onePage)
            .onSpreadChange { new in
                // Narrower than a page: the layout before the first real one.
                guard new.width >= Spread.minimumPageWidth, new != spread else { return }
                let folded = spread.map { $0.width != new.width } ?? false
                var transaction = Transaction(animation: folded && !reduceMotion ? .easeInOut(duration: 0.3) : nil)
                transaction.disablesAnimations = !folded || reduceMotion
                withTransaction(transaction) { spread = new }
            }
    }
}
