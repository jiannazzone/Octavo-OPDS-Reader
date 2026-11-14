import OctavoKit
import SwiftUI

/// Rate (☆) on a BookOrbit book (Adam, 2026-11-13, #120): your rating, 1 to
/// 5 whole stars, from one menu, and "★ 4" once rated. It sits beside "…":
/// folded beside Mark finished, unfolded beside the title.
struct BookRateButton: View {
    let page: BookPage
    let source: any LibrarySource
    /// As tall as the row's other buttons, in a row that fixes its height.
    var fillsHeight = false

    var body: some View {
        Menu {
            Picker("Rating", selection: rating) {
                ForEach(Self.choices, id: \.self) { stars in
                    Text(Self.stars(stars))
                        .accessibilityLabel(Self.spoken(stars))
                        .tag(Optional(stars))
                }
            }
            .pickerStyle(.inline)
            if page.rating != nil {
                Button("Clear rating") { set(nil) }
            }
        } label: {
            label
                .bookRoundLabel(fillsHeight: fillsHeight)
        }
        .bookRoundButton(page.rating == nil ? .circle : .capsule)
        .accessibilityLabel("Rating")
        .accessibilityValue(page.rating.map(Self.spoken) ?? "None")
    }

    @ViewBuilder private var label: some View {
        if let rating = page.rating {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.tint)
                Text(rating, format: .number)
            }
        } else {
            Image(systemName: "star")
        }
    }

    private var rating: Binding<Int?> {
        Binding {
            page.rating
        } set: { stars in
            guard let stars, stars != page.rating else { return }
            set(stars)
        }
    }

    private func set(_ stars: Int?) {
        Task { await page.setRating(stars, from: source) }
    }

    /// Five stars first, as BookOrbit lists them.
    static let choices = [5, 4, 3, 2, 1]

    /// "★★★★" for 4.
    static func stars(_ count: Int) -> String {
        String(repeating: "★", count: count)
    }

    /// "4 stars", "1 star".
    static func spoken(_ count: Int) -> String {
        count == 1 ? "1 star" : "\(count) stars"
    }
}

/// "Rate it" (Adam, 2026-11-13, #120): after you mark a book Finished,
/// Skimmed or Abandoned here and it isn't rated. A star rates it and the
/// row goes, leaving "★ 4" on the star button; ✕ or leaving the screen
/// puts it away (`BookPage.asksRating`).
struct BookRatingPrompt: View {
    let page: BookPage
    let source: any LibrarySource

    var body: some View {
        // Stars and ✕ keep 44 pt each; "Rate it" goes above them where
        // the row is too narrow (unfolded, or at larger text sizes).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                title
                    .frame(maxWidth: .infinity, alignment: .leading)
                buttons
            }
            .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 0) {
                title
                    .padding(.top, 10)
                    .padding(.horizontal, 14)
                buttons
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var title: some View {
        Text("Rate it")
            .font(.subheadline)
            .fixedSize()
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { stars in
                Button {
                    Task { await page.setRating(stars, from: source) }
                } label: {
                    Image(systemName: "star")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rate \(BookRateButton.spoken(stars))")
            }
            Button {
                page.dismissRatingPrompt()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
    }
}
