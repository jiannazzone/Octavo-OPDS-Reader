import OctavoKit
import SwiftUI

/// Contents and bookmarks (decision 17): one panel, a Contents | Bookmarks
/// switch. Contents opens on the chapter the page is in; bookmarks list in
/// the book's order with their chapter, page and first words, and swipe to
/// delete. Choosing either goes there.
struct ReaderContentsPanel: View {
    enum Tab: Hashable {
        case contents, bookmarks
    }

    let rows: [ReaderContentsRow]
    let current: Int?
    let bookmarks: [LocalBookmark]
    /// The page number at a point of the book.
    let page: (Double) -> Int?
    let goToRow: (ReaderContentsRow) -> Void
    let goToBookmark: (LocalBookmark) -> Void
    let remove: (LocalBookmark.ID) -> Void
    @State private var tab = Tab.contents

    /// The panel's own margins: a list in it gets none from the page.
    private static let rowInsets = EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)

    var body: some View {
        VStack(spacing: 6) {
            Picker("Show", selection: $tab) {
                Text("Contents").tag(Tab.contents)
                Text("Bookmarks").tag(Tab.bookmarks)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 14)
            switch tab {
            case .contents: contents
            case .bookmarks: bookmarkList
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
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.label)
                                .lineLimit(2)
                            Spacer(minLength: 12)
                            if let page = row.page {
                                Text(page, format: .number)
                                    .monospacedDigit()
                                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
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
