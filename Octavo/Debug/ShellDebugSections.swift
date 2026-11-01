#if DEBUG
import OctavoKit
import SwiftUI

/// DEBUG ONLY. Switches the Settings stand-in shows until the real screens
/// exist: the shell's stand-in states, and the reading settings whose
/// Customize panel is #18.

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

/// The reader's settings until the Customize panel (#18) has them
/// (decision 13: they live only there). Same keys, so they carry over.
struct ReaderSettingsSection: View {
    @AppStorage(ReaderSettings.alwaysShowControlsKey) private var alwaysShowControls = ReaderSettings.alwaysShowControlsDefault
    @AppStorage(ReaderMargins.key) private var margins = ReaderMargins.standard
    @AppStorage(ReaderSettings.bookModeShadowKey) private var bookModeShadow = ReaderSettings.bookModeShadowDefault

    var body: some View {
        Section {
            Toggle("Always show controls", isOn: $alwaysShowControls)
            Picker("Margins", selection: $margins) {
                Text("Narrow").tag(ReaderMargins.narrow)
                Text("Medium").tag(ReaderMargins.medium)
                Text("Wide").tag(ReaderMargins.wide)
            }
            Toggle("Book-mode shadow", isOn: $bookModeShadow)
        } header: {
            Text("Reader")
        } footer: {
            Text("Debug builds only, until the reader’s Customize panel (#18).")
        }
    }
}
#endif
