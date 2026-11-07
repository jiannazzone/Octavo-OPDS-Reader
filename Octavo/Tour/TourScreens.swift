import OctavoKit
import SwiftUI

/// The tour's screens before the book opens: steps 1 and 2. They cover the
/// tabs as the reader does, and the reader then covers them. Otherwise (the
/// moment before the hinge reports, or before the reader has opened), a plain
/// page.
struct TourScreen: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        switch shell.tour.playing?.step {
        case .closeYourIPhone?:
            TourColumn { TourCloseScreen() }
        case .cover?:
            TourColumn { TourCoverScreen(line: shell.tour.playing?.coverLine ?? "") }
        default:
            Color(.systemBackground)
                .ignoresSafeArea()
        }
    }
}

/// A `NavigationStack` that never pushes, as in `ScreenStack`: the system then
/// puts Skip in the side column.
private struct TourColumn<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(ShellModel.self) private var shell

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        TourSkipButton { shell.tour.finish() }
                    }
                }
                .toolbarTitleDisplayMode(.inline)
        }
    }
}

/// Step 1, Close your iPhone: a Duo closing on the left page, the words on
/// the right. Continue without closing puts the cover on the left page, which
/// then opens as a book's does.
private struct TourCloseScreen: View {
    @Environment(ShellModel.self) private var shell
    @State private var spread = Spread.onePage
    /// Where the left page is, in the window.
    @State private var leftPage = CGRect.zero
    @State private var showsCover = false

    var body: some View {
        Group {
            SpreadPages { _ in
                leftSide
            } right: { _ in
                words
                    .padding(.horizontal, SpreadMetrics.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } folded: {
                VStack(spacing: 32) {
                    TourDuoClosing()
                    words
                }
                .padding(.horizontal, SpreadMetrics.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environment(\.spread, spread)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .vertical)
        .background(Color(.systemBackground))
        .onSpreadChange { spread = $0 }
    }

    private var leftSide: some View {
        ZStack {
            TourDuoClosing()
            if showsCover {
                TourCoverImage()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { leftPage = $0 }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Close your iPhone")
                .font(.title.bold())
            Text("Octavo opens like a book.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Continue without closing") { continueWithoutClosing() }
                .font(.body.weight(.semibold))
                .padding(.top, 8)
                .disabled(showsCover)
        }
    }

    private func continueWithoutClosing() {
        withAnimation(.easeOut(duration: 0.2)) {
            showsCover = true
        } completion: {
            // No left page (turned sideways): the reader just fades in.
            shell.tour.continueWithoutClosing(coverFrame: spread.isTwoPages ? leftPage : nil)
        }
    }
}

/// Step 2: Pride and Prejudice's cover, under the side column and the camera
/// as a book's screen has it, with the line low on it, centred on the cover
/// (not on what the column leaves) and just above the cover's own title.
/// Unfolding opens it, the same gesture as every book afterwards (decision 10).
private struct TourCoverScreen: View {
    let line: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                TourCoverImage()
                Text(line)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16)
                    // The title's band takes the cover's bottom 22%.
                    .padding(.bottom, proxy.size.height * 0.22 + 12)
            }
        }
        .ignoresSafeArea()
    }
}

/// The sample book's cover from the app's bundle, whether or not the book is
/// on the shelf, as a book's screen draws it (`FittedCover`).
private struct TourCoverImage: View {
    @State private var cover = SampleBook.bundledCover.flatMap { UIImage(contentsOfFile: $0.path) }

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let cover {
                    FittedCover(image: cover)
                } else {
                    BookTitleCover(title: SampleBook.book.title, author: "Jane Austen")
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("Cover of \(SampleBook.book.title)")
    }
}

/// A Duo seen from the front, its left half swinging shut over the right and
/// open again. With Reduce Motion it holds part way, already closing.
private struct TourDuoClosing: View {
    /// Seconds for one close and open.
    private static let period = 2.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                duo(angle: 60)
            } else {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    duo(angle: Self.angle(atPhase: time.truncatingRemainder(dividingBy: Self.period) / Self.period))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Flat, closing, closed for a moment, opening.
    private static func angle(atPhase phase: Double) -> Double {
        func eased(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        switch phase {
        case ..<0.15: return 0
        case ..<0.55: return 178 * eased((phase - 0.15) / 0.4)
        case ..<0.8: return 178
        default: return 178 * (1 - eased((phase - 0.8) / 0.2))
        }
    }

    private func duo(angle: Double) -> some View {
        let half = CGSize(width: 96, height: 136)
        return HStack(spacing: 0) {
            panel(corners: .init(topLeading: 14, bottomLeading: 14))
                .frame(width: half.width, height: half.height)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.25)
                // Over the right half as it shuts.
                .zIndex(1)
            panel(corners: .init(bottomTrailing: 14, topTrailing: 14))
                .frame(width: half.width, height: half.height)
        }
    }

    private func panel(corners: RectangleCornerRadii) -> some View {
        UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay {
                UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
                    .strokeBorder(Color.secondary, lineWidth: 2)
            }
    }
}
