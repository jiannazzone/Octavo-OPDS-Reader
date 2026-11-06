import SwiftUI

/// `lineLimit`, with no limit at the accessibility text sizes, where one line
/// shows only a title's first letters (`docs/notes/accessibility.md`).
private struct LargerTextLineLimit: ViewModifier {
    let limit: Int
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        content.lineLimit(size.isAccessibilitySize ? nil : limit)
    }
}

extension View {
    func lineLimit(untilLargerText limit: Int) -> some View {
        modifier(LargerTextLineLimit(limit: limit))
    }
}

/// Side by side, or one over the other at the accessibility text sizes, where
/// side by side leaves each too narrow for a word.
struct LargerTextStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat
    var stackedSpacing: CGFloat?
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let layout = size.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: stackedSpacing ?? spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}

/// `LabeledContent` as usual, with its label over its value at the
/// accessibility text sizes.
struct StackedAtLargerText: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var size

    func makeBody(configuration: Configuration) -> some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                configuration.label
                configuration.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent(configuration)
        }
    }
}
