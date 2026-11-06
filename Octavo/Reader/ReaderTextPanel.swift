import SwiftUI

/// The reader's panels (#18), opened from the column's buttons. One at a
/// time; a tap on the page closes it.
enum ReaderPanel: Equatable {
    case textAndTheme
    case contents
    case search

    /// Opening and closing: a little spring as it grows out of its button.
    /// With Reduce Motion, no bounce.
    static var animation: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15)
    }
}

/// Where a panel sits (decision 13): over the right page of a spread, the
/// left page showing each change as it's made; on one page, a sheet along
/// the bottom. Glass, so the page shows through.
///
/// On a spread it grows out of its button in the column and shrinks back
/// into it; the sheet slides up from the bottom (Adam, 2026-11-02). With
/// Reduce Motion, both fade.
struct ReaderPanelFrame<Content: View>: View {
    let geometry: ReaderGeometry
    /// The spread's fold, if there are two pages.
    let fold: ClosedRange<Double>?
    /// The panel's button, in the window's coordinates (the page's, edge to
    /// edge).
    let source: CGRect?
    /// The sheet keeps its full height (a list that scrolls) rather than
    /// fitting what it shows.
    var fillsSheet = false
    /// How far the keyboard comes up from the bottom; the panel stays above
    /// it.
    var keyboard: Double = 0
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var inset: Double { ReaderLayout.edgeInset }
    /// What shows is cut to it: a list that reaches the safe area, as a panel
    /// level with the progress bar does, draws on past the panel's edge.
    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 26) }

    var body: some View {
        let safe = geometry.safeArea
        let width = Double(geometry.size.width)
        let height = Double(geometry.size.height)
        // Level with the progress bar, or clear of the keyboard while it's up.
        let bottom = min(ReaderLayout.barBottom(in: geometry), height - keyboard - Self.inset)
        // Placed by padding in a layer the size of the page, which is what
        // the transition scales or moves: it attaches to the outermost view,
        // so an offset panel would scale about a point measured from the
        // screen's corner.
        Group {
            if let fold {
                let left = fold.upperBound + Self.inset
                let top = safe.top + Self.inset
                content()
                    .frame(width: max(0, width - safe.right - Self.inset - left), height: max(0, bottom - top), alignment: .top)
                    .clipShape(Self.shape)
                    .glassEffect(.regular, in: Self.shape)
                    .padding(.leading, left)
                    .padding(.top, top)
            } else {
                // The sheet is only as tall as what it shows, up to its most,
                // unless it holds a list.
                let left = safe.left + Self.inset
                let usable = height - safe.top - safe.bottom
                let room = bottom - safe.top - Self.inset
                let maxHeight = min(fillsSheet ? min(640, usable * 0.68) : min(560, usable * 0.62), room)
                content()
                    .frame(width: max(0, width - safe.right - Self.inset - left), height: fillsSheet ? max(0, maxHeight) : nil)
                    .clipShape(Self.shape)
                    .glassEffect(.regular, in: Self.shape)
                    .frame(height: max(0, maxHeight), alignment: .bottom)
                    .padding(.leading, left)
                    .padding(.top, bottom - maxHeight)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .transition(transition)
    }

    /// On a spread, out of the button's centre (or the column's top if it
    /// wasn't found); on one page, up from the bottom.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        guard fold != nil else { return .move(edge: .bottom).combined(with: .opacity) }
        let size = geometry.size
        var anchor = UnitPoint.topTrailing
        if let source, size.width > 0, size.height > 0 {
            anchor = UnitPoint(x: source.midX / size.width, y: source.midY / size.height)
        }
        return .scale(scale: 0.05, anchor: anchor).combined(with: .opacity)
    }
}

/// The way out of a panel, at its top right in every posture (Adam,
/// 2026-11-04): folded, there's little page left to tap.
struct ReaderPanelCloseButton: View {
    let close: () -> Void

    var body: some View {
        // The same frame as A− and A+, for a target worth aiming at.
        Button(role: .close, action: close) {
            Label("Close", systemImage: "xmark")
                .frame(width: 24, height: 24)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

/// Text and theme (decision 13, frames 10 and 11): the themes and A−/A+ in
/// front, then Customize (font, line spacing, margins, page turn, justify,
/// Match Dark Mode, Book-mode shadow, Always show controls). On a spread
/// there's room for both at once; on one page Customize is a step in.
struct ReaderTextPanel: View {
    @Binding var appearance: ReaderAppearance
    /// The iPhone is in Dark Mode.
    let darkMode: Bool
    /// Room for everything at once (a spread).
    let showsAll: Bool
    let close: () -> Void
    @State private var customizing = false
    @AppStorage(ReaderMargins.key) private var margins = ReaderMargins.standard
    @AppStorage(ReaderPageTurn.key) private var pageTurn = ReaderPageTurn.standard
    @AppStorage(ReaderSettings.bookModeShadowKey) private var bookModeShadow = ReaderSettings.bookModeShadowDefault
    @AppStorage(ReaderSettings.alwaysShowControlsKey) private var alwaysShowControls = ReaderSettings.alwaysShowControlsDefault

    var body: some View {
        VStack(spacing: 0) {
            header
            // Scrolls only when it doesn't fit, under the header, so the way
            // out stays in place.
            ViewThatFits(in: .vertical) {
                controls
                ScrollView { controls }
                    .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var header: some View {
        HStack {
            Group {
                if !showsAll, customizing {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { customizing = false }
                    } label: {
                        Label("Text and Theme", systemImage: "chevron.backward")
                    }
                } else {
                    Text("Text and Theme")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.leading, 4)
            Spacer()
            ReaderPanelCloseButton(close: close)
        }
        .padding([.horizontal, .top], 14)
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
        .padding([.horizontal, .bottom], 18)
        .padding(.top, 12)
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
                    .foregroundStyle(.secondaryOnGlass)
            }
        }
    }

    private var textSize: some View {
        HStack {
            Button { appearance.stepText(by: -1) } label: {
                textSizeLabel("Smaller Text", systemImage: "textformat.size.smaller")
            }
            .disabled(!appearance.canShrinkText)
            Spacer()
            Text(appearance.textScale.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .foregroundStyle(.secondaryOnGlass)
            Spacer()
            Button { appearance.stepText(by: 1) } label: {
                textSizeLabel("Larger Text", systemImage: "textformat.size.larger")
            }
            .disabled(!appearance.canGrowText)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .buttonStyle(.glass)
    }

    /// A glass button hugs its label, so the same frame keeps the two the
    /// same size, whatever their symbols' shapes.
    private func textSizeLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(width: 24, height: 24)
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
                .fixedSize()
            }
            LabeledContent("Line Spacing") {
                Picker("Line Spacing", selection: $appearance.lineSpacing) {
                    Text("Book’s").tag(Double?.none)
                    ForEach(ReaderAppearance.lineSpacings, id: \.self) { spacing in
                        Text(spacing.formatted(.number.precision(.fractionLength(1...2)))).tag(Double?.some(spacing))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
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
            LabeledContent("Page Turn") {
                Picker("Page Turn", selection: $pageTurn) {
                    ForEach(ReaderPageTurn.allCases) { style in
                        Text(style.name).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
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
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondaryOnGlass))
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
