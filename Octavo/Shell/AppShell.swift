import SwiftUI

/// The app's root: four tabs in the side column (decision 2), each a
/// `PaneStack` that splits at the hinge when unfolded or half open, and the
/// reader over them when a book is open.
///
/// The reader is a layer over the tabs, not a `fullScreenCover`: a cover
/// presented by an unfold (which starts about 200 ms before the scene moves
/// to the inner display) stays laid out for the outer display, turned on
/// its side (`docs/notes/duo-tabbar.md` §6). A layer in the same hierarchy
/// follows the scene like any other view.
///
/// No pop-up alerts anywhere, except to confirm deleting or removing
/// something (decision 22). Problems show as a `ConnectionBanner` at the top
/// of a tab, a `CoverStripMessage` on a book's cover, or an
/// `EmptyInvitation` on an empty screen; sign-in errors sit under the fields.
struct AppShell: View {
    @State private var model = ShellModel()

    var body: some View {
        ZStack {
            tabs
                .accessibilityHidden(isCovered)
            if let book = model.reading {
                ReaderPlaceholder(book: book)
                    .transition(.opacity)
            }
            #if DEBUG
            if model.showsSpike {
                SpikeLibraryView()
                    .overlay(alignment: .bottomLeading) {
                        Button("Close spike library", systemImage: "xmark") { model.showsSpike = false }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .padding()
                    }
                    .background(Color(.systemBackground))
            }
            #endif
        }
        .animation(.default, value: model.reading)
        .onHingeChange { old, new in
            model.hingeChanged(HingeTransition(from: old, to: new))
        }
        .environment(model)
    }

    private var isCovered: Bool {
        #if DEBUG
        model.reading != nil || model.showsSpike
        #else
        model.reading != nil
        #endif
    }

    private var tabs: some View {
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "house", value: .home) {
                PaneStack(tab: .home, title: "Home", path: $model[path: .home]) { HomePlaceholder() }
            }
            Tab("Library", systemImage: "books.vertical", value: .library) {
                PaneStack(tab: .library, title: "Library", path: $model[path: .library]) { LibraryPlaceholder() }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                PaneStack(tab: .settings, title: "Settings", path: $model[path: .settings]) { SettingsPlaceholder() }
            }
            Tab(value: .search, role: .search) {
                PaneStack(tab: .search, title: "Search", path: $model[path: .search]) { SearchPlaceholder() }
            }
        }
    }
}

#Preview {
    AppShell()
}
