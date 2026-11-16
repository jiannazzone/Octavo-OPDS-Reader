import OctavoKit
import SwiftUI

/// Contents, bookmarks and highlights (decision 17, #125): one panel, a
/// Contents | Bookmarks | Highlights switch. Contents opens on the chapter
/// the page is in; bookmarks and highlights list in the book's order, and
/// swipe to delete. Choosing any of them goes there.
struct ReaderContentsPanel: View {
    enum Tab: Hashable {
        case contents, bookmarks, highlights
    }

    /// The Highlights tab's list (#125). Fixed-layout books have none.
    struct Highlights {
        var list: [LocalHighlight]
        /// BookOrbit's, which this file doesn't have.
        var notFound: [LocalHighlight]
        /// Share All Highlights.
        var export: HighlightsExport?
        var goTo: (LocalHighlight) -> Void
        var remove: (LocalHighlight.ID) -> Void
        /// VoiceOver's actions on a row, beside the swipe's Delete.
        var editNote: (LocalHighlight.ID) -> Void
        var share: (LocalHighlight) -> Void
    }

    let rows: [ReaderContentsRow]
    let current: Int?
    let bookmarks: [LocalBookmark]
    /// The page number at a point of the book.
    let page: (Double) -> Int?
    let goToRow: (ReaderContentsRow) -> Void
    let goToBookmark: (LocalBookmark) -> Void
    let remove: (LocalBookmark.ID) -> Void
    var highlights: Highlights?
    let close: () -> Void
    @State private var tab = Tab.contents

    /// The panel's own margins: a list in it gets none from the page.
    private static let rowInsets = EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Picker("Show", selection: $tab) {
                    Text("Contents").tag(Tab.contents)
                    Text("Bookmarks").tag(Tab.bookmarks)
                    if highlights != nil { Text("Highlights").tag(Tab.highlights) }
                }
                .pickerStyle(.segmented)
                ReaderPanelCloseButton(close: close)
            }
            .padding([.horizontal, .top], 14)
            switch tab {
            case .contents: contents
            case .bookmarks: bookmarkList
            case .highlights: highlightList
            }
        }
    }

    @ViewBuilder private var contents: some View {
        if rows.isEmpty {
            ContentUnavailableView("No Contents", systemImage: "list.bullet", description: Text("This book doesn’t list its chapters."))
        } else {
            ScrollViewReader { proxy in
                List(rows) { row in
                    let isCurrent = row.id == current
                    Button {
                        goToRow(row)
                    } label: {
                        LargerTextStack(alignment: .firstTextBaseline, spacing: 12, stackedSpacing: 0) {
                            Text(row.label)
                                .lineLimit(untilLargerText: 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let page = row.page {
                                Text(page, format: .number)
                                    .monospacedDigit()
                                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondaryOnGlass))
                                    // "I, Page 3", not "I, 3".
                                    .accessibilityLabel(Text("Page \(page)"))
                            }
                        }
                        .padding(.leading, CGFloat(min(row.depth, 4)) * 16)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .listRowBackground(Rectangle().fill(isCurrent ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear)))
                    .listRowInsets(Self.rowInsets)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    // Voice Control: the chapter, without its page.
                    .accessibilityInputLabels([row.label])
                    .id(row.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder private var bookmarkList: some View {
        if bookmarks.isEmpty {
            ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("The bookmark button marks the page you’re on."))
        } else {
            List {
                ForEach(bookmarks) { bookmark in
                    Button {
                        goToBookmark(bookmark)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(heading(for: bookmark))
                                .font(.subheadline.weight(.medium))
                            if let excerpt = bookmark.excerpt {
                                Text("“\(excerpt)”")
                                    .font(.footnote)
                                    .foregroundStyle(.secondaryOnGlass)
                                    .lineLimit(untilLargerText: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(Self.rowInsets)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(bookmark.id) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var highlightList: some View {
        if let highlights {
            if highlights.list.isEmpty && highlights.notFound.isEmpty {
                ContentUnavailableView("No Highlights", systemImage: "highlighter", description: Text("Select text to highlight it."))
            } else {
                List {
                    if let export = highlights.export {
                        ShareLink(item: export, preview: SharePreview(export.fileName)) {
                            Label("Share All Highlights", systemImage: "square.and.arrow.up")
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(Self.rowInsets)
                    }
                    ForEach(highlights.list) { highlight in
                        highlightRow(highlight, heading: heading(for: highlight), goTo: highlights.goTo, in: highlights)
                    }
                    if !highlights.notFound.isEmpty {
                        Section {
                            ForEach(highlights.notFound) { highlight in
                                highlightRow(highlight, heading: highlight.chapter, goTo: nil, in: highlights)
                            }
                        } header: {
                            Text("Not Found in This File")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// The chapter and page, the words with their colour beside them (three
    /// lines at most), and the note in grey. A row with nowhere to go
    /// (`goTo` nil) is plain text.
    private func highlightRow(_ highlight: LocalHighlight, heading: String?, goTo: ((LocalHighlight) -> Void)?, in highlights: Highlights) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            if let heading, !heading.isEmpty {
                Text(verbatim: heading)
                    .font(.subheadline.weight(.medium))
            }
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: HighlightPalette.drawable(highlight.color)))
                    .frame(width: 4)
                    .accessibilityHidden(true)
                Text(verbatim: highlight.text)
                    .font(.footnote)
                    .lineLimit(untilLargerText: 3)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let note = highlight.note {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundStyle(.secondaryOnGlass)
                    .lineLimit(untilLargerText: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        return Group {
            if let goTo {
                Button { goTo(highlight) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(Self.rowInsets)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { highlights.remove(highlight.id) }
        }
        .accessibilityAction(named: Text(highlight.note == nil ? "Add Note" : "Edit Note")) { highlights.editNote(highlight.id) }
        .accessibilityAction(named: Text("Share")) { highlights.share(highlight) }
    }

    /// "Chapter 13 · Page 64", or whichever there is.
    private func heading(for highlight: LocalHighlight) -> String {
        let page = highlight.fraction.flatMap(page).map { String(localized: "Page \($0)", comment: "A highlight's page in the Highlights list") }
        return [highlight.chapter, page].compactMap(\.self).joined(separator: " · ")
    }

    /// "CHAPTER 2. The Carpet-Bag. · 34", or the page alone.
    private func heading(for bookmark: LocalBookmark) -> String {
        let page = bookmark.fraction.flatMap(page).map { String(localized: "Page \($0)", comment: "A bookmark's page in the Bookmarks list") }
        return [bookmark.chapter, page].compactMap(\.self).joined(separator: " · ")
    }
}

/// The ribbon on a bookmarked page (decision 17): at the top of the page,
/// by the column and its Bookmark button.
struct ReaderRibbon: View {
    static let color = Color(red: 0.72, green: 0.17, blue: 0.16)

    var body: some View {
        RibbonShape()
            .fill(Self.color)
            .frame(width: 16, height: 40)
            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private nonisolated struct RibbonShape: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 7))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
