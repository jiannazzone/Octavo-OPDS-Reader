import SwiftUI

// Stand-in screens for the shell, replaced by #13 (Home, Library), #14 (the
// cover page), #15 (Search), #16 (Settings) and #17 (the reader). They show
// the shell's layout and shared states; nothing here is a design.

/// The view for a route.
struct ShellScreen: View {
    let route: ShellRoute

    var body: some View {
        switch route {
        case .collections: CollectionsPlaceholder()
        case .collection: BookListPlaceholder(books: PlaceholderBook.samples, note: "#13")
        case .settingsPage(let name): SettingsPagePlaceholder(name: name)
        case .cover(let book): CoverPlaceholder(book: book)
        }
    }
}

struct HomePlaceholder: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if shell.homeIsEmpty {
            VStack(spacing: 0) {
                ConnectionBannerSlot()
                    .padding(.horizontal, 20)
                EmptyInvitation(
                    symbol: "books.vertical", title: "Nothing in progress",
                    message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
                ) { shell.tab = .library }
            }
        } else {
            List {
                ConnectionBannerSlot()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Section("Continue reading") {
                    ForEach(PlaceholderBook.samples.prefix(2)) { BookLink(book: $0) }
                }
                Section {
                    ForEach(PlaceholderBook.samples.dropFirst(2)) { BookLink(book: $0) }
                } header: {
                    Text("New on BookOrbit")
                } footer: {
                    Text("Stand-in content until #13.")
                }
            }
        }
    }
}

struct LibraryPlaceholder: View {
    var body: some View {
        List {
            ConnectionBannerSlot()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            Section {
                ShellLink(.collections) { Text("Collections") }
            }
            Section {
                ForEach(PlaceholderBook.samples) { BookLink(book: $0) }
            } footer: {
                Text("Stand-in content until #13.")
            }
            #if DEBUG
            SpikeLibrarySection()
            #endif
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
            ShellStatesSection()
            #endif
        }
    }
}

struct CollectionsPlaceholder: View {
    var body: some View {
        List {
            Section {
                ForEach(["Classics", "Spike", "To read next"], id: \.self) { name in
                    ShellLink(.collection(name)) {
                        VStack(alignment: .leading) {
                            Text(name)
                            Text("5 books")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Stand-in content until #13.")
            }
        }
    }
}

struct BookListPlaceholder: View {
    let books: [PlaceholderBook]
    let note: String

    var body: some View {
        List {
            Section {
                ForEach(books) { BookLink(book: $0) }
            } footer: {
                Text("Stand-in content until \(note).")
            }
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

/// A row that opens a book's cover.
struct BookLink: View {
    let book: PlaceholderBook

    var body: some View {
        ShellLink(.cover(book)) {
            HStack(spacing: 12) {
                StandInCover(book: book)
                    .frame(width: 30, height: 45)
                    .clipShape(.rect(cornerRadius: 3))
                VStack(alignment: .leading) {
                    Text(book.title)
                        .lineLimit(1)
                    Text(book.place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A book's cover page: the cover filling the screen, under the camera
/// column (decision 4), and the strip at the bottom. Folded, unfolding here
/// opens the book (`ShellModel.hingeChanged`).
struct CoverPlaceholder: View {
    let book: PlaceholderBook
    @Environment(ShellModel.self) private var shell

    var body: some View {
        StandInCover(book: book)
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
                        Text(book.place)
                            .font(.headline)
                        Text("Stand-in strip until #14")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Open") { shell.openBook(book) }
                        .buttonStyle(.glassProminent)
                }
                ProgressView(value: book.progress)
            }
        }
    }
}

/// A coloured block with the title, standing in for cover artwork.
struct StandInCover: View {
    let book: PlaceholderBook

    var body: some View {
        let hue = Double(book.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 }) / 360
        LinearGradient(
            colors: [Color(hue: hue, saturation: 0.45, brightness: 0.55), Color(hue: hue, saturation: 0.6, brightness: 0.3)],
            startPoint: .top, endPoint: .bottom
        )
        .overlay {
            VStack(spacing: 8) {
                Text(book.title)
                    .font(.system(.largeTitle, design: .serif).bold())
                Text(book.author)
                    .font(.system(.title3, design: .serif))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(40)
            .minimumScaleFactor(0.2)
        }
    }
}

/// The reader, over the tabs. #17 replaces it.
struct ReaderPlaceholder: View {
    let book: PlaceholderBook
    @Environment(ShellModel.self) private var shell

    var body: some View {
        NavigationStack {
            ContentUnavailableView(book.title, systemImage: "book.pages", description: Text("Opened from the shell. The reader comes with #17."))
                .toolbar {
                    Button("Close", systemImage: "xmark") { shell.reading = nil }
                }
        }
        .background(Color(.systemBackground))
    }
}

/// The connection banner, when there's a problem.
struct ConnectionBannerSlot: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let problem = shell.connectionProblem {
            ConnectionBanner(problem: problem) { shell.resolveConnectionProblem() }
        }
    }
}
