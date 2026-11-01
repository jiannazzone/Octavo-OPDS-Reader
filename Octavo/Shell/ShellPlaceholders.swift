import OctavoKit
import SwiftUI

// Stand-in screens for the shell, replaced by #14 (the cover page), #15
// (Search), #16 (Settings) and #17 (the reader). They show the shell's
// layout and shared states; nothing here is a design.

/// The view for a route.
struct ShellScreen: View {
    let route: ShellRoute

    var body: some View {
        switch route {
        case .feed(let entry, let source): FeedScreen(entry: entry, source: source)
        case .settingsPage(let name): SettingsPagePlaceholder(name: name)
        case .cover(let book): CoverPlaceholder(book: book)
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

/// A book's cover page: the cover filling the screen, under the camera
/// column (decision 4), and the strip at the bottom. Folded, unfolding here
/// opens the book (`ShellModel.hingeChanged`).
struct CoverPlaceholder: View {
    let book: SourcedBook
    @Environment(ShellModel.self) private var shell

    var body: some View {
        CoverImage(book: book, size: .full)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                strip
                    .padding()
                    .glassEffect(in: .rect(cornerRadius: 24))
                    .padding(8)
            }
    }

    @ViewBuilder
    private var strip: some View {
        if let message = shell.coverStrip {
            CoverStripStatus(message: message) { shell.coverStrip = nil }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.book.progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Not started")
                            .font(.headline)
                        Text("Stand-in strip until #14")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Open") { shell.openBook(book) }
                        .buttonStyle(.glassProminent)
                }
                ProgressView(value: book.book.progress ?? 0)
            }
        }
    }
}

/// The reader, over the tabs. #17 replaces it.
struct ReaderPlaceholder: View {
    let book: SourcedBook
    @Environment(ShellModel.self) private var shell

    var body: some View {
        NavigationStack {
            ContentUnavailableView(book.book.title, systemImage: "book.pages", description: Text("Opened from the shell. The reader comes with #17."))
                .toolbar {
                    Button("Close", systemImage: "xmark") { shell.reading = nil }
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
