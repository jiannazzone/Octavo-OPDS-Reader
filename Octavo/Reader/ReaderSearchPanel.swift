import SwiftUI

/// Search in book (decision 19): the field, the count, and matches grouped
/// by chapter with the words around them and their page. A match goes to
/// its page; the step bar then takes over.
struct ReaderSearchPanel: View {
    let search: ReaderSearch
    /// The page number at a point of the book.
    let page: (Double) -> Int?
    /// What's typed changed (`submitted` on Return).
    let run: (_ submitted: Bool) -> Void
    let choose: (Int) -> Void
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var search = search
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search in Book", text: $search.query)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { run(true) }
                    if !search.query.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") {
                            search.query = ""
                            focused = true
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                ReaderPanelCloseButton(close: close)
            }
            .padding([.horizontal, .top], 14)
            status
                .font(.footnote)
                .foregroundStyle(.secondaryOnGlass)
                .padding(.horizontal, 18)
            results
        }
        .task(id: search.query) {
            // Searches once typing pauses.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            run(false)
        }
        .onAppear {
            // Reopened with results: they show, without the keyboard.
            if search.matches.isEmpty { focused = true }
        }
    }

    @ViewBuilder private var status: some View {
        if search.searched != nil {
            HStack(spacing: 6) {
                Text(countText)
                if search.isSearching { ProgressView().controlSize(.mini) }
            }
        }
    }

    private var countText: String {
        let count = search.matches.count
        if count == 0 { return search.isSearching ? String(localized: "Searching…") : String(localized: "No matches") }
        let number = count.formatted()
        return search.isTruncated
            ? String(localized: "\(number)+ matches", comment: "Search in book stopped at its limit")
            : String(localized: "\(count) matches", comment: "Search in book's match count")
    }

    private var results: some View {
        ScrollViewReader { proxy in
            list
                .onAppear {
                    // Back from the step bar: on the match being shown.
                    if let current = search.current { proxy.scrollTo(current, anchor: .center) }
                }
        }
    }

    private var list: some View {
        List {
            ForEach(search.groups) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                            .id(item.index)
                    }
                } header: {
                    if let chapter = group.chapter {
                        Text(chapter)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(untilLargerText: 1)
                            .padding(.horizontal, 18)
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func row(_ item: ReaderSearch.Item) -> some View {
        let match = item.match
        return Button {
            focused = false
            choose(item.index)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("\(match.pre)\(Text(match.match).bold().foregroundStyle(.tint))\(match.post)")
                    .font(.subheadline)
                    .lineLimit(untilLargerText: 3)
                Spacer(minLength: 12)
                if let page = match.fraction.flatMap(page) {
                    Text(page, format: .number)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryOnGlass)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Rectangle().fill(item.index == search.current ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear)))
        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
    }
}

/// While stepping through matches: ‹ 3 of 252 › and ✕ (decision 19). The
/// count goes back to the list.
struct ReaderSearchBar: View {
    let search: ReaderSearch
    let step: (Int) -> Void
    let showList: () -> Void
    let end: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button("Previous Match", systemImage: "chevron.backward") {
                if let current = search.current { step(current - 1) }
            }
            .disabled(!search.canGoBack)
            Button(action: showList) {
                Text(countText)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
            }
            .accessibilityHint(Text("Shows the matches"))
            Button("Next Match", systemImage: "chevron.forward") {
                if let current = search.current { step(current + 1) }
            }
            .disabled(!search.canGoForward)
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)
            Button("End Search", systemImage: "xmark", action: end)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var countText: String {
        let number = (search.current ?? 0) + 1
        let total = search.isTruncated ? "\(search.matches.count.formatted())+" : search.matches.count.formatted()
        return String(localized: "\(number) of \(total)", comment: "The match shown, out of all, e.g. 3 of 252")
    }
}
