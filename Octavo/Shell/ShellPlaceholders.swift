import OctavoKit
import SwiftUI

// The route-to-screen map and the stand-in screens, replaced by #15
// (Search), #16 (Settings) and #17 (the reader). The stand-ins show the
// shell's layout and shared states; nothing in them is a design.

/// The view for a route.
struct ShellScreen: View {
    let route: ShellRoute

    var body: some View {
        switch route {
        case .feed(let entry, let source): FeedScreen(entry: entry, source: source)
        case .settingsPage(let name): SettingsPagePlaceholder(name: name)
        case .cover(let book): CoverScreen(book: book)
        }
    }
}

struct SearchPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Stand-in until #15."))
    }
}

struct SettingsPlaceholder: View {
    var body: some View {
        List {
            Section("Server") {
                ShellLink(.settingsPage("BookOrbit")) {
                    VStack(alignment: .leading) {
                        Text("BookOrbit")
                        Text("books.example.com · adam")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Reading progress", value: "Synced")
            }
            Section("Storage") {
                ShellLink(.settingsPage("Books on iPhone")) {
                    LabeledContent("Books on iPhone", value: "12 · 48 MB")
                }
            }
            Section {
                ShellLink(.settingsPage("About")) { Text("About") }
            } header: {
                Text("About")
            } footer: {
                Text("Stand-in content until #16.")
            }
            #if DEBUG
            DebugServerSection()
            DebugTrustSection()
            ShellStatesSection()
            #endif
        }
    }
}

struct SettingsPagePlaceholder: View {
    let name: String

    var body: some View {
        List {
            if name == "BookOrbit" {
                Section {
                    LabeledContent("Address", value: "books.example.com")
                    LabeledContent("Account", value: "adam")
                    LabeledContent("Reading progress", value: "Synced with this server")
                }
            }
            Section {
                Text("Stand-in until #16.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A book's cover page (#14), from the library the book came from. Its
/// author opens their books beside it, and Open goes through the shell so
/// the book joins Home's Continue reading.
struct CoverScreen: View {
    let book: SourcedBook
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.pane) private var pane

    var body: some View {
        if let source = library.source(for: book.source) {
            BookCoverPage(book: book.book, source: source)
                .id(library.connection)
                .environment(\.openLibraryEntry) { entry in
                    shell.open(.feed(entry, from: book.source), from: pane)
                }
                .environment(\.openBook) { opened in
                    shell.openBook(SourcedBook(source: book.source, book: opened))
                }
        } else {
            LibraryNotConnected()
        }
    }
}

/// The reader, over the tabs: the spike's reader until #17 replaces it.
/// Positions stay on the iPhone; syncing them is #11.
struct ReaderPlaceholder: View {
    let book: OpenedBook
    @Environment(ShellModel.self) private var shell

    var body: some View {
        NavigationStack {
            SpikeReaderView(book: book.reader, sync: nil, cfiShape: .point)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { shell.reading = nil }
                    }
                }
        }
        .background(Color(.systemBackground))
    }
}

/// The connection banner, when there's a problem.
struct ConnectionBannerSlot: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let problem = library.connectionProblem {
            ConnectionBanner(problem: problem) { resolve(problem) }
        }
    }

    private func resolve(_ problem: ConnectionProblem) {
        switch problem {
        case .unreachable:
            Task { await library.retry() }
        case .signedOut:
            #if DEBUG
            if library.server?.id == LibraryModel.localBookOrbitID {
                Task { await library.connectLocalBookOrbit() }
                return
            }
            #endif
            // Signing in again belongs to Settings (#9, #16).
            shell.tab = .settings
        }
    }
}
