import OctavoKit
import SwiftUI

/// SPIKE ONLY (deleted after the spike). Lists the books in the app's
/// Documents folder and reopens the last open one on launch.
/// See docs/notes/reader-spike.md for getting books onto the simulator.
struct SpikeLibraryView: View {
    @State private var books: [ReaderBook] = []
    @State private var path: [ReaderBook] = []
    @State private var didReopen = false
    @AppStorage("spike.lastOpenBook") private var lastOpenBook = ""
    private let store = ReadingPositionStore()

    var body: some View {
        NavigationStack(path: $path) {
            List(books) { book in
                NavigationLink(value: book) {
                    VStack(alignment: .leading) {
                        Text(book.fileName)
                        if let position = store.position(forBook: book.id) {
                            Text(position.fraction, format: .percent.precision(.fractionLength(1)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView(
                        "No Books",
                        systemImage: "books.vertical",
                        description: Text("Copy books into the app's Documents folder (see docs/notes/reader-spike.md), then reload.")
                    )
                }
            }
            .navigationTitle("Spike Library")
            .toolbar {
                Button("Reload", systemImage: "arrow.clockwise", action: reload)
            }
            .navigationDestination(for: ReaderBook.self) { book in
                SpikeReaderView(book: book)
            }
        }
        .onAppear {
            reload()
            reopenLastBook()
        }
        .onChange(of: path) {
            lastOpenBook = path.last?.id ?? ""
            if path.isEmpty { reload() }
        }
    }

    private func reload() {
        let documents = URL.documentsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)) ?? []
        books = files
            .filter { ReaderBook.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { ReaderBook(fileURL: $0) }
    }

    private func reopenLastBook() {
        guard !didReopen else { return }
        didReopen = true
        if let book = books.first(where: { $0.id == lastOpenBook }) {
            path = [book]
        }
    }
}

#Preview {
    SpikeLibraryView()
}
