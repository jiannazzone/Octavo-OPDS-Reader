import OctavoKit
import SwiftUI

/// SPIKE ONLY (deleted after the spike). Lists the books in the app's
/// Documents folder and reopens the last open one on launch, plus a way into
/// a BookOrbit server's "Spike" collection. A book opens on a detail screen
/// first, which jumps into the reader when the device unfolds.
/// See docs/notes/reader-spike.md for getting books onto the simulator.
struct SpikeLibraryView: View {
    @State private var books: [ReaderBook] = []
    @State private var path: [SpikeRoute] = []
    @State private var didReopen = false
    @State private var bookOrbit = SpikeBookOrbitSession()
    @AppStorage("spike.lastOpenBook") private var lastOpenBook = ""
    @AppStorage(SpikeSettings.cfiShapeKey) private var cfiShape = ReaderMessage.CFIShape.point
    private let store = ReadingPositionStore()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink("BookOrbit", value: SpikeRoute.bookOrbit)
                }
                Section("On This Device") {
                    ForEach(books) { book in
                        NavigationLink(value: SpikeRoute.detail(book, fileID: nil)) {
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
                    if books.isEmpty {
                        Text("Copy books into the app's Documents folder (see docs/notes/reader-spike.md), then reload.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Spike Library")
            .spikeProbe("library")
            .toolbar {
                Button("Reload", systemImage: "arrow.clockwise", action: reload)
            }
            .navigationDestination(for: SpikeRoute.self) { route in
                switch route {
                case .local(let book):
                    SpikeReaderView(book: book, sync: nil, cfiShape: cfiShape)
                case .bookOrbit:
                    SpikeBookOrbitView(session: bookOrbit) { book, fileID in
                        path.append(.detail(book, fileID: fileID))
                    }
                case .detail(let book, let fileID):
                    SpikeBookDetailView(book: book, fileID: fileID) {
                        path.append(fileID.map { .bookOrbitBook(book, fileID: $0) } ?? .local(book))
                    }
                case .bookOrbitBook(let book, let fileID):
                    SpikeReaderView(book: book, sync: bookOrbit.sync(fileID: fileID), cfiShape: cfiShape)
                }
            }
        }
        .onAppear {
            reload()
            reopenLastBook()
        }
        #if DEBUG
        .task { await SpikeRemote.poll(handle) }
        #endif
        .onChange(of: path) {
            if case .local(let book) = path.last { lastOpenBook = book.id } else { lastOpenBook = "" }
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

    #if DEBUG
    private func handle(_ command: SpikeRemote.Command) async -> String? {
        switch command.cmd {
        case "signin":
            await bookOrbit.signIn()
            path = [.bookOrbit]
            return bookOrbit.errorMessage
        case "open":
            guard let book = bookOrbit.books.first(where: { $0.primaryFile?.id == command.fileID }),
                  let fileID = command.fileID else { return "no such file in the collection" }
            guard let readerBook = await bookOrbit.readerBook(for: book) else { return bookOrbit.errorMessage ?? "download failed" }
            path = [.bookOrbit, .bookOrbitBook(readerBook, fileID: fileID)]
            return nil
        case "close":
            path = [.bookOrbit]
            return nil
        case "openLocal", "detail":
            if let fileID = command.fileID {
                guard let book = bookOrbit.books.first(where: { $0.primaryFile?.id == fileID }),
                      let readerBook = await bookOrbit.readerBook(for: book) else { return "no such file in the collection" }
                path = command.cmd == "detail"
                    ? [.bookOrbit, .detail(readerBook, fileID: fileID)]
                    : [.bookOrbit, .bookOrbitBook(readerBook, fileID: fileID)]
                return nil
            }
            reload()
            guard let book = books.first(where: { $0.fileName == command.name }) else { return "no local book named \(command.name ?? "nil")" }
            path = command.cmd == "detail" ? [.detail(book, fileID: nil)] : [.local(book)]
            return nil
        case "home":
            path = []
            return nil
        case "shape":
            guard let shape = command.shape.flatMap(ReaderMessage.CFIShape.init(rawValue:)) else { return "shape is point or range" }
            cfiShape = shape
            return nil
        default:
            return SpikeRemote.handleReaderCommand(command)
        }
    }
    #endif

    private func reopenLastBook() {
        guard !didReopen else { return }
        didReopen = true
        if let book = books.first(where: { $0.id == lastOpenBook }) {
            path = [.local(book)]
        }
    }
}

enum SpikeRoute: Hashable {
    case local(ReaderBook)
    case detail(ReaderBook, fileID: Int?)
    case bookOrbit
    case bookOrbitBook(ReaderBook, fileID: Int)
}

#Preview {
    SpikeLibraryView()
}
