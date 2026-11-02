import SwiftUI

/// The reader's panels (#18), opened from the column's buttons. One at a
/// time; a tap on the page closes it.
enum ReaderPanel: Equatable {
    case textAndTheme
}

/// Where a panel sits (decision 13): over the right page of a spread, the
/// left page showing each change as it's made; on one page, a sheet along
/// the bottom. Glass, so the page shows through.
struct ReaderPanelFrame<Content: View>: View {
    let geometry: ReaderGeometry
    /// The spread's fold, if there are two pages.
    let fold: ClosedRange<Double>?
    @ViewBuilder let content: () -> Content

    static var inset: Double { 12 }

    var body: some View {
        let safe = geometry.safeArea
        let width = Double(geometry.size.width)
        let height = Double(geometry.size.height)
        let bottom = height - safe.bottom - Self.inset
        if let fold {
            let left = fold.upperBound + Self.inset
            let top = safe.top + Self.inset
            content()
                .frame(width: max(0, width - safe.right - Self.inset - left), height: max(0, bottom - top), alignment: .top)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .offset(x: left, y: top)
        } else {
            // The sheet is only as tall as what it shows, up to its most.
            let left = safe.left + Self.inset
            let maxHeight = min(560, (height - safe.top - safe.bottom) * 0.62)
            content()
                .frame(width: max(0, width - safe.right - Self.inset - left))
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .frame(height: max(0, maxHeight), alignment: .bottom)
                .offset(x: left, y: bottom - maxHeight)
        }
    }
}

/// Text and theme (decision 13, frames 10 and 11): the themes and A−/A+ in
/// front, then Customize (font, line spacing, margins, justify, Match Dark
/// Mode, Book-mode shadow, Always show controls). On a spread there's room
/// for both at once; on one page Customize is a step in.
struct ReaderTextPanel: View {
    @Binding var appearance: ReaderAppearance
    /// The iPhone is in Dark Mode.
    let darkMode: Bool
    /// Room for everything at once (a spread).
    let showsAll: Bool
    @State private var customizing = false
    @AppStorage(ReaderMargins.key) private var margins = ReaderMargins.standard
    @AppStorage(ReaderSettings.bookModeShadowKey) private var bookModeShadow = ReaderSettings.bookModeShadowDefault
    @AppStorage(ReaderSettings.alwaysShowControlsKey) private var alwaysShowControls = ReaderSettings.alwaysShowControlsDefault

    var body: some View {
        // Scrolls only when it doesn't fit.
        ViewThatFits(in: .vertical) {
            controls
            ScrollView { controls }
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsAll || !customizing {
                themes
                textSize
            }
            if showsAll {
                Divider()
                customize
            } else if customizing {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { customizing = false }
                } label: {
                    Label("Text and Theme", systemImage: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                }
                customize
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { customizing = true }
                } label: {
                    HStack {
                        Text("Customize")
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
    }

    private var themes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(ReaderTheme.allCases) { theme in
                    ThemeSwatch(theme: theme, selected: appearance.theme == theme) {
                        appearance.theme = theme
                    }
                }
            }
            if appearance.matchDarkMode, darkMode, appearance.theme != .night {
                Text("Night while the iPhone is in Dark Mode. Turn off Match Dark Mode to choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var textSize: some View {
        HStack {
            Button("Smaller Text", systemImage: "textformat.size.smaller") { appearance.stepText(by: -1) }
                .disabled(!appearance.canShrinkText)
            Spacer()
            Text(appearance.textScale.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Button("Larger Text", systemImage: "textformat.size.larger") { appearance.stepText(by: 1) }
                .disabled(!appearance.canGrowText)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .buttonStyle(.glass)
    }

    private var customize: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Font") {
                Picker("Font", selection: $appearance.font) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.name).tag(font)
                    }
                }
                .pickerStyle(.menu)
            }
            LabeledContent("Line Spacing") {
                HStack(spacing: 10) {
                    Text(appearance.lineSpacing.map { $0.formatted(.number.precision(.fractionLength(1...2))) } ?? "Book’s")
                        .monospacedDigit()
                        .fixedSize()
                        .foregroundStyle(.secondary)
                    Button("Less Line Spacing", systemImage: "minus") { appearance.stepLineSpacing(by: -1) }
                    Button("More Line Spacing", systemImage: "plus") { appearance.stepLineSpacing(by: 1) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Margins")
                Picker("Margins", selection: $margins) {
                    Text("Narrow").tag(ReaderMargins.narrow)
                    Text("Medium").tag(ReaderMargins.medium)
                    Text("Wide").tag(ReaderMargins.wide)
                }
                .pickerStyle(.segmented)
            }
            Toggle("Justify", isOn: $appearance.justify)
            Toggle("Match Dark Mode", isOn: $appearance.matchDarkMode)
            Toggle("Book-Mode Shadow", isOn: $bookModeShadow)
            Toggle("Always Show Controls", isOn: $alwaysShowControls)
        }
    }
}

/// A theme as a small page in its colours.
private struct ThemeSwatch: View {
    let theme: ReaderTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Color(hex: theme.text))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(hex: theme.background), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected ? 2.5 : 1)
                    }
                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension Color {
    /// `#rrggbb`.
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
