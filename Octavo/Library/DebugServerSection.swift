#if DEBUG
import SwiftUI

/// Connects a library until first run (#12) can: the local BookOrbit from
/// `dev/bookorbit/`, a local OPDS server from `dev/opds/`, or the made-up
/// sample library. In the Settings stand-in; debug builds only.
struct DebugServerSection: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Section {
            if let server = library.server {
                LabeledContent(server.name, value: server.detail)
                Button("Disconnect", role: .destructive) { library.disconnect() }
            } else {
                Button {
                    Task { await library.connectLocalBookOrbit() }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Connect local BookOrbit")
                        Text("localhost:3300 · octavo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(library.debugConnection == .connecting)
                ForEach(LibraryModel.DebugOPDSServer.allCases) { server in
                    Button {
                        Task { await library.connectLocalOPDS(server) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Connect local \(server.name)")
                            Text(server.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(library.debugConnection == .connecting)
                }
                Button("Use sample library") {
                    Task { await library.connectSampleLibrary() }
                }
            }
            switch library.debugConnection {
            case .idle: EmptyView()
            case .connecting: ProgressView()
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Debug server")
        } footer: {
            Text("Debug builds only. Tokens and passwords are kept in the Keychain; Disconnect forgets them.")
        }
    }
}
#endif
