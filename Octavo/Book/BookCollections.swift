import OctavoKit
import SwiftUI

/// The details' Collections row on a BookOrbit book (Adam, 2026-11-14,
/// #120, `docs/notes/book-collections.md`): as many names as fit on one
/// line, then a count ("Classics · Spike +3"), and a chevron to the
/// Collections screen.
struct BookCollectionsRow: View {
    let page: BookPage
    let book: SourcedBook
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let names = page.collections?.map(\.title) ?? []
        Button {
            shell.push(.bookCollections(book))
        } label: {
            BookDetailsRow("Collections") {
                HStack(spacing: 6) {
                    BookCollectionNames(names: names)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Collections")
        .accessibilityValue(names.isEmpty ? "None" : names.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// "Classics · Spike +3": the most names that fit on one line, then how
/// many more. "—" for none. At the accessibility text sizes, where the row
/// stacks, every name, wrapping.
struct BookCollectionNames: View {
    let names: [String]
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        if names.isEmpty {
            Text("—")
        } else if size.isAccessibilitySize {
            Text(Self.line(names, showing: names.count))
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: names.count, through: 1, by: -1)), id: \.self) { shown in
                    Text(Self.line(names, showing: shown))
                        .lineLimit(1)
                        .fixedSize()
                }
                // Not even one fits: the first, cut short, and the rest.
                Text(Self.line(names, showing: 1))
                    .lineLimit(1)
            }
        }
    }

    static func line(_ names: [String], showing shown: Int) -> String {
        let line = names.prefix(shown).joined(separator: " · ")
        return shown < names.count ? "\(line) +\(names.count - shown)" : line
    }
}

/// The collections of yours a book is in: a tick on each, a tap to change
/// it, and "New collection" at the end to make one with the book in it.
/// Unfolded, the book's cover is on the left page.
struct BookCollectionsScreen: View {
    let book: SourcedBook
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let source = library.source(for: book.source) {
            let page = shell.pages.page(for: book)
            SpreadPages(folded: .right) { _ in
                Color(.secondarySystemBackground)
                    .overlay {
                        if let cover = page.cover { FittedCover(image: cover) }
                    }
                    .ignoresSafeArea(edges: .vertical)
                    .accessibilityHidden(true)
            } right: { _ in
                BookCollectionsList(page: page, source: source)
            }
            .task {
                page.load(from: source)
                await page.loadCollections(from: source)
            }
        } else {
            LibraryNotConnected()
        }
    }
}

struct BookCollectionsList: View {
    let page: BookPage
    let source: any LibrarySource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Collections")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 12)
                if let choices = page.collectionChoices {
                    ForEach(choices) { collection in
                        row(collection)
                        Divider()
                    }
                    BookNewCollectionRow(page: page, source: source)
                } else if page.collectionsFailed {
                    HStack {
                        Text("Couldn’t load your collections.")
                            .foregroundStyle(.secondaryOnGlass)
                        Spacer()
                        Button("Try again") { Task { await page.loadCollections(from: source) } }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 11)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                if let problem = page.collectionsProblem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondaryOnGlass)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, SpreadMetrics.margin)
            .padding(.top, SpreadMetrics.titleTop)
            .padding(.bottom, 20)
        }
    }

    private func row(_ collection: LibraryBookCollection) -> some View {
        Button {
            Task { await page.setCollection(collection, contains: !collection.contains, from: source) }
        } label: {
            HStack {
                Text(collection.entry.title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if collection.contains {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(collection.contains ? .isSelected : [])
    }
}

/// "New collection": a tap turns it into a name field, and Return makes the
/// collection with the book in it. An empty name puts the row back.
struct BookNewCollectionRow: View {
    let page: BookPage
    let source: any LibrarySource
    @State private var naming = false
    @State private var name = ""
    @State private var making = false
    @FocusState private var focused: Bool

    var body: some View {
        if naming {
            HStack {
                TextField("Name", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .disabled(making)
                    .onSubmit(make)
                if making { ProgressView() }
            }
            .padding(.vertical, 11)
            .onAppear { focused = true }
            .onChange(of: focused) { _, focused in
                if !focused, !making, name.trimmingCharacters(in: .whitespaces).isEmpty { naming = false }
            }
        } else {
            Button {
                name = ""
                naming = true
            } label: {
                Label("New collection", systemImage: "plus")
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    private func make() {
        making = true
        Task {
            let done = await page.newCollection(named: name, from: source)
            making = false
            if done {
                naming = false
                name = ""
            } else {
                focused = true
            }
        }
    }
}
