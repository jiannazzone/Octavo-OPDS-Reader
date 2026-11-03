import SwiftUI

/// The tour's card and rings (decision 29): SwiftUI over the reader, never in
/// the book's page. Liquid Glass, at the bottom of the left page (or of the
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
            return Double(geometry.size.height) - geometry.safeArea.bottom - ReaderPanelFrame<EmptyView>.inset - sheetHeight - 8
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
                    Text(card.message)
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
        case .welcome:
            Button("Start") { shell.tourEvent(.start) }
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

/// The ring on what to tap, over the reader and its column, in the window's
/// coordinates. A column button's frame comes from UIKit, looked up again
/// while the ring shows: the buttons move in as the column comes up.
struct TourRingLayer: View {
    let target: TourRingTarget
    let geometry: ReaderGeometry?
    let layout: ReaderLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var buttonFrame: CGRect?

    var body: some View {
        GeometryReader { proxy in
            if let rect {
                let origin = proxy.frame(in: .global).origin
                TourRing(diameter: rect.size.width)
                    // Starts over if the setting changes under it.
                    .id(reduceMotion)
                    .position(x: rect.midX - origin.x, y: rect.midY - origin.y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: target) {
            guard case .columnButton(let title) = target else { return }
            while !Task.isCancelled {
                let frame = ReaderColumnButton.frame(titled: title)
                if frame != buttonFrame { buttonFrame = frame }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// A square around what to tap.
    private var rect: CGRect? {
        switch target {
        case .rightPage:
            guard let geometry else { return nil }
            let width = Double(geometry.size.width)
            let columns = layout.textColumns(inReaderWidth: width)
            let column = columns?.last ?? (width / 2)...width
            let across = (columns?.count ?? 1) > 1 ? 0.65 : 0.8
            let x = column.lowerBound + across * (column.upperBound - column.lowerBound)
            return CGRect(x: x - 25, y: Double(geometry.size.height) * 0.465 - 25, width: 50, height: 50)
        case .columnButton:
            guard let buttonFrame else { return nil }
            let side = max(buttonFrame.width, buttonFrame.height) + 10
            return CGRect(x: buttonFrame.midX - side / 2, y: buttonFrame.midY - side / 2, width: side, height: side)
        }
    }
}

/// Pulses outward from what to tap; with Reduce Motion it holds still.
private struct TourRing: View {
    let diameter: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(reduceMotion ? 1 : pulsing ? 1.4 : 0.85)
            .opacity(reduceMotion ? 1 : pulsing ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
            }
    }
}
