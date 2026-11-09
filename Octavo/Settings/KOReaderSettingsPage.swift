import OctavoKit
import SwiftUI

/// KOReader sync's page (`docs/notes/koreader-sync-plan.md`, questions 1
/// and 5): signed out, the sync server's address and the account, then Sign
/// in; signed in, where and who, then Sign out, confirmed in an alert.
struct KOReaderSettingsPage: View {
    @Environment(ShellModel.self) private var shell
    @State private var confirmsSignOut = false

    var body: some View {
        SettingsPageList(title: "KOReader sync") {
            if let account = shell.koreader.account {
                Section {
                    LabeledContent("Server", value: account.host)
                    LabeledContent("Username", value: account.username)
                } footer: {
                    Text(Self.limits)
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmsSignOut = true }
                }
            } else {
                KOReaderSignInSection(signIn: shell.koreaderSignIn)
            }
        }
        .alert("Sign out of KOReader sync?", isPresented: $confirmsSignOut) {
            Button("Sign out", role: .destructive) { shell.serverActions.signOutOfKOReader() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your places stay on this \(ThisDevice.name).")
        }
        .onDisappear { shell.koreaderSignIn.left() }
    }

    /// What can sync (question 5): nothing can tell a different copy of a
    /// file, so it's said once.
    static let limits = "EPUB books only. Your other devices need the same file."
    /// The same, under a catalog's switch.
    static let catalogLimits = "EPUB books only. Your other devices need the same file, such as one downloaded from this catalog."
}

/// The sign-in fields and button, in a Settings list: KOReader sync's page,
/// and a catalog's page with its switch on before there's an account.
struct KOReaderSignInSection: View {
    @Bindable var signIn: KOReaderSignIn
    /// The limits under the fields, unless the page says them already.
    var showsLimits = true
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Section {
            LabeledContent("Server") {
                TextField("Server", text: $signIn.address, prompt: Text("sync.example.com"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Username") {
                TextField("Username", text: $signIn.username, prompt: Text("Required"))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Password") {
                SecureField("Password", text: $signIn.password, prompt: Text("Required"))
                    .textContentType(.password)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { signIn.signIn(with: shell.serverActions) }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let error = signIn.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                } else if (try? ServerAddress.parse(signIn.address))?.isPlainHTTP == true {
                    Label("Not encrypted. On other networks, your password could be seen.", systemImage: "lock.open")
                }
                if showsLimits { Text(KOReaderSettingsPage.limits) }
            }
        }
        Section {
            Button {
                signIn.signIn(with: shell.serverActions)
            } label: {
                HStack {
                    Text("Sign in")
                    Spacer(minLength: 8)
                    if signIn.working { ProgressView() }
                }
                .contentShape(.rect)
            }
            .disabled(signIn.working)
        }
    }
}
