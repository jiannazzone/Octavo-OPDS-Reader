import OctavoKit
import SwiftUI

/// SPIKE ONLY (deleted after the spike). The reader with a debug strip showing
/// the live CFI, fraction and sync state, previous/next buttons, and a "go to"
/// field that takes a fraction or a CFI.
///
/// Each move also writes `Documents/spike-state.json` (position, both CFI
/// shapes, the visible text, sync state) so a script on the host can read
/// where the reader is.
struct SpikeReaderView: View {
    let book: ReaderBook
    let sync: (any ProgressSync)?
    let cfiShape: ReaderMessage.CFIShape
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
            if model?.book != book { model = ReaderModel(book: book, sync: sync, cfiShape: cfiShape) }
            #if DEBUG
            SpikeRemote.reader = model
            #endif
        }
        .onDisappear {
            guard let model else { return }
            Task { await model.close() }
        }
    }
}

private struct SpikeReaderContent: View {
    let model: ReaderModel
    @State private var isGoingTo = false
    @State private var target = ""

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
        // The keyboard for "Go To" must not resize the page: foliate
        // re-paginates on every resize.
        .ignoresSafeArea(.keyboard)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Previous", systemImage: "chevron.left", action: model.previous)
                Spacer()
                Button("Go To") { isGoingTo = true }
                Spacer()
                Button("Next", systemImage: "chevron.right", action: model.next)
            }
        }
        .alert("Go To", isPresented: $isGoingTo) {
            TextField("0.5 or epubcfi(…)", text: $target)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Go") { goTo(target) }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: StateKey(model)) {
            await SpikeStateFile.write(model)
        }
        .spikeProbe("reader")
    }

    private var hingeLine: String {
        let angle = model.hingeAngle.map { String(format: " %.0f°", $0) } ?? ""
        let size = model.geometry.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "?"
        let columns = model.layout.columns.map(String.init) ?? "auto"
        let gap = model.layout.gapPercent.map { String(format: " gap %.1f%%", $0) } ?? ""
        let fold = model.layout.fold.map { String(format: " fold %.0f–%.0f", $0.lowerBound, $0.upperBound) } ?? ""
        return "hinge: \(model.posture.rawValue)\(angle) \(size) cols \(columns)\(gap)\(fold)"
    }

    private func goTo(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fraction = Double(trimmed) {
            model.goTo(fraction: fraction)
        } else if !trimmed.isEmpty {
            model.goTo(cfi: trimmed)
        }
    }

    /// Rewrites the state file on every relocation (a fold re-lays out the
    /// page without moving the position) and every layout change.
    private struct StateKey: Equatable {
        var phase: ReaderModel.Phase
        var relocations: Int
        var layout: ReaderLayout
        var posture: ReaderPosture
        var size: CGSize?

        init(_ model: ReaderModel) {
            phase = model.phase
            relocations = model.relocationCount
            layout = model.layout
            posture = model.posture
            size = model.geometry?.size
        }
    }

    /// Fixed height, one line per row: if the strip grew or shrank with its
    /// text, the page would resize and foliate would re-paginate (and, on a
    /// blank page, jump; see docs/notes/reader-spike.md).
    private var debugStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CFI: \(model.position?.cfi ?? "—")")
                .truncationMode(.middle)
            HStack {
                Text("fraction: \(model.position.map { String(format: "%.5f", $0.fraction) } ?? "—")")
                if let location = model.location {
                    Text("loc \(location.current.map(String.init) ?? "?")/\(location.total.map(String.init) ?? "?")")
                }
                Text("from: \(model.restoredFrom ?? "—")/\(model.openingPosition?.label ?? "—")")
            }
            Text(model.tocLabel ?? " ")
            Text("sync: \(model.syncStatus ?? "off") [\(model.cfiShape.rawValue)]")
                .truncationMode(.middle)
            Text(hingeLine)
            Text(model.lastError.map { "error: \($0)" } ?? " ")
                .foregroundStyle(.red)
        }
        .lineLimit(1)
        .font(.caption2.monospaced())
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86, alignment: .topLeading)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

/// SPIKE ONLY. Where the reader is, for scripts on the host.
private enum SpikeStateFile {
    struct State: Encodable {
        var bookID: String
        var title: String?
        var cfi: String?
        var rangeCFI: String?
        var startCFI: String?
        var blankPage: Bool?
        var fraction: Double?
        var tocLabel: String?
        var visibleText: String?
        var restoredFrom: String?
        var openedFrom: String?
        var syncStatus: String?
        var lastPushedCFI: String?
        var relocations: Int
        var posture: ReaderPosture
        var hingeAngle: Double?
        var geometry: ReaderGeometry?
        var layout: ReaderLayout
        var layoutReport: SpikeJSON?
        var watched: SpikeJSON?
        var updatedAt: Date
    }

    static let url = URL.documentsDirectory.appending(path: "spike-state.json")

    static func write(_ model: ReaderModel) async {
        guard model.phase == .open else { return }
        // Let the page settle so the text matches the final relocation.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let state = State(
            bookID: model.book.id,
            title: model.title,
            cfi: model.position?.cfi,
            rangeCFI: model.relocation?.cfi,
            startCFI: model.relocation?.startCFI,
            blankPage: model.relocation?.blankPage,
            fraction: model.position?.fraction,
            tocLabel: model.tocLabel,
            visibleText: await model.visibleText(limit: 4000),
            restoredFrom: model.restoredFrom,
            openedFrom: model.openingPosition?.label,
            syncStatus: model.syncStatus,
            lastPushedCFI: model.lastPushedCFI,
            relocations: model.relocationCount,
            posture: model.posture,
            hingeAngle: model.hingeAngle,
            geometry: model.geometry,
            layout: model.layout,
            layoutReport: await model.layoutReport().map(SpikeJSON.init),
            watched: await watched(model),
            updatedAt: .now
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(state).write(to: url, options: .atomic)
    }

    private static func watched(_ model: ReaderModel) async -> SpikeJSON? {
        #if DEBUG
        guard let cfi = SpikeRemote.watchedCFI else { return nil }
        var result = await model.locate(cfi) ?? [:]
        result["cfi"] = cfi
        return SpikeJSON(result)
        #else
        return nil
        #endif
    }
}

/// SPIKE ONLY. Re-encodes a dictionary that came back from JavaScript.
private struct SpikeJSON: Encodable {
    let object: Any

    init(_ object: Any) { self.object = object }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch object {
        case let value as NSNumber where CFGetTypeID(value) == CFBooleanGetTypeID(): try container.encode(value.boolValue)
        case let value as Int: try container.encode(value)
        case let value as Double: try container.encode(value)
        case let value as String: try container.encode(value)
        case let value as [Any]: try container.encode(value.map(SpikeJSON.init))
        case let value as [String: Any]: try container.encode(value.mapValues(SpikeJSON.init))
        default: try container.encodeNil()
        }
    }
}
