import OctavoKit
import SwiftUI

/// SPIKE ONLY (deleted after the spike). A book's screen, for the
/// cover-display idea in docs/UI-IDEAS.md: browse folded, unfold to read.
/// When the hinge opens from closed while this screen is showing, it calls
/// `read`, which opens the reader at the current position (for a BookOrbit
/// book, the reader pulls the synced position first).
struct SpikeBookDetailView: View {
    let book: ReaderBook
    let fileID: Int?
    let read: () -> Void
    @AppStorage("spike.openOnUnfold") private var openOnUnfold = true
    private let store = ReadingPositionStore()

    var body: some View {
        List {
            Section {
                LabeledContent("File", value: book.fileName)
                LabeledContent("Source", value: fileID.map { "BookOrbit file \($0)" } ?? "This device")
                if let position = store.position(forBook: book.id) {
                    LabeledContent("Saved", value: position.fraction.formatted(.percent.precision(.fractionLength(1))))
                    Text(position.cfi ?? "no CFI")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Read", action: read)
                Toggle("Open When Unfolded", isOn: $openOnUnfold)
            }
        }
        .navigationTitle(book.fileName)
        .onHingeChange { old, new in
            guard openOnUnfold,
                  old.hinge?.status == .closed,
                  let status = new.hinge?.status, status != .closed else { return }
            SpikeEvents.log("handoff", ["book": book.id, "old": SpikeEvents.hinge(old), "new": SpikeEvents.hinge(new)])
            read()
        }
        .spikeProbe("detail")
    }
}
