import SwiftUI

/// The app's root: three tabs in the side column (Home, Library, Search),
/// each the system's split of a list and what's picked from it
/// (`TabSplit`), and the reader over them when a book is open.
///
/// The reader is a layer over the tabs, not a `fullScreenCover`: a cover
/// presented by an unfold (which starts about 200 ms before the scene moves
/// to the inner display) stays laid out for the outer display, turned on
/// its side (`docs/notes/duo-tabbar.md` §6). A layer in the same hierarchy
/// follows the scene like any other view.
///
/// No pop-up alerts anywhere, except to confirm deleting or removing
/// something. Problems show as a `ConnectionBanner` at the top of a screen,
/// a `CoverStripMessage` on a book's screen, or an `EmptyInvitation` on an
/// empty screen; sign-in errors sit under the fields.
struct AppShell: View {
    @State private var model = ShellModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if model.showsSetup {
                    // No tabs, and nothing to skip to (decision 6) unless
                    // the tour brought you here.
                    SetupStack(skip: model.addsBooksAfterTour ? { model.skipAddingBooks() } : nil)
                } else {
                    tabs
                }
            }
            .accessibilityHidden(isCovered)
            if model.tour.isActive {
                TourScreen()
                    .accessibilityHidden(model.reader.reading != nil)
                    .transition(.identity)
            }
            if let book = model.reader.reading {
                ReaderView(
                    book: book, bookmarkSync: model.reader.bookmarkSync,
                    progressSync: model.reader.progressSync, listedPlace: model.reader.listedPlace,
                    connectionReturns: model.connection.returns,
                    opened: { [motion = model.reader.coverMotion] pages in motion?.readerOpened(pages) },
                    closing: { model.reader.closing($0) }
                ) { model.reader.close() }
                    // Another book is another reader: its own model, hooks
                    // and controls, and the old one closes (flushing its
                    // position).
                    .id(book.reader)
                    // Fades in, but leaves at once: a reader still fading
                    // out keeps its web page attached, and an unfold
                    // meanwhile has SwiftUI rebuild that web view, which
                    // WebKit traps on (open, close, open again, unfold).
                    // Opened from its cover, it's there at once, under the
                    // cover's motion.
                    .transition(.asymmetric(insertion: model.reader.coverMotion == nil ? .opacity : .identity, removal: .identity))
            }
            if let motion = model.reader.coverMotion {
                ReaderCoverMotionView(motion: motion)
                    .transition(.identity)
            }
        }
        // Import from Files and the Library's +: the system's picker, no
        // screen of our own (decision 6).
        .fileImporter(
            isPresented: Binding(get: { model.picksFiles }, set: { model.picksFiles = $0 }),
            allowedContentTypes: BookImporter.contentTypes, allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.importBooks(urls) }
        }
        // Settings, from the gear (`SettingsSheet`).
        // Not over setup: a replay's Add your books comes back to it on Skip.
        // SwiftUI writes false back when setup hides it too; only a close
        // or a swipe down closes Settings.
        .sheet(isPresented: Binding(get: { model.showsSettings && !model.showsSetup }, set: { if !$0, !model.showsSetup { model.closeSettings() } })) {
            SettingsSheet()
                .presentationSizing(.page)
        }
        // Open in Octavo, from another app's share sheet.
        .onOpenURL { url in
            Task { await model.openSharedFile(url) }
        }
        .onHingeChange { old, new in
            model.tour.hingeReported(HingeTransition.Fold(new.hinge?.status))
            model.hingeChanged(HingeTransition(from: old, to: new))
        }
        // Nothing from the hinge by now: no fold on this iPhone (decision 29).
        .task {
            try? await Task.sleep(for: .seconds(0.75))
            model.tour.hingeStayedSilent()
        }
        .animation(.default, value: model.reader.reading)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.retryUnsentPlaces() }
        }
        .environment(model)
        .environment(model.library)
        #if DEBUG
        .task { await ReaderRemote.run(shell: model) }
        .debugProbe("shell")
        #endif
    }

    private var isCovered: Bool {
        model.reader.reading != nil || model.tour.isActive
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { model.tab }, set: { model.select($0) })) {
            Tab("Home", systemImage: "house", value: .home) {
                TabSplit(tab: .home) {
                    HomeView()
                } buttons: {
                    settingsButton
                }
            }
            Tab("Library", systemImage: "books.vertical", value: .library) {
                TabSplit(tab: .library) {
                    LibraryView()
                } buttons: {
                    if model.library.hasSeveralServers {
                        ToolbarItem(placement: .topBarTrailing) { ServersMenu() }
                    }
                    // The Library's + for Import from Files, above Settings
                    // (Adam, 2026-11-02).
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import from Files", systemImage: "plus") { model.showFilePicker() }
                    }
                    settingsButton
                }
            }
            Tab(value: .search, role: .search) {
                TabSplit(tab: .search) {
                    SearchView()
                } buttons: {
                    settingsButton
                }
            }
        }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { model.openSettings() }
        }
    }
}

#Preview {
    AppShell()
}
