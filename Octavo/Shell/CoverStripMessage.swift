import SwiftUI

/// A problem or progress with one book, shown on its cover's strip where
/// Open would be (decision 22). Queuing a download for later isn't offered.
nonisolated enum CoverStripMessage: Hashable, Sendable {
    case downloadFailed
    /// Offline, and the book isn't on the iPhone yet.
    case needsConnection
    case downloading(fraction: Double)
}

/// The strip's content for a `CoverStripMessage` (frames 23, 24 and 42).
/// The strip itself, the glass sheet over the cover, is the cover page's
/// (#14). `action` is Try again or Cancel; offline has none.
struct CoverStripStatus: View {
    let message: CoverStripMessage
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.glassProminent)
                }
            }
            if case .downloading(let fraction) = message {
                ProgressView(value: fraction)
            }
        }
    }

    private var headline: String {
        switch message {
        case .downloadFailed: "Couldn’t download"
        case .needsConnection: "Not downloaded"
        case .downloading(let fraction): "Downloading · \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        }
    }

    private var detail: String {
        switch message {
        case .downloadFailed: "Check your connection."
        case .needsConnection: "Needs a connection to download."
        case .downloading: "Opens when it’s done."
        }
    }

    private var actionTitle: String? {
        switch message {
        case .downloadFailed: "Try again"
        case .needsConnection: nil
        case .downloading: "Cancel"
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        CoverStripStatus(message: .downloadFailed) {}
        CoverStripStatus(message: .needsConnection) {}
        CoverStripStatus(message: .downloading(fraction: 0.42)) {}
    }
    .padding()
}
