import OctavoKit
import SwiftUI

/// The server's page (frame 35): where and who, whether reading progress
/// has synced, then Sign out (Sign in, once signed out) and Remove server,
/// each confirmed in an alert (Adam, 2026-11-02).
struct ServerSettingsPage: View {
    let id: LibrarySourceID
    @Environment(ShellModel.self) private var shell
    @Environment(LibraryModel.self) private var library
    @State private var confirmsSignOut = false
    @State private var removal: Removal?
    /// The Name row while it's being typed in.
    @State private var typedName: String?
    @FocusState private var editsName: Bool

    /// What Remove server asks about: the server's downloads, counted when
    /// it's tapped.
    private struct Removal {
        var downloads: [DownloadedBook]
    }

    var body: some View {
        if let server = library.server(id) {
            page(server)
        } else {
            LibraryNotConnected()
        }
    }

    private func page(_ server: LibraryServer) -> some View {
        SettingsPageList(title: server.name) {
            Section {
                LabeledContent("Name") {
                    TextField(
                        "Name", text: Binding { typedName ?? server.name } set: { typedName = $0 },
                        prompt: server.ownName.map(Text.init)
                    )
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .submitLabel(.done)
                    .focused($editsName)
                    .onSubmit { keepName() }
                }
                LabeledContent("Address", value: server.address)
                if let username = server.username {
                    LabeledContent("Account", value: username)
                }
                // An OPDS catalog keeps no place, so says nothing here, as a
                // book's place line doesn't (Adam, 2026-11-02).
                if server.syncsProgress {
                    LabeledContent("Reading progress", value: sync(server).value)
                }
            } footer: {
                if server.syncsProgress, let note = sync(server).note {
                    Text(note)
                }
            }
            if server.source is OPDSSource {
                koreaderSection(server)
            }
            Section {
                if isSignedOut {
                    Button("Sign in") { shell.showSignIn(id) }
                } else if server.signsIn {
                    Button("Sign out", role: .destructive) { confirmsSignOut = true }
                }
                Button("Remove server", role: .destructive) {
                    removal = Removal(downloads: shell.downloads(on: id))
                }
            }
        }
        .alert("Sign out of \(server.name)?", isPresented: $confirmsSignOut) {
            Button("Sign out", role: .destructive) { shell.serverActions.signOut(id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(server.syncsProgress
                ? "Your downloaded books stay on this iPhone. Reading progress syncs again once you sign in."
                : "Your downloaded books stay on this iPhone.")
        }
        .alert("Remove \(server.name)?", isPresented: Binding { removal != nil } set: { if !$0 { removal = nil } }, presenting: removal) { removal in
            if removal.downloads.isEmpty {
                Button("Remove", role: .destructive) { remove(removingBooks: false) }
            } else {
                Button("Keep books on iPhone") { remove(removingBooks: false) }
                    .keyboardShortcut(.defaultAction)
                Button("Remove books too", role: .destructive) { remove(removingBooks: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(Self.removalMessage(removal.downloads))
        }
        .onChange(of: editsName) { _, editing in
            if !editing { keepName() }
        }
    }

    /// A catalog's "Sync with KOReader" (question 2): with no account yet,
    /// the sign-in fields under it.
    @ViewBuilder private func koreaderSection(_ server: LibraryServer) -> some View {
        let account = shell.koreader.account
        Section {
            Toggle("Sync with KOReader", isOn: Binding { server.syncsWithKOReader } set: { shell.serverActions.setKOReaderSync(id, $0) })
        } footer: {
            if server.syncsWithKOReader, let account {
                Text("As \(account.username) on \(account.host). \(KOReaderSettingsPage.catalogLimits)")
            } else {
                Text(KOReaderSettingsPage.catalogLimits)
            }
        }
        if server.syncsWithKOReader, account == nil {
            KOReaderSignInSection(signIn: shell.koreaderSignIn, showsLimits: false)
        }
    }

    /// Done on the keyboard, or leaving the row.
    private func keepName() {
        guard let typedName else { return }
        shell.serverActions.rename(id, to: typedName)
        self.typedName = nil
    }

    private var isSignedOut: Bool {
        if case .signedOut = library.connection(id)?.problem { return true }
        return false
    }

    /// The Reading progress row and the note under it.
    private func sync(_ server: LibraryServer) -> (value: String, note: String?) {
        if isSignedOut { return ("Paused", "Sign in again to sync.") }
        let pending = shell.places.pendingCount(on: server.id)
        if pending > 0 { return ("Not synced yet", pending == 1 ? "1 book pending." : "\(pending) books pending.") }
        return ("Synced", nil)
    }

    private func remove(removingBooks: Bool) {
        Task { await shell.serverActions.remove(id, removingBooks: removingBooks) }
    }

    /// "Its 12 downloaded books use 48 MB. Remove them too, or keep them on
    /// this iPhone?", or "You can add it again any time." without any.
    static func removalMessage(_ downloads: [DownloadedBook]) -> String {
        guard !downloads.isEmpty else { return "You can add it again any time." }
        let size = ByteCountFormatter.string(fromByteCount: downloads.reduce(0) { $0 + $1.size }, countStyle: .file)
        if downloads.count == 1 {
            return "Its downloaded book uses \(size). Remove it too, or keep it on this iPhone?"
        }
        return "Its \(downloads.count) downloaded books use \(size). Remove them too, or keep them on this iPhone?"
    }
}
