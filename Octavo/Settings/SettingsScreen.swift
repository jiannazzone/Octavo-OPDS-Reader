import OctavoKit
import SwiftUI

/// Settings (decision 24, frames 34–37): the server, Library's one switch,
/// Keep screen on, Close book when folded, the books on the iPhone and About.
/// Reading choices live in the reader's Text and theme panel, not here. Those
/// two are the exception: they're set once and left (Adam, 2026-11-06).
///
/// Folded, the list and each page are screens of their own. Unfolded, the
/// list is on the left page and the chosen page on the right (the server's,
/// to start with); a tap on the left changes the right page without a slide
/// (Adam, 2026-11-02). A fold keeps the page that was chosen on top.
struct SettingsScreen: View {
    /// `nil`: the list itself.
    let page: SettingsPage?
    @Environment(\.spread) private var spread
    @Environment(LibraryModel.self) private var library

    var body: some View {
        // With no server yet (books imported), Storage's page to start with.
        let first: SettingsPage = library.server.map { .server($0.id) } ?? .storage
        Group {
            if let pages = spread.pages {
                HStack(spacing: 0) {
                    SettingsList(chosen: page ?? first)
                        .frame(width: pages.leftWidth)
                    Color.clear
                        .frame(width: pages.hingeWidth)
                    SettingsPageView(page: page ?? first)
                        .frame(width: pages.rightWidth)
                }
            } else if let page {
                SettingsPageView(page: page)
            } else {
                SettingsList(chosen: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }
}

/// The page a row opens.
private struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .server(let id): ServerSettingsPage(id: id)
        case .storage: BooksOnIPhonePage()
        case .licences: LicencesPage()
        }
    }
}

/// A page of Settings: its title over a grouped list, on the page's own
/// background (the screen's, so the hinge between the pages matches).
struct SettingsPageList<Content: View>: View {
    let title: String
    /// Settings' own list, which is on the left page unfolded.
    var isOnLeftPage = false
    @ViewBuilder let content: () -> Content
    @Environment(\.spread) private var spread

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenTitle(title)
            List { content() }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 4, for: .scrollContent)
                // At the screen's edge a list otherwise gets this margin from
                // the system, worked out again on every frame of a slide: its
                // rows stop at the margin while the rest of the screen carries
                // on, and they shrink. Stated here, it moves with them.
                .contentMargins(.leading, isOnLeftPage || !spread.isTwoPages ? SpreadMetrics.margin : 0, for: .scrollContent)
        }
    }
}

/// Settings' list (frame 34, without its Reading progress row: Adam,
/// 2026-11-02).
struct SettingsList: View {
    /// Unfolded: the page beside the list, marked in it.
    let chosen: SettingsPage?
    @Environment(ShellModel.self) private var shell
    @Environment(LibraryModel.self) private var library
    @Environment(\.spread) private var spread
    @AppStorage(LibrarySettings.titlesUnderCoversKey) private var titlesUnderCovers = false
    @AppStorage(ReaderScreenOn.key) private var screenOn = ReaderScreenOn.standard
    @AppStorage(ReaderSettings.closeBookWhenFoldedKey) private var closesBookWhenFolded = ReaderSettings.closeBookWhenFoldedDefault

    var body: some View {
        SettingsPageList(title: "Settings", isOnLeftPage: true) {
            // Each server, then Add a server (decision 36). "Server" with one
            // or none, as before.
            Section(library.hasSeveralServers ? "Servers" : "Server") {
                ForEach(library.connections, id: \.server.id) { connection in
                    row(.server(connection.server.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.server.name)
                            Text(connection.server.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    shell.push(.setup(.choose))
                } label: {
                    HStack {
                        Text("Add a server")
                            .foregroundStyle(.tint)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
            }
            Section {
                Toggle("Titles under covers", isOn: $titlesUnderCovers)
            } header: {
                Text("Library")
            } footer: {
                Text("Shows each book’s title beneath its cover.")
            }
            Section {
                Picker("Keep screen on", selection: $screenOn) {
                    ForEach(ReaderScreenOn.allCases) { time in
                        Text(time.name).tag(time)
                    }
                }
                Toggle("Close book when folded", isOn: $closesBookWhenFolded)
            } header: {
                Text("Reading")
            } footer: {
                Text("Keep screen on is how long the screen stays on after you turn a page.")
            }
            Section {
                row(.storage) {
                    LabeledContent("Books on iPhone", value: shell.downloads().summary())
                }
                ClearCoversRow()
            } header: {
                Text("Storage")
            } footer: {
                Text("Covers download again when they’re next shown.")
            }
            Section {
                Button {
                    shell.showTour()
                } label: {
                    HStack {
                        Text("Show the tour")
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
            }
            Section {
                LabeledContent("Version", value: AboutOctavo.version)
                link("Source code", to: AboutOctavo.sourceCode)
                link("Privacy Policy", to: AboutOctavo.privacyPolicy)
                row(.licences) { Text("Licences") }
            } header: {
                Text("About")
            } footer: {
                Text("Octavo is free software under the Mozilla Public License 2.0.")
            }
            #if DEBUG
            DebugServerSection()
            DebugTrustSection()
            ShellStatesSection()
            ReaderSettingsSection()
            #endif
        }
    }

    private func link(_ title: LocalizedStringKey, to destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Opens GitHub in Safari")
    }

    private func row(_ page: SettingsPage, @ViewBuilder label: () -> some View) -> some View {
        Button {
            shell.openSettingsPage(page, twoPages: spread.isTwoPages)
        } label: {
            HStack {
                label()
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .listRowBackground(chosen == page ? Color.accentColor.opacity(0.14) : nil)
        .accessibilityAddTraits(chosen == page ? .isSelected : [])
    }
}

/// What About shows.
nonisolated enum AboutOctavo {
    static let sourceCode = URL(string: "https://github.com/jiannazzone/Octavo-OPDS-Reader")!
    /// Apple requires a link in the app as well as in the listing (guideline 5.1.1).
    static let privacyPolicy = URL(string: "https://github.com/jiannazzone/Octavo-OPDS-Reader/blob/main/docs/PRIVACY.md")!

    /// "0.1 (1)": the version and the build.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }
}
