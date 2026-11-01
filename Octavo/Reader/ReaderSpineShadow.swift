import SwiftUI

/// The shadow in the spine of a book held half open (decision 9), drawn over
/// the gap between the two pages. It sits outside the book's content, so it
/// never touches the text or the book's own styles. Ignores touches.
struct ReaderSpineShadow: View {
    /// The gap between the pages, in the page's coordinates.
    let gap: ClosedRange<Double>
    let height: Double

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.05), location: 0.25),
                .init(color: .black.opacity(0.2), location: 0.5),
                .init(color: .black.opacity(0.05), location: 0.75),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: gap.upperBound - gap.lowerBound, height: height)
        .offset(x: gap.lowerBound)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
