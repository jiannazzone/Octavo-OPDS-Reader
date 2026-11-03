import OctavoKit
import SwiftUI

/// The tour's screens before the book opens: steps 1 and 2. They cover the
/// tabs as the reader does, and the reader then covers them. Otherwise (the
/// moment before the hinge reports, or before the reader has opened), a plain
/// page.
struct TourScreen: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        switch shell.tour?.step {
        case .closeYourIPhone?:
            TourColumn { TourCloseScreen() }
        case .cover?:
            TourColumn { TourCoverScreen(line: shell.tour?.coverLine ?? "") }
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
                        TourSkipButton { shell.skipTour() }
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
            if let pages = spread.pages {
                HStack(spacing: 0) {
                    leftSide
                        .frame(width: pages.leftWidth)
                    Color.clear
                        .frame(width: pages.hingeWidth)
                    words
                        .padding(.horizontal, SpreadMetrics.margin)
                        .frame(width: pages.rightWidth, alignment: .leading)
                }
            } else {
                VStack(spacing: 32) {
                    TourDuoClosing()
                    words
                }
                .padding(.horizontal, SpreadMetrics.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .vertical)
        .background(Color(.systemBackground))
        .onGeometryChange(for: Spread.self) { Spread($0) } action: { spread = $0 }
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
            shell.tourContinueWithoutClosing(coverFrame: spread.isTwoPages ? leftPage : nil)
        }
    }
}

/// Step 2: Pride and Prejudice's cover, under the side column and the camera
/// as a book's screen has it, with the line low on it, just above the cover's
/// own title. Unfolding opens it, the same gesture as every book afterwards
/// (decision 10).
private struct TourCoverScreen: View {
    let line: String

    var body: some View {
        GeometryReader { proxy in
            let full = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                TourCoverImage()
                    .ignoresSafeArea()
                Text(line)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16)
                    // The title's band takes the cover's bottom 22%.
                    .padding(.bottom, max(16, full * 0.22 + 12 - proxy.safeAreaInsets.bottom))
            }
        }
    }
}

/// The sample book's cover from the app's bundle, whether or not the book is
/// on the shelf, filling its space and cropped to it.
private struct TourCoverImage: View {
    @State private var cover = SampleBook.bundledCover.flatMap { UIImage(contentsOfFile: $0.path) }

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                } else {
                    BookTitleCover(title: SampleBook.book.title, author: "Jane Austen")
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("Cover of \(SampleBook.book.title)")
    }
}

/// A Duo seen from the front, its right half swinging shut over the left and
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
            panel(corners: .init(bottomTrailing: 14, topTrailing: 14))
                .frame(width: half.width, height: half.height)
                .rotation3DEffect(.degrees(-angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.25)
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
