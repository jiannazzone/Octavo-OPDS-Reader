import SwiftUI

/// The tour's card (decision 29): SwiftUI over the reader, never in the book's
/// page. Liquid Glass, at the bottom of the left page (or of the
/// one page), in the same place for every step, clear of where the progress
/// bar comes up.
struct TourCardSlot: View {
    let step: TourFlow.Step
    let geometry: ReaderGeometry
    let layout: ReaderLayout
    /// The sheet along the bottom of one page, if a panel is open: the card
    /// sits above it.
    var sheetHeight: Double?
    /// The progress bar's height, and a gap above it.
    @ScaledMetric(relativeTo: .footnote) private var barClearance = 96.0

    var body: some View {
        let column = Self.column(in: geometry, layout: layout)
        TourCard(step: step)
            .frame(width: min(column.upperBound - column.lowerBound, 380))
            .frame(height: max(0, bottom), alignment: .bottom)
            .offset(x: column.lowerBound)
            .transition(.opacity)
    }

    private var bottom: Double {
        if let sheetHeight {
            return ReaderLayout.barBottom(in: geometry) - sheetHeight - 8
        }
        return ReaderLayout.barBottom(in: geometry) - barClearance
    }

    /// The left page's text, or the one page's.
    static func column(in geometry: ReaderGeometry, layout: ReaderLayout) -> ClosedRange<Double> {
        if let first = layout.textColumns(inReaderWidth: Double(geometry.size.width))?.first { return first }
        let left = geometry.safeArea.left + 16
        return left...max(left, Double(geometry.size.width) - geometry.safeArea.right - 16)
    }
}

/// One step's words, its dots and its buttons, if it has any: a step that
/// asks for something moves on when it's done.
private struct TourCard: View {
    let step: TourFlow.Step
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let card = step.card {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.headline)
                    Text(TourCardWords.emphasized(card.message))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 16) {
                TourDots(current: step.dot, count: TourFlow.Step.dotCount)
                Spacer(minLength: 0)
                buttons
                    .font(.subheadline.weight(.semibold))
            }
            .frame(minHeight: 20)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        // Nothing on the card turns the page beneath it.
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {}
    }

    @ViewBuilder private var buttons: some View {
        switch step {
        case .makeItYours:
            Button("Done") { shell.tourEvent(.done) }
        case .addYourBooks:
            Button("Not now") { shell.skipTour() }
                .tint(.secondary)
            Button("Add books") { shell.tourAddBooks() }
        default:
            EmptyView()
        }
    }
}

/// Skip, in the side column on every tour screen (decision 30). The word as
/// a picture: the column takes only buttons with an image, and puts any other
/// beside itself, over the page.
struct TourSkipButton: View {
    let action: () -> Void

    private static let word: UIImage = {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .medium)]
        let text = "Skip" as NSString
        let size = text.size(withAttributes: attributes)
        return UIGraphicsImageRenderer(size: size).image { _ in
            text.draw(at: .zero, withAttributes: attributes)
        }
        .withRenderingMode(.alwaysTemplate)
    }()

    var body: some View {
        Button(action: action) {
            Image(uiImage: Self.word)
        }
        .accessibilityLabel("Skip")
    }
}

/// A card's sentence, with the button it names picked out, as the column has
/// it: blue (Adam, 2026-11-03).
nonisolated enum TourCardWords {
    static let buttons = ["···", "Aa"]

    static func emphasized(_ message: String) -> AttributedString {
        var words = AttributedString(message)
        for button in buttons {
            guard let range = words.range(of: button) else { continue }
            words[range].foregroundColor = .accentColor
            words[range].font = .subheadline.weight(.semibold)
        }
        return words
    }
}

/// How far along the tour is.
struct TourDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    // UIKit's: on glass, SwiftUI's primary comes out pale.
                    .fill(Color(uiColor: index == current ? .label : .tertiaryLabel))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
