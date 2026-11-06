import OctavoKit
import SwiftUI

/// The server's place for the open book, when another reader moved it on
/// while this one was open (Adam, 2026-11-02). Coming back to the app checks
/// (`ReaderModel.checkServerPlace`); a place on this page isn't offered.
nonisolated struct ReaderServerPlace: Equatable, Sendable {
    /// As the server has it.
    var position: ReadingPosition
    /// Where it falls in the book: the server's percentage, which another
    /// foliate reader computes as the footer does, else as the bridge
    /// places it.
    var fraction: Double
    var chapter: String?
    /// The visible page's start when it was offered. Leaving that page is
    /// reading on, which keeps this iPhone's place.
    var offeredOn: String

    /// "BookOrbit: 62%", with the name the server goes by.
    func label(server: String) -> String {
        let percent = ReaderPlace(chapter: nil, location: nil, fraction: fraction).percent
        return String(localized: "\(server): \(percent)", comment: "The server's reading place for the open book, e.g. BookOrbit: 62%")
    }
}

/// The capsule offering the server's place: "BookOrbit: 62% · Chapter 54",
/// Go and ✕ (Adam, 2026-11-02). It takes the footer's place, like search's
/// step bar; turning the page leaves it, as ✕ does.
struct ReaderServerPlaceBar: View {
    let place: ReaderServerPlace
    /// The name the book's server goes by.
    let server: String
    let go: () -> Void
    let stay: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
            Button("Go", action: go)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.onAccent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel(Text("Go to \(place.label(server: server))", comment: "VoiceOver: go to the server's place, e.g. Go to BookOrbit: 62%"))
            Button("Stay Here", systemImage: "xmark", action: stay)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    private var text: AttributedString {
        var text = AttributedString(place.label(server: server))
        if let chapter = place.chapter {
            var rest = AttributedString(" · \(chapter)")
            if contrast != .increased { rest.foregroundColor = .secondary }
            text += rest
        }
        return text
    }
}
