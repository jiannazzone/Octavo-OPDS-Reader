import OctavoKit
import SwiftUI

/// SPIKE ONLY (deleted after the spike). The reader with a debug strip showing
/// the live CFI and fraction, and previous/next buttons.
struct SpikeReaderView: View {
    let book: ReaderBook
    // Made in `.task` rather than `init`, so SwiftUI re-creating this view
    // doesn't spin up throwaway web pages.
    @State private var model: ReaderModel?

    var body: some View {
        Group {
            if let model {
                SpikeReaderContent(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.title ?? book.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: book) {
            if model?.book != book { model = ReaderModel(book: book) }
        }
    }
}

private struct SpikeReaderContent: View {
    let model: ReaderModel

    var body: some View {
        VStack(spacing: 0) {
            debugStrip
            ReaderWebView(model: model)
                .overlay {
                    switch model.phase {
                    case .loading: ProgressView()
                    case .open: EmptyView()
                    case .failed(let message): ContentUnavailableView("Couldn't Open", systemImage: "exclamationmark.triangle", description: Text(message))
                    }
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Previous", systemImage: "chevron.left", action: model.previous)
                Spacer()
                Button("Next", systemImage: "chevron.right", action: model.next)
            }
        }
    }

    private var debugStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CFI: \(model.position?.cfi ?? "—")")
                .lineLimit(3)
                .textSelection(.enabled)
            HStack {
                Text("fraction: \(model.position.map { String(format: "%.5f", $0.fraction) } ?? "—")")
                if let location = model.location {
                    Text("loc \(location.current.map(String.init) ?? "?")/\(location.total.map(String.init) ?? "?")")
                }
                if let restoredFrom = model.restoredFrom {
                    Text("from: \(restoredFrom)")
                }
            }
            if let tocLabel = model.tocLabel {
                Text(tocLabel).lineLimit(1)
            }
            if let error = model.lastError {
                Text("error: \(error)").foregroundStyle(.red).lineLimit(2)
            }
        }
        .font(.caption2.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
