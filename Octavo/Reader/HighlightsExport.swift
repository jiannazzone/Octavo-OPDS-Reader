import CoreTransferable
import Foundation
import OctavoKit
import UniformTypeIdentifiers

/// Share All Highlights (#125): the book's highlights as Markdown, offered
/// both as text and as a file named "<Title> – Highlights.md", so each app
/// on the share sheet takes the one it can.
struct HighlightsExport: Transferable {
    let title: String
    let authors: [String]
    let highlights: [LocalHighlight]
    let notFound: [LocalHighlight]

    @MainActor
    init(book: LibraryBook, highlights: ReaderHighlights) {
        title = book.title
        authors = book.authors
        self.highlights = highlights.list
        notFound = highlights.notFound
    }

    /// Built when it's shared, not each time the list draws.
    var markdown: String {
        HighlightExport.markdown(
            title: title, authors: authors, highlights: highlights, notFound: notFound,
            notFoundHeading: String(localized: "Not Found in This File", comment: "Heading in the Highlights list and the export")
        )
    }

    var fileName: String {
        HighlightExport.fileName(title: title, suffix: String(localized: "Highlights", comment: "After the title in the export's file name"))
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "md") ?? .plainText) { export in
            SentTransferredFile(try export.writeFile())
        }
        ProxyRepresentation(exporting: \.markdown)
    }

    /// In a folder of its own under the temporary directory, the last one
    /// cleared first, so exports don't pile up.
    private func writeFile() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "HighlightsExport", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try Data(markdown.utf8).write(to: url, options: .atomic)
        return url
    }
}
