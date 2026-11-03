import OctavoKit
import SwiftUI

/// A setup step across the spread (Adam, 2026-11-01): what it is on the
/// left page, under the title, and what you do on the right. Folded, one
/// page: the words, the form, then any help, such as where to find an
/// address.
struct SetupPage<Explanation: View, Form: View, Help: View>: View {
    @ViewBuilder let explanation: () -> Explanation
    @ViewBuilder let form: () -> Form
    @ViewBuilder var help: () -> Help
    @Environment(\.spread) private var spread

    var body: some View {
        ScrollView {
            if let pages = spread.pages {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        explanation()
                        help()
                    }
                    .padding(.horizontal, SpreadMetrics.margin)
                    .frame(width: pages.leftWidth, alignment: .leading)
                    Color.clear
                        .frame(width: pages.hingeWidth, height: 1)
                    form()
                        .padding(.horizontal, SpreadMetrics.margin)
                        .frame(width: pages.rightWidth, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    explanation()
                    form()
                    help()
                }
                .padding(.horizontal, SpreadMetrics.margin)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .padding(.bottom, 20)
    }
}

extension SetupPage where Help == EmptyView {
    init(@ViewBuilder explanation: @escaping () -> Explanation, @ViewBuilder form: @escaping () -> Form) {
        self.explanation = explanation
        self.form = form
        help = { EmptyView() }
    }
}

/// The step for a route.
struct SetupScreen: View {
    let step: SetupStep

    var body: some View {
        switch step {
        case .choose: ServerChoices()
        case .bookOrbit: BookOrbitSetup()
        case .opds: CatalogSetup()
        case .trust: TrustSetup()
        case .sync: SyncSetup()
        }
    }
}

/// "Add your books": the kinds of server (frame 05), and where to get one
/// (Adam, 2026-11-01), then Import from Files as a third choice and the
/// sample book as a quiet row under them (Adam, 2026-11-02). A file that
/// didn't come in says why under the choices.
struct SetupStart: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        SetupPage {
            SetupText("Octavo reads the books on your own server, or ones you import. Choose where your books are.")
        } form: {
            VStack(alignment: .leading, spacing: 10) {
                ServerChoiceButtons()
                SetupChoice(title: "Import from Files", detail: "EPUB, MOBI, AZW3 or FB2 files", working: shell.isImporting) {
                    shell.showFilePicker()
                }
                SetupError(message: ImportFailure.summary(shell.setupImportFailures))
                    .padding(.horizontal, 4)
                SampleBookRow()
                    .padding(.top, 4)
            }
        } help: {
            ServerSuggestions()
        }
    }
}

/// Settings' Add a server, once books were imported without one: the kinds
/// of server and where to get one, each step a screen with Back.
private struct ServerChoices: View {
    var body: some View {
        SetupPage {
            SetupText("Choose the kind of server you have. Its books join the ones on this iPhone.")
        } form: {
            VStack(spacing: 10) {
                ServerChoiceButtons()
            }
        } help: {
            ServerSuggestions()
        }
    }
}

private struct ServerChoiceButtons: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        SetupChoice(title: "BookOrbit", detail: "Your Reading Space") {
            shell.push(.setup(.bookOrbit))
        }
        SetupChoice(title: "OPDS catalog", detail: "Calibre-Web, COPS, Kavita, Komga…") {
            shell.push(.setup(.opds))
        }
    }
}

/// "Read a sample book": Pride and Prejudice, straight into the reader
/// (decision 6). Leaving it comes back here until something is added.
private struct SampleBookRow: View {
    @Environment(ShellModel.self) private var shell
    @State private var cover: UIImage?

    var body: some View {
        Button {
            shell.readSampleBook()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                    } else {
                        StandInCover(title: SampleBook.book.title, author: "Jane Austen", seed: LibraryBookID.sample.rawValue)
                    }
                }
                .aspectRatio(2 / 3, contentMode: .fill)
                .frame(width: 40, height: 60)
                .clipShape(.rect(cornerRadius: 3))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read a sample book")
                        .font(.headline)
                        .foregroundStyle(.tint)
                    Text("Pride and Prejudice, Jane Austen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(SampleBook.bundledFile == nil)
        .task {
            cover = SampleBook.bundledCover.flatMap { UIImage(contentsOfFile: $0.path) }
        }
    }
}

/// "Don't have one yet?": where to get a server, as one quiet card beside
/// the choices (Adam, 2026-11-01). Generic symbols, not the projects' logos
/// (BookOrbit's assets can't be copied in; calibre's are calibre's). Each
/// row opens the project's site in Safari.
private struct ServerSuggestions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Don’t have one yet?")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 12)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            SuggestionRow(
                name: "BookOrbit", line: "Self-hosted library, reader and apps", symbol: "server.rack", tint: .purple,
                site: URL(string: "https://github.com/bookorbit/bookorbit")!
            )
            Divider()
                .padding(.leading, 44)
            SuggestionRow(
                name: "calibre", line: "Your books on a Mac or PC, shared over OPDS", symbol: "books.vertical", tint: .green,
                site: URL(string: "https://calibre-ebook.com")!
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }
}

private struct SuggestionRow: View {
    let name: String
    let line: String
    let symbol: String
    let tint: Color
    let site: URL

    var body: some View {
        Link(destination: site) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.15), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(site.host() ?? "its site") in Safari")
    }
}

/// Sign in to BookOrbit (frame 06).
private struct BookOrbitSetup: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        @Bindable var setup = shell.setup
        SetupPage {
            SetupText("Your BookOrbit library, with your place in each book synced with BookOrbit’s own reader and apps.")
        } form: {
            VStack(alignment: .leading, spacing: 12) {
                AddressField(prompt: "books.example.com", address: $setup.bookOrbitAddress) {
                    setup.signInToBookOrbit()
                }
                SetupField("Username", text: $setup.bookOrbitUsername)
                    .textContentType(.username)
                SetupField("Password", text: $setup.bookOrbitPassword, secure: true)
                    .textContentType(.password)
                    .onSubmit { setup.signInToBookOrbit() }
                SetupButton("Sign in", working: setup.working) {
                    setup.signInToBookOrbit()
                }
                SetupError(message: setup.error)
            }
        } help: {
            SetupText("The address you open BookOrbit at in a browser, such as books.example.com or 192.168.1.5:3300.")
                .font(.footnote)
        }
        .onDisappear { setup.leftStep() }
    }
}

/// An OPDS catalog's address, then a sign-in only if it asks (frames 27,
/// 28).
private struct CatalogSetup: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        @Bindable var setup = shell.setup
        SetupPage {
            SetupText("Paste your catalog’s address. If it asks for a password, you will be automatically prompted.")
        } form: {
            VStack(alignment: .leading, spacing: 12) {
                AddressField(prompt: "https://books.example.com/opds", address: $setup.catalogAddress) {
                    setup.connectToCatalog()
                }
                if let signIn = setup.signIn {
                    Text(signIn.title.map { "Found “\($0)”. Sign-in required." } ?? "The catalog asks for a sign-in.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SetupField(signIn.usernameLabel ?? "Username", text: $setup.catalogUsername)
                        .textContentType(.username)
                    SetupField(signIn.passwordLabel ?? "Password", text: $setup.catalogPassword, secure: true)
                        .textContentType(.password)
                        .onSubmit { setup.connectToCatalog() }
                }
                SetupButton(setup.signIn == nil ? "Connect" : "Sign in", working: setup.working) {
                    setup.connectToCatalog()
                }
                SetupError(message: setup.error)
            }
        } help: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where to find it")
                    .font(.subheadline.weight(.semibold))
                Group {
                    Text("**calibre** (Content server) · …/opds")
                    Text("**Calibre-Web** · …/opds")
                    Text("**COPS** · …/feed.php")
                    Text("**Komga** · …/opds/v1.2/catalog")
                    Text("**Kavita** · the OPDS link in its settings")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .onDisappear { setup.leftStep() }
    }
}

/// "Trust this server" (decision 25): who the certificate says it's for, and
/// its fingerprint to compare with the server's own.
private struct TrustSetup: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let setup = shell.setup
        if let question = setup.trustQuestion {
            let certificate = question.certificate
            SetupPage {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: question.changed ? "exclamationmark.shield" : "lock.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(question.changed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                    if question.changed {
                        Text("This server’s certificate changed")
                            .font(.title3.weight(.semibold))
                    }
                    SetupText(question.message)
                }
            } form: {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        TrustRow("Server", certificate.port == 443 ? certificate.host : "\(certificate.host):\(certificate.port)")
                        Divider()
                        TrustRow("Issued to", certificate.subject.isEmpty ? "No name" : certificate.subject)
                        if certificate.isSelfSigned {
                            Divider()
                            TrustRow("Issued by", "Itself (self-signed)")
                        }
                        if let expiry = certificate.notValidAfter {
                            Divider()
                            TrustRow(expiry < .now ? "Expired" : "Expires", expiry.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.changed ? "New fingerprint (SHA-256)" : "Fingerprint (SHA-256)")
                            .font(.subheadline.weight(.semibold))
                        Fingerprint(sha256: certificate.pin.sha256)
                    }
                    if let trusted = question.trusted {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("The one you trusted")
                                .font(.subheadline.weight(.semibold))
                            Fingerprint(sha256: trusted.sha256)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if question.changed {
                        SetupButton("Don’t connect", working: false) { setup.decideTrust(false) }
                        Button(role: .destructive) {
                            setup.decideTrust(true)
                        } label: {
                            Text(certificate.isTrustedBySystem ? "Use the new certificate" : "Trust the new certificate")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .foregroundStyle(.red)
                    } else {
                        SetupButton("Trust", working: false) { setup.decideTrust(true) }
                        Button {
                            setup.decideTrust(false)
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }
            }
        }
    }
}

private struct TrustRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        LabeledContent(label, value: value)
            .padding(.vertical, 8)
    }
}

/// Where reading progress syncs, after a BookOrbit sign-in (frame 39):
/// BookOrbit itself or nothing. Not shown for now
/// (`SavedServer.offersSyncChoice`); it returns with a real choice, such as
/// iCloud or KOReader sync.
private struct SyncSetup: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        @Bindable var setup = shell.setup
        SetupPage {
            SetupText("Where Octavo keeps your place in each book, so you can pick up where you left off on another device.")
        } form: {
            VStack(alignment: .leading, spacing: 10) {
                SetupChoice(
                    title: "This BookOrbit server", detail: "Your place matches BookOrbit’s reader and apps",
                    selected: setup.syncsProgress
                ) { setup.syncsProgress = true }
                SetupChoice(title: "Don’t sync", detail: "Your place stays on this iPhone", selected: !setup.syncsProgress) {
                    setup.syncsProgress = false
                }
                SetupButton("Done", working: false) { setup.finishBookOrbit() }
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: Pieces

private struct SetupText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A kind of server, or a sync choice: a bordered row with a title and a
/// line about it. Selected, it's tinted and checked.
private struct SetupChoice: View {
    let title: String
    let detail: String
    var selected: Bool? = nil
    /// A spinner at the end while it's busy (an import copying in).
    var working = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if working {
                    ProgressView()
                } else if selected == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == true ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected == true ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(working)
        .accessibilityAddTraits(selected == true ? .isSelected : [])
    }
}

/// An address: the URL keyboard, no capitals or corrections, and "Not
/// encrypted" under it for plain http (decision 25).
private struct AddressField: View {
    let prompt: String
    @Binding var address: String
    /// Return: the step's action.
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SetupField("Address", text: $address, prompt: prompt)
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .onSubmit(submit)
            if (try? ServerAddress.parse(address))?.isPlainHTTP == true {
                Label("Not encrypted. Octavo uses http:// only at home or over a VPN.", systemImage: "lock.open")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A labelled field in a rounded box.
private struct SetupField: View {
    let label: String
    @Binding var text: String
    var prompt: String?
    var secure = false

    init(_ label: String, text: Binding<String>, prompt: String? = nil, secure: Bool = false) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.secure = secure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(label, text: $text, prompt: prompt.map(Text.init))
                } else {
                    TextField(label, text: $text, prompt: prompt.map(Text.init))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
        }
    }
}

/// The step's action, wide, with a spinner while it works.
private struct SetupButton: View {
    let title: String
    let working: Bool
    let action: () -> Void

    init(_ title: String, working: Bool, action: @escaping () -> Void) {
        self.title = title
        self.working = working
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Text(title)
                    .opacity(working ? 0 : 1)
                if working {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(working)
    }
}

/// What went wrong, under the fields (decision 22).
private struct SetupError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Sign in again, from the signed-out banner (decision 22): the server's
/// address as it was added, the account, a new password. Back to where you
/// were once it works.
struct SignInAgainScreen: View {
    @Environment(ShellModel.self) private var shell
    @State private var username: String?
    @State private var password = ""
    @State private var attempt = Attempt()
    @State private var error: String?

    var body: some View {
        if let saved = shell.servers.load() {
            let name = saved.name
            SetupPage {
                SetupText("Signed out of \(name). Reading works without it; sign in again to see your library and keep your place in step.")
            } form: {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Server", value: saved.detail.components(separatedBy: " · ").first ?? name)
                        .padding(.bottom, 4)
                    SetupField("Username", text: Binding { username ?? saved.username ?? "" } set: { username = $0 })
                        .textContentType(.username)
                    SetupField("Password", text: $password, secure: true)
                        .textContentType(.password)
                        .onSubmit { signIn(saved) }
                    SetupButton("Sign in", working: attempt.running) { signIn(saved) }
                    SetupError(message: error)
                }
            }
            // Typing again stops the try that's running; leaving stops it too.
            .onChange(of: username) { edited() }
            .onChange(of: password) { edited() }
            .onDisappear { attempt.cancel() }
        } else {
            LibraryNotConnected()
        }
    }

    private func signIn(_ saved: SavedServer) {
        let username = username ?? saved.username ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            error = "Enter your username and password."
            return
        }
        error = nil
        let host = URL(string: saved.address.replacingOccurrences(of: OPDSURLSecret.placeholder, with: "key"))?.host()
        let password = password
        attempt.start { isCurrent in
            do {
                try await shell.signInAgain(username: username, password: password)
                guard isCurrent() else { return }
                self.password = ""
                shell.pop(shell.tab)
            } catch {
                guard isCurrent() else { return }
                self.error = SetupModel.message(for: error, server: saved.name, host: host)
            }
        } timedOut: {
            error = "\(host ?? saved.name) didn’t answer. Check that this iPhone is on the same network as the server."
        }
    }

    private func edited() {
        attempt.cancel()
        error = nil
    }
}
