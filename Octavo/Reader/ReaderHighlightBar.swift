import OctavoKit
import SwiftUI

/// The highlight bar (#125): while text is selected, at the page's foot,
/// BookOrbit's colours and Note. A colour highlights the words; the bar then
/// stays, the colour ringed and trash beside it, until a tap on the page or
/// a turn.
struct ReaderHighlightBar: View {
    let model: ReaderModel
    /// Note was tapped: the highlight whose note to write.
    let writeNote: (LocalHighlight.ID) -> Void

    var body: some View {
        let highlight = model.barHighlight
        HStack(spacing: 6) {
            HighlightColorRow(selected: highlight?.color) { hex in
                Task { await model.pickHighlightColor(hex) }
            }
            if highlight != nil {
                Button("Delete Highlight", systemImage: "trash", role: .destructive, action: model.removeBarHighlight)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 36, height: 36)
                    .transition(.opacity)
            }
            Button("Note", systemImage: "square.and.pencil") {
                Task { if let id = await model.highlightForNote() { writeNote(id) } }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 36, height: 36)
        }
        .font(.title3)
        // As BookOrbit's capsule: on one line, so it fits the page.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .animation(.easeOut(duration: 0.2), value: highlight?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Highlight"))
    }
}

/// BookOrbit's ten colours in a row that scrolls (#125): five and a half show,
/// always from yellow, and the rest are a swipe away. The highlight's own
/// colour is ringed; one that isn't among the ten rings none. The bar's;
/// the card has room for all ten (`HighlightColorGrid`).
struct HighlightColorRow: View {
    /// The highlight's colour as stored, if there's a highlight.
    let selected: String?
    let pick: (String) -> Void

    private static let dot = HighlightColorDot.size
    private static let ringRoom = HighlightColorDot.ringRoom
    private static let spacing = 10.0
    /// Five and a half dots: the half says there's more.
    private static let width = 5 * (dot + 2 * ringRoom + spacing) + (dot + 2 * ringRoom) / 2

    var body: some View {
        let ringed = selected.flatMap(HighlightPalette.color(for:))
        ScrollView(.horizontal) {
            HStack(spacing: Self.spacing) {
                ForEach(HighlightPalette.colors) { color in
                    HighlightColorDot(color: color, isSelected: color == ringed, pick: pick)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(width: Self.width)
    }

    /// What VoiceOver and Voice Control call it.
    nonisolated static func name(of color: HighlightPalette.Color) -> String {
        switch color.name {
        case "yellow": String(localized: "Yellow", comment: "A highlight colour")
        case "green": String(localized: "Green", comment: "A highlight colour")
        case "blue": String(localized: "Blue", comment: "A highlight colour")
        case "pink": String(localized: "Pink", comment: "A highlight colour")
        case "orange": String(localized: "Orange", comment: "A highlight colour")
        case "red": String(localized: "Red", comment: "A highlight colour")
        case "olive": String(localized: "Olive", comment: "A highlight colour")
        case "cyan": String(localized: "Cyan", comment: "A highlight colour")
        case "purple": String(localized: "Purple", comment: "A highlight colour")
        default: String(localized: "Gray", comment: "A highlight colour")
        }
    }
}

/// The ten colors in two rows of five across a highlight's card (#125): all
/// of them at once, where the card has the room the bar doesn't. Rows for
/// the card's own grid, so its buttons share the colors' columns.
enum HighlightColorGrid {
    static let columns = 5

    @ViewBuilder
    static func rows(selected: String?, pick: @escaping (String) -> Void) -> some View {
        let ringed = selected.flatMap(HighlightPalette.color(for:))
        ForEach(Array(stride(from: 0, to: HighlightPalette.colors.count, by: columns)), id: \.self) { start in
            GridRow {
                ForEach(HighlightPalette.colors[start..<min(start + columns, HighlightPalette.colors.count)]) { color in
                    HighlightColorDot(color: color, isSelected: color == ringed, pick: pick)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// One colour to pick, ringed if it's the highlight's own.
struct HighlightColorDot: View {
    let color: HighlightPalette.Color
    let isSelected: Bool
    let pick: (String) -> Void

    static let size = 28.0
    /// Room around a dot for its ring.
    static let ringRoom = 3.0

    var body: some View {
        Button {
            pick(color.hex)
        } label: {
            Circle()
                .fill(Color(hex: color.hex))
                .frame(width: Self.size, height: Self.size)
                .padding(Self.ringRoom)
                .overlay {
                    if isSelected { Circle().strokeBorder(.primary, lineWidth: 2) }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(HighlightColorRow.name(of: color)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
