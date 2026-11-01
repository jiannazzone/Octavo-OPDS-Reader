import SwiftUI

/// Root: the app shell. In debug builds, launching with `-spike 1` shows the
/// spike's screens instead, for the tools in `docs/notes/` that drive them.
struct ContentView: View {
    var body: some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "spike") {
            SpikeLibraryView()
        } else {
            AppShell()
        }
        #else
        AppShell()
        #endif
    }
}

#Preview {
    ContentView()
}
