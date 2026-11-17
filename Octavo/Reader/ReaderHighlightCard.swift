import OctavoKit
import SwiftUI
import UIKit

/// A highlight's card (#125): tapped on the page, it comes up where a
/// footnote's card would, in its style. One grid of five columns: Share,
/// Copy, Note, Delete and ✕ over the ten colors in two rows; then the note,
/// if there is one.
struct ReaderHighlightCard: View {
    let highlight: LocalHighlight
    /// What Share adds after the quote: the title and author.
    let source: String?
    let theme: ReaderTheme
    let recolor: (String) -> Void
    let writeNote: () -> Void
    let delete: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // One grid of five columns: the buttons over the colours, each
            // in a colour's column, ✕ in the last.
            Grid(horizontalSpacing: 0, verticalSpacing: 8) {
                GridRow {
                    ShareLink(item: ReaderHighlightCard.shareText(highlight.text, source: source)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = highlight.text
                    }
                    Button(highlight.note == nil ? "Add Note" : "Edit Note", systemImage: "square.and.pencil", action: writeNote)
                    Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    ReaderPanelCloseButton(close: close)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 44)
                HighlightColorGrid.rows(selected: highlight.color, pick: recolor)
            }
            if let note = highlight.note {
                Text(verbatim: note)
                    .font(.body)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(Color(hex: theme.background).opacity(0.72)), in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The quote, then where it's from: "“…” — Pride and Prejudice, Jane
    /// Austen".
    nonisolated static func shareText(_ text: String, source: String?) -> String {
        guard let source, !source.isEmpty else { return "“\(text)”" }
        return "“\(text)”\n— \(source)"
    }

    /// "Title, Author", or whichever there is.
    nonisolated static func source(title: String, authors: [String]) -> String? {
        let parts = [title, authors.joined(separator: ", ")].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// A highlight's note (#125): a system sheet with the quote in its colour on
/// top, then the note. Cancel keeps the highlight and leaves the note as it
/// was; Done saves it, and an empty one clears it.
struct ReaderHighlightNoteSheet: View {
    let highlight: LocalHighlight
    let save: (String) -> Void
    let cancel: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(highlight: LocalHighlight, save: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.highlight = highlight
        self.save = save
        self.cancel = cancel
        _text = State(initialValue: highlight.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: HighlightPalette.drawable(highlight.color)))
                            .frame(width: 4)
                            .accessibilityHidden(true)
                        Text(verbatim: highlight.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    TextField("Note", text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(4...)
                }
                .padding()
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { save(text) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }
}
