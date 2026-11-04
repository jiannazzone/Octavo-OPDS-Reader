import OctavoKit
import SwiftUI

/// Away from your place after a jump (decision 33): the scrubber, Contents, a
/// bookmark, a chapter button or a search result. Your place stays saved as it
/// was, here and on the server, until you settle: Back returns to it, and ✕
/// or reading on makes the page you're on your place. Closing the book keeps
/// the trip, on this iPhone only: it reopens where you were looking.
nonisolated struct ReaderTrip: Codable, Equatable, Sendable {
    /// Page turns forward from where you landed that count as reading on.
    static let turnsToReadOn = 5

    /// Where you were before the first jump.
    var place: ReadingPosition
    /// Its number, as the footer counts.
    var placePage: Int?
    /// Where it falls in the book, as the progress line shows it.
    var placeFraction = 0.0
    /// Where you are now.
    var page: ReadingPosition?
    /// Where that falls in the book, as the progress line shows it.
    var pageFraction = 0.0
    /// Turns forward from where you landed, less turns back.
    var turns = 0

    /// A jump landed. Another one starts the count again and keeps the way back.
    mutating func landed(on page: ReadingPosition?, fraction: Double) {
        self.page = page
        pageFraction = fraction
        turns = 0
    }

    mutating func turned(from old: Double, to new: Double) {
        if new > old { turns += 1 } else if new < old { turns -= 1 }
    }

    var hasReadOn: Bool { turns >= Self.turnsToReadOn }

    /// "Back to page 312".
    var backLabel: String {
        placePage.map { String(localized: "Back to page \($0)", comment: "Goes back to your place after a jump, e.g. Back to page 312") }
            ?? String(localized: "Go Back", comment: "Goes back to your place after a jump, when it has no page number")
    }

    /// "Opens at 90%", on the book's screen.
    var opensAtLabel: String {
        let percent = ReaderPlace(chapter: nil, location: nil, fraction: pageFraction).percent
        return String(localized: "Opens at \(percent)", comment: "Where a book reopens while you're away from your place, e.g. Opens at 90%")
    }
}

/// "Back to page 312" with ✕, under the left page (decision 33). It stays up
/// with the controls hidden, which go on the next tap.
struct ReaderBackBar: View {
    static let height = 38.0

    let trip: ReaderTrip
    let back: () -> Void
    let stay: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: back) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.uturn.backward")
                        .accessibilityHidden(true)
                    Text(trip.backLabel)
                        .lineLimit(1)
                }
                .padding(.leading, 13)
                .padding(.trailing, 5)
                .frame(height: Self.height)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            Button("Stay Here", systemImage: "xmark", action: stay)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: Self.height)
                .contentShape(.rect)
        }
        .font(.subheadline)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
