import OctavoKit
import SwiftUI

/// SPIKE ONLY (deleted after the spike). Signs in to a BookOrbit server,
/// lists its "Spike" collection, and downloads a book to open it with
/// progress sync. Tokens live in memory, so every launch signs in again.
@Observable
final class SpikeBookOrbitSession {
    #if DEBUG
    // The local dev server from dev/bookorbit/README.md.
    var serverURL = "http://localhost:3300"
    var username = "octavo"
    var password = "OctavoDev1"
    #else
    var serverURL = ""
    var username = ""
    var password = ""
    #endif

    private(set) var client: BookOrbitClient?
    private(set) var user: BookOrbitUser?
    private(set) var books: [BookOrbitBook] = []
    private(set) var isWorking = false
    var errorMessage: String?

    static let collectionName = "Spike"

    func signIn() async {
        guard let url = URL(string: serverURL) else {
            errorMessage = "Not a URL"
            return
        }
        await run {
            let client = BookOrbitClient(baseURL: url, deviceLabel: "Octavo spike")
            user = try await client.login(username: username, password: password)
            self.client = client
            try await loadBooks()
        }
    }

    func reload() async {
        await run { try await loadBooks() }
    }

    private func loadBooks() async throws {
        guard let client else { return }
        guard let collection = try await client.collections().first(where: { $0.name == Self.collectionName }) else {
            errorMessage = "No “\(Self.collectionName)” collection"
            return
        }
        books = try await client.collectionBooks(collectionID: collection.id).items
    }

    /// The book's primary file, downloaded once and kept in Caches.
    func readerBook(for book: BookOrbitBook) async -> ReaderBook? {
        guard let client, let file = book.primaryFile else { return nil }
        // `format` comes from the server; only known extensions reach the path.
        let format = file.format?.lowercased() ?? "epub"
        guard ReaderBook.supportedExtensions.contains(format) else {
            errorMessage = "Unsupported format \(format)"
            return nil
        }
        let destination = URL.cachesDirectory.appending(path: "BookOrbit/\(file.id).\(format)")
        var result: ReaderBook?
        await run {
            if !FileManager.default.fileExists(atPath: destination.path) {
                try await client.download(fileID: file.id, to: destination)
            }
            result = ReaderBook(fileURL: destination, id: Self.bookID(fileID: file.id))
        }
        return result
    }

    func sync(fileID: Int) -> BookOrbitProgressSync? {
        client.map { BookOrbitProgressSync(client: $0, fileID: fileID) }
    }

    /// Local position key for a BookOrbit file.
    static func bookID(fileID: Int) -> String { "bookorbit-file-\(fileID)" }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct SpikeBookOrbitView: View {
    let session: SpikeBookOrbitSession
    let open: (ReaderBook, Int) -> Void
    @AppStorage(SpikeSettings.cfiShapeKey) private var cfiShape = ReaderMessage.CFIShape.point

    var body: some View {
        @Bindable var session = session
        Form {
            if session.user == nil {
                Section("Server") {
                    TextField("URL", text: $session.serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                    TextField("Username", text: $session.username)
                        .textContentType(.username)
                    SecureField("Password", text: $session.password)
                    Button("Sign In") { Task { await session.signIn() } }
                        .disabled(session.isWorking)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            } else {
                Section("Signed in as \(session.user?.username ?? "?")") {
                    Picker("Push CFI as", selection: $cfiShape) {
                        ForEach(ReaderMessage.CFIShape.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
                Section(SpikeBookOrbitSession.collectionName) {
                    ForEach(session.books) { book in
                        Button {
                            Task {
                                guard let file = book.primaryFile,
                                      let readerBook = await session.readerBook(for: book) else { return }
                                open(readerBook, file.id)
                            }
                        } label: {
                            LabeledContent(book.title) {
                                if let fraction = book.readingFraction {
                                    Text(fraction, format: .percent.precision(.fractionLength(1)))
                                }
                            }
                        }
                        .disabled(session.isWorking)
                    }
                }
            }
            if let message = session.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .overlay { if session.isWorking { ProgressView() } }
        .navigationTitle("BookOrbit")
        .refreshable { await session.reload() }
    }
}

enum SpikeSettings {
    static let cfiShapeKey = "spike.cfiShape"
}
