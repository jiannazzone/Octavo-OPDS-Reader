import SwiftUI

/// Setup, shown instead of the tabs before there's a server or a book
/// (decision 6): the system's push stack, each step sliding in with Back
/// (decision 157). Nothing to skip to, unless the tour brought you here.
/// Each step lays itself out by its room (`measuresSpread`): its words on the
/// left page and what you do on the right, unfolded.
struct SetupStack: View {
    /// The tour's Add your books has Skip (decision 30).
    let skip: (() -> Void)?
    @Environment(ShellModel.self) private var shell

    var body: some View {
        NavigationStack(path: steps) {
            SetupStart()
                .measuresSpread()
                .routeTitle("Add your books")
                .toolbar {
                    if let skip {
                        ToolbarItem(placement: .topBarTrailing) { TourSkipButton(action: skip) }
                    }
                }
                .navigationDestination(for: ShellRoute.self) { route in
                    ShellScreen(route: route)
                        .measuresSpread()
                        .routeTitle(route.title)
                }
        }
    }

    /// Setup's steps, which Back and the swipe change.
    private var steps: Binding<[ShellRoute]> {
        Binding { shell[path: .setup].routes } set: { shell[path: .setup].replace($0) }
    }
}
