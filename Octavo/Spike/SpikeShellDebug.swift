#if DEBUG
import SwiftUI

/// SPIKE ONLY (deleted with the spike). Debug-only controls the app shell
/// shows until the real screens exist: the spike's screens over the tabs,
/// a Library row to open them, and switches for the shell's stand-in states.

/// The spike's library over the tabs, with a way back to the shell.
struct SpikeLibraryOverlay: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        SpikeLibraryView()
            .overlay(alignment: .bottomLeading) {
                Button("Close spike library", systemImage: "xmark") { shell.showsSpike = false }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .padding()
            }
            .background(Color(.systemBackground))
    }
}

/// The Library row that opens the spike's screens, for opening books until
/// the reader (#17) does.
struct SpikeLibrarySection: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Section {
            Button("Spike library", systemImage: "hammer") { shell.showsSpike = true }
        } footer: {
            Text("Debug builds only: the spike’s screens, for reading books until the reader (#17) exists.")
        }
    }
}

/// Switches the stand-in states on and off, to look at them.
struct ShellStatesSection: View {
    @Environment(ShellModel.self) private var shell
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var shell = shell
        @Bindable var library = library
        Section {
            Picker("Connection", selection: $library.connectionProblem) {
                Text("Fine").tag(ConnectionProblem?.none)
                Text("Unreachable").tag(ConnectionProblem?.some(.unreachable(server: "BookOrbit")))
                Text("Signed out").tag(ConnectionProblem?.some(.signedOut(server: "BookOrbit")))
            }
            Picker("Cover strip", selection: $shell.coverStrip) {
                Text("Normal").tag(CoverStripMessage?.none)
                Text("Couldn’t download").tag(CoverStripMessage?.some(.downloadFailed))
                Text("Not downloaded").tag(CoverStripMessage?.some(.needsConnection))
                Text("Downloading").tag(CoverStripMessage?.some(.downloading(fraction: 0.42)))
            }
        } header: {
            Text("Shell states")
        } footer: {
            Text("Debug builds only.")
        }
    }
}
#endif
