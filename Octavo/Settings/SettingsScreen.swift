import OctavoKit
import SwiftUI

/// Settings (decision 24, frames 34–37): the server, Library's one switch,
/// Keep screen on, Close book when folded, the books on the iPhone and About.
/// Reading choices live in the reader's Text and theme panel, not here. Those
/// two are the exception: they're set once and left (Adam, 2026-11-06).
///
/// A sheet from the gear holding the system's split, as system Settings is
/// on the open Duo (Adam, 2026-11-08): the list on the left (`SettingsList`),
/// the chosen page on the right (the server's, to start with), where a page's
/// own screens push. Folded, the list, and a row pushes its page with Back.
struct SettingsSheet: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        TabSplit(tab: .settings, buttonsOnList: true) {
            SettingsList()
        } buttons: {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) { shell.closeSettings() }
            }
        }
    }
}

/// The page a row opens.
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .server(let id): ServerSettingsPage(id: id)
        case .koreader: KOReaderSettingsPage()
        case .storage: BooksOnIPhonePage()
        case .licences: LicencesPage()
        }
    }
}

/// A page of Settings: a grouped list under its title.
struct SettingsPageList<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        List { content() }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
    }
}

/// Settings' list (frame 34, without its Reading progress row: Adam,
/// 2026-11-02).
struct SettingsList: View {
    @Environment(ShellModel.self) private var shell
    @Environment(LibraryModel.self) private var library
    @AppStorage(LibrarySettings.titlesUnderCoversKey) private var titlesUnderCovers = false
    @AppStorage(ReaderScreenOn.key) private var screenOn = ReaderScreenOn.standard
    @AppStorage(ReaderSettings.closeBookWhenFoldedKey) private var closesBookWhenFolded = ReaderSettings.closeBookWhenFoldedDefault

    var body: some View {
        // A `List` whose selection is the page on the right (`TabSplit`): a
        // row is a link to its page, so folded it pushes with Back.
        List(selection: shell.pickBinding(.settings)) {
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
                NavigationLink(value: ShellRoute.setup(.choose)) {
                    Text("Add a server")
                        .foregroundStyle(.tint)
                }
            }
            Section {
                row(.koreader) {
                    LabeledContent("KOReader sync", value: shell.koreader.account?.username ?? "Off")
                }
            } footer: {
                Text("Syncs your place with KOReader for books from catalogs and Files.")
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
                    shell.closeSettings()
                    shell.tour.show()
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
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inlineLarge)
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
        NavigationLink(value: ShellRoute.settingsPage(page)) {
            label()
        }
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
